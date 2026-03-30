defmodule ClaudeCode.Options do
  @moduledoc """
  Session option validation, CLI flag conversion, and configuration guide.

  This module is the **single source of truth** for all options passed to
  `ClaudeCode.start_link/1` or `ClaudeCode.query/2`.
  It provides validation using NimbleOptions, converts Elixir options to
  CLI flags, and manages option precedence.

  ## Option Precedence

  Options are resolved in this order (highest to lowest priority):

  1. **Session-level options** — passed to `start_link/1` or `query/2`
  2. **Application config** — set in `config/config.exs`
  3. **Default values** — built-in defaults

      # Application config (lowest priority)
      config :claude_code, timeout: 300_000

      # Session-level overrides app config
      {:ok, session} = ClaudeCode.start_link(timeout: 120_000)

  ## Session Options

  Options for `ClaudeCode.start_link/1` and `ClaudeCode.query/2`. These are set once
  when the CLI subprocess is launched and apply to the entire session.

  ### Authentication & Identity

  | Option       | Type   | Default                 | Description |
  | ------------ | ------ | ----------------------- | ----------- |
  | `api_key`    | string | `ANTHROPIC_API_KEY` env | Anthropic API key (passed via env var to CLI, never in arguments) |
  | `name`       | atom   | -                       | Register the session process with a name for easy reference. See [Named Sessions](sessions.md#named-sessions) |
  | `session_id` | string | auto-generated          | Use a specific UUID instead of auto-generating one |

  ### Model & Prompting

  | Option                 | Type       | Default  | Description |
  | ---------------------- | ---------- | -------- | ----------- |
  | `model`                | string     | "sonnet" | Model alias (`"sonnet"`, `"opus"`, `"haiku"`) or full model ID |
  | `fallback_model`       | string     | -        | Automatic fallback model when the primary is overloaded |
  | `system_prompt`        | string     | -        | Replace the entire default system prompt. See [Modifying System Prompts](modifying-system-prompts.md) |
  | `append_system_prompt` | string     | -        | Append custom text to the end of the default system prompt. See [Modifying System Prompts](modifying-system-prompts.md#method-3-appending-to-the-system-prompt) |
  | `agent`                | string     | -        | Select a named agent for the session. Must be defined in `:agents` or settings. See [Subagents](subagents.md#using-the-agent-option) |
  | `agents`               | list/map   | -        | Define custom subagents. See [Subagents](subagents.md#creating-subagents) and `ClaudeCode.Agent` |
  | `thinking`             | atom/tuple | -        | Extended thinking: `:adaptive`, `:disabled`, or `{:enabled, budget_tokens: N}` |
  | `effort`               | atom       | -        | Thinking effort: `:low`, `:medium`, `:high`, `:max` (`:max` is Opus only) |
  | `betas`                | list       | -        | Beta feature flags (e.g. `["context-1m-2025-08-07"]`, API key users only) |
  | `max_thinking_tokens`  | integer    | -        | **Deprecated:** use `:thinking` instead |

  ### Limits

  | Option            | Type        | Default     | Description |
  | ----------------- | ----------- | ----------- | ----------- |
  | `timeout`         | timeout     | `:infinity` | Max wait for next message on the stream (ms or `:infinity`). Resets on each message |
  | `control_timeout` | pos_integer | 60_000      | Max wait for CLI control responses (initialize handshake, MCP server startup) |
  | `max_turns`       | integer     | unlimited   | Maximum agentic turns (tool-use round trips). Exits with error when reached. See [Cost Controls](cost-tracking.md#cost-controls) |
  | `max_budget_usd`  | number      | -           | Maximum dollar amount to spend on API calls before stopping. See [Cost Controls](cost-tracking.md#cost-controls) |
  | `max_buffer_size` | pos_integer | 1_048_576   | Max buffer size in bytes for incoming JSON data. Protects against unbounded memory growth |

  ### Tool Control

  | Option             | Type      | Default | Description |
  | ------------------ | --------- | ------- | ----------- |
  | `tools`            | atom/list | -       | Restrict which built-in tools are available: `:default` (all), `[]` (none), or list of names. See [Permissions](permissions.md) |
  | `allowed_tools`    | list      | -       | Tools to auto-approve without prompting (e.g. `["View", "Bash(git:*)"]`). Unlisted tools fall through to `:permission_mode`. See [Allow and deny rules](permissions.md#allow-and-deny-rules) |
  | `disallowed_tools` | list      | -       | Tools to always deny. Checked first, overrides `:allowed_tools` and `:permission_mode`. See [Allow and deny rules](permissions.md#allow-and-deny-rules) |
  | `add_dir`          | list      | -       | Additional directories Claude can access (each path validated as existing directory) |
  | `tool_config`      | map       | -       | Per-tool config (e.g. `%{"askUserQuestion" => %{"previewFormat" => "html"}}`) |

  ### Permissions & Security

  | Option                               | Type          | Default    | Description |
  | ------------------------------------ | ------------- | ---------- | ----------- |
  | `permission_mode`                    | atom          | `:default` | `:default`, `:accept_edits`, `:bypass_permissions`, `:delegate`, `:dont_ask`, `:plan`. See [Permission modes](permissions.md#permission-modes) |
  | `can_use_tool`                       | module/fn     | -          | Programmatic permission callback. Mutually exclusive with `:permission_prompt_tool`. See [can_use_tool](hooks.md#can_use_tool) |
  | `permission_prompt_tool`             | string        | -          | MCP tool name for permission prompts in non-interactive mode. See [Permission delegation](mcp.md#permission-delegation) |
  | `sandbox`                            | struct/kw/map | -          | Sandbox settings for bash command isolation. See `ClaudeCode.Sandbox` and [Secure Deployment](secure-deployment.md#isolation-technologies) |
  | `allow_dangerously_skip_permissions` | boolean       | false      | Enable permission bypassing as an option. Required when using `:bypass_permissions` mode |
  | `dangerously_skip_permissions`       | boolean       | false      | Directly bypass all permission checks. Only for sandboxes with no internet access |

  ### MCP Servers

  See the [MCP guide](mcp.md) for setup, transport types, tool search, and authentication.

  | Option              | Type    | Default | Description |
  | ------------------- | ------- | ------- | ----------- |
  | `mcp_config`        | string  | -       | Path to MCP servers JSON config file (or JSON string). See [From a config file](mcp.md#from-a-config-file) |
  | `mcp_servers`       | map     | -       | Inline MCP server config. Values: Anubis module atom or config map per server. See [In code](mcp.md#in-code) |
  | `strict_mcp_config` | boolean | false   | Only use servers from `:mcp_config`/`:mcp_servers`, ignore global config. See [Strict MCP configuration](mcp.md#strict-mcp-configuration) |

  ### Session Lifecycle

  See the [Sessions guide](sessions.md) for resume, fork, and supervision patterns.

  | Option                   | Type           | Default | Description |
  | ------------------------ | -------------- | ------- | ----------- |
  | `resume`                 | string         | -       | Resume a previous conversation by session ID. See [Resume by ID](sessions.md#resume-by-id) |
  | `resume_session_at`      | string         | -       | When resuming, only include messages up to this UUID (use with `:resume`) |
  | `fork_session`           | boolean        | false   | When resuming, create a new session ID instead of reusing the original. See [Fork to explore alternatives](sessions.md#fork-to-explore-alternatives) |
  | `continue`               | boolean        | false   | Continue the most recent conversation in the current directory |
  | `from_pr`                | string/integer | -       | Resume a session linked to a GitHub PR by number or URL |
  | `no_session_persistence` | boolean        | false   | Disable session persistence — sessions won't be saved to disk or resumable |
  | `worktree`               | boolean/string | -       | Run in an isolated git worktree (`true` for auto-named, or branch name string) |

  ### Output & Streaming

  | Option                     | Type    | Default | Description |
  | -------------------------- | ------- | ------- | ----------- |
  | `output_format`            | map     | -       | Structured output: `%{type: :json_schema, schema: schema_map}`. See [Structured Outputs](structured-outputs.md) |
  | `include_partial_messages` | boolean | false   | Include partial message chunks for character-level streaming. See [Streaming Output](streaming-output.md) |
  | `replay_user_messages`     | boolean | false   | Re-emit user messages from stdin back on stdout for acknowledgment |
  | `prompt_suggestions`       | boolean | false   | Emit predicted next user prompts after each turn |

  ### Settings & Plugins

  | Option                   | Type       | Default | Description |
  | ------------------------ | ---------- | ------- | ----------- |
  | `settings`               | map/string | -       | Load additional settings from a file path, JSON string, or map (auto-encoded to JSON) |
  | `setting_sources`        | list       | -       | Which filesystem settings to load: `["user", "project", "local"]`. Include `"project"` for CLAUDE.md files |
  | `plugins`                | list       | -       | Load custom plugins (strings or maps with `type: :local`). See [Plugins](plugins.md) and `ClaudeCode.Plugin` |
  | `hooks`                  | map        | -       | Lifecycle hook configurations for intercepting events. See [Hooks](hooks.md) |
  | `disable_slash_commands` | boolean    | false   | Disable all skills and slash commands for this session. See [Skills](skills.md) |

  ### Environment & CLI

  | Option                      | Type        | Default    | Description |
  | --------------------------- | ----------- | ---------- | ----------- |
  | `env`                       | map         | `%{}`      | Extra env vars merged into CLI subprocess. String values set, `false` unsets |
  | `inherit_env`               | atom/list   | `:all`     | System env inheritance: `:all`, `[]`, or list of names/`{:prefix, "..."}` tuples. See [Environment Variable Control](secure-deployment.md#environment-variable-control) |
  | `cwd`                       | string      | -          | Working directory for the CLI subprocess |
  | `cli_path`                  | atom/string | `:bundled` | CLI binary resolution: `:bundled` (auto-install), `:global` (system), or explicit path |
  | `file`                      | list        | -          | File resources to download at startup (`"file_id:relative_path"` format) |
  | `enable_file_checkpointing` | boolean     | false      | Track file changes for rewinding. See [File Checkpointing](file-checkpointing.md) |
  | `extra_args`                | map         | `%{}`      | Additional CLI arguments passed directly to the binary (flag → value or `true` for boolean flags) |

  ### Debugging

  | Option       | Type           | Default | Description |
  | ------------ | -------------- | ------- | ----------- |
  | `debug`      | boolean/string | -       | Enable debug mode with optional category filter (e.g. `"api,hooks"` or `"!1p,!file"`) |
  | `debug_file` | string         | -       | Write debug logs to a specific file path (implicitly enables debug) |

  ### Elixir SDK Only

  These options are specific to the Elixir SDK and have no CLI or upstream SDK equivalent.

  | Option    | Type  | Default     | Description |
  | --------- | ----- | ----------- | ----------- |
  | `adapter` | tuple | CLI adapter | Backend adapter as `{Module, config}`. See `ClaudeCode.Adapter`, [Distributed Sessions](distributed-sessions.md) |

  > **Note:** `:name`, `:timeout`, `:control_timeout`, `:max_buffer_size`, `:inherit_env`,
  > and `:hooks` are also Elixir-only — they control SDK-side behavior and are not sent to the CLI.
  > They appear in their respective sections above.

  ## Application Configuration

  Set defaults in `config/config.exs`:

      config :claude_code,
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        model: "sonnet",
        timeout: 180_000,
        system_prompt: "You are a helpful assistant",
        allowed_tools: ["View"]

  ### CLI Binary Configuration

  The SDK manages the Claude CLI binary via application config:

      config :claude_code,
        cli_path: :bundled,               # :bundled (default), :global, or "/path/to/claude"
        cli_version: "x.y.z",            # Version to install (default: SDK's tested version)
        cli_dir: nil                      # Directory for downloaded binary (default: priv/bin/)

  | Mode     | Value                | Behavior |
  | -------- | -------------------- | -------- |
  | Bundled  | `:bundled` (default) | Uses priv/bin/ binary. Auto-installs if missing. Verifies version matches SDK |
  | Global   | `:global`            | Finds existing system install via PATH or common locations. No auto-install |
  | Explicit | `"/path/to/claude"`  | Uses that exact binary. Error if not found |

  Mix tasks: `mix claude_code.install`, `mix claude_code.uninstall`, `mix claude_code.path`.

  For releases, see [Hosting](hosting.md).

  ### Environment-Specific Configuration

      # config/dev.exs
      config :claude_code,
        timeout: 60_000,
        permission_mode: :accept_edits

      # config/prod.exs
      config :claude_code,
        timeout: :infinity,
        permission_mode: :default

      # config/test.exs
      config :claude_code,
        api_key: "test-key",
        timeout: 5_000

  ## Environment Variable Merging

  Merge precedence (lowest to highest): system env (filtered by `:inherit_env`)
  → `:env` option → SDK-required vars → `:api_key`.

  See [Secure Deployment](secure-deployment.md#environment-variable-control) for
  production lockdown patterns.

  ## Validation Errors

  Invalid options raise descriptive errors:

      {:ok, session} = ClaudeCode.start_link(timeout: "not a number")
      # => ** (NimbleOptions.ValidationError) invalid value for :timeout option:
      #       expected positive integer, got: "not a number"
  """

  require Logger

  @session_opts_schema [
    # Elixir-specific options
    api_key: [type: :string, doc: "Anthropic API key"],
    name: [type: :atom, doc: "Process name for the session"],
    timeout: [
      type: :timeout,
      default: :infinity,
      doc:
        "Max time in ms to wait for the next message on the stream. Resets on each message. Accepts a positive integer or :infinity."
    ],
    control_timeout: [
      type: :pos_integer,
      default: 60_000,
      doc:
        "Max time in ms to wait for CLI control responses (e.g. initialize handshake, MCP server startup). " <>
          "Useful when MCP servers are slow to start."
    ],
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
    hooks: [
      type: :map,
      doc: """
      Lifecycle hook configurations.

      A map of event names to lists of hook entries. Each entry can be:

      - A **bare module** or **2-arity function** (shorthand — registered without a matcher)
      - A **map** with `:matcher`, `:hooks`, and optional `:timeout`

      Shorthand:
          hooks: %{
            PreToolUse: [MyApp.BashGuard],
            PostToolUse: [fn input, _id -> Logger.info(inspect(input)); :ok end]
          }

      Full form (required for matchers, timeouts, or `:where`):
          hooks: %{
            PreToolUse: [%{matcher: "Bash", hooks: [MyApp.BashGuard]}],
            PostToolUse: [%{hooks: [MyApp.AuditLogger]}]
          }

      Mixed:
          hooks: %{
            PreToolUse: [
              MyApp.GlobalGuard,
              %{matcher: "Bash", hooks: [MyApp.BashGuard], timeout: 30}
            ]
          }
      """
    ],
    env: [
      type: {:map, :string, {:or, [:string, {:in, [false]}]}},
      default: %{},
      doc: """
      Environment variables to merge with system environment when spawning CLI.

      String values set the variable. A value of `false` unsets the variable,
      leveraging Erlang Port's native env unsetting behavior.

      These variables override system environment variables but are overridden by
      SDK-required variables (CLAUDE_CODE_ENTRYPOINT, CLAUDE_CODE_SDK_VERSION) and
      the `:api_key` option (which sets ANTHROPIC_API_KEY).

      Merge precedence (lowest to highest):
      1. System environment variables (filtered by `:inherit_env`)
      2. User `:env` option (these values)
      3. SDK-required variables
      4. `:api_key` option

      Useful for:
      - MCP tools that need specific env vars
      - Providing PATH or other tool-specific configuration
      - Testing with custom environment
      - Unsetting sensitive vars: `env: %{"SECRET" => false}`

      Example:
          env: %{
            "MY_CUSTOM_VAR" => "value",
            "PATH" => "/custom/bin:" <> System.get_env("PATH"),
            "RELEASE_COOKIE" => false
          }
      """
    ],
    inherit_env: [
      type: {:or, [{:in, [:all]}, {:list, {:or, [:string, {:tuple, [{:in, [:prefix]}, :string]}]}}]},
      default: :all,
      doc: """
      Controls which system environment variables are inherited by the CLI subprocess.

      - `:all` (default) — inherit all system env vars, minus CLAUDECODE
      - `[]` — inherit nothing from system env (only SDK vars, `:env`, and `:api_key`)
      - List of exact strings and/or `{:prefix, "..."}` tuples — only inherit matching vars

      CLAUDECODE is always stripped from inherited env when using `:all`.
      With an explicit list, it is included if matched.

      Examples:
          inherit_env: :all
          inherit_env: []
          inherit_env: ["PATH", "HOME", {:prefix, "CLAUDE_"}, {:prefix, "HTTP_"}]
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
    max_thinking_tokens: [type: :integer, doc: "Maximum tokens for thinking blocks (deprecated: use :thinking instead)"],
    thinking: [
      type: {:custom, __MODULE__, :validate_thinking, []},
      doc: """
      Extended thinking configuration. Takes precedence over :max_thinking_tokens.

      - `:adaptive` — Use adaptive thinking (defaults to 32,000 token budget)
      - `:disabled` — Disable extended thinking
      - `{:enabled, budget_tokens: N}` — Enable with specific token budget

      Example:
          thinking: :adaptive
          thinking: {:enabled, budget_tokens: 16_000}
      """
    ],
    effort: [
      type: {:in, [:low, :medium, :high, :max]},
      doc: "Effort level for the session (:low, :medium, :high, :max)"
    ],
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
        ~s(MCP server configurations. Values can be an Anubis server module atom or a config map. Example: %{"my-tools" => MyApp.MCPServer, "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}})
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
    replay_user_messages: [
      type: :boolean,
      default: false,
      doc: "Re-emit user messages from stdin back on stdout for acknowledgment (only works with stream-json input/output)"
    ],
    allow_dangerously_skip_permissions: [
      type: :boolean,
      default: false,
      doc:
        "Enable bypassing all permission checks as an option. Required when using permission_mode: :bypass_permissions. Recommended only for sandboxes with no internet access."
    ],
    dangerously_skip_permissions: [
      type: :boolean,
      default: false,
      doc:
        "Bypass all permission checks. Recommended only for sandboxes with no internet access. Unlike :allow_dangerously_skip_permissions, this directly enables bypassing without requiring a separate permission mode."
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
      type: {:custom, __MODULE__, :validate_sandbox, []},
      doc: """
      Sandbox settings for bash command isolation (merged into CLI `--settings`).

      Accepts a `ClaudeCode.Sandbox` struct, keyword list, or map.
      Maps and keyword lists are converted to a `ClaudeCode.Sandbox` struct.

      See `ClaudeCode.Sandbox` for all available fields.

      ## Examples

          sandbox: ClaudeCode.Sandbox.new(
            enabled: true,
            filesystem: [allow_write: ["/tmp/build"]],
            network: [allowed_domains: ["github.com"]]
          )

          # Keyword shorthand (auto-converted to struct)
          sandbox: [enabled: true, filesystem: [allow_write: ["/tmp"]]]
      """
    ],
    can_use_tool: [
      type: {:custom, ClaudeCode.Options, :validate_can_use_tool, []},
      type_doc: "module implementing `ClaudeCode.Hook` | `(map(), String.t() | nil -> term())`",
      doc:
        "Permission prompt callback. Receives tool info map and tool_use_id, returns a permission decision. Mutually exclusive with :permission_prompt_tool."
    ],
    enable_file_checkpointing: [
      type: :boolean,
      default: false,
      doc: "Enable file checkpointing to track file changes during the session (set via env var, not CLI flag)"
    ],
    worktree: [
      type: {:or, [:boolean, :string]},
      doc: "Create a new git worktree for this session (true for auto-named, or string for custom name)"
    ],
    prompt_suggestions: [
      type: :boolean,
      default: false,
      doc: "Enable prompt suggestions - emits predicted next user prompts after each turn"
    ],
    resume_session_at: [
      type: :string,
      doc: "When resuming, only resume messages up to and including the message with this UUID (use with :resume)"
    ],
    tool_config: [
      type: {:map, :string, :map},
      doc:
        ~s|Per-tool configuration for built-in tools. Map of tool name to config map (e.g. %{"askUserQuestion" => %{"previewFormat" => "html"}})|
    ],
    extra_args: [
      type: {:map, :string, {:or, [:string, {:in, [true]}]}},
      default: %{},
      doc:
        ~s|Additional CLI arguments passed directly to the claude binary. Map of flag name to value string, or `true` for boolean flags (e.g. %{"--some-flag" => "value", "--bool-flag" => true}).|
    ],
    max_buffer_size: [
      type: :pos_integer,
      default: 1_048_576,
      doc:
        "Maximum buffer size in bytes for incoming JSON data. Protects against unbounded memory growth. Default: 1MB (1_048_576 bytes)."
    ]
  ]

  # App config uses same option names directly - no mapping needed

  @doc """
  Returns the session options schema.
  """
  def session_schema, do: @session_opts_schema

  @doc """
  Validates session options using NimbleOptions.

  The CLI will handle API key resolution from the environment if not provided.

  ## Examples

      iex> ClaudeCode.Options.validate_session_options([api_key: "sk-test"])
      {:ok, [api_key: "sk-test", timeout: :infinity]}

      iex> ClaudeCode.Options.validate_session_options([])
      {:ok, [timeout: :infinity]}
  """
  def validate_session_options(opts) do
    validated =
      opts |> normalize_agents() |> NimbleOptions.validate!(@session_opts_schema)

    warn_deprecated_max_thinking_tokens(validated)
    validate_mutual_exclusions(validated)
  rescue
    e in NimbleOptions.ValidationError ->
      {:error, e}
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

  @doc false
  def validate_thinking(:adaptive), do: {:ok, :adaptive}
  def validate_thinking(:disabled), do: {:ok, :disabled}

  def validate_thinking({:enabled, opts}) when is_list(opts) do
    case Keyword.fetch(opts, :budget_tokens) do
      {:ok, budget} when is_integer(budget) and budget > 0 ->
        {:ok, {:enabled, opts}}

      {:ok, _} ->
        {:error, "expected :budget_tokens to be a positive integer"}

      :error ->
        {:error, "expected {:enabled, budget_tokens: pos_integer}, missing :budget_tokens"}
    end
  end

  def validate_thinking(other),
    do: {:error, "expected :adaptive, :disabled, or {:enabled, budget_tokens: pos_integer}, got: #{inspect(other)}"}

  @doc false
  def validate_sandbox(%ClaudeCode.Sandbox{} = sandbox), do: {:ok, sandbox}

  def validate_sandbox(opts) when is_list(opts) do
    {:ok, ClaudeCode.Sandbox.new(opts)}
  end

  def validate_sandbox(opts) when is_map(opts) do
    {:ok, ClaudeCode.Sandbox.new(opts)}
  end

  def validate_sandbox(other) do
    {:error, "expected a %ClaudeCode.Sandbox{} struct, keyword list, or map, got: #{inspect(other)}"}
  end

  @doc false
  def validate_can_use_tool(callback) when is_function(callback, 2), do: {:ok, callback}

  def validate_can_use_tool(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :call, 2) do
      {:ok, module}
    else
      {:error, "expected a module implementing ClaudeCode.Hook (call/2), got: #{inspect(module)}"}
    end
  end

  def validate_can_use_tool(other) do
    {:error, "expected a module implementing ClaudeCode.Hook or a 2-arity function, got: #{inspect(other)}"}
  end

  defp validate_mutual_exclusions(opts) do
    if Keyword.get(opts, :can_use_tool) && Keyword.get(opts, :permission_prompt_tool) do
      {:error,
       %NimbleOptions.ValidationError{
         key: :can_use_tool,
         message: ":can_use_tool and :permission_prompt_tool are mutually exclusive — use one or the other"
       }}
    else
      {:ok, opts}
    end
  end

  defp warn_deprecated_max_thinking_tokens(opts) do
    if Keyword.has_key?(opts, :max_thinking_tokens) && !Keyword.has_key?(opts, :thinking) do
      Logger.warning(
        ":max_thinking_tokens is deprecated, use thinking: :adaptive | :disabled | {:enabled, budget_tokens: N} instead"
      )
    end
  end

  defp normalize_agents(opts) do
    case Keyword.get(opts, :agents) do
      [%ClaudeCode.Agent{} | _] = agents ->
        Keyword.put(opts, :agents, ClaudeCode.Agent.to_agents_map(agents))

      _ ->
        opts
    end
  end
end
