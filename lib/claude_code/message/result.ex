defmodule ClaudeCode.Message.Result do
  @moduledoc """
  Represents a result message from the Claude CLI.
  
  Result messages are the final message in a conversation, containing
  the final response, timing information, token usage, and cost.
  """
  
  @enforce_keys [:type, :subtype, :is_error, :duration_ms, :duration_api_ms,
                 :num_turns, :result, :session_id, :total_cost_usd, :usage]
  defstruct [
    :type,
    :subtype,
    :is_error,
    :duration_ms,
    :duration_api_ms,
    :num_turns,
    :result,
    :session_id,
    :total_cost_usd,
    :usage
  ]
  
  @type t :: %__MODULE__{
    type: :result,
    subtype: :success | :error | atom(),
    is_error: boolean(),
    duration_ms: integer(),
    duration_api_ms: integer(),
    num_turns: integer(),
    result: String.t(),
    session_id: String.t(),
    total_cost_usd: float(),
    usage: usage_summary()
  }
  
  @type usage_summary :: %{
    input_tokens: integer(),
    cache_creation_input_tokens: integer(),
    cache_read_input_tokens: integer(),
    output_tokens: integer(),
    server_tool_use: %{
      web_search_requests: integer()
    }
  }
  
  @doc """
  Creates a new Result message from JSON data.
  
  ## Examples
  
      iex> Result.new(%{"type" => "result", "subtype" => "success", ...})
      {:ok, %Result{...}}
      
      iex> Result.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "result"} = json) do
    required_fields = ["subtype", "is_error", "duration_ms", "duration_api_ms",
                      "num_turns", "result", "session_id", "total_cost_usd", "usage"]
    
    missing = Enum.filter(required_fields, &(not Map.has_key?(json, &1)))
    
    if Enum.empty?(missing) do
      message = %__MODULE__{
        type: :result,
        subtype: parse_subtype(json["subtype"]),
        is_error: json["is_error"],
        duration_ms: json["duration_ms"],
        duration_api_ms: json["duration_api_ms"],
        num_turns: json["num_turns"],
        result: json["result"],
        session_id: json["session_id"],
        total_cost_usd: parse_float(json["total_cost_usd"]),
        usage: parse_usage(json["usage"])
      }
      
      {:ok, message}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end
  
  def new(_), do: {:error, :invalid_message_type}
  
  @doc """
  Type guard to check if a value is a Result message.
  """
  @spec is_result_message?(any()) :: boolean()
  def is_result_message?(%__MODULE__{type: :result}), do: true
  def is_result_message?(_), do: false
  
  defp parse_subtype("success"), do: :success
  defp parse_subtype("error"), do: :error
  defp parse_subtype(other) when is_binary(other), do: String.to_atom(other)
  
  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value * 1.0
  defp parse_float(_), do: 0.0
  
  defp parse_usage(usage_data) when is_map(usage_data) do
    %{
      input_tokens: usage_data["input_tokens"] || 0,
      cache_creation_input_tokens: usage_data["cache_creation_input_tokens"] || 0,
      cache_read_input_tokens: usage_data["cache_read_input_tokens"] || 0,
      output_tokens: usage_data["output_tokens"] || 0,
      server_tool_use: parse_server_tool_use(usage_data["server_tool_use"])
    }
  end
  
  defp parse_usage(_), do: %{
    input_tokens: 0,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    output_tokens: 0,
    server_tool_use: %{web_search_requests: 0}
  }
  
  defp parse_server_tool_use(%{"web_search_requests" => count}), do: %{web_search_requests: count}
  defp parse_server_tool_use(_), do: %{web_search_requests: 0}
end