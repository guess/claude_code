defmodule ClaudeCode.Usage do
  @moduledoc """
  Token usage statistics from the Claude API.

  Matches the `BetaUsage` type from the Anthropic SDK. Parsed from CLI JSON
  payloads in both `AssistantMessage` and `ResultMessage`.

  ## Fields

    * `:input_tokens` - Number of input tokens consumed
    * `:output_tokens` - Number of output tokens generated
    * `:cache_creation_input_tokens` - Tokens used to create cache entries
    * `:cache_read_input_tokens` - Tokens read from cache
    * `:server_tool_use` - Server-side tool usage stats (web search/fetch)
    * `:service_tier` - Service tier used (`"standard"`, `"priority"`, `"batch"`)
    * `:cache_creation` - Ephemeral cache creation token breakdown
    * `:inference_geo` - Geographic region where inference ran
    * `:iterations` - Per-iteration usage breakdown
    * `:speed` - Inference speed mode (`"standard"`, `"fast"`)
  """

  @type t :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cache_creation_input_tokens: non_neg_integer(),
          cache_read_input_tokens: non_neg_integer(),
          server_tool_use: server_tool_use() | nil,
          service_tier: String.t() | nil,
          cache_creation: cache_creation() | nil,
          inference_geo: String.t() | nil,
          iterations: [map()],
          speed: String.t() | nil
        }

  @type server_tool_use :: %{
          web_search_requests: non_neg_integer(),
          web_fetch_requests: non_neg_integer()
        }

  @type cache_creation :: %{
          ephemeral_5m_input_tokens: non_neg_integer(),
          ephemeral_1h_input_tokens: non_neg_integer()
        }

  @doc """
  Parses a usage map from CLI JSON into a `t:t/0` map.

  ## Examples

      iex> ClaudeCode.Usage.parse(%{"input_tokens" => 100, "output_tokens" => 50})
      %{input_tokens: 100, output_tokens: 50, cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0, server_tool_use: nil, service_tier: nil,
        cache_creation: nil, inference_geo: nil, iterations: [], speed: nil}

  """
  @spec parse(map() | nil) :: t()
  def parse(data) when is_map(data) do
    %{
      input_tokens: data["input_tokens"] || 0,
      output_tokens: data["output_tokens"] || 0,
      cache_creation_input_tokens: data["cache_creation_input_tokens"] || 0,
      cache_read_input_tokens: data["cache_read_input_tokens"] || 0,
      server_tool_use: parse_server_tool_use(data["server_tool_use"]),
      service_tier: data["service_tier"],
      cache_creation: parse_cache_creation(data["cache_creation"]),
      inference_geo: data["inference_geo"],
      iterations: data["iterations"] || [],
      speed: data["speed"]
    }
  end

  def parse(_) do
    %{
      input_tokens: 0,
      output_tokens: 0,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      server_tool_use: nil,
      service_tier: nil,
      cache_creation: nil,
      inference_geo: nil,
      iterations: [],
      speed: nil
    }
  end

  @doc """
  Parses a server_tool_use sub-map from CLI JSON.
  """
  @spec parse_server_tool_use(map() | nil) :: server_tool_use() | nil
  def parse_server_tool_use(%{} = data) when map_size(data) > 0 do
    %{
      web_search_requests: data["web_search_requests"] || 0,
      web_fetch_requests: data["web_fetch_requests"] || 0
    }
  end

  def parse_server_tool_use(_), do: nil

  @doc """
  Parses a cache_creation sub-map from CLI JSON.
  """
  @spec parse_cache_creation(map() | nil) :: cache_creation() | nil
  def parse_cache_creation(%{"ephemeral_5m_input_tokens" => t5m, "ephemeral_1h_input_tokens" => t1h}) do
    %{ephemeral_5m_input_tokens: t5m, ephemeral_1h_input_tokens: t1h}
  end

  def parse_cache_creation(_), do: nil
end
