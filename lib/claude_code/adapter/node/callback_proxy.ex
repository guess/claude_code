defmodule ClaudeCode.Adapter.Node.CallbackProxy do
  @moduledoc false

  use GenServer

  alias ClaudeCode.Adapter.ControlHandler
  alias ClaudeCode.Adapter.Port, as: AdapterPort
  alias ClaudeCode.Hook.Registry, as: HookRegistry

  require Logger

  defstruct [:sdk_mcp_servers, :hook_registry]

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      sdk_mcp_servers: AdapterPort.extract_sdk_mcp_servers(Keyword.take(opts, [:mcp_servers])),
      hook_registry: Keyword.get(opts, :hook_registry, %HookRegistry{})
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:control_request, msg}, _from, state) do
    request = get_in(msg, ["request"])
    subtype = get_in(request, ["subtype"])
    response = dispatch(subtype, request, state)
    {:reply, response, state}
  end

  defp dispatch("mcp_message", request, state) do
    server_name = request["server_name"]
    jsonrpc = request["message"]
    {:ok, ControlHandler.handle_mcp_message(server_name, jsonrpc, state.sdk_mcp_servers)}
  end

  defp dispatch("hook_callback", request, state) do
    ControlHandler.handle_hook_callback(request, state.hook_registry)
  end

  defp dispatch("can_use_tool", request, state) do
    {:ok, ControlHandler.handle_can_use_tool(request, state.hook_registry, %{})}
  end

  defp dispatch(subtype, _request, _state) do
    Logger.warning("CallbackProxy received unhandled control request: #{subtype}")
    {:error, "Unhandled control request: #{subtype}"}
  end

  # Silently discard messages not meant for this GenServer (e.g. Plug's
  # {:plug_conn, :sent} notification or async HTTP response tuples that
  # arrive when the proxy PID happens to be the conn owner process).
  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
