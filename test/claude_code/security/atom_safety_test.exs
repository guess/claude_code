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

  describe "unknown values do not create unbounded atoms" do
    test "assistant unknown stop_reason stays string and avoids atom growth" do
      base = assistant_payload()

      atoms_added =
        atom_growth(200, fn i ->
          payload = put_in(base, ["message", "stop_reason"], "unknown_stop_#{i}_#{unique_suffix()}")
          {:ok, message} = AssistantMessage.new(payload)
          assert is_binary(message.message.stop_reason)
        end)

      assert atoms_added <= 60
    end

    test "result unknown subtype stays string and avoids atom growth" do
      base = result_payload()

      atoms_added =
        atom_growth(200, fn i ->
          payload = Map.put(base, "subtype", "unknown_subtype_#{i}_#{unique_suffix()}")
          {:ok, message} = ResultMessage.new(payload)
          assert is_binary(message.subtype)
        end)

      assert atoms_added <= 60
    end

    test "system unknown subtype stays string and avoids atom growth" do
      atoms_added =
        atom_growth(200, fn i ->
          payload = %{
            "type" => "system",
            "subtype" => "future_subtype_#{i}_#{unique_suffix()}",
            "session_id" => "session-1",
            "custom_field" => "custom-value"
          }

          {:ok, message} = SystemMessage.new(payload)
          assert is_binary(message.subtype)
        end)

      assert atoms_added <= 60
    end

    test "partial assistant unknown event type stays string and avoids atom growth" do
      atoms_added =
        atom_growth(200, fn i ->
          payload = %{
            "type" => "stream_event",
            "session_id" => "session-1",
            "event" => %{"type" => "future_event_#{i}_#{unique_suffix()}"}
          }

          {:ok, message} = PartialAssistantMessage.new(payload)
          assert is_binary(message.event.type)
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
