defmodule ClaudeCode.MCP.StatusTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Status, as: ServerStatus

  describe "new/1" do
    test "parses connected server with full info" do
      data = %{
        "name" => "my-tools",
        "status" => "connected",
        "server_info" => %{"name" => "my-tools-server", "version" => "1.0.0"},
        "config" => %{"type" => "stdio", "command" => "npx"},
        "scope" => "project",
        "tools" => [%{"name" => "read_file", "description" => "Read a file"}]
      }

      status = ServerStatus.new(data)

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

      status = ServerStatus.new(data)

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
        status = ServerStatus.new(%{"name" => "s", "status" => wire})
        assert status.status == expected
      end
    end

    test "defaults unknown status to :pending" do
      status = ServerStatus.new(%{"name" => "s", "status" => "unknown"})
      assert status.status == :pending
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON" do
      status = %ServerStatus{name: "my-server", status: :connected}
      json = Jason.encode!(status)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "my-server"
      assert decoded["status"] == "connected"
    end
  end
end
