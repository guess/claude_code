defmodule ClaudeCode.HookTest do
  use ExUnit.Case, async: true

  describe "behaviour" do
    test "module that implements call/2 satisfies the behaviour" do
      defmodule TestHook do
        @moduledoc false
        @behaviour ClaudeCode.Hook

        @impl true
        def call(_input, _tool_use_id), do: :allow
      end

      assert TestHook.call(%{tool_name: "Bash"}, nil) == :allow
    end

    test "anonymous function can serve as a hook" do
      hook_fn = fn _input, _tool_use_id -> :allow end
      assert hook_fn.(%{tool_name: "Bash"}, nil) == :allow
    end
  end

  describe "invoke/3" do
    test "invokes a module callback" do
      defmodule AllowHook do
        @moduledoc false
        @behaviour ClaudeCode.Hook

        @impl true
        def call(_input, _tool_use_id), do: :allow
      end

      assert ClaudeCode.Hook.invoke(AllowHook, %{}, nil) == :allow
    end

    test "invokes an anonymous function" do
      hook_fn = fn %{tool_name: name}, _id -> {:deny, "#{name} blocked"} end
      assert ClaudeCode.Hook.invoke(hook_fn, %{tool_name: "Bash"}, nil) == {:deny, "Bash blocked"}
    end

    test "returns {:error, reason} when callback raises" do
      bad_hook = fn _input, _id -> raise "boom" end
      assert {:error, _reason} = ClaudeCode.Hook.invoke(bad_hook, %{}, nil)
    end
  end
end
