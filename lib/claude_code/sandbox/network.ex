defmodule ClaudeCode.Sandbox.Network do
  @moduledoc """
  Network isolation settings for sandbox configuration.

  Maps to the `SandboxNetworkConfig` type in the TS SDK.

  ## Fields

    * `:allowed_domains` - Domains to allow for outbound network traffic.
      Supports wildcards (e.g., `*.example.com`).
    * `:allow_managed_domains_only` - (Managed settings only) Only managed
      settings' `allowedDomains` and WebFetch allow rules are respected.
    * `:allow_unix_sockets` - Unix socket paths accessible in sandbox
      (SSH agents, etc.).
    * `:allow_all_unix_sockets` - Allow all Unix socket connections in sandbox.
    * `:allow_local_binding` - Allow binding to localhost ports (macOS only).
    * `:http_proxy_port` - HTTP proxy port if bringing your own proxy.
    * `:socks_proxy_port` - SOCKS5 proxy port if bringing your own proxy.

  ## Examples

      iex> ClaudeCode.Sandbox.Network.new(allowed_domains: ["*.example.com"], allow_local_binding: true)
      %ClaudeCode.Sandbox.Network{allowed_domains: ["*.example.com"], allow_managed_domains_only: nil, allow_unix_sockets: nil, allow_all_unix_sockets: nil, allow_local_binding: true, http_proxy_port: nil, socks_proxy_port: nil}

  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.Sandbox.Helpers

  @fields [
    :allowed_domains,
    :allow_managed_domains_only,
    :allow_unix_sockets,
    :allow_all_unix_sockets,
    :allow_local_binding,
    :http_proxy_port,
    :socks_proxy_port
  ]

  defstruct @fields

  @type t :: %__MODULE__{
          allowed_domains: [String.t()] | nil,
          allow_managed_domains_only: boolean() | nil,
          allow_unix_sockets: [String.t()] | nil,
          allow_all_unix_sockets: boolean() | nil,
          allow_local_binding: boolean() | nil,
          http_proxy_port: non_neg_integer() | nil,
          socks_proxy_port: non_neg_integer() | nil
        }

  @doc """
  Creates a new Network struct.

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
  def to_settings_map(%__MODULE__{} = net) do
    %{}
    |> maybe_put("allowedDomains", net.allowed_domains)
    |> maybe_put("allowManagedDomainsOnly", net.allow_managed_domains_only)
    |> maybe_put("allowUnixSockets", net.allow_unix_sockets)
    |> maybe_put("allowAllUnixSockets", net.allow_all_unix_sockets)
    |> maybe_put("allowLocalBinding", net.allow_local_binding)
    |> maybe_put("httpProxyPort", net.http_proxy_port)
    |> maybe_put("socksProxyPort", net.socks_proxy_port)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
