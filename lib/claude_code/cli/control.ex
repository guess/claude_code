defmodule ClaudeCode.CLI.Control do
  @moduledoc """
  Bidirectional control protocol for the Claude CLI.

  Builds and classifies control messages that share the stdin/stdout
  transport with regular SDK messages. Part of the CLI protocol layer.

  ## Message Classification

  All messages from the CLI are classified into one of three categories:

    * `{:control_request, msg}` — The CLI is requesting something from the SDK
    * `{:control_response, msg}` — The CLI is responding to a previous SDK request
    * `{:message, msg}` — A regular SDK message (system, assistant, user, result, etc.)

  ## Outbound Requests (SDK -> CLI)

  Request builders produce single-line JSON strings suitable for writing
  to the CLI's stdin:

    * `initialize_request/3` — Initialize the control protocol
    * `set_model_request/2` — Change the active model
    * `set_permission_mode_request/2` — Change the permission mode
    * `rewind_files_request/2` — Rewind files to a previous state
    * `mcp_status_request/1` — Query MCP server status

  ## Response Builders (SDK -> CLI)

  When the CLI sends a control request, the SDK responds with:

    * `success_response/2` — Successful response with data
    * `error_response/2` — Error response with message

  ## Response Parsing (CLI -> SDK)

  When the CLI responds to an SDK request:

    * `parse_control_response/1` — Parse into tagged tuples
  """

  # --- Classification ---------------------------------------------------------

  @doc """
  Classifies a decoded JSON message as a control or regular message.

  ## Examples

      iex> ClaudeCode.CLI.Control.classify(%{"type" => "control_request", "request_id" => "req_1"})
      {:control_request, %{"type" => "control_request", "request_id" => "req_1"}}

      iex> ClaudeCode.CLI.Control.classify(%{"type" => "assistant", "message" => %{}})
      {:message, %{"type" => "assistant", "message" => %{}}}

  """
  @spec classify(map()) :: {:control_request, map()} | {:control_response, map()} | {:message, map()}
  def classify(%{"type" => "control_request"} = msg), do: {:control_request, msg}
  def classify(%{"type" => "control_response"} = msg), do: {:control_response, msg}
  def classify(msg), do: {:message, msg}

  # --- Request ID Generation --------------------------------------------------

  @doc """
  Generates a unique request ID with the given counter prefix.

  The format is `req_{counter}_{hex}` where `hex` is 8 random hex characters.

  ## Examples

      iex> id = ClaudeCode.CLI.Control.generate_request_id(0)
      iex> String.starts_with?(id, "req_0_")
      true

  """
  @spec generate_request_id(non_neg_integer()) :: String.t()
  def generate_request_id(counter) do
    hex = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    "req_#{counter}_#{hex}"
  end

  # --- Outbound Request Builders (SDK -> CLI) ---------------------------------

  @doc """
  Builds an initialize control request JSON string.

  ## Parameters

    * `request_id` - Unique request identifier
    * `hooks` - Optional hook configurations (map or nil)
    * `agents` - Optional agent configurations (map or nil)

  """
  @spec initialize_request(String.t(), map() | nil, map() | nil) :: String.t()
  def initialize_request(request_id, hooks \\ nil, agents \\ nil) do
    request =
      %{subtype: "initialize"}
      |> maybe_put(:hooks, hooks)
      |> maybe_put(:agents, agents)

    encode_control_request(request_id, request)
  end

  @doc """
  Builds a set_model control request JSON string.

  ## Parameters

    * `request_id` - Unique request identifier
    * `model` - The model identifier string

  """
  @spec set_model_request(String.t(), String.t()) :: String.t()
  def set_model_request(request_id, model) do
    encode_control_request(request_id, %{subtype: "set_model", model: model})
  end

  @doc """
  Builds a set_permission_mode control request JSON string.

  ## Parameters

    * `request_id` - Unique request identifier
    * `mode` - The permission mode string (e.g., "bypassPermissions")

  """
  @spec set_permission_mode_request(String.t(), String.t()) :: String.t()
  def set_permission_mode_request(request_id, mode) do
    encode_control_request(request_id, %{subtype: "set_permission_mode", permission_mode: mode})
  end

  @doc """
  Builds a rewind_files control request JSON string.

  ## Parameters

    * `request_id` - Unique request identifier
    * `user_message_id` - The user message ID to rewind to

  """
  @spec rewind_files_request(String.t(), String.t()) :: String.t()
  def rewind_files_request(request_id, user_message_id) do
    encode_control_request(request_id, %{subtype: "rewind_files", user_message_id: user_message_id})
  end

  @doc """
  Builds an mcp_status control request JSON string.

  ## Parameters

    * `request_id` - Unique request identifier

  """
  @spec mcp_status_request(String.t()) :: String.t()
  def mcp_status_request(request_id) do
    encode_control_request(request_id, %{subtype: "mcp_status"})
  end

  # --- Response Builders (SDK -> CLI, answering CLI requests) -----------------

  @doc """
  Builds a success control response JSON string.

  Used to respond to a control request from the CLI with a successful result.

  ## Parameters

    * `request_id` - The request ID being responded to
    * `response_data` - The response payload (map)

  """
  @spec success_response(String.t(), map()) :: String.t()
  def success_response(request_id, response_data) do
    Jason.encode!(%{
      type: "control_response",
      response: %{subtype: "success", request_id: request_id, response: response_data}
    })
  end

  @doc """
  Builds an error control response JSON string.

  Used to respond to a control request from the CLI with an error.

  ## Parameters

    * `request_id` - The request ID being responded to
    * `error_message` - The error description string

  """
  @spec error_response(String.t(), String.t()) :: String.t()
  def error_response(request_id, error_message) do
    Jason.encode!(%{
      type: "control_response",
      response: %{subtype: "error", request_id: request_id, error: error_message}
    })
  end

  # --- Response Parsing (CLI -> SDK) ------------------------------------------

  @doc """
  Parses a control response message from the CLI.

  Returns tagged tuples indicating success or error:

    * `{:ok, request_id, response_data}` — Successful response
    * `{:error, request_id, error_message}` — Error response or parse failure

  ## Examples

      iex> msg = %{"type" => "control_response", "response" => %{"subtype" => "success", "request_id" => "req_1", "response" => %{}}}
      iex> ClaudeCode.CLI.Control.parse_control_response(msg)
      {:ok, "req_1", %{}}

  """
  @spec parse_control_response(map()) :: {:ok, String.t(), map()} | {:error, String.t() | nil, String.t()}
  def parse_control_response(%{"response" => %{"subtype" => "success", "request_id" => req_id, "response" => data}}) do
    {:ok, req_id, data}
  end

  def parse_control_response(%{"response" => %{"subtype" => "error", "request_id" => req_id, "error" => error}}) do
    {:error, req_id, error}
  end

  def parse_control_response(%{"response" => %{"subtype" => subtype, "request_id" => req_id}}) do
    {:error, req_id, "Unknown control response subtype: #{subtype}"}
  end

  def parse_control_response(_) do
    {:error, nil, "Invalid control response: missing response field"}
  end

  # --- Private ----------------------------------------------------------------

  defp encode_control_request(request_id, request) do
    Jason.encode!(%{type: "control_request", request_id: request_id, request: request})
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
