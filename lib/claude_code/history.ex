defmodule ClaudeCode.History do
  @moduledoc """
  Utilities for reading and parsing Claude Code session history files.

  Claude Code stores conversation history in JSONL files at:
  `~/.claude/projects/<encoded-project-path>/<session-id>.jsonl`

  This module provides functions to:
  - List sessions with rich metadata (`list_sessions/1`)
  - Read and parse session JSONL files
  - Extract conversation history with proper chain building (`get_messages/2`)

  ## Session File Format

  Session files contain various message types:
  - `user` - User messages (prompts and tool results)
  - `assistant` - Assistant responses
  - `system` - System events (errors, etc.)
  - `summary` - Conversation summary
  - `file-history-snapshot` - File tracking metadata
  - `queue-operation` - Internal operations

  ## Examples

      # List sessions with metadata
      {:ok, sessions} = ClaudeCode.History.list_sessions(directory: ".")
      Enum.each(sessions, fn s -> IO.puts("\#{s.summary} (\#{s.session_id})") end)

      # Get messages with proper chain building
      {:ok, messages} = ClaudeCode.History.get_messages("abc123-def456")

      # Read raw session entries
      {:ok, entries} = ClaudeCode.History.read_session("abc123-def456")

  """

  alias ClaudeCode.CLI.Parser
  alias ClaudeCode.History.ConversationChain
  alias ClaudeCode.History.LiteReader
  alias ClaudeCode.History.SessionInfo
  alias ClaudeCode.History.SessionMessage
  alias ClaudeCode.History.Worktree

  @type session_id :: String.t()

  defp default_claude_dir, do: Path.expand("~/.claude")

  # Maximum length for a single filesystem path component.
  @max_sanitized_length 200
  @sanitize_re ~r/[^a-zA-Z0-9]/

  # ============================================================================
  # Session Listing
  # ============================================================================

  @doc """
  Lists sessions with rich metadata extracted from stat + head/tail reads.

  When `:project_path` is provided, returns sessions for that project directory
  (and optionally its git worktrees). When omitted, returns sessions across
  all projects.

  ## Options

  - `:project_path` - Project directory to list sessions for (nil = all projects)
  - `:limit` - Maximum number of sessions to return
  - `:include_worktrees` - Scan git worktrees (default: `true`)
  - `:claude_dir` - Override `~/.claude` (for testing)

  ## Examples

      # List sessions for the current project
      {:ok, sessions} = ClaudeCode.History.list_sessions(project_path: ".")

      # List all sessions across all projects
      {:ok, sessions} = ClaudeCode.History.list_sessions()

      # With limit
      {:ok, recent} = ClaudeCode.History.list_sessions(project_path: ".", limit: 10)

  """
  @spec list_sessions(keyword()) :: {:ok, [SessionInfo.t()]}
  def list_sessions(opts \\ []) do
    directory = Keyword.get(opts, :project_path)
    limit = Keyword.get(opts, :limit)
    include_worktrees = Keyword.get(opts, :include_worktrees, true)

    sessions =
      if directory do
        list_sessions_for_project(directory, limit, include_worktrees, opts)
      else
        list_all_sessions(limit, opts)
      end

    {:ok, sessions}
  end

  # ============================================================================
  # Message Retrieval (Chain-built)
  # ============================================================================

  @doc """
  Reads a session's conversation messages using `parentUuid` chain building.

  Parses the full JSONL, builds the conversation chain via `parentUuid`
  links, and returns visible user/assistant messages in chronological order.

  ## Options

  - `:project_path` - Project directory to find the session in
  - `:limit` - Maximum number of messages to return
  - `:offset` - Number of messages to skip from the start (default: 0)
  - `:claude_dir` - Override `~/.claude` (for testing)

  ## Examples

      {:ok, messages} = ClaudeCode.History.get_messages("abc123-def456")

      # With pagination
      {:ok, page} = ClaudeCode.History.get_messages(session_id, limit: 10, offset: 20)

  """
  @spec get_messages(session_id(), keyword()) :: {:ok, [SessionMessage.t()]} | {:error, term()}
  def get_messages(session_id, opts \\ []) do
    if is_nil(LiteReader.validate_uuid(session_id)) do
      {:ok, []}
    else
      directory = Keyword.get(opts, :project_path)
      limit = Keyword.get(opts, :limit)
      offset = Keyword.get(opts, :offset, 0)

      case read_session_file_content(session_id, directory, opts) do
        nil ->
          {:ok, []}

        content ->
          entries = ConversationChain.parse_entries(content)
          chain = ConversationChain.build(entries)
          visible = ConversationChain.filter_visible(chain)
          messages = Enum.map(visible, &ConversationChain.to_session_message/1)

          result =
            case {limit, offset} do
              {nil, 0} -> messages
              {nil, off} -> Enum.drop(messages, off)
              {lim, 0} -> Enum.take(messages, lim)
              {lim, off} -> messages |> Enum.drop(off) |> Enum.take(lim)
            end

          {:ok, result}
      end
    end
  end

  # ============================================================================
  # Raw Session Reading
  # ============================================================================

  @doc """
  Reads a session JSONL file by session ID and returns all entries as normalized maps.

  Searches through all project directories to find the session file.
  Returns every line as a snake_case string-keyed map, including metadata entries
  (summaries, queue operations, etc.) that have no SDK struct representation.
  Use `get_messages/2` to get properly chain-built conversation messages.

  ## Options

  - `:project_path` - Specific project path to search in (optional)
  - `:claude_dir` - Override the Claude directory (default: `~/.claude`)

  ## Examples

      {:ok, entries} = ClaudeCode.History.read_session("abc123-def456")

      # Search in a specific project
      {:ok, entries} = ClaudeCode.History.read_session("abc123", project_path: "/my/project")

  """
  @spec read_session(session_id(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def read_session(session_id, opts \\ []) do
    with {:ok, path} <- find_session_path(session_id, opts) do
      read_file(path)
    end
  end

  @doc """
  Reads a session JSONL file from a specific path and returns all entries as normalized maps.

  Returns every line as a snake_case string-keyed map, preserving all entry types
  (user, assistant, system, summary, queue operations, etc.). Keys are normalized
  from camelCase to snake_case for consistency with live CLI output.

  ## Examples

      {:ok, entries} = ClaudeCode.History.read_file("/path/to/session.jsonl")

  """
  @spec read_file(Path.t()) :: {:ok, [map()]} | {:error, term()}
  def read_file(path) do
    case File.read(path) do
      {:ok, content} -> decode_jsonl(content)
      {:error, reason} -> {:error, {:file_read_error, reason, path}}
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
    with {:ok, entries} <- read_session(session_id, opts) do
      summary =
        Enum.find_value(entries, fn
          %{"type" => "summary", "summary" => text} -> text
          _ -> nil
        end)

      {:ok, summary}
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
    claude_dir = Keyword.get(opts, :claude_dir, default_claude_dir())
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
  Lists all projects that have session history.

  ## Options

  - `:claude_dir` - Override the Claude directory (default: `~/.claude`)

  ## Examples

      {:ok, ["/Users/me/project1", "/Users/me/project2"]} =
        ClaudeCode.History.list_projects()

  """
  @spec list_projects(keyword()) :: {:ok, [Path.t()]} | {:error, term()}
  def list_projects(opts \\ []) do
    claude_dir = Keyword.get(opts, :claude_dir, default_claude_dir())
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
  Sanitizes a project path matching the Python SDK's `_sanitize_path` behavior.

  Replaces all non-alphanumeric characters with hyphens. For paths exceeding
  200 characters, truncates and appends a hash suffix.

  ## Examples

      iex> ClaudeCode.History.sanitize_path("/Users/me/project")
      "-Users-me-project"

  """
  @spec sanitize_path(Path.t()) :: String.t()
  def sanitize_path(path) do
    sanitized = Regex.replace(@sanitize_re, path, "-")

    if String.length(sanitized) <= @max_sanitized_length do
      sanitized
    else
      hash = simple_hash(path)
      String.slice(sanitized, 0, @max_sanitized_length) <> "-" <> hash
    end
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

  # ============================================================================
  # Private - Session Listing
  # ============================================================================

  defp list_sessions_for_project(directory, limit, include_worktrees, opts) do
    canonical_dir = canonicalize_path(directory)

    worktree_paths =
      if include_worktrees do
        case Worktree.list_paths(canonical_dir) do
          {:ok, paths} -> paths
          _ -> []
        end
      else
        []
      end

    sessions =
      if length(worktree_paths) <= 1 do
        # No worktrees — just scan the single project dir
        case find_project_dir(canonical_dir, opts) do
          nil -> []
          project_dir -> read_sessions_from_dir(project_dir, canonical_dir)
        end
      else
        scan_worktree_dirs(canonical_dir, worktree_paths, opts)
      end

    sessions
    |> deduplicate_by_session_id()
    |> sort_and_limit(limit)
  end

  defp list_all_sessions(limit, opts) do
    claude_dir = Keyword.get(opts, :claude_dir, default_claude_dir())
    projects_dir = Path.join(claude_dir, "projects")

    case File.ls(projects_dir) do
      {:ok, dirs} ->
        dirs
        |> Enum.filter(&File.dir?(Path.join(projects_dir, &1)))
        |> Enum.flat_map(fn dir ->
          project_dir = Path.join(projects_dir, dir)
          read_sessions_from_dir(project_dir, nil)
        end)
        |> deduplicate_by_session_id()
        |> sort_and_limit(limit)

      {:error, _} ->
        []
    end
  end

  defp scan_worktree_dirs(canonical_dir, worktree_paths, opts) do
    claude_dir = Keyword.get(opts, :claude_dir, default_claude_dir())
    projects_dir = Path.join(claude_dir, "projects")

    # Always include the user's actual directory
    seen_dirs = MapSet.new()

    {initial_sessions, seen_dirs} =
      case find_project_dir(canonical_dir, opts) do
        nil ->
          {[], seen_dirs}

        project_dir ->
          dir_name = Path.basename(project_dir)
          sessions = read_sessions_from_dir(project_dir, canonical_dir)
          {sessions, MapSet.put(seen_dirs, dir_name)}
      end

    all_dirents =
      case File.ls(projects_dir) do
        {:ok, dirs} -> Enum.filter(dirs, &File.dir?(Path.join(projects_dir, &1)))
        _ -> []
      end

    # Build indexed worktree prefixes (longest first)
    indexed =
      worktree_paths
      |> Enum.map(fn wt -> {wt, sanitize_path(wt)} end)
      |> Enum.sort_by(fn {_, prefix} -> String.length(prefix) end, :desc)

    {all_sessions, _} =
      Enum.reduce(all_dirents, {initial_sessions, seen_dirs}, fn dir_name, {sessions, seen} ->
        if dir_name in seen do
          {sessions, seen}
        else
          case find_matching_worktree(dir_name, indexed) do
            nil ->
              {sessions, seen}

            wt_path ->
              project_dir = Path.join(projects_dir, dir_name)
              new_sessions = read_sessions_from_dir(project_dir, wt_path)
              {sessions ++ new_sessions, MapSet.put(seen, dir_name)}
          end
        end
      end)

    all_sessions
  end

  defp find_matching_worktree(dir_name, indexed) do
    Enum.find_value(indexed, fn {wt_path, prefix} ->
      is_match =
        dir_name == prefix or
          (String.length(prefix) >= @max_sanitized_length and
             String.starts_with?(dir_name, prefix <> "-"))

      if is_match, do: wt_path
    end)
  end

  defp read_sessions_from_dir(project_dir, project_path) do
    case File.ls(project_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
        |> Enum.flat_map(&read_session_metadata(project_dir, &1, project_path))

      {:error, _} ->
        []
    end
  end

  defp read_session_metadata(project_dir, filename, project_path) do
    path = Path.join(project_dir, filename)

    case LiteReader.read_metadata(path) do
      {:ok, %SessionInfo{} = info} ->
        info = maybe_fill_cwd(info, project_path)
        [info]

      {:error, _} ->
        []
    end
  end

  defp maybe_fill_cwd(%SessionInfo{cwd: nil} = info, project_path) when is_binary(project_path) do
    %{info | cwd: project_path}
  end

  defp maybe_fill_cwd(info, _project_path), do: info

  defp deduplicate_by_session_id(sessions) do
    sessions
    |> Enum.group_by(& &1.session_id)
    |> Enum.map(fn {_id, group} ->
      Enum.max_by(group, & &1.last_modified)
    end)
  end

  defp sort_and_limit(sessions, limit) do
    sorted = Enum.sort_by(sessions, & &1.last_modified, :desc)

    if is_integer(limit) and limit > 0 do
      Enum.take(sorted, limit)
    else
      sorted
    end
  end

  defp find_project_dir(project_path, opts) do
    claude_dir = Keyword.get(opts, :claude_dir, default_claude_dir())
    projects_dir = Path.join(claude_dir, "projects")

    # Try sanitized path first (Python SDK style)
    sanitized = sanitize_path(project_path)
    exact_dir = Path.join(projects_dir, sanitized)

    cond do
      File.dir?(exact_dir) ->
        exact_dir

      String.length(sanitized) > @max_sanitized_length ->
        # Try prefix matching for long paths with hash mismatches
        find_by_prefix(projects_dir, sanitized) ||
          try_old_encoding(projects_dir, project_path)

      true ->
        # Also try the old-style encoding for backward compatibility
        try_old_encoding(projects_dir, project_path)
    end
  end

  defp find_by_prefix(projects_dir, sanitized) do
    prefix = String.slice(sanitized, 0, @max_sanitized_length)

    case File.ls(projects_dir) do
      {:ok, dirs} ->
        Enum.find_value(dirs, fn dir ->
          full = Path.join(projects_dir, dir)
          if File.dir?(full) and String.starts_with?(dir, prefix <> "-"), do: full
        end)

      _ ->
        nil
    end
  end

  defp try_old_encoding(projects_dir, project_path) do
    encoded = encode_project_path(project_path)
    dir = Path.join(projects_dir, encoded)
    if File.dir?(dir), do: dir
  end

  defp canonicalize_path(directory) do
    directory |> Path.expand() |> resolve_symlinks()
  end

  defp resolve_symlinks(path) do
    case :file.read_link_all(String.to_charlist(path)) do
      {:ok, target} -> List.to_string(target)
      _ -> path
    end
  end

  # ============================================================================
  # Private - Message Retrieval
  # ============================================================================

  defp read_session_file_content(session_id, directory, opts) do
    claude_dir = Keyword.get(opts, :claude_dir, default_claude_dir())
    file_name = "#{session_id}.jsonl"

    if directory do
      read_from_project_dir(session_id, directory, file_name, opts) ||
        read_from_worktrees(directory, file_name, opts)
    else
      read_from_all_projects(claude_dir, file_name)
    end
  end

  defp read_from_project_dir(_session_id, directory, file_name, opts) do
    canonical_dir = canonicalize_path(directory)

    case find_project_dir(canonical_dir, opts) do
      nil ->
        nil

      project_dir ->
        path = Path.join(project_dir, file_name)

        case File.read(path) do
          {:ok, content} -> content
          _ -> nil
        end
    end
  end

  defp read_from_worktrees(directory, file_name, opts) do
    canonical_dir = canonicalize_path(directory)

    case Worktree.list_paths(canonical_dir) do
      {:ok, paths} ->
        paths
        |> Enum.reject(&(&1 == canonical_dir))
        |> Enum.find_value(&try_read_from_worktree(&1, file_name, opts))

      _ ->
        nil
    end
  end

  defp try_read_from_worktree(wt_path, file_name, opts) do
    case find_project_dir(wt_path, opts) do
      nil -> nil
      project_dir -> try_read_file(Path.join(project_dir, file_name))
    end
  end

  defp try_read_file(path) do
    case File.read(path) do
      {:ok, content} -> content
      _ -> nil
    end
  end

  defp read_from_all_projects(claude_dir, file_name) do
    projects_dir = Path.join(claude_dir, "projects")

    case File.ls(projects_dir) do
      {:ok, dirs} ->
        Enum.find_value(dirs, fn dir ->
          path = Path.join([projects_dir, dir, file_name])

          case File.read(path) do
            {:ok, content} -> content
            _ -> nil
          end
        end)

      _ ->
        nil
    end
  end

  # ============================================================================
  # Private - Path helpers
  # ============================================================================

  @doc """
  Port of the JS simpleHash function (32-bit integer hash, base36).
  """
  @spec simple_hash(String.t()) :: String.t()
  def simple_hash(s) do
    h =
      s
      |> String.to_charlist()
      |> Enum.reduce(0, fn char, h ->
        h = Bitwise.bsl(h, 5) - h + char
        # Emulate JS `hash |= 0` (coerce to 32-bit signed int)
        <<signed::signed-integer-32>> = <<Bitwise.band(h, 0xFFFFFFFF)::unsigned-integer-32>>
        signed
      end)

    h |> abs() |> Integer.to_string(36) |> String.downcase()
  end

  # ============================================================================
  # Private - Session file search
  # ============================================================================

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

  defp decode_jsonl(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {line, index}, {:ok, acc} ->
      case Jason.decode(line) do
        {:ok, map} -> {:cont, {:ok, [Parser.normalize_keys(map) | acc]}}
        {:error, error} -> {:halt, {:error, {:json_decode_error, index, error}}}
      end
    end)
    |> case do
      {:ok, maps} -> {:ok, Enum.reverse(maps)}
      error -> error
    end
  end
end
