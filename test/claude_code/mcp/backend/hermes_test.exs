defmodule ClaudeCode.MCP.Backend.HermesTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Backend.Hermes, as: Backend

  describe "compatible?/1" do
    test "returns true for modules with start_link/1 that are not SDK servers" do
      defmodule FakeHermesModule do
        @moduledoc false
        @behaviour Hermes.Server

        def start_link(_opts), do: {:ok, self()}
      end

      assert Backend.compatible?(FakeHermesModule)
    end

    test "returns false for SDK server modules" do
      refute Backend.compatible?(ClaudeCode.TestTools)
    end

    test "returns false for regular modules" do
      refute Backend.compatible?(String)
    end

    test "returns false for non-existent modules" do
      refute Backend.compatible?(DoesNotExist)
    end
  end
end
