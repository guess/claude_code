defmodule ClaudeCode.History do
  @moduledoc """
  Utilities for reading and parsing Claude Code session history files.

  Claude Code stores conversation history in JSONL files at:
  `~/.claude/projects/<encoded-project-path>/<session-id>.jsonl`

  This module provides functions to:
  - Find session files by session ID
  - Read and parse session JSONL files
  - Extract conversation history (user/assistant messages)

  ## Session File Format

  Session files contain various message types:
  - `user` - User messages (prompts and tool results)
  - `assistant` - Assistant responses
  - `system` - System events (errors, etc.)
  - `summary` - Conversation summary
  - `file-history-snapshot` - File tracking metadata
  - `queue-operation` - Internal operations

  ## Examples

      # Read a session by ID
      {:ok, messages} = ClaudeCode.History.read_session("abc123-def456")

      # Get just the conversation (user/assistant messages)
      {:ok, conversation} = ClaudeCode.History.conversation("abc123-def456")

      # Read from a specific file path
      {:ok, messages} = ClaudeCode.History.read_file("/path/to/session.jsonl")

      # Find session file location
      {:ok, path} = ClaudeCode.History.find_session_path("abc123-def456")

  """

  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.UserMessage

  @type session_id :: String.t()
  @type history_entry :: map()
  @type parsed_message :: AssistantMessage.t() | UserMessage.t() | map()

  @claude_dir Path.expand("~/.claude")

  # Message types we parse into SDK structs
  @conversation_types ["user", "assistant"]

  @doc """
  Reads and parses a session file by session ID.

  Searches through all project directories to find the session file.
  Returns all entries from the session file, including metadata entries.

  ## Options

  - `:project_path` - Specific project path to search in (optional)
  - `:claude_dir` - Override the Claude directory (default: `~/.claude`)

  ## Examples

      {:ok, messages} = ClaudeCode.History.read_session("abc123-def456")

      # Search in a specific project
      {:ok, messages} = ClaudeCode.History.read_session("abc123", project_path: "/my/project")

  """
  @spec read_session(session_id(), keyword()) :: {:ok, [history_entry()]} | {:error, term()}
  def read_session(session_id, opts \\ []) do
    case find_session_path(session_id, opts) do
      {:ok, path} -> read_file(path)
      {:error, _} = error -> error
    end
  end

  @doc """
  Reads and parses a session JSONL file from a specific path.

  Returns all entries from the file as maps with normalized keys.

  ## Examples

      {:ok, entries} = ClaudeCode.History.read_file("/path/to/session.jsonl")

  """
  @spec read_file(Path.t()) :: {:ok, [history_entry()]} | {:error, term()}
  def read_file(path) do
    case File.read(path) do
      {:ok, content} ->
        parse_jsonl(content)

      {:error, reason} ->
        {:error, {:file_read_error, reason, path}}
    end
  end

  @doc """
  Extracts the conversation history from a session.

  Returns only user and assistant messages, parsed into SDK message structs.
  Other message types (system events, metadata) are excluded.

  ## Options

  Same as `read_session/2`.

  ## Examples

      {:ok, conversation} = ClaudeCode.History.conversation("abc123-def456")

      # Each message is a UserMessage or AssistantMessage struct
      Enum.each(conversation, fn
        %UserMessage{message: %{content: content}} ->
          IO.puts("User: \#{inspect(content)}")
        %AssistantMessage{message: %{content: content}} ->
          IO.puts("Assistant: \#{inspect(content)}")
      end)

  """
  @spec conversation(session_id(), keyword()) :: {:ok, [parsed_message()]} | {:error, term()}
  def conversation(session_id, opts \\ []) do
    case read_session(session_id, opts) do
      {:ok, entries} ->
        messages =
          entries
          |> Enum.filter(&conversation_message?/1)
          |> Enum.map(&parse_conversation_message/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, msg} -> msg end)

        {:ok, messages}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Extracts the conversation history from a session file path.

  Returns only user and assistant messages, parsed into SDK message structs.

  ## Examples

      {:ok, conversation} = ClaudeCode.History.conversation_from_file("/path/to/session.jsonl")

  """
  @spec conversation_from_file(Path.t()) :: {:ok, [parsed_message()]} | {:error, term()}
  def conversation_from_file(path) do
    case read_file(path) do
      {:ok, entries} ->
        messages =
          entries
          |> Enum.filter(&conversation_message?/1)
          |> Enum.map(&parse_conversation_message/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, msg} -> msg end)

        {:ok, messages}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets the conversation summary from a session, if available.

  Returns the summary text or nil if no summary exists.

  ## Examples

      {:ok, "User asked about..."} = ClaudeCode.History.summary("abc123-def456")
      {:ok, nil} = ClaudeCode.History.summary("new-session-id")

  """
  @spec summary(session_id(), keyword()) :: {:ok, String.t() | nil} | {:error, term()}
  def summary(session_id, opts \\ []) do
    case read_session(session_id, opts) do
      {:ok, entries} ->
        summary =
          entries
          |> Enum.find(&match?(%{"type" => "summary"}, &1))
          |> case do
            %{"summary" => text} -> text
            _ -> nil
          end

        {:ok, summary}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Finds the file path for a session ID.

  Searches through all project directories in `~/.claude/projects/`.

  ## Options

  - `:project_path` - Specific project path to search in (optional)
  - `:claude_dir` - Override the Claude directory (default: `~/.claude`)

  ## Examples

      {:ok, "/Users/me/.claude/projects/-my-project/abc123.jsonl"} =
        ClaudeCode.History.find_session_path("abc123")

      {:error, {:session_not_found, "abc123"}} =
        ClaudeCode.History.find_session_path("nonexistent")

  """
  @spec find_session_path(session_id(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def find_session_path(session_id, opts \\ []) do
    claude_dir = Keyword.get(opts, :claude_dir, @claude_dir)
    projects_dir = Path.join(claude_dir, "projects")

    case Keyword.get(opts, :project_path) do
      nil ->
        # Search all project directories
        search_all_projects(projects_dir, session_id)

      project_path ->
        # Search specific project
        encoded = encode_project_path(project_path)
        project_dir = Path.join(projects_dir, encoded)
        search_project_dir(project_dir, session_id)
    end
  end

  @doc """
  Lists all session IDs for a project.

  ## Options

  - `:claude_dir` - Override the Claude directory (default: `~/.claude`)

  ## Examples

      {:ok, ["abc123", "def456"]} = ClaudeCode.History.list_sessions("/my/project")

  """
  @spec list_sessions(Path.t(), keyword()) :: {:ok, [session_id()]} | {:error, term()}
  def list_sessions(project_path, opts \\ []) do
    claude_dir = Keyword.get(opts, :claude_dir, @claude_dir)
    projects_dir = Path.join(claude_dir, "projects")
    encoded = encode_project_path(project_path)
    project_dir = Path.join(projects_dir, encoded)

    case File.ls(project_dir) do
      {:ok, files} ->
        session_ids =
          files
          |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
          |> Enum.map(&String.trim_trailing(&1, ".jsonl"))
          |> Enum.sort()

        {:ok, session_ids}

      {:error, reason} ->
        {:error, {:project_not_found, reason, project_path}}
    end
  end

  @doc """
  Lists all projects that have session history.

  ## Options

  - `:claude_dir` - Override the Claude directory (default: `~/.claude`)

  ## Examples

      {:ok, ["/Users/me/project1", "/Users/me/project2"]} =
        ClaudeCode.History.list_projects()

  """
  @spec list_projects(keyword()) :: {:ok, [Path.t()]} | {:error, term()}
  def list_projects(opts \\ []) do
    claude_dir = Keyword.get(opts, :claude_dir, @claude_dir)
    projects_dir = Path.join(claude_dir, "projects")

    case File.ls(projects_dir) do
      {:ok, dirs} ->
        paths =
          dirs
          |> Enum.filter(&File.dir?(Path.join(projects_dir, &1)))
          |> Enum.map(&decode_project_path/1)
          |> Enum.sort()

        {:ok, paths}

      {:error, reason} ->
        {:error, {:projects_dir_error, reason}}
    end
  end

  @doc """
  Encodes a project path to the format used by Claude Code.

  Replaces `/` and `_` with `-` in the path to match the CLI's encoding.

  ## Examples

      iex> ClaudeCode.History.encode_project_path("/Users/me/project")
      "-Users-me-project"

      iex> ClaudeCode.History.encode_project_path("/Users/me/my_project")
      "-Users-me-my-project"

  """
  @spec encode_project_path(Path.t()) :: String.t()
  def encode_project_path(path) do
    path
    |> Path.expand()
    |> String.replace(~r"[/_]", "-")
  end

  @doc """
  Decodes an encoded project path back to a path format.

  Replaces `-` with `/`. Note that this encoding is lossy - if the original
  path contained `-` or `_` characters, they cannot be distinguished from path
  separators. For example, `/a/b-c`, `/a/b_c`, and `/a/b/c` all encode to `-a-b-c`.

  This function is primarily useful for display purposes. For matching against
  known paths, use `encode_project_path/1` instead.

  ## Examples

      iex> ClaudeCode.History.decode_project_path("-Users-me-project")
      "/Users/me/project"

  """
  @spec decode_project_path(String.t()) :: Path.t()
  def decode_project_path(encoded) do
    String.replace(encoded, "-", "/")
  end

  # Private functions

  defp search_all_projects(projects_dir, session_id) do
    case File.ls(projects_dir) do
      {:ok, dirs} ->
        result =
          dirs
          |> Enum.filter(&File.dir?(Path.join(projects_dir, &1)))
          |> Enum.find_value(fn dir ->
            project_dir = Path.join(projects_dir, dir)

            case search_project_dir(project_dir, session_id) do
              {:ok, path} -> {:ok, path}
              _ -> nil
            end
          end)

        case result do
          {:ok, _} = success -> success
          nil -> {:error, {:session_not_found, session_id}}
        end

      {:error, reason} ->
        {:error, {:projects_dir_error, reason}}
    end
  end

  defp search_project_dir(project_dir, session_id) do
    direct_path = Path.join(project_dir, "#{session_id}.jsonl")

    if File.exists?(direct_path) do
      {:ok, direct_path}
    else
      search_subagents_dir(project_dir, session_id)
    end
  end

  defp search_subagents_dir(project_dir, session_id) do
    subagents_dir = Path.join([project_dir, session_id, "subagents"])

    with true <- File.dir?(subagents_dir),
         {:ok, files} <- File.ls(subagents_dir),
         file when not is_nil(file) <- Enum.find(files, &String.ends_with?(&1, ".jsonl")) do
      {:ok, Path.join(subagents_dir, file)}
    else
      _ -> {:error, {:session_not_found, session_id}}
    end
  end

  defp parse_jsonl(content) do
    entries =
      content
      |> String.split("\n", trim: true)
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {line, index}, {:ok, acc} ->
        case Jason.decode(line) do
          {:ok, json} ->
            normalized = normalize_keys(json)
            {:cont, {:ok, [normalized | acc]}}

          {:error, error} ->
            {:halt, {:error, {:json_decode_error, index, error}}}
        end
      end)

    case entries do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      normalized_key = normalize_key(key)
      normalized_value = normalize_keys(value)
      {normalized_key, normalized_value}
    end)
  end

  defp normalize_keys(list) when is_list(list) do
    Enum.map(list, &normalize_keys/1)
  end

  defp normalize_keys(value), do: value

  # Convert camelCase keys to snake_case for consistency with SDK
  defp normalize_key("sessionId"), do: "session_id"
  defp normalize_key("parentUuid"), do: "parent_uuid"
  defp normalize_key("isSidechain"), do: "is_sidechain"
  defp normalize_key("userType"), do: "user_type"
  defp normalize_key("gitBranch"), do: "git_branch"
  defp normalize_key("toolUseResult"), do: "tool_use_result"
  defp normalize_key("requestId"), do: "request_id"
  defp normalize_key("stopReason"), do: "stop_reason"
  defp normalize_key("stopSequence"), do: "stop_sequence"
  defp normalize_key("inputTokens"), do: "input_tokens"
  defp normalize_key("outputTokens"), do: "output_tokens"
  defp normalize_key(key), do: key

  defp conversation_message?(%{"type" => type}) when type in @conversation_types, do: true
  defp conversation_message?(_), do: false

  defp parse_conversation_message(%{"type" => "user"} = entry) do
    UserMessage.new(entry)
  end

  defp parse_conversation_message(%{"type" => "assistant"} = entry) do
    AssistantMessage.new(entry)
  end
end
