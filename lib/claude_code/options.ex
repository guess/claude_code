defmodule ClaudeCode.Options do
  @moduledoc """
  Handles option validation and CLI flag conversion.

  This module provides validation for session and query options using NimbleOptions,
  converts Elixir options to CLI flags, and manages option precedence:
  query > session > app config > defaults.
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
    permission_mode: [type: {:in, [:auto_accept_all, :auto_accept_reads, :ask_always]}, default: :ask_always, doc: "Permission handling mode"],
    
    # Legacy aliases for backward compatibility
    working_directory: [type: :string, doc: "Alias for cwd (deprecated, use cwd)"],
    max_conversation_turns: [type: :integer, doc: "Alias for max_turns (deprecated, use max_turns)"]
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
    permission_mode: [type: {:in, [:auto_accept_all, :auto_accept_reads, :ask_always]}, doc: "Override permission mode for this query"],
    
    # Legacy aliases
    working_directory: [type: :string, doc: "Alias for cwd (deprecated, use cwd)"],
    max_conversation_turns: [type: :integer, doc: "Alias for max_turns (deprecated, use max_turns)"]
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

  ## Examples

      iex> ClaudeCode.Options.validate_session_options([api_key: "sk-test"])
      {:ok, [api_key: "sk-test", model: "sonnet", timeout: 300_000, permission_mode: :ask_always, max_conversation_turns: 50]}
      
      iex> ClaudeCode.Options.validate_session_options([])
      {:error, %NimbleOptions.ValidationError{}}
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

  Ignores internal options like :api_key and :name that are not CLI flags.

  ## Examples

      iex> ClaudeCode.Options.to_cli_args([system_prompt: "You are helpful"])
      ["--system-prompt", "You are helpful"]
      
      iex> ClaudeCode.Options.to_cli_args([allowed_tools: ["View", "Bash(git:*)"]])
      ["--allowed-tools", "View,Bash(git:*)"]
  """
  def to_cli_args(opts) do
    opts
    |> Enum.reduce([], fn {key, value}, acc ->
      case convert_option_to_cli_flag(key, value) do
        {flag, flag_value} -> [flag, flag_value | acc]
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
    Keyword.merge(app_config, session_opts)
  end

  @doc """
  Resolves final options using complete precedence chain.

  Precedence: query > session > app config > defaults
  """
  def resolve_final_options(session_opts, query_opts) do
    # Extract defaults from schema
    defaults = extract_defaults_from_schema(@session_opts_schema)

    # Apply precedence chain: defaults -> app config -> session -> query
    defaults
    |> Keyword.merge(get_app_config())
    |> Keyword.merge(session_opts)
    |> Keyword.merge(query_opts)
  end

  # Private functions

  defp extract_defaults_from_schema(schema) do
    Enum.reduce(schema, [], fn {key, opts}, acc ->
      case Keyword.get(opts, :default) do
        nil -> acc
        default -> Keyword.put(acc, key, default)
      end
    end)
  end

  defp convert_option_to_cli_flag(:api_key, _value), do: nil
  defp convert_option_to_cli_flag(:name, _value), do: nil
  defp convert_option_to_cli_flag(:permission_handler, _value), do: nil
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
    {"--allowed-tools", tools_csv}
  end

  defp convert_option_to_cli_flag(:disallowed_tools, value) when is_list(value) do
    tools_csv = Enum.join(value, ",")
    {"--disallowed-tools", tools_csv}
  end

  defp convert_option_to_cli_flag(:cwd, value) do
    # Use cwd directly as argument, not a flag
    {"--cwd", to_string(value)}
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

  defp convert_option_to_cli_flag(:permission_mode, value) do
    mode_string = value |> to_string() |> String.replace("_", "-")
    {"--permission-mode", mode_string}
  end

  defp convert_option_to_cli_flag(:timeout, value) do
    {"--timeout", to_string(value)}
  end

  # Legacy aliases (handle for backward compatibility)
  defp convert_option_to_cli_flag(:working_directory, value) do
    {"--working-directory", to_string(value)}
  end

  defp convert_option_to_cli_flag(:max_conversation_turns, value) do
    {"--max-conversation-turns", to_string(value)}
  end

  defp convert_option_to_cli_flag(key, value) do
    # Convert unknown keys to kebab-case flags
    flag_name = "--" <> (key |> to_string() |> String.replace("_", "-"))
    {flag_name, to_string(value)}
  end
end
