defmodule ClaudeCode.Message.SystemMessage do
  @moduledoc """
  Umbrella module for system message subtypes from the Claude CLI.

  System messages are emitted by the CLI for session initialization,
  hook lifecycle events, status updates, task progress, and other
  informational events. Each subtype has its own struct module under
  `ClaudeCode.Message.SystemMessage.*`.
  """

  alias __MODULE__.CompactBoundary
  alias __MODULE__.ElicitationComplete
  alias __MODULE__.FilesPersisted
  alias __MODULE__.HookProgress
  alias __MODULE__.HookResponse
  alias __MODULE__.HookStarted
  alias __MODULE__.Init
  alias __MODULE__.LocalCommandOutput
  alias __MODULE__.Status
  alias __MODULE__.TaskNotification
  alias __MODULE__.TaskProgress
  alias __MODULE__.TaskStarted

  @type t ::
          Init.t()
          | CompactBoundary.t()
          | HookStarted.t()
          | HookResponse.t()
          | HookProgress.t()
          | Status.t()
          | LocalCommandOutput.t()
          | FilesPersisted.t()
          | ElicitationComplete.t()
          | TaskStarted.t()
          | TaskProgress.t()
          | TaskNotification.t()

  @doc """
  Checks if a value is any type of system message.
  """
  @spec type?(any()) :: boolean()
  def type?(%Init{}), do: true
  def type?(%CompactBoundary{}), do: true
  def type?(%HookStarted{}), do: true
  def type?(%HookResponse{}), do: true
  def type?(%HookProgress{}), do: true
  def type?(%Status{}), do: true
  def type?(%LocalCommandOutput{}), do: true
  def type?(%FilesPersisted{}), do: true
  def type?(%ElicitationComplete{}), do: true
  def type?(%TaskStarted{}), do: true
  def type?(%TaskProgress{}), do: true
  def type?(%TaskNotification{}), do: true
  def type?(_), do: false
end
