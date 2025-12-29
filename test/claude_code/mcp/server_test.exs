defmodule ClaudeCode.MCP.ServerTest do
  use ExUnit.Case

  alias ClaudeCode.MCP.Server

  describe "stdio_command/1" do
    test "generates stdio command configuration" do
      result = Server.stdio_command(module: MyApp.MCPServer)

      assert result.command == "mix"
      assert result.args == ["run", "--no-halt", "-e", "MyApp.MCPServer.start_link(transport: :stdio)"]
      assert result.env["MIX_ENV"] == "prod"
    end

    test "allows custom mix_env" do
      result = Server.stdio_command(module: MyApp.MCPServer, mix_env: "dev")

      assert result.env["MIX_ENV"] == "dev"
    end

    test "raises when module is missing" do
      assert_raise KeyError, fn ->
        Server.stdio_command([])
      end
    end
  end

  # Integration tests for start_link/1 would require a real Hermes server module.
  # These are tested separately in integration tests or manually.
  # The key functionality (config generation) is tested via the Config module tests.
end
