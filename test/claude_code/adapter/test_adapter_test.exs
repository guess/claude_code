defmodule ClaudeCode.Adapter.TestAdapterTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Test

  test "implements all ClaudeCode.Adapter callbacks" do
    Code.ensure_loaded!(Test)
    callbacks = ClaudeCode.Adapter.behaviour_info(:callbacks)

    Enum.each(callbacks, fn {fun, arity} ->
      assert function_exported?(Test, fun, arity),
             "Missing callback: #{fun}/#{arity}"
    end)
  end
end
