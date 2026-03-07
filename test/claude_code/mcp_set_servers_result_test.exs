defmodule ClaudeCode.McpSetServersResultTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.McpSetServersResult

  describe "new/1" do
    test "parses all fields from JSON map" do
      data = %{
        "added" => ["server-a", "server-b"],
        "removed" => ["server-c"],
        "errors" => %{"server-d" => "Connection refused"}
      }

      result = McpSetServersResult.new(data)

      assert result.added == ["server-a", "server-b"]
      assert result.removed == ["server-c"]
      assert result.errors == %{"server-d" => "Connection refused"}
    end

    test "defaults to empty collections" do
      result = McpSetServersResult.new(%{})

      assert result.added == []
      assert result.removed == []
      assert result.errors == %{}
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON" do
      result = %McpSetServersResult{added: ["a"], removed: ["b"], errors: %{"c" => "err"}}
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert decoded["added"] == ["a"]
      assert decoded["removed"] == ["b"]
      assert decoded["errors"] == %{"c" => "err"}
    end
  end
end
