defmodule ClaudeCode.Sandbox do
  @moduledoc """
  Top-level sandbox configuration struct.

  Maps to the `SandboxSettings` type in the TS SDK. Provides bash command
  sandboxing with filesystem and network isolation.

  See the [official sandboxing documentation](https://code.claude.com/docs/en/sandboxing)
  for full details.

  ## Fields

    * `:enabled` - Enable bash sandboxing (macOS, Linux, and WSL2).
    * `:auto_allow_bash_if_sandboxed` - Auto-approve bash commands when sandboxed.
    * `:allow_unsandboxed_commands` - Allow commands to run outside sandbox via
      `dangerouslyDisableSandbox` parameter. When `false`, the escape hatch is disabled.
    * `:enable_weaker_nested_sandbox` - Enable weaker sandbox for unprivileged Docker
      environments (Linux and WSL2 only). Reduces security.
    * `:excluded_commands` - Commands that should run outside the sandbox.
    * `:ignore_violations` - Map of violation categories to ignore.
    * `:ripgrep` - Custom ripgrep binary configuration (`%{command: path, args: [flags]}`).
    * `:filesystem` - Filesystem isolation settings. See `ClaudeCode.Sandbox.Filesystem`.
    * `:network` - Network isolation settings. See `ClaudeCode.Sandbox.Network`.

  ## Examples

  Explicit sub-struct construction:

      sandbox = ClaudeCode.Sandbox.new(
        enabled: true,
        auto_allow_bash_if_sandboxed: true,
        filesystem: ClaudeCode.Sandbox.Filesystem.new(
          allow_write: ["/tmp/build"],
          deny_read: ["~/.aws/credentials"]
        ),
        network: ClaudeCode.Sandbox.Network.new(
          allowed_domains: ["*.example.com"],
          allow_local_binding: true
        )
      )

  Auto-wrapping from keyword lists (sub-structs are created automatically):

      sandbox = ClaudeCode.Sandbox.new(
        enabled: true,
        filesystem: [allow_write: ["/tmp/build"], deny_read: ["~/.aws/credentials"]],
        network: [allowed_domains: ["*.example.com"], allow_local_binding: true]
      )

  """

  alias ClaudeCode.Sandbox.Filesystem
  alias ClaudeCode.Sandbox.Helpers
  alias ClaudeCode.Sandbox.Network

  @fields [
    :enabled,
    :auto_allow_bash_if_sandboxed,
    :allow_unsandboxed_commands,
    :enable_weaker_nested_sandbox,
    :excluded_commands,
    :ignore_violations,
    :ripgrep,
    :filesystem,
    :network
  ]

  defstruct @fields

  @type t :: %__MODULE__{
          enabled: boolean() | nil,
          auto_allow_bash_if_sandboxed: boolean() | nil,
          allow_unsandboxed_commands: boolean() | nil,
          enable_weaker_nested_sandbox: boolean() | nil,
          excluded_commands: [String.t()] | nil,
          ignore_violations: %{String.t() => [String.t()]} | nil,
          ripgrep: map() | nil,
          filesystem: Filesystem.t() | nil,
          network: Network.t() | nil
        }

  @doc """
  Creates a new Sandbox struct.

  Accepts a keyword list or map (atom, string, or camelCase string keys).
  Unknown keys are ignored.

  When `:filesystem` or `:network` is a keyword list or map (not already a struct),
  it is automatically wrapped into the corresponding `ClaudeCode.Sandbox.Filesystem`
  or `ClaudeCode.Sandbox.Network` struct via their `new/1`.

  ## Examples

      iex> ClaudeCode.Sandbox.new(enabled: true, filesystem: [allow_write: ["/tmp"]])
      %ClaudeCode.Sandbox{enabled: true, auto_allow_bash_if_sandboxed: nil, allow_unsandboxed_commands: nil, enable_weaker_nested_sandbox: nil, excluded_commands: nil, ignore_violations: nil, ripgrep: nil, filesystem: %ClaudeCode.Sandbox.Filesystem{allow_write: ["/tmp"], deny_write: nil, deny_read: nil}, network: nil}

  """
  @spec new(keyword() | map()) :: t()
  def new(opts) when is_list(opts) do
    %__MODULE__{
      enabled: Keyword.get(opts, :enabled),
      auto_allow_bash_if_sandboxed: Keyword.get(opts, :auto_allow_bash_if_sandboxed),
      allow_unsandboxed_commands: Keyword.get(opts, :allow_unsandboxed_commands),
      enable_weaker_nested_sandbox: Keyword.get(opts, :enable_weaker_nested_sandbox),
      excluded_commands: Keyword.get(opts, :excluded_commands),
      ignore_violations: Keyword.get(opts, :ignore_violations),
      ripgrep: Keyword.get(opts, :ripgrep),
      filesystem: wrap_filesystem(Keyword.get(opts, :filesystem)),
      network: wrap_network(Keyword.get(opts, :network))
    }
  end

  def new(opts) when is_map(opts) do
    opts |> Helpers.normalize_map_keys(@fields) |> new()
  end

  @doc """
  Converts to the camelCase map expected by the CLI.

  Nil fields are omitted. Nested `filesystem` and `network` structs delegate
  to their own `to_settings_map/1` -- if the result is an empty map, the key
  is omitted entirely.
  """
  @spec to_settings_map(t()) :: map()
  def to_settings_map(%__MODULE__{} = sandbox) do
    %{}
    |> maybe_put("enabled", sandbox.enabled)
    |> maybe_put("autoAllowBashIfSandboxed", sandbox.auto_allow_bash_if_sandboxed)
    |> maybe_put("allowUnsandboxedCommands", sandbox.allow_unsandboxed_commands)
    |> maybe_put("enableWeakerNestedSandbox", sandbox.enable_weaker_nested_sandbox)
    |> maybe_put("excludedCommands", sandbox.excluded_commands)
    |> maybe_put("ignoreViolations", sandbox.ignore_violations)
    |> maybe_put("ripgrep", sandbox.ripgrep)
    |> maybe_put_nested("filesystem", sandbox.filesystem, &Filesystem.to_settings_map/1)
    |> maybe_put_nested("network", sandbox.network, &Network.to_settings_map/1)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_nested(map, _key, nil, _converter), do: map

  defp maybe_put_nested(map, key, struct, converter) do
    nested = converter.(struct)
    if nested == %{}, do: map, else: Map.put(map, key, nested)
  end

  defp wrap_filesystem(nil), do: nil
  defp wrap_filesystem(%Filesystem{} = fs), do: fs
  defp wrap_filesystem(opts) when is_list(opts) or is_map(opts), do: Filesystem.new(opts)

  defp wrap_network(nil), do: nil
  defp wrap_network(%Network{} = net), do: net
  defp wrap_network(opts) when is_list(opts) or is_map(opts), do: Network.new(opts)
end

defimpl Jason.Encoder, for: ClaudeCode.Sandbox do
  def encode(sandbox, opts) do
    sandbox
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Sandbox do
  def encode(sandbox, encoder) do
    sandbox
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
