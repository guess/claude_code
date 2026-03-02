defmodule ClaudeCode.Sandbox.Filesystem do
  @moduledoc """
  Filesystem isolation settings for sandbox configuration.

  Maps to the `SandboxFilesystemConfig` type in the TS SDK.

  ## Fields

    * `:allow_write` - Additional paths where sandboxed commands can write.
      Arrays merge across settings scopes.
    * `:deny_write` - Paths where sandboxed commands cannot write.
      Arrays merge across settings scopes.
    * `:deny_read` - Paths where sandboxed commands cannot read.
      Arrays merge across settings scopes.

  ## Path Prefixes

  | Prefix | Meaning | Example |
  |--------|---------|---------|
  | `//` | Absolute path from filesystem root | `//tmp/build` -> `/tmp/build` |
  | `~/` | Relative to home directory | `~/.kube` -> `$HOME/.kube` |
  | `/` | Relative to settings file directory | `/build` -> `$SETTINGS_DIR/build` |
  | `./` or none | Relative path | `./output` |

  ## Examples

      iex> ClaudeCode.Sandbox.Filesystem.new(allow_write: ["/tmp/build", "~/.kube"], deny_read: ["~/.aws/credentials"])
      %ClaudeCode.Sandbox.Filesystem{allow_write: ["/tmp/build", "~/.kube"], deny_write: nil, deny_read: ["~/.aws/credentials"]}

  """

  alias ClaudeCode.Sandbox.Helpers

  @fields [:allow_write, :deny_write, :deny_read]

  defstruct @fields

  @type t :: %__MODULE__{
          allow_write: [String.t()] | nil,
          deny_write: [String.t()] | nil,
          deny_read: [String.t()] | nil
        }

  @doc """
  Creates a new Filesystem struct.

  Accepts a keyword list or map (atom or string keys). Unknown keys are ignored.
  """
  @spec new(keyword() | map()) :: t()
  def new(opts) when is_list(opts) do
    struct(__MODULE__, opts)
  end

  def new(opts) when is_map(opts) do
    opts |> Helpers.normalize_map_keys(@fields) |> new()
  end

  @doc """
  Converts to the camelCase map expected by the CLI.
  """
  @spec to_settings_map(t()) :: map()
  def to_settings_map(%__MODULE__{} = fs) do
    %{}
    |> maybe_put("allowWrite", fs.allow_write)
    |> maybe_put("denyWrite", fs.deny_write)
    |> maybe_put("denyRead", fs.deny_read)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Jason.Encoder, for: ClaudeCode.Sandbox.Filesystem do
  def encode(fs, opts) do
    fs
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Sandbox.Filesystem do
  def encode(fs, encoder) do
    fs
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
