defmodule ClaudeCode.Options do
  @moduledoc """
  Handles option validation and CLI flag conversion.

  This module provides validation for session and query options using NimbleOptions,
  converts Elixir options to CLI flags, and manages option precedence:
  query > session > app config > defaults.
  """

  @session_opts_schema [
    api_key: [type: :string, required: true, doc: "Anthropic API key"],
    model: [type: :string, default: "sonnet", doc: "Model to use"],
    system_prompt: [type: :string, doc: "System prompt for Claude"],
    allowed_tools: [type: {:list, :string}, doc: ~s{List of allowed tools (e.g. ["View", "Bash(git:*)"])}],
    max_conversation_turns: [type: :integer, default: 50, doc: "Max conversation turns"],
    working_directory: [type: :string, doc: "Working directory for file operations"],
    permission_mode: [
      type: {:in, [:auto_accept_all, :auto_accept_reads, :ask_always]},
      default: :ask_always,
      doc: "Permission handling mode"
    ],
    timeout: [type: :timeout, default: 300_000, doc: "Query timeout in ms"],
    permission_handler: [type: :atom, doc: "Custom permission handler module"],
    name: [type: :atom, doc: "Process name for the session"]
  ]

  @query_opts_schema [
    system_prompt: [type: :string, doc: "Override system prompt for this query"],
    timeout: [type: :timeout, doc: "Override timeout for this query"],
    allowed_tools: [type: {:list, :string}, doc: "Override allowed tools for this query"]
  ]

  @app_config_mapping %{
    default_model: :model,
    default_system_prompt: :system_prompt,
    default_timeout: :timeout,
    default_permission_mode: :permission_mode,
    default_max_conversation_turns: :max_conversation_turns,
    default_working_directory: :working_directory,
    default_allowed_tools: :allowed_tools,
    default_permission_handler: :permission_handler
  }

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

  Maps app config keys like :default_model to option keys like :model.
  """
  def get_app_config do
    :claude_code
    |> Application.get_all_env()
    |> Enum.map(fn {key, value} ->
      case Map.get(@app_config_mapping, key) do
        nil -> nil
        option_key -> {option_key, value}
      end
    end)
    |> Enum.reject(&is_nil/1)
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

  defp convert_option_to_cli_flag(:system_prompt, value) do
    {"--system-prompt", to_string(value)}
  end

  defp convert_option_to_cli_flag(:allowed_tools, value) when is_list(value) do
    tools_csv = Enum.join(value, ",")
    {"--allowed-tools", tools_csv}
  end

  defp convert_option_to_cli_flag(:max_conversation_turns, value) do
    {"--max-conversation-turns", to_string(value)}
  end

  defp convert_option_to_cli_flag(:working_directory, value) do
    {"--working-directory", to_string(value)}
  end

  defp convert_option_to_cli_flag(:permission_mode, value) do
    flag_value = value |> to_string() |> String.replace("_", "-")
    {"--permission-mode", flag_value}
  end

  defp convert_option_to_cli_flag(:timeout, value) do
    {"--timeout", to_string(value)}
  end

  defp convert_option_to_cli_flag(:model, value) do
    {"--model", to_string(value)}
  end

  defp convert_option_to_cli_flag(key, value) do
    # Convert unknown keys to kebab-case flags
    flag_name = "--" <> (key |> to_string() |> String.replace("_", "-"))
    {flag_name, to_string(value)}
  end
end
