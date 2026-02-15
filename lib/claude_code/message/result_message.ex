defmodule ClaudeCode.Message.ResultMessage do
  @moduledoc """
  Represents a result message from the Claude CLI.

  Result messages are the final message in a conversation, containing
  the final response, timing information, token usage, and cost.

  ## String.Chars Protocol

  `Result` implements `String.Chars`, so you can use it directly with
  `IO.puts/1` or string interpolation:

      {:ok, result} = ClaudeCode.query(session, "Hello")
      IO.puts(result)  # prints just the result text

  Matches the official SDK schema for successful results:
  ```
  {
    type: "result",
    subtype: "success",
    uuid: string,
    duration_ms: float,
    duration_api_ms: float,
    is_error: boolean,
    num_turns: int,
    result: string,
    stop_reason: string | null,
    session_id: string,
    total_cost_usd: float,
    usage: object,
    modelUsage: {model: ModelUsage},
    permission_denials: PermissionDenial[],
    structured_output?: unknown
  }
  ```

  And for error results:
  ```
  {
    type: "result",
    subtype: "error_max_turns" | "error_during_execution" | "error_max_budget_usd" | "error_max_structured_output_retries",
    uuid: string,
    duration_ms: float,
    duration_api_ms: float,
    is_error: boolean,
    num_turns: int,
    session_id: string,
    total_cost_usd: float,
    usage: object,
    modelUsage: {model: ModelUsage},
    permission_denials: PermissionDenial[],
    errors: string[]
  }
  ```
  """

  alias ClaudeCode.Types

  @enforce_keys [
    :type,
    :subtype,
    :is_error,
    :duration_ms,
    :duration_api_ms,
    :num_turns,
    :session_id,
    :total_cost_usd,
    :usage
  ]
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
    :usage,
    :uuid,
    :stop_reason,
    :model_usage,
    :permission_denials,
    :structured_output,
    :errors
  ]

  @type t :: %__MODULE__{
          type: :result,
          subtype: Types.result_subtype(),
          is_error: boolean(),
          duration_ms: float(),
          duration_api_ms: float(),
          num_turns: non_neg_integer(),
          result: String.t() | nil,
          session_id: Types.session_id(),
          total_cost_usd: float(),
          usage: Types.usage(),
          uuid: String.t() | nil,
          stop_reason: Types.stop_reason(),
          model_usage: %{String.t() => Types.model_usage()},
          permission_denials: [Types.permission_denial()],
          structured_output: any() | nil,
          errors: [String.t()] | nil
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
    required_fields = [
      "subtype",
      "is_error",
      "duration_ms",
      "duration_api_ms",
      "num_turns",
      "session_id",
      "total_cost_usd",
      "usage"
    ]

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
        usage: parse_usage(json["usage"]),
        uuid: json["uuid"],
        stop_reason: parse_stop_reason(json["stop_reason"]),
        model_usage: parse_model_usage(json["modelUsage"]),
        permission_denials: parse_permission_denials(json["permission_denials"]),
        structured_output: json["structured_output"],
        errors: json["errors"]
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
  @spec result_message?(any()) :: boolean()
  def result_message?(%__MODULE__{type: :result}), do: true
  def result_message?(_), do: false

  defp parse_subtype("success"), do: :success
  defp parse_subtype("error_max_turns"), do: :error_max_turns
  defp parse_subtype("error_during_execution"), do: :error_during_execution
  defp parse_subtype("error_max_budget_usd"), do: :error_max_budget_usd
  defp parse_subtype("error_max_structured_output_retries"), do: :error_max_structured_output_retries
  defp parse_subtype(other) when is_binary(other), do: String.to_atom(other)

  defp parse_stop_reason(nil), do: nil
  defp parse_stop_reason("end_turn"), do: :end_turn
  defp parse_stop_reason("max_tokens"), do: :max_tokens
  defp parse_stop_reason("stop_sequence"), do: :stop_sequence
  defp parse_stop_reason("tool_use"), do: :tool_use
  defp parse_stop_reason(other) when is_binary(other), do: String.to_atom(other)

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value * 1.0
  defp parse_float(_), do: 0.0

  defp parse_usage(usage_data) when is_map(usage_data) do
    %{
      input_tokens: usage_data["input_tokens"] || 0,
      cache_creation_input_tokens: usage_data["cache_creation_input_tokens"] || 0,
      cache_read_input_tokens: usage_data["cache_read_input_tokens"] || 0,
      output_tokens: usage_data["output_tokens"] || 0,
      server_tool_use: parse_server_tool_use(usage_data["server_tool_use"]),
      service_tier: usage_data["service_tier"],
      cache_creation: parse_cache_creation(usage_data["cache_creation"]),
      inference_geo: usage_data["inference_geo"],
      iterations: usage_data["iterations"] || [],
      speed: usage_data["speed"]
    }
  end

  defp parse_usage(_),
    do: %{
      input_tokens: 0,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      output_tokens: 0,
      server_tool_use: %{web_search_requests: 0, web_fetch_requests: 0},
      service_tier: nil,
      cache_creation: nil,
      inference_geo: nil,
      iterations: [],
      speed: nil
    }

  defp parse_server_tool_use(%{} = data) when map_size(data) > 0 do
    %{
      web_search_requests: data["web_search_requests"] || 0,
      web_fetch_requests: data["web_fetch_requests"] || 0
    }
  end

  defp parse_server_tool_use(_), do: %{web_search_requests: 0, web_fetch_requests: 0}

  defp parse_cache_creation(%{"ephemeral_5m_input_tokens" => t5m, "ephemeral_1h_input_tokens" => t1h}) do
    %{ephemeral_5m_input_tokens: t5m, ephemeral_1h_input_tokens: t1h}
  end

  defp parse_cache_creation(_), do: nil

  defp parse_model_usage(model_usage) when is_map(model_usage) do
    Map.new(model_usage, fn {model, usage_data} ->
      {model, parse_single_model_usage(usage_data)}
    end)
  end

  defp parse_model_usage(_), do: %{}

  # NOTE: modelUsage uses camelCase keys from the CLI (e.g., "inputTokens" not "input_tokens")
  defp parse_single_model_usage(usage_data) when is_map(usage_data) do
    %{
      input_tokens: usage_data["inputTokens"] || 0,
      output_tokens: usage_data["outputTokens"] || 0,
      cache_creation_input_tokens: usage_data["cacheCreationInputTokens"],
      cache_read_input_tokens: usage_data["cacheReadInputTokens"],
      web_search_requests: usage_data["webSearchRequests"] || 0,
      cost_usd: usage_data["costUSD"],
      context_window: usage_data["contextWindow"],
      max_output_tokens: usage_data["maxOutputTokens"]
    }
  end

  defp parse_single_model_usage(_), do: nil

  defp parse_permission_denials(denials) when is_list(denials) do
    Enum.map(denials, fn denial ->
      %{
        tool_name: denial["tool_name"],
        tool_use_id: denial["tool_use_id"],
        tool_input: denial["tool_input"] || %{}
      }
    end)
  end

  defp parse_permission_denials(_), do: []
end

defimpl String.Chars, for: ClaudeCode.Message.ResultMessage do
  def to_string(%{result: nil, errors: errors}) when is_list(errors) do
    "Error: " <> Enum.join(errors, ", ")
  end

  def to_string(%{result: nil}), do: ""
  def to_string(%{result: result}), do: result
end

defimpl Jason.Encoder, for: ClaudeCode.Message.ResultMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.ResultMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
