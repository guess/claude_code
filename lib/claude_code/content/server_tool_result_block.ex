defmodule ClaudeCode.Content.ServerToolResultBlock do
  @moduledoc """
  Represents a server-side tool result content block within a Claude message.

  Server tool result blocks contain the output from server-side tool executions
  such as web_search, web_fetch, code_execution, bash_code_execution,
  text_editor_code_execution, and tool_search. Unlike regular tool_result blocks,
  these results come from tools executed by the API itself.

  The `type` field distinguishes the specific tool (e.g., `:web_search_tool_result`,
  `:code_execution_tool_result`), mirroring how `ServerToolUseBlock` uses its
  `name` field for the use side.

  ## Known Types

  - `:web_search_tool_result` - Web search results or error
  - `:web_fetch_tool_result` - Web page fetch results or error
  - `:code_execution_tool_result` - Code execution results, errors, or encrypted results
  - `:bash_code_execution_tool_result` - Bash code execution results or error
  - `:text_editor_code_execution_tool_result` - Text editor code execution results or error
  - `:tool_search_tool_result` - Tool search results or error
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :tool_use_id, :content]
  defstruct [:type, :tool_use_id, :content, :caller]

  @type server_tool_result_type ::
          :web_search_tool_result
          | :web_fetch_tool_result
          | :code_execution_tool_result
          | :bash_code_execution_tool_result
          | :text_editor_code_execution_tool_result
          | :tool_search_tool_result

  @type t :: %__MODULE__{
          type: server_tool_result_type(),
          tool_use_id: String.t(),
          content: term(),
          caller: map() | nil
        }

  @type_mapping %{
    "web_search_tool_result" => :web_search_tool_result,
    "web_fetch_tool_result" => :web_fetch_tool_result,
    "code_execution_tool_result" => :code_execution_tool_result,
    "bash_code_execution_tool_result" => :bash_code_execution_tool_result,
    "text_editor_code_execution_tool_result" => :text_editor_code_execution_tool_result,
    "tool_search_tool_result" => :tool_search_tool_result
  }

  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => type} = data) when is_map_key(@type_mapping, type) do
    required = ["tool_use_id", "content"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      {:ok,
       %__MODULE__{
         type: @type_mapping[type],
         tool_use_id: data["tool_use_id"],
         content: data["content"],
         caller: data["caller"]
       }}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}
end

defimpl String.Chars, for: ClaudeCode.Content.ServerToolResultBlock do
  def to_string(%{type: type}), do: "[#{type}]"
end
