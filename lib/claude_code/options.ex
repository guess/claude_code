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
  - `:max_thinking_tokens` - Maximum tokens for thinking blocks (integer, optional)

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
  - `:strict_mcp_config` - Only use MCP servers from mcp_config/mcp_servers (boolean, default: false)
    When true, ignores all global MCP configurations and only uses explicitly provided MCP config.
  - `:permission_prompt_tool` - MCP tool for handling permission prompts (string, optional)
  - `:permission_mode` - Permission handling mode (atom, default: :default)
    Options: `:default`, `:accept_edits`, `:bypass_permissions`, `:delegate`, `:dont_ask`, `:plan`
  - `:output_format` - Output format for structured outputs (map, optional)
    Must have `:type` key (currently only `:json_schema` supported) and `:schema` key with JSON Schema.
    Example: `%{type: :json_schema, schema: %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}}`
  - `:settings` - Settings configuration (string or map, optional)
    Can be a file path, JSON string, or map that will be JSON encoded
    Example: `%{"feature" => true}` or `"/path/to/settings.json"`
  - `:setting_sources` - List of setting sources to load (list of strings, optional)
    Valid sources: `"user"`, `"project"`, `"local"`
    Example: `["user", "project", "local"]`
  - `:plugins` - Plugin configurations to load (list of maps or strings, optional)
    Each plugin can be a path string or a map with `:type` and `:path` keys.
    Currently only `:local` type is supported.
    Example: `["./my-plugin"]` or `[%{type: :local, path: "./my-plugin"}]`

  ### Elixir-Specific Options
  - `:name` - GenServer process name (atom, optional)
  - `:timeout` - Query timeout in milliseconds (timeout, default: 300_000) - **Elixir only, not passed to CLI**
  - `:cli_path` - CLI binary resolution mode: `:bundled` (default), `:global`, or explicit path string
  - `:resume` - Session ID to resume a previous conversation (string, optional)
  - `:fork_session` - When resuming, create a new session ID instead of reusing the original (boolean, optional)
    Must be used with `:resume`. Creates a fork of the conversation.
  - `:continue` - Continue the most recent conversation in the current directory (boolean, optional)
  - `:tool_callback` - Post-execution callback for tool monitoring (function, optional)
    Receives a map with `:name`, `:input`, `:result`, `:is_error`, `:tool_use_id`, `:timestamp`
  - `:cwd` - Current working directory (string, optional)
  - `:env` - Environment variables to merge with system environment (map of string to string, default: %{})
    User-provided env vars override system vars but are overridden by SDK vars and `:api_key`.
    Example: `%{"MY_VAR" => "value", "PATH" => "/custom/bin:" <> System.get_env("PATH")}`

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
    cli_path: [
      type: {:or, [{:in, [:bundled, :global]}, :string]},
      doc: """
      CLI binary resolution mode.

      - `:bundled` (default) — Use priv/bin/ binary, auto-install if missing, verify version matches SDK's pinned version
      - `:global` — Find existing system install via PATH or common locations, no auto-install
      - `"/path/to/claude"` — Use exact binary path

      Can also be set via application config: `config :claude_code, cli_path: :global`
      """
    ],
    resume: [type: :string, doc: "Session ID to resume a previous conversation"],
    fork_session: [
      type: :boolean,
      default: false,
      doc: "When resuming, create a new session ID instead of reusing the original"
    ],
    continue: [
      type: :boolean,
      default: false,
      doc: "Continue the most recent conversation in the current directory"
    ],
    adapter: [
      type: {:tuple, [:atom, :any]},
      doc: """
      Optional adapter for testing. A tuple of `{module, name}` where:
      - `module` implements the `ClaudeCode.Adapter` behaviour
      - `name` is passed to the adapter's `stream/3` callback

      Example:
          adapter: {ClaudeCode.Test, MyApp.Chat}
      """
    ],
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
    env: [
      type: {:map, :string, :string},
      default: %{},
      doc: """
      Environment variables to merge with system environment when spawning CLI.

      These variables override system environment variables but are overridden by
      SDK-required variables (CLAUDE_CODE_ENTRYPOINT, CLAUDE_CODE_SDK_VERSION) and
      the `:api_key` option (which sets ANTHROPIC_API_KEY).

      Merge precedence (lowest to highest):
      1. System environment variables
      2. User `:env` option (these values)
      3. SDK-required variables
      4. `:api_key` option

      Useful for:
      - MCP tools that need specific env vars
      - Providing PATH or other tool-specific configuration
      - Testing with custom environment

      Example:
          env: %{
            "MY_CUSTOM_VAR" => "value",
            "PATH" => "/custom/bin:" <> System.get_env("PATH")
          }
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
    max_thinking_tokens: [type: :integer, doc: "Maximum tokens for thinking blocks"],
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
    strict_mcp_config: [
      type: :boolean,
      default: false,
      doc: "Only use MCP servers from mcp_config/mcp_servers, ignoring global MCP configurations"
    ],
    permission_prompt_tool: [type: :string, doc: "MCP tool for handling permission prompts"],
    permission_mode: [
      type: {:in, [:default, :accept_edits, :bypass_permissions, :delegate, :dont_ask, :plan]},
      default: :default,
      doc: "Permission handling mode (:default, :accept_edits, :bypass_permissions, :delegate, :dont_ask, :plan)"
    ],
    add_dir: [type: {:list, :string}, doc: "Additional directories for tool access"],
    output_format: [
      type: :map,
      doc: "Output format for structured outputs - map with type: :json_schema and schema keys"
    ],
    settings: [
      type: {:or, [:string, {:map, :string, :any}]},
      doc: "Settings as file path, JSON string, or map to be JSON encoded"
    ],
    setting_sources: [
      type: {:list, :string},
      doc: "List of setting sources to load (user, project, local)"
    ],
    plugins: [
      type: {:list, {:or, [:string, :map]}},
      doc: "Plugin configurations - list of paths or maps with type: :local and path keys"
    ],
    include_partial_messages: [
      type: :boolean,
      default: false,
      doc: "Include partial message chunks as they arrive for character-level streaming"
    ],
    allow_dangerously_skip_permissions: [
      type: :boolean,
      default: false,
      doc:
        "Enable bypassing all permission checks as an option. Required when using permission_mode: :bypass_permissions. Recommended only for sandboxes with no internet access."
    ],
    disable_slash_commands: [
      type: :boolean,
      default: false,
      doc: "Disable all skills/slash commands"
    ],
    no_session_persistence: [
      type: :boolean,
      default: false,
      doc: "Disable session persistence - sessions will not be saved to disk and cannot be resumed"
    ],
    session_id: [
      type: :string,
      doc: "Use a specific session ID for the conversation (must be a valid UUID)"
    ],
    file: [
      type: {:list, :string},
      doc:
        ~s{File resources to download at startup. Format: file_id:relative_path (e.g. ["file_abc:doc.txt", "file_def:img.png"])}
    ],
    from_pr: [
      type: {:or, [:string, :integer]},
      doc: "Resume a session linked to a PR by PR number or URL"
    ],
    debug: [
      type: {:or, [:boolean, :string]},
      doc: ~s{Enable debug mode with optional category filtering (e.g. true or "api,hooks" or "!1p,!file")}
    ],
    debug_file: [
      type: :string,
      doc: "Write debug logs to a specific file path (implicitly enables debug mode)"
    ],
    sandbox: [
      type: {:map, :string, :any},
      doc: "Sandbox settings for bash command isolation (merged into --settings)"
    ],
    enable_file_checkpointing: [
      type: :boolean,
      default: false,
      doc: "Enable file checkpointing to track file changes during the session (set via env var, not CLI flag)"
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
    max_thinking_tokens: [type: :integer, doc: "Override max thinking tokens for this query"],
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
    strict_mcp_config: [
      type: :boolean,
      doc: "Only use MCP servers from mcp_config/mcp_servers, ignoring global MCP configurations"
    ],
    cwd: [type: :string, doc: "Override working directory for this query"],
    timeout: [type: :timeout, doc: "Override timeout for this query"],
    permission_mode: [
      type: {:in, [:default, :accept_edits, :bypass_permissions, :delegate, :dont_ask, :plan]},
      doc: "Override permission mode for this query"
    ],
    add_dir: [type: {:list, :string}, doc: "Override additional directories for this query"],
    output_format: [
      type: :map,
      doc: "Override output format for this query"
    ],
    settings: [
      type: {:or, [:string, {:map, :string, :any}]},
      doc: "Override settings for this query (file path, JSON string, or map)"
    ],
    setting_sources: [
      type: {:list, :string},
      doc: "Override setting sources for this query (user, project, local)"
    ],
    plugins: [
      type: {:list, {:or, [:string, :map]}},
      doc: "Override plugin configurations for this query"
    ],
    include_partial_messages: [
      type: :boolean,
      doc: "Include partial message chunks as they arrive for character-level streaming"
    ],
    disable_slash_commands: [
      type: :boolean,
      doc: "Disable all skills/slash commands for this query"
    ],
    no_session_persistence: [
      type: :boolean,
      doc: "Disable session persistence for this query"
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
  defdelegate to_cli_args(opts), to: ClaudeCode.CLI.Command

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
end
