defmodule ClaudeCode.Adapter.TestAdapterTest do
  use ExUnit.Case, async: true

  test "implements all ClaudeCode.Adapter callbacks" do
    callbacks = ClaudeCode.Adapter.behaviour_info(:callbacks)

    Enum.each(callbacks, fn {fun, arity} ->
      assert function_exported?(ClaudeCode.Adapter.Test, fun, arity),
             "Missing callback: #{fun}/#{arity}"
    end)
  end
end
