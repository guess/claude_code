defmodule ClaudeCode.Message.SystemMessage.HookResponse do
  @moduledoc """
  Represents a hook response system message from the Claude CLI.

  Emitted when a hook completes execution with its final result.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:hook_response`
  - `:session_id` - Session identifier
  - `:uuid` - Message UUID
  - `:hook_id` - Unique identifier for this hook execution
  - `:hook_name` - Name of the hook that executed
  - `:hook_event` - Event that triggered the hook
  - `:output` - Combined or processed output
  - `:stdout` - Standard output from the hook process
  - `:stderr` - Standard error from the hook process
  - `:exit_code` - Exit code of the hook process
  - `:outcome` - Outcome of the hook execution (`:success`, `:error`, or `:cancelled`)

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "hook_response",
    "session_id": "...",
    "uuid": "...",
    "hook_id": "hook_abc123",
    "hook_name": "my_hook",
    "hook_event": "on_tool_start",
    "output": "done",
    "stdout": "done",
    "stderr": null,
    "exit_code": 0,
    "outcome": "success"
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :hook_id, :hook_name, :hook_event]
  defstruct [
    :type,
    :subtype,
    :uuid,
    :session_id,
    :hook_id,
    :hook_name,
    :hook_event,
    :output,
    :stdout,
    :stderr,
    :exit_code,
    :outcome
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :hook_response,
          uuid: String.t() | nil,
          session_id: String.t(),
          hook_id: String.t(),
          hook_name: String.t(),
          hook_event: String.t(),
          output: String.t() | nil,
          stdout: String.t() | nil,
          stderr: String.t() | nil,
          exit_code: integer() | nil,
          outcome: :success | :error | :cancelled | nil
        }

  @doc """
  Creates a new HookResponse from JSON data.

  The `"outcome"` string is parsed to an atom (`:success`, `:error`, or `:cancelled`).

  ## Examples

      iex> HookResponse.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "hook_response",
      ...>   "session_id" => "session-1",
      ...>   "hook_id" => "hook_abc",
      ...>   "hook_name" => "my_hook",
      ...>   "hook_event" => "on_tool_start",
      ...>   "exit_code" => 0,
      ...>   "outcome" => "success"
      ...> })
      {:ok, %HookResponse{type: :system, subtype: :hook_response, outcome: :success, ...}}

      iex> HookResponse.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{
          "type" => "system",
          "subtype" => "hook_response",
          "session_id" => session_id,
          "hook_id" => hook_id,
          "hook_name" => hook_name,
          "hook_event" => hook_event
        } = json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :hook_response,
       uuid: json["uuid"],
       session_id: session_id,
       hook_id: hook_id,
       hook_name: hook_name,
       hook_event: hook_event,
       output: json["output"],
       stdout: json["stdout"],
       stderr: json["stderr"],
       exit_code: json["exit_code"],
       outcome: parse_outcome(json["outcome"])
     }}
  end

  def new(%{"type" => "system", "subtype" => "hook_response"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a HookResponse.
  """
  @spec hook_response?(any()) :: boolean()
  def hook_response?(%__MODULE__{type: :system, subtype: :hook_response}), do: true
  def hook_response?(_), do: false

  defp parse_outcome("success"), do: :success
  defp parse_outcome("error"), do: :error
  defp parse_outcome("cancelled"), do: :cancelled
  defp parse_outcome(_), do: nil
end
