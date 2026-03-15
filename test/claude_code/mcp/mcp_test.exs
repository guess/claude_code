defmodule ClaudeCode.MCPTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP

  describe "backend_for/1" do
    test "returns :sdk for SDK server modules" do
      assert MCP.backend_for(ClaudeCode.TestTools) == :sdk
    end

    test "returns {:subprocess, Backend.Hermes} for Hermes-compatible modules" do
      defmodule FakeHermesServer do
        @moduledoc false
        def start_link(_opts), do: {:ok, self()}
      end

      assert MCP.backend_for(FakeHermesServer) == {:subprocess, ClaudeCode.MCP.Backend.Hermes}
    end

    test "returns :unknown for unrecognized modules" do
      assert MCP.backend_for(String) == :unknown
    end

    test "returns :unknown for non-existent modules" do
      assert MCP.backend_for(DoesNotExist) == :unknown
    end
  end
end
