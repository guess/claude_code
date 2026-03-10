defmodule ClaudeCode.Content.ServerToolUseBlock do
  @moduledoc """
  Represents a server-side tool use content block within a Claude message.

  Server tool use blocks indicate that the API is invoking a server-side tool
  such as web_search, web_fetch, code_execution, or text_editor_code_execution.
  Unlike regular tool_use blocks, these are handled by the API itself rather
  than by the client.
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :id, :name, :input]
  defstruct [:type, :id, :name, :input, :caller]

  @type server_tool_name ::
          :web_search
          | :web_fetch
          | :code_execution
          | :bash_code_execution
          | :text_editor_code_execution
          | :tool_search_tool_regex
          | :tool_search_tool_bm25
          | String.t()

  @type t :: %__MODULE__{
          type: :server_tool_use,
          id: String.t(),
          name: server_tool_name(),
          input: map(),
          caller: map() | nil
        }

  @known_names ~w(web_search web_fetch code_execution bash_code_execution text_editor_code_execution tool_search_tool_regex tool_search_tool_bm25)

  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "server_tool_use"} = data) do
    required = ["id", "name", "input"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      {:ok,
       %__MODULE__{
         type: :server_tool_use,
         id: data["id"],
         name: parse_name(data["name"]),
         input: data["input"],
         caller: data["caller"]
       }}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}
  defp parse_name(name) when name in @known_names, do: String.to_atom(name)
  defp parse_name(name) when is_binary(name), do: name
end

defimpl String.Chars, for: ClaudeCode.Content.ServerToolUseBlock do
  def to_string(%{name: name}), do: "[server tool: #{name}]"
end
