defmodule ClaudeCode.Options do
  @moduledoc """
  Handles option validation and CLI flag conversion.

  This module is the **single source of truth** for all ClaudeCode options.
  It provides validation for session and query options using NimbleOptions,
  converts Elixir options to CLI flags, and manages option precedence:
  query > session > app config > environment variables > defaults.

  ## Session Options

  Session options are used when starting a ClaudeCode session. Most options
  can be overridden at the query level.

  ### API Key
  - `:api_key` - Anthropic API key (string, optional - falls back to ANTHROPIC_API_KEY env var)

  ### Claude Configuration
  - `:model` - Claude model to use (string, optional - CLI uses its default)
  - `:fallback_model` - Fallback model if primary fails (string, optional)
  - `:system_prompt` - Override system prompt (string, optional)
  - `:append_system_prompt` - Append to system prompt (string, optional)
  - `:max_turns` - Limit agentic turns in non-interactive mode (integer, optional)
  - `:max_budget_usd` - Maximum dollar amount to spend on API calls (number, optional)
  - `:agent` - Agent name for the session (string, optional)
    Overrides the 'agent' setting. Different from `:agents` which defines custom agents.
  - `:betas` - Beta headers to include in API requests (list of strings, optional)
    Example: `["feature-x", "feature-y"]`

  ### Tool Control
  - `:tools` - Specify the list of available tools from the built-in set (optional)
    Use `:default` for all tools, `[]` to disable all, or a list of tool names.
    Example: `tools: :default` or `tools: ["Bash", "Edit", "Read"]`
  - `:allowed_tools` - List of allowed tools (list of strings, optional)
    Example: `["View", "Bash(git:*)"]`
  - `:disallowed_tools` - List of denied tools (list of strings, optional)
  - `:add_dir` - Additional directories for tool access (list of strings, optional)
    Example: `["/tmp", "/var/log"]`

  ### Advanced Options
  - `:agents` - Custom agent definitions (map, optional)
    Map of agent name to agent configuration. Each agent must have `description` and `prompt`.
    Example: `%{"code-reviewer" => %{"description" => "Reviews code", "prompt" => "You are a code reviewer", "tools" => ["Read", "Edit"], "model" => "sonnet"}}`
  - `:mcp_config` - Path to MCP servers JSON config file (string, optional)
  - `:mcp_servers` - MCP server configurations as a map (map, optional)
    Values can be a Hermes MCP module (atom), a module map with custom env, or a command config map.
    Example: `%{"my-tools" => MyApp.MCPServer, "custom" => %{module: MyApp.MCPServer, env: %{"DEBUG" => "1"}}, "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}}`
  - `:permission_prompt_tool` - MCP tool for handling permission prompts (string, optional)
  - `:permission_mode` - Permission handling mode (atom, default: :default)
    Options: `:default`, `:accept_edits`, `:bypass_permissions`
  - `:output_format` - Output format (string, optional)
    Options: `"text"`, `"json"`, `"stream-json"`
  - `:json_schema` - JSON Schema for structured output validation (string or map, optional)
    When provided as a map, it will be JSON encoded automatically.
    Example: `%{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"]}`
  - `:settings` - Settings configuration (string or map, optional)
    Can be a file path, JSON string, or map that will be JSON encoded
    Example: `%{"feature" => true}` or `"/path/to/settings.json"`
  - `:setting_sources` - List of setting sources to load (list of strings, optional)
    Valid sources: `"user"`, `"project"`, `"local"`
    Example: `["user", "project", "local"]`

  ### Elixir-Specific Options
  - `:name` - GenServer process name (atom, optional)
  - `:timeout` - Query timeout in milliseconds (timeout, default: 300_000) - **Elixir only, not passed to CLI**
  - `:resume` - Session ID to resume a previous conversation (string, optional)
  - `:tool_callback` - Post-execution callback for tool monitoring (function, optional)
    Receives a map with `:name`, `:input`, `:result`, `:is_error`, `:tool_use_id`, `:timestamp`
  - `:cwd` - Current working directory (string, optional)

  ## Query Options

  Query options can override session defaults for individual queries.
  All session options except `:api_key` and `:name` can be used as query options.

  ## Option Precedence

  Options are resolved in this order (highest to lowest priority):
  1. Query-level options
  2. Session-level options
  3. Application configuration
  4. Environment variables (ANTHROPIC_API_KEY for api_key)
  5. Schema defaults

  ## Usage Examples

      # Session with comprehensive options
      {:ok, session} = ClaudeCode.start_link(
        api_key: "sk-ant-...",
        model: "opus",
        fallback_model: "sonnet",
        system_prompt: "You are an Elixir expert",
        allowed_tools: ["View", "Edit", "Bash(git:*)"],
        add_dir: ["/tmp", "/var/log"],
        max_turns: 20,
        timeout: 180_000,
        permission_mode: :default
      )

      # Query with option overrides
      ClaudeCode.query(session, "Help with testing",
        system_prompt: "Focus on ExUnit patterns",
        allowed_tools: ["View"],
        timeout: 60_000
      )

      # Application configuration
      # config/config.exs
      config :claude_code,
        model: "sonnet",
        timeout: 120_000,
        allowed_tools: ["View", "Edit"]

      # Session with MCP servers configured inline
      {:ok, session} = ClaudeCode.start_link(
        mcp_servers: %{
          # Hermes MCP server module - auto-generates stdio config
          "my-tools" => MyApp.MCPServer,
          # Hermes module with custom environment variables
          "my-tools-debug" => %{module: MyApp.MCPServer, env: %{"DEBUG" => "1"}},
          # Explicit command config for external MCP servers
          "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}
        }
      )

  ## Security Considerations

  - **`:permission_mode`**: Controls permission handling behavior.
    Use `:bypass_permissions` only in development environments.
  - **`:add_dir`**: Grants tool access to additional directories.
    Only include safe directories.
  - **`:allowed_tools`**: Use tool restrictions to limit Claude's capabilities.
    Example: `["View", "Bash(git:*)"]` allows read-only operations and git commands.
  """

  @session_opts_schema [
    # Elixir-specific options
    api_key: [type: :string, doc: "Anthropic API key"],
    name: [type: :atom, doc: "Process name for the session"],
    timeout: [type: :timeout, default: 300_000, doc: "Query timeout in ms"],
    resume: [type: :string, doc: "Session ID to resume a previous conversation"],
    tool_callback: [
      type: {:fun, 1},
      doc: """
      Optional callback invoked after each tool execution.

      Receives a map with:
      - `:name` - Tool name (string)
      - `:input` - Tool input (map)
      - `:result` - Tool result (string)
      - `:is_error` - Whether the tool errored (boolean)
      - `:tool_use_id` - Unique ID for correlation (string)
      - `:timestamp` - When the result was received (DateTime)

      The callback is invoked asynchronously and should not block.

      Example:
          tool_callback: fn event ->
            Logger.info("Tool \#{event.name} executed")
          end
      """
    ],

    # CLI options (aligned with TypeScript SDK)
    model: [type: :string, doc: "Model to use"],
    fallback_model: [type: :string, doc: "Fallback model to use if primary model fails"],
    cwd: [type: :string, doc: "Current working directory"],
    system_prompt: [type: :string, doc: "Override system prompt"],
    append_system_prompt: [type: :string, doc: "Append to system prompt"],
    max_turns: [type: :integer, doc: "Limit agentic turns in non-interactive mode"],
    max_budget_usd: [type: {:or, [:float, :integer]}, doc: "Maximum dollar amount to spend on API calls"],
    agent: [type: :string, doc: "Agent name for the session (overrides 'agent' setting)"],
    betas: [type: {:list, :string}, doc: "Beta headers to include in API requests"],
    tools: [
      type: {:or, [{:in, [:default]}, {:list, :string}]},
      doc: "Available tools: :default for all, [] for none, or list of tool names"
    ],
    allowed_tools: [type: {:list, :string}, doc: ~s{List of allowed tools (e.g. ["View", "Bash(git:*)"])}],
    disallowed_tools: [type: {:list, :string}, doc: "List of denied tools"],
    agents: [
      type: {:map, :string, {:map, :string, :any}},
      doc:
        "Custom agent definitions. Map of agent name to config with 'description', 'prompt', 'tools' (optional), 'model' (optional)"
    ],
    mcp_config: [type: :string, doc: "Path to MCP servers JSON config file"],
    mcp_servers: [
      type: {:map, :string, {:or, [:atom, :map]}},
      doc:
        ~s(MCP server configurations. Values can be a Hermes module atom or a config map. Example: %{"my-tools" => MyApp.MCPServer, "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}})
    ],
    permission_prompt_tool: [type: :string, doc: "MCP tool for handling permission prompts"],
    permission_mode: [
      type: {:in, [:default, :accept_edits, :bypass_permissions]},
      default: :default,
      doc: "Permission handling mode"
    ],
    add_dir: [type: {:list, :string}, doc: "Additional directories for tool access"],
    output_format: [type: :string, doc: "Output format (text, json, stream-json)"],
    json_schema: [
      type: {:or, [:string, {:map, :string, :any}]},
      doc: "JSON Schema for structured output validation (JSON string or map)"
    ],
    settings: [
      type: {:or, [:string, {:map, :string, :any}]},
      doc: "Settings as file path, JSON string, or map to be JSON encoded"
    ],
    setting_sources: [
      type: {:list, :string},
      doc: "List of setting sources to load (user, project, local)"
    ],
    include_partial_messages: [
      type: :boolean,
      default: false,
      doc: "Include partial message chunks as they arrive for character-level streaming"
    ],
    input_format: [
      type: {:in, [:text, :stream_json]},
      doc: "Input format for streaming mode (:text or :stream_json)"
    ]
  ]

  @query_opts_schema [
    # Query-level overrides for CLI options
    model: [type: :string, doc: "Override model for this query"],
    fallback_model: [type: :string, doc: "Override fallback model for this query"],
    system_prompt: [type: :string, doc: "Override system prompt for this query"],
    append_system_prompt: [type: :string, doc: "Append to system prompt for this query"],
    max_turns: [type: :integer, doc: "Override max turns for this query"],
    max_budget_usd: [type: {:or, [:float, :integer]}, doc: "Override max budget for this query"],
    agent: [type: :string, doc: "Override agent for this query"],
    betas: [type: {:list, :string}, doc: "Override beta headers for this query"],
    tools: [
      type: {:or, [{:in, [:default]}, {:list, :string}]},
      doc: "Override available tools: :default for all, [] for none, or list"
    ],
    allowed_tools: [type: {:list, :string}, doc: "Override allowed tools for this query"],
    disallowed_tools: [type: {:list, :string}, doc: "Override disallowed tools for this query"],
    agents: [
      type: {:map, :string, :map},
      doc: "Override agent definitions for this query"
    ],
    mcp_servers: [
      type: {:map, :string, {:or, [:atom, :map]}},
      doc: "Override MCP server configurations for this query"
    ],
    cwd: [type: :string, doc: "Override working directory for this query"],
    timeout: [type: :timeout, doc: "Override timeout for this query"],
    permission_mode: [
      type: {:in, [:default, :accept_edits, :bypass_permissions]},
      doc: "Override permission mode for this query"
    ],
    add_dir: [type: {:list, :string}, doc: "Override additional directories for this query"],
    output_format: [type: :string, doc: "Override output format for this query"],
    json_schema: [
      type: {:or, [:string, {:map, :string, :any}]},
      doc: "JSON Schema for structured output validation (JSON string or map)"
    ],
    settings: [
      type: {:or, [:string, {:map, :string, :any}]},
      doc: "Override settings for this query (file path, JSON string, or map)"
    ],
    setting_sources: [
      type: {:list, :string},
      doc: "Override setting sources for this query (user, project, local)"
    ],
    include_partial_messages: [
      type: :boolean,
      doc: "Include partial message chunks as they arrive for character-level streaming"
    ],
    input_format: [
      type: {:in, [:text, :stream_json]},
      doc: "Override input format for this query (:text or :stream_json)"
    ]
  ]

  # App config uses same option names directly - no mapping needed

  @doc """
  Returns the session options schema.
  """
  def session_schema, do: @session_opts_schema

  @doc """
  Returns the query options schema.
  """
  def query_schema, do: @query_opts_schema

  @doc """
  Validates session options using NimbleOptions.

  The CLI will handle API key resolution from the environment if not provided.

  ## Examples

      iex> ClaudeCode.Options.validate_session_options([api_key: "sk-test"])
      {:ok, [api_key: "sk-test", timeout: 300_000]}

      iex> ClaudeCode.Options.validate_session_options([])
      {:ok, [timeout: 300_000]}
  """
  def validate_session_options(opts) do
    validated = NimbleOptions.validate!(opts, @session_opts_schema)
    {:ok, validated}
  rescue
    e in NimbleOptions.ValidationError ->
      {:error, e}
  end

  @doc """
  Validates query options using NimbleOptions.

  ## Examples

      iex> ClaudeCode.Options.validate_query_options([timeout: 60_000])
      {:ok, [timeout: 60_000]}

      iex> ClaudeCode.Options.validate_query_options([invalid: "option"])
      {:error, %NimbleOptions.ValidationError{}}
  """
  def validate_query_options(opts) do
    validated = NimbleOptions.validate!(opts, @query_opts_schema)
    {:ok, validated}
  rescue
    e in NimbleOptions.ValidationError ->
      {:error, e}
  end

  @doc """
  Converts Elixir options to CLI arguments.

  Ignores internal options like :api_key, :name, and :timeout that are not CLI flags.

  ## Examples

      iex> ClaudeCode.Options.to_cli_args([system_prompt: "You are helpful"])
      ["--system-prompt", "You are helpful"]

      iex> ClaudeCode.Options.to_cli_args([allowed_tools: ["View", "Bash(git:*)"]])
      ["--allowedTools", "View,Bash(git:*)"]
  """
  def to_cli_args(opts) do
    opts
    |> Enum.reduce([], fn {key, value}, acc ->
      case convert_option_to_cli_flag(key, value) do
        {flag, flag_value} -> [flag_value, flag | acc]
        # Handle multiple flag entries (like add_dir)
        flag_entries when is_list(flag_entries) -> flag_entries ++ acc
        nil -> acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Merges session and query options with query taking precedence.

  ## Examples

      iex> session_opts = [timeout: 60_000, model: "sonnet"]
      iex> query_opts = [timeout: 120_000]
      iex> ClaudeCode.Options.merge_options(session_opts, query_opts)
      [model: "sonnet", timeout: 120_000]
  """
  def merge_options(session_opts, query_opts) do
    Keyword.merge(session_opts, query_opts)
  end

  @doc """
  Gets application configuration for claude_code.

  Returns only valid option keys from the session schema.
  """
  def get_app_config do
    valid_keys = @session_opts_schema |> Keyword.keys() |> MapSet.new()

    :claude_code
    |> Application.get_all_env()
    |> Enum.filter(fn {key, _value} -> MapSet.member?(valid_keys, key) end)
  end

  @doc """
  Applies application config defaults to session options.

  Session options take precedence over app config.
  """
  def apply_app_config_defaults(session_opts) do
    app_config = get_app_config()

    # Apply app config first, then session opts
    Keyword.merge(app_config, session_opts)
  end

  # Private functions

  defp convert_option_to_cli_flag(:api_key, _value), do: nil
  defp convert_option_to_cli_flag(:name, _value), do: nil
  defp convert_option_to_cli_flag(:timeout, _value), do: nil
  defp convert_option_to_cli_flag(:tool_callback, _value), do: nil
  defp convert_option_to_cli_flag(:resume, _value), do: nil
  defp convert_option_to_cli_flag(_key, nil), do: nil

  # TypeScript SDK aligned options
  defp convert_option_to_cli_flag(:system_prompt, value) do
    {"--system-prompt", to_string(value)}
  end

  defp convert_option_to_cli_flag(:append_system_prompt, value) do
    {"--append-system-prompt", to_string(value)}
  end

  defp convert_option_to_cli_flag(:max_turns, value) do
    {"--max-turns", to_string(value)}
  end

  defp convert_option_to_cli_flag(:max_budget_usd, value) do
    {"--max-budget-usd", to_string(value)}
  end

  defp convert_option_to_cli_flag(:agent, value) do
    {"--agent", to_string(value)}
  end

  defp convert_option_to_cli_flag(:betas, value) when is_list(value) do
    if value == [] do
      nil
    else
      Enum.flat_map(value, fn beta -> ["--betas", to_string(beta)] end)
    end
  end

  defp convert_option_to_cli_flag(:tools, :default) do
    {"--tools", "default"}
  end

  defp convert_option_to_cli_flag(:tools, value) when is_list(value) do
    tools_csv = Enum.join(value, ",")
    {"--tools", tools_csv}
  end

  defp convert_option_to_cli_flag(:allowed_tools, value) when is_list(value) do
    tools_csv = Enum.join(value, ",")
    {"--allowedTools", tools_csv}
  end

  defp convert_option_to_cli_flag(:disallowed_tools, value) when is_list(value) do
    tools_csv = Enum.join(value, ",")
    {"--disallowedTools", tools_csv}
  end

  defp convert_option_to_cli_flag(:cwd, _value) do
    # cwd is handled internally by changing working directory when spawning CLI process
    # It's not passed as a CLI flag since the CLI doesn't support --cwd
    nil
  end

  defp convert_option_to_cli_flag(:mcp_config, value) do
    {"--mcp-config", to_string(value)}
  end

  defp convert_option_to_cli_flag(:permission_prompt_tool, value) do
    {"--permission-prompt-tool", to_string(value)}
  end

  defp convert_option_to_cli_flag(:model, value) do
    {"--model", to_string(value)}
  end

  defp convert_option_to_cli_flag(:fallback_model, value) do
    {"--fallback-model", to_string(value)}
  end

  defp convert_option_to_cli_flag(:permission_mode, :default), do: nil

  defp convert_option_to_cli_flag(:permission_mode, :accept_edits) do
    {"--permission-mode", "acceptEdits"}
  end

  defp convert_option_to_cli_flag(:permission_mode, :bypass_permissions) do
    {"--permission-mode", "bypassPermissions"}
  end

  defp convert_option_to_cli_flag(:add_dir, value) when is_list(value) do
    if value == [] do
      nil
    else
      # Return a flat list of alternating flags and values
      Enum.flat_map(value, fn dir -> ["--add-dir", to_string(dir)] end)
    end
  end

  defp convert_option_to_cli_flag(:output_format, value) do
    {"--output-format", to_string(value)}
  end

  defp convert_option_to_cli_flag(:json_schema, value) when is_map(value) do
    json_string = Jason.encode!(value)
    {"--json-schema", json_string}
  end

  defp convert_option_to_cli_flag(:json_schema, value) do
    {"--json-schema", to_string(value)}
  end

  defp convert_option_to_cli_flag(:settings, value) when is_map(value) do
    json_string = Jason.encode!(value)
    {"--settings", json_string}
  end

  defp convert_option_to_cli_flag(:settings, value) do
    {"--settings", to_string(value)}
  end

  defp convert_option_to_cli_flag(:setting_sources, value) when is_list(value) do
    sources_csv = Enum.join(value, ",")
    {"--setting-sources", sources_csv}
  end

  defp convert_option_to_cli_flag(:agents, value) when is_map(value) do
    json_string = Jason.encode!(value)
    {"--agents", json_string}
  end

  defp convert_option_to_cli_flag(:mcp_servers, value) when is_map(value) do
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

    json_string = Jason.encode!(expanded)
    {"--mcp-servers", json_string}
  end

  defp convert_option_to_cli_flag(:include_partial_messages, true) do
    # Boolean flag without value - return as list to be flattened
    ["--include-partial-messages"]
  end

  defp convert_option_to_cli_flag(:include_partial_messages, false), do: nil

  defp convert_option_to_cli_flag(:input_format, :text) do
    {"--input-format", "text"}
  end

  defp convert_option_to_cli_flag(:input_format, :stream_json) do
    {"--input-format", "stream-json"}
  end

  defp convert_option_to_cli_flag(key, value) do
    # Convert unknown keys to kebab-case flags
    flag_name = "--" <> (key |> to_string() |> String.replace("_", "-"))
    {flag_name, to_string(value)}
  end

  # Private helpers

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
