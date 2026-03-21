defmodule ClaudeCode.System.RemoteTest do
  use ExUnit.Case, async: false

  alias ClaudeCode.System.Remote

  describe "cmd/3" do
    test "calls :rpc.call with the node from opts" do
      result = Remote.cmd("echo", ["hello"], node: node())
      assert {"hello\n", 0} = result
    end

    test "raises on badrpc" do
      assert_raise RuntimeError, ~r/Remote command failed/, fn ->
        Remote.cmd("echo", ["hello"], node: :"nonexistent@nowhere")
      end
    end

    test "strips :node from opts before passing to System.cmd" do
      result = Remote.cmd("echo", ["test"], node: node(), stderr_to_stdout: true)
      assert {"test\n", 0} = result
    end
  end

  describe "node_from_adapter_config/0" do
    test "falls back to adapter config when no node opt" do
      prev = Application.get_env(:claude_code, :adapter)
      Application.put_env(:claude_code, :adapter, {ClaudeCode.Adapter.Node, [node: node()]})

      try do
        result = Remote.cmd("echo", ["from_config"], [])
        assert {"from_config\n", 0} = result
      after
        if prev, do: Application.put_env(:claude_code, :adapter, prev),
        else: Application.delete_env(:claude_code, :adapter)
      end
    end

    test "raises descriptive error when no node configured" do
      prev = Application.get_env(:claude_code, :adapter)
      Application.delete_env(:claude_code, :adapter)

      try do
        assert_raise ArgumentError, ~r/No :node option provided/, fn ->
          Remote.cmd("echo", ["hello"], [])
        end
      after
        if prev, do: Application.put_env(:claude_code, :adapter, prev)
      end
    end
  end
end
