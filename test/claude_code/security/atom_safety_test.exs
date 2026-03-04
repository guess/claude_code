defmodule ClaudeCode.Security.AtomSafetyTest do
  use ExUnit.Case, async: false

  alias ClaudeCode.Adapter.ControlHandler
  alias ClaudeCode.Hook.Registry, as: HookRegistry
  alias ClaudeCode.MCP.Router
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage

  defmodule AtomAuditTools do
    @moduledoc false
    use ClaudeCode.MCP.Server, name: "atom-audit-tools"

    tool :echo, "Echo params" do
      field(:known, :string)

      def execute(_params) do
        {:ok, "ok"}
      end
    end
  end

  describe "tier 2 enums remain atomized" do
    # Bounded enum atomization is intentional; atom-safety hardening targets open-ended key spaces.
    test "assistant unknown stop_reason is atomized" do
      payload = put_in(assistant_payload(), ["message", "stop_reason"], "future_stop_reason")

      assert {:ok, message} = AssistantMessage.new(payload)
      assert message.message.stop_reason == :future_stop_reason
    end

    test "result unknown subtype is atomized" do
      payload = Map.put(result_payload(), "subtype", "future_result_subtype")

      assert {:ok, message} = ResultMessage.new(payload)
      assert message.subtype == :future_result_subtype
    end

    test "system unknown subtype is atomized" do
      payload = %{
        "type" => "system",
        "subtype" => "future_system_subtype",
        "session_id" => "session-1",
        "custom_field" => "custom-value"
      }

      assert {:ok, message} = SystemMessage.new(payload)
      assert message.subtype == :future_system_subtype
    end

    test "partial assistant unknown event type is atomized" do
      payload = %{
        "type" => "stream_event",
        "session_id" => "session-1",
        "event" => %{"type" => "future_event_type"}
      }

      assert {:ok, message} = PartialAssistantMessage.new(payload)
      assert message.event.type == :future_event_type
    end
  end

  describe "tier 3 and tier 4 keep unbounded keys as strings" do
    test "partial assistant unknown usage keys stay strings and avoid atom growth" do
      atoms_added =
        atom_growth(200, fn i ->
          usage_key = "usage_metric_#{i}_#{unique_suffix()}"

          payload = %{
            "type" => "stream_event",
            "session_id" => "session-1",
            "event" => %{
              "type" => "message_delta",
              "usage" => %{usage_key => i, "output_tokens" => 10}
            }
          }

          assert {:ok, message} = PartialAssistantMessage.new(payload)
          assert Map.has_key?(message.event.usage, usage_key)
          assert message.event.usage[:output_tokens] == 10
        end)

      assert atoms_added <= 60
    end

    test "control handler keeps unknown hook keys as strings without atom growth" do
      test_pid = self()

      hook = fn input, _tool_use_id ->
        send(test_pid, {:hook_input, input})
        :allow
      end

      {registry, _wire} = HookRegistry.new(%{PreToolUse: [%{hooks: [hook]}]}, nil)

      atoms_added =
        atom_growth(200, fn i ->
          dynamic_key = "dyn_key_#{i}_#{unique_suffix()}"

          request = %{
            "callback_id" => "hook_0",
            "input" => %{"tool_name" => "Bash", dynamic_key => "ls"},
            "tool_use_id" => nil
          }

          _ = ControlHandler.handle_hook_callback(request, registry)
          assert_receive {:hook_input, input}, 1000
          assert input.tool_name == "Bash"
          assert input[dynamic_key] == "ls"
        end)

      assert atoms_added <= 60
    end

    test "mcp router does not atomize unknown argument keys" do
      atoms_added =
        atom_growth(200, fn i ->
          dynamic_key = "dyn_arg_#{i}_#{unique_suffix()}"

          message = %{
            "jsonrpc" => "2.0",
            "id" => i,
            "method" => "tools/call",
            "params" => %{
              "name" => "echo",
              "arguments" => %{"known" => "value", dynamic_key => "x"}
            }
          }

          response = Router.handle_request(AtomAuditTools, message)
          assert response["result"]["isError"] == false
        end)

      assert atoms_added <= 60
    end
  end

  defp atom_growth(iterations, fun) do
    before_count = :erlang.system_info(:atom_count)

    Enum.each(1..iterations, fun)

    :erlang.garbage_collect()
    after_count = :erlang.system_info(:atom_count)
    after_count - before_count
  end

  defp unique_suffix do
    "#{System.unique_integer([:positive])}_#{System.system_time(:microsecond)}"
  end

  defp assistant_payload do
    %{
      "type" => "assistant",
      "message" => %{
        "id" => "msg-1",
        "type" => "message",
        "role" => "assistant",
        "model" => "claude",
        "content" => [%{"type" => "text", "text" => "ok"}],
        "stop_reason" => nil,
        "stop_sequence" => nil,
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      },
      "session_id" => "session-1"
    }
  end

  defp result_payload do
    %{
      "type" => "result",
      "subtype" => "success",
      "is_error" => false,
      "duration_ms" => 1,
      "duration_api_ms" => 1,
      "num_turns" => 1,
      "result" => "ok",
      "session_id" => "session-1",
      "total_cost_usd" => 0.0,
      "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
    }
  end
end
