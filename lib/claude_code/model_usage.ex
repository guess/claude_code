defmodule ClaudeCode.ModelUsage do
  @moduledoc """
  Per-model token usage statistics from the Claude CLI.

  Used by `ClaudeCode.Message.ResultMessage` to provide a breakdown of
  token usage per model (e.g., when fallback models are involved).

  ## Fields

    * `:input_tokens` - Number of input tokens consumed
    * `:output_tokens` - Number of output tokens generated
    * `:cache_creation_input_tokens` - Tokens used to create cache entries
    * `:cache_read_input_tokens` - Tokens read from cache
    * `:web_search_requests` - Number of web search requests made
    * `:cost_usd` - Cost in USD for this model's usage
    * `:context_window` - Context window size for this model
    * `:max_output_tokens` - Maximum output tokens for this model
  """

  @type t :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cache_creation_input_tokens: non_neg_integer() | nil,
          cache_read_input_tokens: non_neg_integer() | nil,
          web_search_requests: non_neg_integer(),
          cost_usd: float() | nil,
          context_window: non_neg_integer() | nil,
          max_output_tokens: non_neg_integer() | nil
        }

  @doc """
  Parses a model usage map from CLI JSON.

  Accepts a map keyed by model name with usage data values.
  Returns a map with the same keys and parsed `t:t/0` values.

  Returns an empty map for nil or non-map input.

  ## Examples

      iex> ClaudeCode.ModelUsage.parse(%{"claude-sonnet" => %{"input_tokens" => 100, "output_tokens" => 50}})
      %{"claude-sonnet" => %{input_tokens: 100, output_tokens: 50, cache_creation_input_tokens: nil, cache_read_input_tokens: nil, web_search_requests: 0, cost_usd: nil, context_window: nil, max_output_tokens: nil}}

      iex> ClaudeCode.ModelUsage.parse(nil)
      %{}

  """
  @spec parse(map() | nil) :: %{String.t() => t()}
  def parse(model_usage) when is_map(model_usage) do
    Map.new(model_usage, fn {model, usage_data} ->
      {model, parse_single(usage_data)}
    end)
  end

  def parse(_), do: %{}

  @doc """
  Parses a single model's usage data from CLI JSON.

  Returns `nil` for nil or non-map input.

  ## Examples

      iex> ClaudeCode.ModelUsage.parse_single(%{"input_tokens" => 100, "output_tokens" => 50})
      %{input_tokens: 100, output_tokens: 50, cache_creation_input_tokens: nil, cache_read_input_tokens: nil, web_search_requests: 0, cost_usd: nil, context_window: nil, max_output_tokens: nil}

      iex> ClaudeCode.ModelUsage.parse_single(nil)
      nil

  """
  @spec parse_single(map() | nil) :: t() | nil
  def parse_single(usage_data) when is_map(usage_data) do
    %{
      input_tokens: usage_data["input_tokens"] || 0,
      output_tokens: usage_data["output_tokens"] || 0,
      cache_creation_input_tokens: usage_data["cache_creation_input_tokens"],
      cache_read_input_tokens: usage_data["cache_read_input_tokens"],
      web_search_requests: usage_data["web_search_requests"] || 0,
      cost_usd: usage_data["cost_usd"],
      context_window: usage_data["context_window"],
      max_output_tokens: usage_data["max_output_tokens"]
    }
  end

  def parse_single(_), do: nil
end
