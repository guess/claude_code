defmodule ClaudeCode.History.LiteReader do
  @moduledoc """
  Reads session file metadata using only head/tail reads for fast extraction.

  Matches the Python SDK's `_read_session_lite` + `_extract_first_prompt_from_head`
  approach: reads the first and last 64KB of a session file to extract metadata
  without parsing the full JSONL content.
  """

  alias ClaudeCode.History.SessionInfo

  @lite_read_buf_size 65_536

  @uuid_re ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  # Patterns matching auto-generated or system messages to skip when
  # looking for the first meaningful user prompt.
  @skip_first_prompt_re ~r/^(?:<local-command-stdout>|<session-start-hook>|<tick>|<goal>|\[Request interrupted by user[^\]]*\]|\s*<ide_opened_file>[\s\S]*<\/ide_opened_file>\s*$|\s*<ide_selection>[\s\S]*<\/ide_selection>\s*$)/

  @command_name_re ~r/<command-name>(.*?)<\/command-name>/

  @doc """
  Reads metadata from a session JSONL file using head/tail reads.

  Returns `{:ok, %SessionInfo{}}` or `{:error, reason}`.
  """
  @spec read_metadata(Path.t()) :: {:ok, SessionInfo.t()} | {:error, term()}
  def read_metadata(path) do
    filename = Path.basename(path, ".jsonl")

    case validate_uuid(filename) do
      nil -> {:error, :invalid_uuid}
      session_id -> do_read_metadata(path, session_id)
    end
  end

  @doc """
  Validates a string as a UUID. Returns the string if valid, nil otherwise.
  """
  @spec validate_uuid(String.t()) :: String.t() | nil
  def validate_uuid(maybe_uuid) do
    if Regex.match?(@uuid_re, maybe_uuid), do: maybe_uuid
  end

  # -- Private ----------------------------------------------------------------

  defp do_read_metadata(path, session_id) do
    case read_lite(path) do
      {:ok, %{head: head, tail: tail, mtime: mtime, size: size}} ->
        # Check first line for sidechain
        first_line = head |> String.split("\n", parts: 2) |> hd()

        if sidechain?(first_line) do
          {:error, :sidechain}
        else
          build_session_info(session_id, head, tail, mtime, size)
        end

      {:error, _} = error ->
        error
    end
  end

  defp build_session_info(session_id, head, tail, mtime, size) do
    custom_title = extract_last_json_string_field(tail, "customTitle")
    first_prompt = extract_first_prompt_from_head(head)
    summary = custom_title || extract_last_json_string_field(tail, "summary") || first_prompt

    # Skip metadata-only sessions (no title, no summary, no prompt)
    if is_nil(summary) or summary == "" do
      {:error, :no_summary}
    else
      git_branch =
        extract_last_json_string_field(tail, "gitBranch") ||
          extract_json_string_field(head, "gitBranch")

      cwd = extract_json_string_field(head, "cwd")

      {:ok,
       %SessionInfo{
         session_id: session_id,
         summary: summary,
         last_modified: mtime,
         file_size: size,
         custom_title: custom_title,
         first_prompt: first_prompt,
         git_branch: git_branch,
         cwd: cwd
       }}
    end
  end

  defp read_lite(path) do
    case :file.open(path, [:read, :binary, :raw]) do
      {:ok, fd} ->
        try do
          read_lite_from_fd(fd, path)
        after
          :file.close(fd)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_lite_from_fd(fd, path) do
    with {:ok, file_info} <- :file.read_file_info(path),
         {:ok, head} when byte_size(head) > 0 <- :file.read(fd, @lite_read_buf_size) do
      size = elem(file_info, 1)
      mtime = file_info_to_epoch_ms(file_info)
      tail = read_tail(fd, head, size)

      {:ok, %{head: head, tail: tail, mtime: mtime, size: size}}
    else
      {:ok, _empty} -> {:error, :empty_file}
      :eof -> {:error, :empty_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp file_info_to_epoch_ms(file_info) do
    mtime_secs = :calendar.datetime_to_gregorian_seconds(elem(file_info, 5))
    unix_epoch = :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
    (mtime_secs - unix_epoch) * 1000
  end

  defp read_tail(_fd, head, size) when size <= @lite_read_buf_size, do: head

  defp read_tail(fd, head, size) do
    tail_offset = max(0, size - @lite_read_buf_size)
    {:ok, _} = :file.position(fd, tail_offset)

    case :file.read(fd, @lite_read_buf_size) do
      {:ok, tail_bytes} -> tail_bytes
      _ -> head
    end
  end

  defp sidechain?(line) do
    String.contains?(line, "\"isSidechain\":true") or
      String.contains?(line, "\"isSidechain\": true")
  end

  @doc false
  # Exposed for testing
  def extract_first_prompt_from_head(head) do
    command_fallback = nil

    head
    |> String.split("\n")
    |> Enum.reduce_while(command_fallback, fn line, cmd_fallback ->
      case extract_prompt_from_line(line, cmd_fallback) do
        {:found, prompt} -> {:halt, {:found, prompt}}
        {:command, new_fallback} -> {:cont, new_fallback}
        :skip -> {:cont, cmd_fallback}
      end
    end)
    |> case do
      {:found, prompt} -> prompt
      nil -> nil
      fallback when is_binary(fallback) -> fallback
    end
  end

  defp extract_prompt_from_line(line, cmd_fallback) do
    if skip_line?(line) do
      :skip
    else
      parse_user_prompt(line, cmd_fallback)
    end
  end

  defp skip_line?(line) do
    not user_type_line?(line) or
      String.contains?(line, "\"tool_result\"") or
      contains_bool_field?(line, "isMeta") or
      contains_bool_field?(line, "isCompactSummary")
  end

  defp user_type_line?(line) do
    String.contains?(line, ~s("type":"user")) or
      String.contains?(line, ~s("type": "user"))
  end

  defp contains_bool_field?(line, field) do
    String.contains?(line, ~s("#{field}":true)) or
      String.contains?(line, ~s("#{field}": true))
  end

  defp parse_user_prompt(line, cmd_fallback) do
    case Jason.decode(line) do
      {:ok, %{"type" => "user", "message" => %{"content" => content}}} ->
        extract_prompt_from_content(content, cmd_fallback)

      _ ->
        :skip
    end
  end

  defp extract_prompt_from_content(content, cmd_fallback) when is_binary(content) do
    check_prompt_text(content, cmd_fallback)
  end

  defp extract_prompt_from_content(content, cmd_fallback) when is_list(content) do
    texts =
      Enum.flat_map(content, fn
        %{"type" => "text", "text" => text} when is_binary(text) -> [text]
        _ -> []
      end)

    texts
    |> Enum.reduce_while(cmd_fallback, fn text, fallback ->
      case check_prompt_text(text, fallback) do
        {:found, _} = found -> {:halt, found}
        {:command, new_fallback} -> {:cont, new_fallback}
        :skip -> {:cont, fallback}
      end
    end)
    |> case do
      {:found, _} = found -> found
      other -> if other == cmd_fallback, do: :skip, else: {:command, other}
    end
  end

  defp extract_prompt_from_content(_content, _cmd_fallback), do: :skip

  defp check_prompt_text(raw, cmd_fallback) do
    result = raw |> String.replace("\n", " ") |> String.trim()

    cond do
      result == "" ->
        :skip

      Regex.match?(@command_name_re, result) ->
        case Regex.run(@command_name_re, result) do
          [_, cmd_name] ->
            new_fallback = if is_nil(cmd_fallback), do: cmd_name, else: cmd_fallback
            {:command, new_fallback}

          _ ->
            :skip
        end

      Regex.match?(@skip_first_prompt_re, result) ->
        :skip

      String.length(result) > 200 ->
        truncated = result |> String.slice(0, 200) |> String.trim_trailing()
        {:found, truncated <> "\u2026"}

      true ->
        {:found, result}
    end
  end

  @doc """
  Extracts the first occurrence of a JSON string field without full parsing.

  Looks for `"key":"value"` or `"key": "value"` patterns.
  """
  @spec extract_json_string_field(String.t(), String.t()) :: String.t() | nil
  def extract_json_string_field(text, key) do
    patterns = [~s("#{key}":"), ~s("#{key}": ")]

    Enum.find_value(patterns, fn pattern ->
      case :binary.match(text, pattern) do
        {pos, len} ->
          value_start = pos + len
          extract_json_string_value(text, value_start)

        :nomatch ->
          nil
      end
    end)
  end

  @doc """
  Extracts the last occurrence of a JSON string field without full parsing.
  """
  @spec extract_last_json_string_field(String.t(), String.t()) :: String.t() | nil
  def extract_last_json_string_field(text, key) do
    patterns = [~s("#{key}":"), ~s("#{key}": ")]

    Enum.reduce(patterns, nil, fn pattern, last_value ->
      find_all_occurrences(text, pattern, 0, last_value)
    end)
  end

  defp find_all_occurrences(text, pattern, search_from, last_value) do
    case :binary.match(text, pattern, [{:scope, {search_from, byte_size(text) - search_from}}]) do
      {pos, len} ->
        value_start = pos + len

        case extract_json_string_value(text, value_start) do
          nil ->
            find_all_occurrences(text, pattern, value_start, last_value)

          value ->
            find_all_occurrences(text, pattern, value_start, value)
        end

      :nomatch ->
        last_value
    end
  end

  defp extract_json_string_value(text, start) do
    text_size = byte_size(text)
    do_extract_json_string_value(text, start, text_size, start)
  end

  defp do_extract_json_string_value(text, pos, text_size, value_start) when pos < text_size do
    case :binary.at(text, pos) do
      ?\\ ->
        do_extract_json_string_value(text, pos + 2, text_size, value_start)

      ?" ->
        raw = binary_part(text, value_start, pos - value_start)
        unescape_json_string(raw)

      _ ->
        do_extract_json_string_value(text, pos + 1, text_size, value_start)
    end
  end

  defp do_extract_json_string_value(_text, _pos, _text_size, _value_start), do: nil

  defp unescape_json_string(raw) do
    if String.contains?(raw, "\\") do
      case Jason.decode(~s("#{raw}")) do
        {:ok, str} when is_binary(str) -> str
        _ -> raw
      end
    else
      raw
    end
  end
end
