defmodule ClaudeCode.McpSetServersResult do
  @moduledoc """
  Result of a `ClaudeCode.set_mcp_servers/2` operation.

  ## Fields

    * `:added` - Names of servers that were added
    * `:removed` - Names of servers that were removed
    * `:errors` - Map of server names to error messages for servers that failed to connect
  """

  defstruct added: [],
            removed: [],
            errors: %{}

  @type t :: %__MODULE__{
          added: [String.t()],
          removed: [String.t()],
          errors: %{String.t() => String.t()}
        }

  @doc """
  Creates an McpSetServersResult from a JSON map.

  ## Examples

      iex> ClaudeCode.McpSetServersResult.new(%{"added" => ["a"], "removed" => ["b"], "errors" => %{"c" => "failed"}})
      %ClaudeCode.McpSetServersResult{added: ["a"], removed: ["b"], errors: %{"c" => "failed"}}

  """
  @spec new(map()) :: t()
  def new(data) when is_map(data) do
    %__MODULE__{
      added: data["added"] || [],
      removed: data["removed"] || [],
      errors: data["errors"] || %{}
    }
  end
end

defimpl Jason.Encoder, for: ClaudeCode.McpSetServersResult do
  def encode(result, opts) do
    result
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.McpSetServersResult do
  def encode(result, encoder) do
    result
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
