defmodule ClaudeCode.McpServerStatusTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.McpServerStatus

  describe "new/1" do
    test "parses connected server with full info" do
      data = %{
        "name" => "my-tools",
        "status" => "connected",
        "serverInfo" => %{"name" => "my-tools-server", "version" => "1.0.0"},
        "config" => %{"type" => "stdio", "command" => "npx"},
        "scope" => "project",
        "tools" => [%{"name" => "read_file", "description" => "Read a file"}]
      }

      status = McpServerStatus.new(data)

      assert status.name == "my-tools"
      assert status.status == :connected
      assert status.server_info == %{name: "my-tools-server", version: "1.0.0"}
      assert status.config == %{"type" => "stdio", "command" => "npx"}
      assert status.scope == "project"
      assert [%{"name" => "read_file"}] = status.tools
    end

    test "parses failed server with error" do
      data = %{
        "name" => "broken",
        "status" => "failed",
        "error" => "Connection refused"
      }

      status = McpServerStatus.new(data)

      assert status.status == :failed
      assert status.error == "Connection refused"
      assert status.server_info == nil
    end

    test "parses all status values" do
      for {wire, expected} <- [
            {"connected", :connected},
            {"failed", :failed},
            {"needs-auth", :needs_auth},
            {"pending", :pending},
            {"disabled", :disabled}
          ] do
        status = McpServerStatus.new(%{"name" => "s", "status" => wire})
        assert status.status == expected
      end
    end

    test "defaults unknown status to :pending" do
      status = McpServerStatus.new(%{"name" => "s", "status" => "unknown"})
      assert status.status == :pending
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON" do
      status = %McpServerStatus{name: "my-server", status: :connected}
      json = Jason.encode!(status)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "my-server"
      assert decoded["status"] == "connected"
    end
  end
end
