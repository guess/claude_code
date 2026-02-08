defmodule ClaudeCode.AdapterTest do
  use ExUnit.Case, async: true

  describe "behaviour callbacks" do
    test "defines all required callbacks" do
      callbacks = ClaudeCode.Adapter.behaviour_info(:callbacks)

      assert {:start_link, 2} in callbacks
      assert {:send_query, 4} in callbacks
      assert {:interrupt, 1} in callbacks
      assert {:health, 1} in callbacks
      assert {:stop, 1} in callbacks

      # Old signature should not exist
      refute {:send_query, 5} in callbacks
    end
  end
end
