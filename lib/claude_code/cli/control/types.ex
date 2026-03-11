defmodule ClaudeCode.CLI.Control.Types do
  @moduledoc """
  Type definitions for control protocol responses.

  These types describe the shape of maps returned by control protocol
  operations like `ClaudeCode.Session.set_mcp_servers/2` and `ClaudeCode.Session.rewind_files/2`.
  """

  @typedoc """
  Result of a `ClaudeCode.Session.set_mcp_servers/2` operation.

  ## Fields

    * `:added` - Names of servers that were added
    * `:removed` - Names of servers that were removed
    * `:errors` - Map of server names to error messages for servers that failed to connect
  """
  @type set_servers_result :: %{
          added: [String.t()],
          removed: [String.t()],
          errors: %{String.t() => String.t()}
        }

  @typedoc """
  Result of a `ClaudeCode.Session.rewind_files/2` operation.

  ## Fields

    * `:can_rewind` - Whether the rewind can be performed
    * `:error` - Error message if rewind cannot be performed
    * `:files_changed` - List of file paths that were changed
    * `:insertions` - Number of line insertions
    * `:deletions` - Number of line deletions
  """
  @type rewind_files_result :: %{
          can_rewind: boolean(),
          error: String.t() | nil,
          files_changed: [String.t()] | nil,
          insertions: non_neg_integer() | nil,
          deletions: non_neg_integer() | nil
        }

  @typedoc """
  Response from session initialization (matches `SDKControlInitializeResponse`).

  Returned by `ClaudeCode.Session.server_info/1`.
  """
  @type initialize_response :: %{
          commands: [ClaudeCode.Session.SlashCommand.t()],
          agents: [ClaudeCode.Session.AgentInfo.t()],
          models: [ClaudeCode.Model.Info.t()],
          account: ClaudeCode.Session.AccountInfo.t() | nil,
          output_style: String.t() | nil,
          available_output_styles: [String.t()],
          fast_mode_state: String.t() | nil
        }
end
