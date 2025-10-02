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

  ### Required Options
  - `:api_key` - Anthropic API key (string, required - falls back to ANTHROPIC_API_KEY env var)

  ### Claude Configuration
  - `:model` - Claude model to use (string, optional - CLI uses its default)
  - `:system_prompt` - Override system prompt (string, optional)
  - `:append_system_prompt` - Append to system prompt (string, optional)
  - `:max_turns` - Limit agentic turns in non-interactive mode (integer, optional)

  ### Tool Control
  - `:allowed_tools` - List of allowed tools (list of strings, optional)
    Example: `["View", "Bash(git:*)"]`
  - `:disallowed_tools` - List of denied tools (list of strings, optional)
  - `:add_dir` - Additional directories for tool access (list of strings, optional)
    Example: `["/tmp", "/var/log"]`

  ### Advanced Options
  - `:mcp_config` - Path to MCP servers JSON config file (string, optional)
  - `:permission_prompt_tool` - MCP tool for handling permission prompts (string, optional)
  - `:permission_mode` - Permission handling mode (atom, default: :default)
    Options: `:default`, `:accept_edits`, `:bypass_permissions`
  - `:output_format` - Output format (string, optional)
    Options: `"text"`, `"json"`, `"stream-json"`

  ### Elixir-Specific Options
  - `:name` - GenServer process name (atom, optional)
  - `:timeout` - Query timeout in milliseconds (timeout, default: 300_000) - **Elixir only, not passed to CLI**
  - `:permission_handler` - Custom permission handler module (atom, optional)
  - `:cwd` - Current working directory (string, optional)

  ## Query Options

  Query options can override session defaults for individual queries.
  All session options except `:api_key`, `:name`, and `:permission_handler`
  can be used as query options.

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
    api_key: [type: :string, required: true, doc: "Anthropic API key"],
    name: [type: :atom, doc: "Process name for the session"],
    timeout: [type: :timeout, default: 300_000, doc: "Query timeout in ms"],
    permission_handler: [type: :atom, doc: "Custom permission handler module"],

    # CLI options (aligned with TypeScript SDK)
    model: [type: :string, doc: "Model to use"],
    cwd: [type: :string, doc: "Current working directory"],
    system_prompt: [type: :string, doc: "Override system prompt"],
    append_system_prompt: [type: :string, doc: "Append to system prompt"],
    max_turns: [type: :integer, doc: "Limit agentic turns in non-interactive mode"],
    allowed_tools: [type: {:list, :string}, doc: ~s{List of allowed tools (e.g. ["View", "Bash(git:*)"])}],
    disallowed_tools: [type: {:list, :string}, doc: "List of denied tools"],
    mcp_config: [type: :string, doc: "Path to MCP servers JSON config file"],
    permission_prompt_tool: [type: :string, doc: "MCP tool for handling permission prompts"],
    permission_mode: [
      type: {:in, [:default, :accept_edits, :bypass_permissions]},
      default: :default,
      doc: "Permission handling mode"
    ],
    add_dir: [type: {:list, :string}, doc: "Additional directories for tool access"],
    output_format: [type: :string, doc: "Output format (text, json, stream-json)"]
  ]

  @query_opts_schema [
    # Query-level overrides for CLI options
    system_prompt: [type: :string, doc: "Override system prompt for this query"],
    append_system_prompt: [type: :string, doc: "Append to system prompt for this query"],
    max_turns: [type: :integer, doc: "Override max turns for this query"],
    allowed_tools: [type: {:list, :string}, doc: "Override allowed tools for this query"],
    disallowed_tools: [type: {:list, :string}, doc: "Override disallowed tools for this query"],
    cwd: [type: :string, doc: "Override working directory for this query"],
    timeout: [type: :timeout, doc: "Override timeout for this query"],
    permission_mode: [
      type: {:in, [:default, :accept_edits, :bypass_permissions]},
      doc: "Override permission mode for this query"
    ],
    add_dir: [type: {:list, :string}, doc: "Override additional directories for this query"],
    output_format: [type: :string, doc: "Override output format for this query"]
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

  If no `:api_key` is provided in options, falls back to checking the
  `ANTHROPIC_API_KEY` environment variable.

  ## Examples

      iex> ClaudeCode.Options.validate_session_options([api_key: "sk-test"])
      {:ok, [api_key: "sk-test", timeout: 300_000]}

      iex> ClaudeCode.Options.validate_session_options([])
      {:error, %NimbleOptions.ValidationError{}}
  """
  def validate_session_options(opts) do
    # Check for API key fallback before validation
    opts_with_api_key_fallback = maybe_add_api_key_from_env(opts)

    validated = NimbleOptions.validate!(opts_with_api_key_fallback, @session_opts_schema)
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

  Ignores internal options like :api_key, :name, :timeout, and :permission_handler that are not CLI flags.

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

  Session options take precedence over app config, which takes
  precedence over environment variables.
  """
  def apply_app_config_defaults(session_opts) do
    app_config = get_app_config()

    # Apply environment variable fallback first, then app config, then session opts
    []
    |> maybe_add_api_key_from_env()
    |> Keyword.merge(app_config)
    |> Keyword.merge(session_opts)
  end

  # Private functions

  defp maybe_add_api_key_from_env(opts) do
    case Keyword.get(opts, :api_key) do
      nil ->
        # No api_key provided, check environment variable
        case System.get_env("ANTHROPIC_API_KEY") do
          nil -> opts
          api_key -> Keyword.put(opts, :api_key, api_key)
        end

      _ ->
        # api_key already provided, use as-is
        opts
    end
  end

  defp convert_option_to_cli_flag(:api_key, _value), do: nil
  defp convert_option_to_cli_flag(:name, _value), do: nil
  defp convert_option_to_cli_flag(:permission_handler, _value), do: nil
  defp convert_option_to_cli_flag(:timeout, _value), do: nil
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

  defp convert_option_to_cli_flag(key, value) do
    # Convert unknown keys to kebab-case flags
    flag_name = "--" <> (key |> to_string() |> String.replace("_", "-"))
    {flag_name, to_string(value)}
  end
end
