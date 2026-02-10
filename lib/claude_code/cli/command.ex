defmodule ClaudeCode.CLI.Command do
  @moduledoc """
  Builds CLI command arguments from validated options.

  This module is the CLI protocol layer responsible for:
  - Converting Elixir options to CLI flags (`to_cli_args/1`)
  - Assembling the full argument list for a CLI invocation (`build_args/3`)

  It is used by `ClaudeCode.Adapter.Local` for local subprocess management.
  """

  @required_flags ["--output-format", "stream-json", "--verbose", "--print"]

  @doc """
  Builds the full argument list for a CLI invocation.

  Combines required flags, optional `--resume` flag, option-derived CLI flags,
  and the prompt into a single flat list of strings.

  ## Parameters

    * `prompt` - The user prompt string (appended as the final argument)
    * `opts`   - Validated option keyword list
    * `session_id` - Optional session ID for `--resume` (nil to omit)

  ## Examples

      iex> ClaudeCode.CLI.Command.build_args("hello", [model: "opus"], nil)
      ["--output-format", "stream-json", "--verbose", "--print", "--model", "opus", "hello"]

      iex> ClaudeCode.CLI.Command.build_args("hello", [], "sess-123")
      ["--output-format", "stream-json", "--verbose", "--print", "--resume", "sess-123", "hello"]
  """
  @spec build_args(String.t(), keyword(), String.t() | nil) :: [String.t()]
  def build_args(prompt, opts, session_id) do
    resume_args = if session_id, do: ["--resume", session_id], else: []
    option_args = to_cli_args(opts)

    @required_flags ++ resume_args ++ option_args ++ [prompt]
  end

  @doc """
  Converts Elixir options to CLI arguments.

  Ignores internal options like :api_key, :name, and :timeout that are not CLI flags.

  ## Examples

      iex> ClaudeCode.CLI.Command.to_cli_args([system_prompt: "You are helpful"])
      ["--system-prompt", "You are helpful"]

      iex> ClaudeCode.CLI.Command.to_cli_args([allowed_tools: ["View", "Bash(git:*)"]])
      ["--allowedTools", "View,Bash(git:*)"]
  """
  @spec to_cli_args(keyword()) :: [String.t()]
  def to_cli_args(opts) do
    opts
    |> preprocess_sandbox()
    |> Enum.reduce([], fn {key, value}, acc ->
      case convert_option(key, value) do
        {flag, flag_value} -> [flag_value, flag | acc]
        # Handle multiple flag entries (like add_dir)
        flag_entries when is_list(flag_entries) -> flag_entries ++ acc
        nil -> acc
      end
    end)
    |> Enum.reverse(Keyword.get(opts, :extra_args, []))
  end

  # -- Private: option conversion ---------------------------------------------

  defp convert_option(:api_key, _value), do: nil
  defp convert_option(:name, _value), do: nil
  defp convert_option(:timeout, _value), do: nil
  defp convert_option(:tool_callback, _value), do: nil
  # :can_use_tool triggers --permission-prompt-tool stdio; the callback itself
  # is handled by the adapter, not passed as a CLI flag
  defp convert_option(:can_use_tool, nil), do: nil

  defp convert_option(:can_use_tool, _value) do
    {"--permission-prompt-tool", "stdio"}
  end

  defp convert_option(:hooks, _value), do: nil
  defp convert_option(:resume, _value), do: nil
  defp convert_option(:adapter, _value), do: nil
  defp convert_option(:cli_path, _value), do: nil

  defp convert_option(:fork_session, true) do
    # Boolean flag without value - return as list to be flattened
    ["--fork-session"]
  end

  defp convert_option(:fork_session, false), do: nil

  defp convert_option(:continue, true) do
    # Boolean flag without value - return as list to be flattened
    ["--continue"]
  end

  defp convert_option(:continue, false), do: nil

  defp convert_option(_key, nil), do: nil

  # TypeScript SDK aligned options
  defp convert_option(:system_prompt, value) do
    {"--system-prompt", to_string(value)}
  end

  defp convert_option(:append_system_prompt, value) do
    {"--append-system-prompt", to_string(value)}
  end

  defp convert_option(:max_turns, value) do
    {"--max-turns", to_string(value)}
  end

  defp convert_option(:max_budget_usd, value) do
    {"--max-budget-usd", to_string(value)}
  end

  defp convert_option(:max_thinking_tokens, value) do
    {"--max-thinking-tokens", to_string(value)}
  end

  defp convert_option(:agent, value) do
    {"--agent", to_string(value)}
  end

  defp convert_option(:betas, value) when is_list(value) do
    if value == [] do
      nil
    else
      Enum.flat_map(value, fn beta -> ["--betas", to_string(beta)] end)
    end
  end

  defp convert_option(:tools, :default) do
    {"--tools", "default"}
  end

  defp convert_option(:tools, []) do
    # Empty list means no built-in tools - CLI accepts "" to disable all
    {"--tools", ""}
  end

  defp convert_option(:tools, value) when is_list(value) do
    tools_csv = Enum.join(value, ",")
    {"--tools", tools_csv}
  end

  defp convert_option(:allowed_tools, value) when is_list(value) do
    tools_csv = Enum.join(value, ",")
    {"--allowedTools", tools_csv}
  end

  defp convert_option(:disallowed_tools, value) when is_list(value) do
    tools_csv = Enum.join(value, ",")
    {"--disallowedTools", tools_csv}
  end

  defp convert_option(:cwd, _value) do
    # cwd is handled internally by changing working directory when spawning CLI process
    # It's not passed as a CLI flag since the CLI doesn't support --cwd
    nil
  end

  defp convert_option(:mcp_config, value) do
    {"--mcp-config", to_string(value)}
  end

  defp convert_option(:permission_prompt_tool, value) do
    {"--permission-prompt-tool", to_string(value)}
  end

  defp convert_option(:model, value) do
    {"--model", to_string(value)}
  end

  defp convert_option(:fallback_model, value) do
    {"--fallback-model", to_string(value)}
  end

  defp convert_option(:permission_mode, :default) do
    {"--permission-mode", "default"}
  end

  defp convert_option(:permission_mode, :accept_edits) do
    {"--permission-mode", "acceptEdits"}
  end

  defp convert_option(:permission_mode, :bypass_permissions) do
    {"--permission-mode", "bypassPermissions"}
  end

  defp convert_option(:permission_mode, :delegate) do
    {"--permission-mode", "delegate"}
  end

  defp convert_option(:permission_mode, :dont_ask) do
    {"--permission-mode", "dontAsk"}
  end

  defp convert_option(:permission_mode, :plan) do
    {"--permission-mode", "plan"}
  end

  defp convert_option(:add_dir, value) when is_list(value) do
    if value == [] do
      nil
    else
      # Return a flat list of alternating flags and values
      Enum.flat_map(value, fn dir -> ["--add-dir", to_string(dir)] end)
    end
  end

  defp convert_option(:output_format, %{type: :json_schema, schema: schema}) when is_map(schema) do
    json_string = Jason.encode!(schema)
    {"--json-schema", json_string}
  end

  defp convert_option(:output_format, _value), do: nil

  defp convert_option(:settings, value) when is_map(value) do
    json_string = Jason.encode!(value)
    {"--settings", json_string}
  end

  defp convert_option(:settings, value) do
    {"--settings", to_string(value)}
  end

  defp convert_option(:setting_sources, value) when is_list(value) do
    sources_csv = Enum.join(value, ",")
    {"--setting-sources", sources_csv}
  end

  defp convert_option(:plugins, value) when is_list(value) do
    if value == [] do
      nil
    else
      # Extract path from each plugin config (string path or map with type: :local)
      Enum.flat_map(value, fn
        path when is_binary(path) ->
          ["--plugin-dir", path]

        %{type: :local, path: path} ->
          ["--plugin-dir", to_string(path)]

        _other ->
          []
      end)
    end
  end

  # :agents is sent via the control protocol initialize handshake, not as a CLI flag
  defp convert_option(:agents, _value), do: nil

  defp convert_option(:mcp_servers, value) when is_map(value) do
    # Expand any module atoms to their stdio command config
    expanded =
      Map.new(value, fn
        {name, module} when is_atom(module) ->
          {name, expand_hermes_module(module, %{})}

        {name, %{module: module} = config} when is_atom(module) ->
          {name, expand_hermes_module(module, config)}

        {name, %{"module" => module} = config} when is_atom(module) ->
          {name, expand_hermes_module(module, config)}

        {name, config} when is_map(config) ->
          {name, config}
      end)

    # CLI expects mcpServers wrapper format via --mcp-config flag
    json_string = Jason.encode!(%{mcpServers: expanded})
    {"--mcp-config", json_string}
  end

  defp convert_option(:include_partial_messages, true) do
    # Boolean flag without value - return as list to be flattened
    ["--include-partial-messages"]
  end

  defp convert_option(:include_partial_messages, false), do: nil

  defp convert_option(:strict_mcp_config, true) do
    # Boolean flag without value - return as list to be flattened
    ["--strict-mcp-config"]
  end

  defp convert_option(:strict_mcp_config, false), do: nil

  defp convert_option(:allow_dangerously_skip_permissions, true) do
    ["--allow-dangerously-skip-permissions"]
  end

  defp convert_option(:allow_dangerously_skip_permissions, false), do: nil

  defp convert_option(:disable_slash_commands, true) do
    ["--disable-slash-commands"]
  end

  defp convert_option(:disable_slash_commands, false), do: nil

  defp convert_option(:no_session_persistence, true) do
    ["--no-session-persistence"]
  end

  defp convert_option(:no_session_persistence, false), do: nil

  defp convert_option(:session_id, value) do
    {"--session-id", value}
  end

  defp convert_option(:file, value) when is_list(value) do
    if value == [] do
      nil
    else
      Enum.flat_map(value, fn spec -> ["--file", to_string(spec)] end)
    end
  end

  defp convert_option(:from_pr, value) do
    {"--from-pr", to_string(value)}
  end

  defp convert_option(:debug, true), do: ["--debug"]
  defp convert_option(:debug, false), do: nil

  defp convert_option(:debug, value) when is_binary(value) do
    {"--debug", value}
  end

  defp convert_option(:debug_file, value) do
    {"--debug-file", to_string(value)}
  end

  defp convert_option(:input_format, :text) do
    {"--input-format", "text"}
  end

  defp convert_option(:input_format, :stream_json) do
    {"--input-format", "stream-json"}
  end

  # Internal options - not passed as CLI flags
  # :sandbox is preprocessed into :settings; :enable_file_checkpointing is set via env var
  defp convert_option(:sandbox, _value), do: nil
  defp convert_option(:enable_file_checkpointing, _value), do: nil
  defp convert_option(:callers, _value), do: nil
  defp convert_option(:name, _value), do: nil
  defp convert_option(:adapter, _value), do: nil
  defp convert_option(:stub_name, _value), do: nil
  defp convert_option(:env, _value), do: nil
  defp convert_option(:max_buffer_size, _value), do: nil
  defp convert_option(:extra_args, _value), do: nil

  defp convert_option(key, value) do
    # Convert unknown keys to kebab-case flags
    flag_name = "--" <> (key |> to_string() |> String.replace("_", "-"))
    {flag_name, to_string(value)}
  end

  # -- Private: sandbox preprocessing ----------------------------------------

  defp preprocess_sandbox(opts) do
    case Keyword.pop(opts, :sandbox) do
      {nil, opts} ->
        opts

      {sandbox, opts} ->
        merged = merge_sandbox_into_settings(Keyword.get(opts, :settings), sandbox)
        Keyword.put(opts, :settings, merged)
    end
  end

  defp merge_sandbox_into_settings(nil, sandbox), do: %{"sandbox" => sandbox}

  defp merge_sandbox_into_settings(settings, sandbox) when is_map(settings) do
    Map.put(settings, "sandbox", sandbox)
  end

  defp merge_sandbox_into_settings(json_string, sandbox) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, decoded} -> Map.put(decoded, "sandbox", sandbox)
      {:error, _} -> %{"sandbox" => sandbox}
    end
  end

  # -- Private: Hermes MCP module expansion -----------------------------------

  defp expand_hermes_module(module, config) do
    # Generate stdio command config for a Hermes MCP server module
    # This allows the CLI to spawn the Elixir app with the MCP server
    startup_code = "#{inspect(module)}.start_link(transport: :stdio)"

    # Extract custom env from config (supports both atom and string keys)
    custom_env = config[:env] || config["env"] || %{}
    merged_env = Map.merge(%{"MIX_ENV" => "prod"}, custom_env)

    %{
      command: "mix",
      args: ["run", "--no-halt", "-e", startup_code],
      env: merged_env
    }
  end
end
