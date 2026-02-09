defmodule ClaudeCode.Adapter.TestAdapterTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Test

  test "implements all required ClaudeCode.Adapter callbacks" do
    Code.ensure_loaded!(Test)
    all_callbacks = ClaudeCode.Adapter.behaviour_info(:callbacks)
    optional_callbacks = ClaudeCode.Adapter.behaviour_info(:optional_callbacks)
    required_callbacks = all_callbacks -- optional_callbacks

    Enum.each(required_callbacks, fn {fun, arity} ->
      assert function_exported?(Test, fun, arity),
             "Missing callback: #{fun}/#{arity}"
    end)
  end
end
