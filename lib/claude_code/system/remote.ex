defmodule ClaudeCode.System.Remote do
  @moduledoc false
  @behaviour ClaudeCode.System

  require Logger

  @impl true
  def cmd(command, args, opts) do
    {node_opt, sys_opts} = Keyword.pop(opts, :node)
    node = node_opt || node_from_adapter_config()

    Logger.debug("Executing remote command on #{node}: #{command} #{inspect(args)}")

    case :rpc.call(node, System, :cmd, [command, args, sys_opts]) do
      {:badrpc, reason} ->
        raise "Remote command failed on #{node}: #{inspect(reason)}"

      result ->
        result
    end
  end

  defp node_from_adapter_config do
    case Application.get_env(:claude_code, :adapter) do
      {ClaudeCode.Adapter.Node, opts} ->
        Keyword.fetch!(opts, :node)

      other ->
        raise ArgumentError,
              "No :node option provided and no adapter node configured. " <>
                "Pass node: explicitly or configure adapter: {ClaudeCode.Adapter.Node, node: ...}. " <>
                "Got adapter config: #{inspect(other)}"
    end
  end
end
