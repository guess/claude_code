defmodule ClaudeCode.MapUtilsTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MapUtils

  describe "safe_atomize_key/1" do
    test "passes through atom keys unchanged" do
      assert MapUtils.safe_atomize_key(:foo) == :foo
    end

    test "converts known string keys to atoms" do
      assert MapUtils.safe_atomize_key("type") == :type
      assert MapUtils.safe_atomize_key("model") == :model
      assert MapUtils.safe_atomize_key("content") == :content
    end

    test "converts explicitly mapped CLI hook keys to atoms" do
      # BaseHookInput
      assert MapUtils.safe_atomize_key("hook_event_name") == :hook_event_name
      assert MapUtils.safe_atomize_key("transcript_path") == :transcript_path
      assert MapUtils.safe_atomize_key("session_id") == :session_id
      assert MapUtils.safe_atomize_key("cwd") == :cwd
      assert MapUtils.safe_atomize_key("permission_mode") == :permission_mode

      # Tool-lifecycle hooks
      assert MapUtils.safe_atomize_key("tool_name") == :tool_name
      assert MapUtils.safe_atomize_key("tool_input") == :tool_input
      assert MapUtils.safe_atomize_key("tool_use_id") == :tool_use_id
      assert MapUtils.safe_atomize_key("tool_response") == :tool_response
      assert MapUtils.safe_atomize_key("is_interrupt") == :is_interrupt

      # SubagentContextMixin
      assert MapUtils.safe_atomize_key("agent_id") == :agent_id
      assert MapUtils.safe_atomize_key("agent_type") == :agent_type

      # Stop / SubagentStop
      assert MapUtils.safe_atomize_key("stop_hook_active") == :stop_hook_active
      assert MapUtils.safe_atomize_key("agent_transcript_path") == :agent_transcript_path

      # PreCompact
      assert MapUtils.safe_atomize_key("custom_instructions") == :custom_instructions

      # Notification
      assert MapUtils.safe_atomize_key("notification_type") == :notification_type

      # PermissionRequest
      assert MapUtils.safe_atomize_key("permission_suggestions") == :permission_suggestions
    end

    test "keeps unknown string keys as strings" do
      assert MapUtils.safe_atomize_key("zzz_nonexistent_atom_key_42") == "zzz_nonexistent_atom_key_42"
    end
  end

  describe "safe_atomize_keys/1" do
    test "atomizes known keys" do
      assert MapUtils.safe_atomize_keys(%{"type" => "text", "model" => "claude"}) ==
               %{type: "text", model: "claude"}
    end

    test "keeps unknown keys as strings" do
      result = MapUtils.safe_atomize_keys(%{"type" => "text", "zzz_unknown_key_99" => "val"})
      assert result[:type] == "text"
      assert result["zzz_unknown_key_99"] == "val"
    end

    test "passes through atom keys" do
      assert MapUtils.safe_atomize_keys(%{type: "text"}) == %{type: "text"}
    end

    test "does not recurse into values" do
      result = MapUtils.safe_atomize_keys(%{"type" => %{"zzz_nested_unknown_88" => 1}})
      assert result[:type] == %{"zzz_nested_unknown_88" => 1}
    end
  end

  describe "safe_atomize_keys_recursive/1" do
    test "recursively atomizes known keys" do
      input = %{"type" => "text", "usage" => %{"input_tokens" => 10}}
      result = MapUtils.safe_atomize_keys_recursive(input)
      assert result[:type] == "text"
      assert result[:usage][:input_tokens] == 10
    end

    test "keeps unknown keys as strings at all levels" do
      input = %{"type" => "text", "zzz_outer_77" => %{"zzz_inner_77" => 1}}
      result = MapUtils.safe_atomize_keys_recursive(input)
      assert result[:type] == "text"
      assert result["zzz_outer_77"]["zzz_inner_77"] == 1
    end

    test "handles lists" do
      input = %{"content" => [%{"type" => "text"}]}
      result = MapUtils.safe_atomize_keys_recursive(input)
      assert result[:content] == [%{type: "text"}]
    end

    test "passes through scalars" do
      assert MapUtils.safe_atomize_keys_recursive("hello") == "hello"
      assert MapUtils.safe_atomize_keys_recursive(42) == 42
      assert MapUtils.safe_atomize_keys_recursive(nil) == nil
    end
  end

  describe "atom table safety" do
    test "does not create new atoms from unknown keys" do
      unique = "zzz_atom_safety_test_#{System.unique_integer([:positive])}"

      MapUtils.safe_atomize_keys(%{unique => "value"})
      MapUtils.safe_atomize_keys_recursive(%{unique => %{unique => "nested"}})

      # The key should never have been added to the atom table
      assert String.to_existing_atom(unique) == :does_not_exist
    catch
      :error, :badarg ->
        # Expected: String.to_existing_atom raises ArgumentError when the atom doesn't exist
        :ok
    end
  end
end
