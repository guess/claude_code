defmodule ClaudeCode.Input do
  @moduledoc """
  Builds input messages for stream-json input format.

  When using `--input-format stream-json`, the CLI accepts NDJSON messages via stdin.
  This module provides builders for the various message types.

  ## Message Format

  Messages are JSON objects with the following structure:

      %{
        type: "user",
        message: %{role: "user", content: "Your message"},
        session_id: "default",
        parent_tool_use_id: nil
      }

  ## Usage

      # Build a user message
      json = ClaudeCode.Input.user_message("Hello, Claude!")

      # With explicit session ID
      json = ClaudeCode.Input.user_message("Hello!", "my-session-123")

  """

  @doc """
  Builds a user message for stream-json input.

  ## Parameters

    * `content` - The message content (string)
    * `session_id` - Session ID for conversation continuity (default: "default")
    * `opts` - Additional options:
      * `:parent_tool_use_id` - Tool use ID if responding to a tool (default: nil)

  ## Examples

      iex> ClaudeCode.Input.user_message("What is 2 + 2?")
      ~s({"type":"user","message":{"role":"user","content":"What is 2 + 2?"},"session_id":"default","parent_tool_use_id":null})

      iex> ClaudeCode.Input.user_message("Hello", "session-123")
      ~s({"type":"user","message":{"role":"user","content":"Hello"},"session_id":"session-123","parent_tool_use_id":null})

  """
  @spec user_message(String.t(), String.t(), keyword()) :: String.t()
  def user_message(content, session_id \\ "default", opts \\ []) do
    parent_tool_use_id = Keyword.get(opts, :parent_tool_use_id)

    Jason.encode!(%{
      type: "user",
      message: %{role: "user", content: content},
      session_id: session_id,
      parent_tool_use_id: parent_tool_use_id
    })
  end

  @doc """
  Builds a tool response message for stream-json input.

  Use this when responding to a tool use request from Claude.

  ## Parameters

    * `tool_use_id` - The ID of the tool use being responded to
    * `result` - The result of the tool execution (string or map)
    * `session_id` - Session ID for conversation continuity
    * `opts` - Additional options:
      * `:is_error` - Whether the tool execution resulted in an error (default: false)

  ## Examples

      iex> ClaudeCode.Input.tool_response("tool-123", "File created", "session-456")
      # Returns JSON with tool result

  """
  @spec tool_response(String.t(), String.t() | map(), String.t(), keyword()) :: String.t()
  def tool_response(tool_use_id, result, session_id, opts \\ []) do
    is_error = Keyword.get(opts, :is_error, false)

    content =
      case result do
        result when is_binary(result) -> result
        result when is_map(result) -> Jason.encode!(result)
      end

    Jason.encode!(%{
      type: "user",
      message: %{
        role: "user",
        content: [%{type: "tool_result", tool_use_id: tool_use_id, content: content, is_error: is_error}]
      },
      session_id: session_id,
      parent_tool_use_id: tool_use_id
    })
  end
end
