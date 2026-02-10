defmodule ClaudeCode.Options do
  @moduledoc """
  Option validation, CLI flag conversion, and configuration guide.

  This module is the **single source of truth** for all ClaudeCode options.
  It provides validation for session and query options using NimbleOptions,
  converts Elixir options to CLI flags, and manages option precedence.

  ## Option Precedence

  Options are resolved in this order (highest to lowest priority):

  1. **Query-level options** — passed to `query/3` or `stream/3`
  2. **Session-level options** — passed to `start_link/1`
  3. **Application config** — set in `config/config.exs`
  4. **Default values** — built-in defaults

      # Application config (lowest priority)
      config :claude_code, timeout: 300_000

      # Session-level overrides app config
      {:ok, session} = ClaudeCode.start_link(timeout: 120_000)

      # Query-level overrides session
      ClaudeCode.stream(session, "Hello", timeout: 60_000)

  ## Session Options

  All options for `ClaudeCode.start_link/1`:

  ### Authentication

  | Option    | Type   | Default                 | Description                  |
  | --------- | ------ | ----------------------- | ---------------------------- |
  | `api_key` | string | `ANTHROPIC_API_KEY` env | Anthropic API key            |
  | `name`    | atom   | -                       | Register session with a name |

  ### Model Configuration

  | Option                 | Type    | Default  | Description                                 |
  | ---------------------- | ------- | -------- | ------------------------------------------- |
  | `model`                | string  | "sonnet" | Claude model to use                         |
  | `fallback_model`       | string  | -        | Fallback if primary model fails             |
  | `system_prompt`        | string  | -        | Override system prompt                      |
  | `append_system_prompt` | string  | -        | Append to default system prompt             |
  | `max_turns`            | integer | -        | Limit conversation turns                    |
  | `max_budget_usd`       | number  | -        | Maximum dollar amount to spend on API calls |
  | `agent`                | string  | -        | Agent name for the session                  |
  | `betas`                | list    | -        | Beta headers for API requests               |
  | `max_thinking_tokens`  | integer | -        | Maximum tokens for thinking blocks          |

  ### Timeouts

  | Option    | Type    | Default | Description                   |
  | --------- | ------- | ------- | ----------------------------- |
  | `timeout` | integer | 300_000 | Query timeout in milliseconds |

  ### Tool Control

  | Option             | Type      | Default    | Description                                         |
  | ------------------ | --------- | ---------- | --------------------------------------------------- |
  | `tools`            | atom/list | -          | Available tools: `:default`, `[]`, or list of names |
  | `allowed_tools`    | list      | -          | Tools Claude can use                                |
  | `disallowed_tools` | list      | -          | Tools Claude cannot use                             |
  | `add_dir`          | list      | -          | Additional accessible directories                   |
  | `permission_mode`  | atom      | `:default` | Permission handling mode                            |

  ### Advanced

  | Option                     | Type       | Default     | Description                                                     |
  | -------------------------- | ---------- | ----------- | --------------------------------------------------------------- |
  | `adapter`                  | tuple      | CLI adapter | Backend adapter as `{Module, config}` tuple                     |
  | `resume`                   | string     | -           | Session ID to resume                                            |
  | `fork_session`             | boolean    | false       | Create new session ID when resuming                             |
  | `continue`                 | boolean    | false       | Continue most recent conversation in current directory          |
  | `mcp_config`               | string     | -           | Path to MCP config file                                         |
  | `strict_mcp_config`        | boolean    | false       | Only use MCP servers from explicit config                       |
  | `agents`                   | map        | -           | Custom agent configurations                                     |
  | `settings`                 | map/string | -           | Team settings                                                   |
  | `setting_sources`          | list       | -           | Setting source priority                                         |
  | `tool_callback`            | function   | -           | Called after tool executions                                     |
  | `include_partial_messages` | boolean    | false       | Enable character-level streaming                                |
  | `output_format`            | map        | -           | Structured output format (see Structured Outputs section)       |
  | `plugins`                  | list       | -           | Plugin configurations to load (paths or maps with type: :local) |

  ## Query Options

  Options that can be passed to `stream/3`:

  | Option                     | Type    | Description                             |
  | -------------------------- | ------- | --------------------------------------- |
  | `timeout`                  | integer | Override session timeout                |
  | `system_prompt`            | string  | Override system prompt for this query   |
  | `append_system_prompt`     | string  | Append to system prompt                 |
  | `max_turns`                | integer | Limit turns for this query              |
  | `max_budget_usd`           | number  | Maximum dollar amount for this query    |
  | `agent`                    | string  | Agent to use for this query             |
  | `betas`                    | list    | Beta headers for this query             |
  | `max_thinking_tokens`      | integer | Maximum tokens for thinking blocks      |
  | `tools`                    | list    | Available tools for this query          |
  | `allowed_tools`            | list    | Allowed tools for this query            |
  | `disallowed_tools`         | list    | Disallowed tools for this query         |
  | `output_format`            | map     | Structured output format for this query |
  | `plugins`                  | list    | Plugin configurations for this query    |
  | `include_partial_messages` | boolean | Enable deltas for this query            |

  Note: `api_key` and `name` cannot be overridden at query time.

  ## Application Configuration

  Set defaults in `config/config.exs`:

      config :claude_code,
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        model: "sonnet",
        timeout: 180_000,
        system_prompt: "You are a helpful assistant",
        allowed_tools: ["View"]

  ### CLI Configuration

  The SDK manages the Claude CLI binary via the `:cli_path` option:

      config :claude_code,
        cli_path: :bundled,               # :bundled (default), :global, or "/path/to/claude"
        cli_version: "x.y.z",            # Version to install (default: SDK's tested version)
        cli_dir: nil                      # Directory for downloaded binary (default: priv/bin/)

  Resolution modes:

  | Mode     | Value                  | Behavior                                                                        |
  | -------- | ---------------------- | ------------------------------------------------------------------------------- |
  | Bundled  | `:bundled` (default)   | Uses priv/bin/ binary. Auto-installs if missing. Verifies version matches SDK. |
  | Global   | `:global`              | Finds existing system install via PATH or common locations. No auto-install.   |
  | Explicit | `"/path/to/claude"`    | Uses that exact binary. Error if not found.                                    |

  Mix tasks:

      mix claude_code.install              # Install or update to SDK's tested version
      mix claude_code.install --version x.y.z   # Install specific version
      mix claude_code.install --force      # Force reinstall even if version matches
      mix claude_code.uninstall            # Remove the bundled CLI binary
      mix claude_code.path                 # Print the resolved CLI binary path

  For releases:

      # Option 1: Pre-install during release build (recommended)
      # (Run mix claude_code.install before building the release)

      # Option 2: Configure writable directory for runtime download
      config :claude_code, cli_dir: "/var/lib/claude_code"

      # Option 3: Use system-installed CLI
      config :claude_code, cli_path: :global

  ### Environment-Specific Configuration

      # config/dev.exs
      config :claude_code,
        timeout: 60_000,
        permission_mode: :accept_edits

      # config/prod.exs
      config :claude_code,
        timeout: 300_000,
        permission_mode: :default

      # config/test.exs
      config :claude_code,
        api_key: "test-key",
        timeout: 5_000

  ## Model Selection

      # Use a specific model
      {:ok, session} = ClaudeCode.start_link(model: "opus")

      # With fallback
      {:ok, session} = ClaudeCode.start_link(
        model: "opus",
        fallback_model: "sonnet"
      )

  Available models: `"sonnet"`, `"opus"`, `"haiku"`, or full model IDs.

  ## System Prompts

      # Override completely
      {:ok, session} = ClaudeCode.start_link(
        system_prompt: "You are an Elixir expert. Only discuss Elixir."
      )

      # Append to default
      {:ok, session} = ClaudeCode.start_link(
        append_system_prompt: "Always format code with proper indentation."
      )

  ## Cost Control

      # Limit spending per query
      session
      |> ClaudeCode.stream("Complex analysis task", max_budget_usd: 5.00)
      |> Stream.run()

      # Set a session-wide budget limit
      {:ok, session} = ClaudeCode.start_link(
        max_budget_usd: 25.00
      )

  ## Structured Outputs

  Use the `:output_format` option with a JSON Schema to get validated structured responses:

      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"},
          "skills" => %{"type" => "array", "items" => %{"type" => "string"}}
        },
        "required" => ["name", "age"]
      }

      session
      |> ClaudeCode.stream("Extract person info from: John is 30 and knows Elixir",
           output_format: %{type: :json_schema, schema: schema})
      |> ClaudeCode.Stream.text_content()
      |> Enum.join()

  The `:output_format` option accepts a map with:

  - `:type` — currently only `:json_schema` is supported
  - `:schema` — a JSON Schema map defining the expected structure

  ## Tool Configuration

      # Use all default tools
      {:ok, session} = ClaudeCode.start_link(tools: :default)

      # Specify available tools (subset of built-in)
      {:ok, session} = ClaudeCode.start_link(
        tools: ["Bash", "Edit", "Read"]
      )

      # Disable all tools
      {:ok, session} = ClaudeCode.start_link(tools: [])

      # Allow specific tools with patterns
      {:ok, session} = ClaudeCode.start_link(
        allowed_tools: ["View", "Edit", "Bash(git:*)"]
      )

      # Disallow specific tools
      {:ok, session} = ClaudeCode.start_link(
        disallowed_tools: ["Bash", "Write"]
      )

      # Additional directories
      {:ok, session} = ClaudeCode.start_link(
        add_dir: ["/app/lib", "/app/test"]
      )

  ## MCP Server Control

  Claude Code can connect to MCP (Model Context Protocol) servers for additional
  tools. By default, it uses globally configured MCP servers. Use `strict_mcp_config`
  to control this:

      # No tools at all (no built-in tools, no MCP servers)
      {:ok, session} = ClaudeCode.start_link(
        tools: [],
        strict_mcp_config: true
      )

      # Built-in tools only (ignore global MCP servers)
      {:ok, session} = ClaudeCode.start_link(
        tools: :default,
        strict_mcp_config: true
      )

      # Default behavior (built-in tools + global MCP servers)
      {:ok, session} = ClaudeCode.start_link()

      # Specific MCP servers only (no global config)
      {:ok, session} = ClaudeCode.start_link(
        strict_mcp_config: true,
        mcp_servers: %{
          "my-tools" => %{command: "npx", args: ["my-mcp-server"]}
        }
      )

  ### Using Hermes MCP Modules

  You can use Elixir-based MCP servers built with Hermes MCP:

      {:ok, session} = ClaudeCode.start_link(
        strict_mcp_config: true,
        mcp_servers: %{
          "my-tools" => MyApp.MCPServer,
          "custom" => %{module: MyApp.MCPServer, env: %{"DEBUG" => "1"}}
        }
      )

  ## Custom Agents

  Configure custom agents with specialized behaviors:

      agents = %{
        "code-reviewer" => %{
          "description" => "Expert code reviewer",
          "prompt" => "You review code for quality and best practices.",
          "tools" => ["View", "Grep", "Glob"],
          "model" => "sonnet"
        }
      }

      {:ok, session} = ClaudeCode.start_link(agents: agents)

  See the Subagents Guide for more details.

  ## Team Settings

      # From file path
      {:ok, session} = ClaudeCode.start_link(
        settings: "/path/to/settings.json"
      )

      # From map (auto-encoded to JSON)
      {:ok, session} = ClaudeCode.start_link(
        settings: %{
          "team_name" => "My Team",
          "preferences" => %{"theme" => "dark"}
        }
      )

      # Control setting sources
      {:ok, session} = ClaudeCode.start_link(
        setting_sources: [:user, :project, :local]
      )

  ## Plugins

  Load custom plugins to extend Claude's capabilities:

      # From a directory path
      {:ok, session} = ClaudeCode.start_link(
        plugins: ["./my-plugin"]
      )

      # With explicit type (currently only :local is supported)
      {:ok, session} = ClaudeCode.start_link(
        plugins: [
          %{type: :local, path: "./my-plugin"},
          "./another-plugin"
        ]
      )

  ## Runtime Control

  Some settings can be changed mid-conversation without restarting the session,
  using the bidirectional control protocol:

      # Switch model on the fly
      {:ok, _} = ClaudeCode.set_model(session, "opus")

      # Change permission mode
      {:ok, _} = ClaudeCode.set_permission_mode(session, :bypass_permissions)

      # Query MCP server status
      {:ok, status} = ClaudeCode.get_mcp_status(session)

  See the Sessions guide for more details.

  ## Validation Errors

  Invalid options raise descriptive errors:

      {:ok, session} = ClaudeCode.start_link(timeout: "not a number")
      # => ** (NimbleOptions.ValidationError) invalid value for :timeout option:
      #       expected positive integer, got: "not a number"

  ## Security Considerations

  - **`:permission_mode`** — controls permission handling behavior.
    Use `:bypass_permissions` only in development environments.
  - **`:add_dir`** — grants tool access to additional directories.
    Only include safe directories.
  - **`:allowed_tools`** — use tool restrictions to limit Claude's capabilities.
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
