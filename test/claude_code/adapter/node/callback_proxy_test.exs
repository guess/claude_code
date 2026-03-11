defmodule ClaudeCode.Adapter.Node.CallbackProxyTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Node.CallbackProxy
  alias ClaudeCode.Hook.Registry, as: HookRegistry

  defmodule AllowHook do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(_input, _tool_use_id), do: :allow
  end

  describe "start_link/1 and control request handling" do
    test "handles mcp_message control requests" do
      {:ok, proxy} =
        CallbackProxy.start_link(
          mcp_servers: %{"calc" => ClaudeCode.TestTools},
          hook_registry: %HookRegistry{}
        )

      msg = %{
        "request_id" => "req_1",
        "request" => %{
          "subtype" => "mcp_message",
          "server_name" => "calc",
          "message" => %{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "tools/call",
            "params" => %{"name" => "add", "arguments" => %{"x" => 5, "y" => 3}}
          }
        }
      }

      response = GenServer.call(proxy, {:control_request, msg})
      assert %{"mcp_response" => %{"result" => result}} = response
      assert result["content"] == [%{"type" => "text", "text" => "8"}]
    end

    test "handles hook_callback control requests" do
      hooks = %{PostToolUse: [%{hooks: [AllowHook]}]}
      {registry, _wire} = HookRegistry.new(hooks)

      {:ok, proxy} =
        CallbackProxy.start_link(
          mcp_servers: nil,
          hook_registry: registry
        )

      msg = %{
        "request_id" => "req_1",
        "request" => %{
          "subtype" => "hook_callback",
          "callback_id" => "hook_0",
          "input" => %{"tool_name" => "Read"},
          "tool_use_id" => nil
        }
      }

      response = GenServer.call(proxy, {:control_request, msg})
      assert is_map(response)
    end

    test "returns nil for unknown control request subtypes" do
      {:ok, proxy} =
        CallbackProxy.start_link(
          mcp_servers: nil,
          hook_registry: %HookRegistry{}
        )

      msg = %{
        "request_id" => "req_1",
        "request" => %{"subtype" => "unknown_type"}
      }

      response = GenServer.call(proxy, {:control_request, msg})
      assert response == nil
    end

    test "returns mcp error for unknown server name" do
      {:ok, proxy} =
        CallbackProxy.start_link(
          mcp_servers: nil,
          hook_registry: %HookRegistry{}
        )

      msg = %{
        "request_id" => "req_1",
        "request" => %{
          "subtype" => "mcp_message",
          "server_name" => "nonexistent",
          "message" => %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
        }
      }

      response = GenServer.call(proxy, {:control_request, msg})
      assert %{"mcp_response" => %{"error" => _}} = response
    end
  end
end
