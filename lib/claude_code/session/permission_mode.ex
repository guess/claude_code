defmodule ClaudeCode.Session.PermissionMode do
  @moduledoc """
  Permission mode for controlling how Claude handles permission requests.

  ## Values

    * `:default` - Standard permission prompting
    * `:accept_edits` - Auto-accept file edits without prompting
    * `:bypass_permissions` - Bypass all permission checks (requires `:allow_dangerously_skip_permissions`)
    * `:delegate` - Delegate permission decisions
    * `:dont_ask` - Never prompt for permissions
    * `:plan` - Planning mode only
  """

  @type t ::
          :default
          | :accept_edits
          | :bypass_permissions
          | :delegate
          | :dont_ask
          | :plan
          | String.t()

  @mapping %{
    "default" => :default,
    "acceptEdits" => :accept_edits,
    "bypassPermissions" => :bypass_permissions,
    "delegate" => :delegate,
    "dontAsk" => :dont_ask,
    "plan" => :plan
  }

  @doc """
  Parses a camelCase permission mode string from the CLI into an atom.

  Returns `nil_fallback` (default `nil`) for nil input. Unrecognized string
  values are kept as strings for forward compatibility.

  ## Examples

      iex> ClaudeCode.Session.PermissionMode.parse("default")
      :default

      iex> ClaudeCode.Session.PermissionMode.parse("acceptEdits")
      :accept_edits

      iex> ClaudeCode.Session.PermissionMode.parse("bypassPermissions")
      :bypass_permissions

      iex> ClaudeCode.Session.PermissionMode.parse("futureMode")
      "futureMode"

      iex> ClaudeCode.Session.PermissionMode.parse(nil)
      nil

      iex> ClaudeCode.Session.PermissionMode.parse(nil, :default)
      :default

  """
  @spec parse(String.t() | nil, t() | nil) :: t() | nil
  def parse(value, nil_fallback \\ nil)
  def parse(value, _nil_fallback) when is_binary(value), do: Map.get(@mapping, value, value)
  def parse(_nil, nil_fallback), do: nil_fallback

  @doc """
  Encodes a permission mode atom to its camelCase CLI string.

  ## Examples

      iex> ClaudeCode.Session.PermissionMode.encode(:default)
      "default"

      iex> ClaudeCode.Session.PermissionMode.encode(:accept_edits)
      "acceptEdits"

      iex> ClaudeCode.Session.PermissionMode.encode(:bypass_permissions)
      "bypassPermissions"

  """
  @spec encode(t()) :: String.t()
  def encode(:default), do: "default"
  def encode(:accept_edits), do: "acceptEdits"
  def encode(:bypass_permissions), do: "bypassPermissions"
  def encode(:delegate), do: "delegate"
  def encode(:dont_ask), do: "dontAsk"
  def encode(:plan), do: "plan"
  def encode(mode) when is_binary(mode), do: mode
end
