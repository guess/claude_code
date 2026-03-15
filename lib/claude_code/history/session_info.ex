defmodule ClaudeCode.History.SessionInfo do
  @moduledoc """
  Metadata about a Claude Code session, extracted from session file stat + head/tail reads.

  This struct provides rich session listing without requiring full JSONL parsing,
  matching the Python SDK's `SDKSessionInfo` type.

  ## Fields

    * `:session_id` - UUID of the session
    * `:summary` - Display title (`custom_title || summary || first_prompt`)
    * `:last_modified` - Milliseconds since epoch
    * `:file_size` - File size in bytes
    * `:custom_title` - User-set custom title, if any
    * `:first_prompt` - First meaningful user prompt (truncated to 200 chars)
    * `:git_branch` - Git branch the session was on
    * `:cwd` - Working directory of the session
  """

  use ClaudeCode.JSONEncoder

  defstruct [
    :session_id,
    :summary,
    :last_modified,
    :file_size,
    :custom_title,
    :first_prompt,
    :git_branch,
    :cwd
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          summary: String.t() | nil,
          last_modified: integer(),
          file_size: integer(),
          custom_title: String.t() | nil,
          first_prompt: String.t() | nil,
          git_branch: String.t() | nil,
          cwd: String.t() | nil
        }
end
