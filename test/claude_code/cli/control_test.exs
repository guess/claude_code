defmodule ClaudeCode.CLI.ControlTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.CLI.Control

  describe "classify/1" do
    test "classifies control_response messages" do
      msg = %{"type" => "control_response", "response" => %{}}
      assert {:control_response, ^msg} = Control.classify(msg)
    end

    test "classifies control_request messages" do
      msg = %{"type" => "control_request", "request_id" => "req_1", "request" => %{}}
      assert {:control_request, ^msg} = Control.classify(msg)
    end

    test "classifies regular messages" do
      msg = %{"type" => "assistant", "message" => %{}}
      assert {:message, ^msg} = Control.classify(msg)
    end

    test "classifies system messages as regular messages" do
      msg = %{"type" => "system", "subtype" => "init"}
      assert {:message, ^msg} = Control.classify(msg)
    end

    test "classifies result messages as regular messages" do
      msg = %{"type" => "result", "subtype" => "success"}
      assert {:message, ^msg} = Control.classify(msg)
    end
  end

  describe "generate_request_id/1" do
    test "generates request ID with counter prefix" do
      id = Control.generate_request_id(0)
      assert String.starts_with?(id, "req_0_")
    end

    test "generates request ID with incrementing counter" do
      id = Control.generate_request_id(42)
      assert String.starts_with?(id, "req_42_")
    end

    test "generates unique request IDs" do
      id1 = Control.generate_request_id(1)
      id2 = Control.generate_request_id(1)
      assert id1 != id2
    end

    test "includes hex suffix" do
      id = Control.generate_request_id(0)
      [_req, _counter, hex] = String.split(id, "_")
      assert Regex.match?(~r/^[0-9a-f]+$/, hex)
    end
  end

  describe "initialize_request/3" do
    test "builds initialize request JSON" do
      json = Control.initialize_request("req_1_abc")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_1_abc"
      assert decoded["request"]["subtype"] == "initialize"
    end

    test "includes hooks when provided" do
      hooks = %{"PreToolUse" => [%{"matcher" => "Bash"}]}
      json = Control.initialize_request("req_1_abc", hooks)
      decoded = Jason.decode!(json)

      assert decoded["request"]["hooks"] == hooks
    end

    test "includes agents when provided" do
      agents = %{"reviewer" => %{"prompt" => "Review code"}}
      json = Control.initialize_request("req_1_abc", nil, agents)
      decoded = Jason.decode!(json)

      assert decoded["request"]["agents"] == agents
    end

    test "produces single-line JSON (no newlines)" do
      json = Control.initialize_request("req_1_abc")
      refute String.contains?(json, "\n")
    end
  end

  describe "set_model_request/2" do
    test "builds set_model request JSON" do
      json = Control.set_model_request("req_2_def", "claude-sonnet-4-5-20250929")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_2_def"
      assert decoded["request"]["subtype"] == "set_model"
      assert decoded["request"]["model"] == "claude-sonnet-4-5-20250929"
    end
  end

  describe "set_permission_mode_request/2" do
    test "builds set_permission_mode request JSON" do
      json = Control.set_permission_mode_request("req_3_ghi", "bypassPermissions")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_3_ghi"
      assert decoded["request"]["subtype"] == "set_permission_mode"
      assert decoded["request"]["permission_mode"] == "bypassPermissions"
    end
  end

  describe "rewind_files_request/2" do
    test "builds rewind_files request JSON" do
      json = Control.rewind_files_request("req_4_jkl", "user-msg-uuid-123")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_4_jkl"
      assert decoded["request"]["subtype"] == "rewind_files"
      assert decoded["request"]["user_message_id"] == "user-msg-uuid-123"
    end
  end

  describe "mcp_status_request/1" do
    test "builds mcp_status request JSON" do
      json = Control.mcp_status_request("req_5_mno")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_5_mno"
      assert decoded["request"]["subtype"] == "mcp_status"
    end
  end

  describe "success_response/2" do
    test "builds success control response JSON" do
      json = Control.success_response("req_1_abc", %{status: "ok"})
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_response"
      assert decoded["response"]["subtype"] == "success"
      assert decoded["response"]["request_id"] == "req_1_abc"
      assert decoded["response"]["response"]["status"] == "ok"
    end

    test "produces single-line JSON" do
      json = Control.success_response("req_1_abc", %{})
      refute String.contains?(json, "\n")
    end
  end

  describe "error_response/2" do
    test "builds error control response JSON" do
      json = Control.error_response("req_1_abc", "Not implemented: can_use_tool")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_response"
      assert decoded["response"]["subtype"] == "error"
      assert decoded["response"]["request_id"] == "req_1_abc"
      assert decoded["response"]["error"] == "Not implemented: can_use_tool"
    end
  end

  describe "parse_control_response/1" do
    test "parses success control response" do
      msg = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => "req_1_abc",
          "response" => %{"model" => "claude-3"}
        }
      }

      assert {:ok, "req_1_abc", %{"model" => "claude-3"}} = Control.parse_control_response(msg)
    end

    test "parses error control response" do
      msg = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "error",
          "request_id" => "req_2_def",
          "error" => "Unknown request type"
        }
      }

      assert {:error, "req_2_def", "Unknown request type"} = Control.parse_control_response(msg)
    end

    test "returns error for missing response field" do
      msg = %{"type" => "control_response"}
      assert {:error, nil, "Invalid control response: missing response field"} = Control.parse_control_response(msg)
    end

    test "returns error for unknown subtype" do
      msg = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "unknown",
          "request_id" => "req_3_ghi"
        }
      }

      assert {:error, "req_3_ghi", "Unknown control response subtype: unknown"} =
               Control.parse_control_response(msg)
    end
  end
end
