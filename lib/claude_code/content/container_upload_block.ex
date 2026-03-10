defmodule ClaudeCode.Content.ContainerUploadBlock do
  @moduledoc """
  Represents a container upload content block within a Claude message.

  Container upload blocks reference a file to be uploaded to or from a container.
  The file is identified by its `file_id`.
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :file_id]
  defstruct [:type, :file_id]

  @type t :: %__MODULE__{
          type: :container_upload,
          file_id: String.t()
        }

  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "container_upload", "file_id" => file_id}) do
    {:ok, %__MODULE__{type: :container_upload, file_id: file_id}}
  end

  def new(%{"type" => "container_upload"}), do: {:error, {:missing_fields, [:file_id]}}
  def new(_), do: {:error, :invalid_content_type}
end

defimpl String.Chars, for: ClaudeCode.Content.ContainerUploadBlock do
  def to_string(%{file_id: file_id}), do: "[container upload: #{file_id}]"
end
