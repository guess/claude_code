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

  describe "notification helpers" do
    test "notify_message/3 sends adapter_message to session" do
      session = self()
      request_id = make_ref()
      message = %{type: :test}

      ClaudeCode.Adapter.notify_message(session, request_id, message)

      assert_receive {:adapter_message, ^request_id, ^message}
    end

    test "notify_done/3 sends adapter_done to session" do
      session = self()
      request_id = make_ref()

      ClaudeCode.Adapter.notify_done(session, request_id, :completed)

      assert_receive {:adapter_done, ^request_id, :completed}
    end

    test "notify_error/3 sends adapter_error to session" do
      session = self()
      request_id = make_ref()

      ClaudeCode.Adapter.notify_error(session, request_id, :timeout)

      assert_receive {:adapter_error, ^request_id, :timeout}
    end

    test "notify_status/2 sends adapter_status to session" do
      session = self()

      ClaudeCode.Adapter.notify_status(session, :ready)
      assert_receive {:adapter_status, :ready}

      ClaudeCode.Adapter.notify_status(session, :provisioning)
      assert_receive {:adapter_status, :provisioning}

      ClaudeCode.Adapter.notify_status(session, {:error, :cli_not_found})
      assert_receive {:adapter_status, {:error, :cli_not_found}}
    end
  end
end
