defmodule ClaudeCode.Types do
  @moduledoc """
  Type definitions for the ClaudeCode SDK.

  These types match the official Claude SDK schema for messages
  returned from the CLI with --output-format stream-json.
  """
  
  alias ClaudeCode.Content

  @type model :: String.t()

  @type stop_reason :: :end_turn | :max_tokens | :stop_sequence | :tool_use | nil

  @type role :: :user | :assistant

  @type session_id :: String.t()

  @type permission_mode :: :default | :accept_edits | :bypass_permissions | :plan

  @type result_subtype :: :success | :error_max_turns | :error_during_execution

  @type usage :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cache_creation_input_tokens: non_neg_integer() | nil,
          cache_read_input_tokens: non_neg_integer() | nil,
          server_tool_use: server_tool_usage() | nil
        }

  @type server_tool_usage :: %{
          web_search_requests: non_neg_integer()
        }

  @type mcp_server :: %{
          name: String.t(),
          status: String.t()
        }

  @type message_content :: String.t() | [Content.t()]

  @type message :: %{
          id: String.t(),
          type: :message,
          role: role(),
          content: [Content.t()],
          model: model(),
          stop_reason: stop_reason(),
          stop_sequence: String.t() | nil,
          usage: usage()
        }

  @type message_param :: %{
          content: message_content(),
          role: role()
        }
end
