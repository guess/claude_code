defmodule ClaudeCode.Hook.OutputTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Hook.Output
  alias ClaudeCode.Hook.PermissionDecision.Allow
  alias ClaudeCode.Hook.PermissionDecision.Deny

  describe "Output.to_wire/1 - sync wrapper" do
    test "empty output returns empty map" do
      assert Output.to_wire(%Output{}) == %{}
    end

    test "control fields are camelCased" do
      result = Output.to_wire(%Output{continue: false, stop_reason: "done"})
      assert result["continue"] == false
      assert result["stopReason"] == "done"
    end

    test "all top-level fields" do
      result =
        Output.to_wire(%Output{
          continue: true,
          suppress_output: true,
          stop_reason: "reason",
          decision: "block",
          system_message: "warning",
          reason: "explanation"
        })

      assert result["continue"] == true
      assert result["suppressOutput"] == true
      assert result["stopReason"] == "reason"
      assert result["decision"] == "block"
      assert result["systemMessage"] == "warning"
      assert result["reason"] == "explanation"
    end

    test "nil fields are omitted" do
      result = Output.to_wire(%Output{continue: false})
      assert result == %{"continue" => false}
      refute Map.has_key?(result, "stopReason")
    end

    test "wraps hook_specific_output in hookSpecificOutput" do
      result =
        Output.to_wire(%Output{
          hook_specific_output: %Output.PreToolUse{permission_decision: "allow"}
        })

      assert result["hookSpecificOutput"]["hookEventName"] == "PreToolUse"
      assert result["hookSpecificOutput"]["permissionDecision"] == "allow"
    end

    test "combines top-level fields with hook_specific_output" do
      result =
        Output.to_wire(%Output{
          continue: true,
          reason: "because",
          hook_specific_output: %Output.SessionStart{additional_context: "ctx"}
        })

      assert result["continue"] == true
      assert result["reason"] == "because"
      assert result["hookSpecificOutput"]["hookEventName"] == "SessionStart"
      assert result["hookSpecificOutput"]["additionalContext"] == "ctx"
    end
  end

  describe "Output.to_wire/1 - Async" do
    test "basic async" do
      result = Output.to_wire(%Output.Async{})
      assert result == %{"async" => true}
    end

    test "async with timeout" do
      result = Output.to_wire(%Output.Async{timeout: 5000})
      assert result == %{"async" => true, "asyncTimeout" => 5000}
    end

    test "async with nil timeout omits asyncTimeout" do
      result = Output.to_wire(%Output.Async{timeout: nil})
      assert result == %{"async" => true}
      refute Map.has_key?(result, "asyncTimeout")
    end
  end

  describe "PreToolUse.to_wire/1" do
    test "all fields" do
      result =
        Output.PreToolUse.to_wire(%Output.PreToolUse{
          permission_decision: "allow",
          permission_decision_reason: "safe",
          updated_input: %{"cmd" => "ls"},
          additional_context: "prod"
        })

      assert result["hookEventName"] == "PreToolUse"
      assert result["permissionDecision"] == "allow"
      assert result["permissionDecisionReason"] == "safe"
      assert result["updatedInput"] == %{"cmd" => "ls"}
      assert result["additionalContext"] == "prod"
    end

    test "nil fields omitted" do
      result = Output.PreToolUse.to_wire(%Output.PreToolUse{permission_decision: "deny"})
      assert result["hookEventName"] == "PreToolUse"
      assert result["permissionDecision"] == "deny"
      refute Map.has_key?(result, "updatedInput")
      refute Map.has_key?(result, "permissionDecisionReason")
      refute Map.has_key?(result, "additionalContext")
    end

    test "empty struct produces only hookEventName" do
      result = Output.PreToolUse.to_wire(%Output.PreToolUse{})
      assert result == %{"hookEventName" => "PreToolUse"}
    end
  end

  describe "PostToolUse.to_wire/1" do
    test "with additional_context" do
      result = Output.PostToolUse.to_wire(%Output.PostToolUse{additional_context: "info"})
      assert result["hookEventName"] == "PostToolUse"
      assert result["additionalContext"] == "info"
    end

    test "with updated_mcp_tool_output" do
      result =
        Output.PostToolUse.to_wire(%Output.PostToolUse{
          updated_mcp_tool_output: %{"data" => "modified"}
        })

      assert result["hookEventName"] == "PostToolUse"
      assert result["updatedMCPToolOutput"] == %{"data" => "modified"}
    end

    test "with both fields" do
      result =
        Output.PostToolUse.to_wire(%Output.PostToolUse{
          additional_context: "ctx",
          updated_mcp_tool_output: %{"result" => "ok"}
        })

      assert result["hookEventName"] == "PostToolUse"
      assert result["additionalContext"] == "ctx"
      assert result["updatedMCPToolOutput"] == %{"result" => "ok"}
    end

    test "empty struct produces only hookEventName" do
      result = Output.PostToolUse.to_wire(%Output.PostToolUse{})
      assert result == %{"hookEventName" => "PostToolUse"}
    end
  end

  describe "additional_context-only events" do
    test "PostToolUseFailure" do
      result =
        Output.PostToolUseFailure.to_wire(%Output.PostToolUseFailure{additional_context: "ctx"})

      assert result["hookEventName"] == "PostToolUseFailure"
      assert result["additionalContext"] == "ctx"
    end

    test "UserPromptSubmit" do
      result =
        Output.UserPromptSubmit.to_wire(%Output.UserPromptSubmit{additional_context: "ctx"})

      assert result["hookEventName"] == "UserPromptSubmit"
      assert result["additionalContext"] == "ctx"
    end

    test "SessionStart" do
      result = Output.SessionStart.to_wire(%Output.SessionStart{additional_context: "ctx"})
      assert result["hookEventName"] == "SessionStart"
      assert result["additionalContext"] == "ctx"
    end

    test "Notification" do
      result = Output.Notification.to_wire(%Output.Notification{additional_context: "ctx"})
      assert result["hookEventName"] == "Notification"
      assert result["additionalContext"] == "ctx"
    end

    test "SubagentStart" do
      result = Output.SubagentStart.to_wire(%Output.SubagentStart{additional_context: "ctx"})
      assert result["hookEventName"] == "SubagentStart"
      assert result["additionalContext"] == "ctx"
    end

    test "empty structs produce only hookEventName" do
      assert Output.PostToolUseFailure.to_wire(%Output.PostToolUseFailure{}) ==
               %{"hookEventName" => "PostToolUseFailure"}

      assert Output.UserPromptSubmit.to_wire(%Output.UserPromptSubmit{}) ==
               %{"hookEventName" => "UserPromptSubmit"}

      assert Output.SessionStart.to_wire(%Output.SessionStart{}) ==
               %{"hookEventName" => "SessionStart"}

      assert Output.Notification.to_wire(%Output.Notification{}) ==
               %{"hookEventName" => "Notification"}

      assert Output.SubagentStart.to_wire(%Output.SubagentStart{}) ==
               %{"hookEventName" => "SubagentStart"}
    end
  end

  describe "PreCompact.to_wire/1" do
    test "with custom_instructions" do
      result = Output.PreCompact.to_wire(%Output.PreCompact{custom_instructions: "Remember X"})
      assert result["hookEventName"] == "PreCompact"
      assert result["customInstructions"] == "Remember X"
    end

    test "empty struct produces only hookEventName" do
      result = Output.PreCompact.to_wire(%Output.PreCompact{})
      assert result == %{"hookEventName" => "PreCompact"}
    end
  end

  describe "PermissionDecision.Allow.to_wire/1" do
    test "basic allow" do
      result = Allow.to_wire(%Allow{})
      assert result == %{"behavior" => "allow"}
    end

    test "allow with updated_input" do
      result =
        Allow.to_wire(%Allow{
          updated_input: %{"cmd" => "safe"}
        })

      assert result["behavior"] == "allow"
      assert result["updatedInput"] == %{"cmd" => "safe"}
    end

    test "allow with updated_permissions" do
      perms = [%{"type" => "toolAlwaysAllow", "tool" => "Bash"}]

      result =
        Allow.to_wire(%Allow{
          updated_permissions: perms
        })

      assert result["behavior"] == "allow"
      assert result["updatedPermissions"] == perms
    end

    test "allow with both fields" do
      result =
        Allow.to_wire(%Allow{
          updated_input: %{"cmd" => "ls"},
          updated_permissions: [%{"type" => "toolAlwaysAllow"}]
        })

      assert result["behavior"] == "allow"
      assert result["updatedInput"] == %{"cmd" => "ls"}
      assert result["updatedPermissions"] == [%{"type" => "toolAlwaysAllow"}]
    end
  end

  describe "PermissionDecision.Deny.to_wire/1" do
    test "basic deny" do
      result = Deny.to_wire(%Deny{})
      assert result == %{"behavior" => "deny"}
    end

    test "deny with message" do
      result =
        Deny.to_wire(%Deny{
          message: "blocked"
        })

      assert result["behavior"] == "deny"
      assert result["message"] == "blocked"
    end

    test "deny with interrupt" do
      result =
        Deny.to_wire(%Deny{
          message: "stop",
          interrupt: true
        })

      assert result["behavior"] == "deny"
      assert result["message"] == "stop"
      assert result["interrupt"] == true
    end

    test "deny with only interrupt" do
      result =
        Deny.to_wire(%Deny{interrupt: true})

      assert result["behavior"] == "deny"
      assert result["interrupt"] == true
      refute Map.has_key?(result, "message")
    end
  end

  describe "PermissionRequest.to_wire/1" do
    test "allow decision" do
      result =
        Output.PermissionRequest.to_wire(%Output.PermissionRequest{
          decision: %Allow{updated_input: %{"x" => 1}}
        })

      assert result["hookEventName"] == "PermissionRequest"
      assert result["decision"]["behavior"] == "allow"
      assert result["decision"]["updatedInput"] == %{"x" => 1}
    end

    test "deny decision" do
      result =
        Output.PermissionRequest.to_wire(%Output.PermissionRequest{
          decision: %Deny{message: "no", interrupt: true}
        })

      assert result["hookEventName"] == "PermissionRequest"
      assert result["decision"]["behavior"] == "deny"
      assert result["decision"]["message"] == "no"
      assert result["decision"]["interrupt"] == true
    end
  end

  describe "PermissionDecision standalone (can_use_tool)" do
    test "allow via Output.to_wire" do
      result = Output.to_wire(%Allow{})
      assert result == %{"behavior" => "allow"}
    end

    test "deny via Output.to_wire" do
      result = Output.to_wire(%Deny{message: "no"})
      assert result == %{"behavior" => "deny", "message" => "no"}
    end

    test "allow with fields via Output.to_wire" do
      result =
        Output.to_wire(%Allow{
          updated_input: %{"safe" => true},
          updated_permissions: [%{"type" => "allow"}]
        })

      assert result["behavior"] == "allow"
      assert result["updatedInput"] == %{"safe" => true}
      assert result["updatedPermissions"] == [%{"type" => "allow"}]
    end

    test "deny with interrupt via Output.to_wire" do
      result =
        Output.to_wire(%Deny{message: "blocked", interrupt: true})

      assert result["behavior"] == "deny"
      assert result["message"] == "blocked"
      assert result["interrupt"] == true
    end
  end

  # -- coerce/2 tests --

  describe "coerce/2 — tier 1 (bare :ok)" do
    import ExUnit.CaptureLog

    test "bare :ok returns empty Output struct" do
      assert %Output{} = Output.coerce(:ok, "PreToolUse")
      assert %Output{} = Output.coerce(:ok, "PostToolUse")
    end

    test "bare :allow delegates to {:allow, []}" do
      result = Output.coerce(:allow, "PreToolUse")
      assert %Output{hook_specific_output: %Output.PreToolUse{permission_decision: "allow"}} = result
    end

    test "bare :deny delegates to {:deny, []}" do
      result = Output.coerce(:deny, "PreToolUse")
      assert %Output{hook_specific_output: %Output.PreToolUse{permission_decision: "deny"}} = result
    end
  end

  describe "coerce/2 — bare :allow/:deny for non-permission events" do
    import ExUnit.CaptureLog

    test "bare :allow for PostToolUse logs warning and returns empty Output" do
      log =
        capture_log(fn ->
          assert %Output{hook_specific_output: nil} = Output.coerce(:allow, "PostToolUse")
        end)

      assert log =~ "only applies to PreToolUse"
    end

    test "bare :deny for Stop logs warning and returns empty Output" do
      log =
        capture_log(fn ->
          assert %Output{hook_specific_output: nil} = Output.coerce(:deny, "Stop")
        end)

      assert log =~ "only applies to PreToolUse"
    end

    test "{:allow, opts} for SessionStart logs warning and returns empty Output" do
      log =
        capture_log(fn ->
          assert %Output{} = Output.coerce({:allow, []}, "SessionStart")
        end)

      assert log =~ "only applies to PreToolUse"
    end

    test "{:deny, opts} for Notification logs warning and returns empty Output" do
      log =
        capture_log(fn ->
          assert %Output{} = Output.coerce({:deny, []}, "Notification")
        end)

      assert log =~ "only applies to PreToolUse"
    end
  end

  describe "coerce/2 — catch-all (unrecognized values)" do
    import ExUnit.CaptureLog

    test "unrecognized atom logs warning and returns empty Output" do
      log =
        capture_log(fn ->
          assert %Output{} = Output.coerce(:bogus, "PreToolUse")
        end)

      assert log =~ "unrecognized value"
    end

    test "unrecognized tuple logs warning and returns empty Output" do
      log =
        capture_log(fn ->
          assert %Output{} = Output.coerce({:unknown, []}, "PostToolUse")
        end)

      assert log =~ "unrecognized value"
    end

    test "string value logs warning and returns empty Output" do
      log =
        capture_log(fn ->
          assert %Output{} = Output.coerce("allow", "PreToolUse")
        end)

      assert log =~ "unrecognized value"
    end
  end

  describe "coerce/2 — tier 2 (struct passthrough)" do
    test "Output struct passes through unchanged" do
      output = %Output{suppress_output: true}
      assert Output.coerce(output, "PreToolUse") == output
    end
  end

  describe "coerce/2 — :halt (Stop/SubagentStop)" do
    test "halt with stop_reason" do
      result = Output.coerce({:halt, stop_reason: "Budget remaining"}, "Stop")
      assert %Output{continue: false, stop_reason: "Budget remaining"} = result
    end

    test "halt with stop_reason for SubagentStop" do
      result = Output.coerce({:halt, stop_reason: "Task complete"}, "SubagentStop")
      assert %Output{continue: false, stop_reason: "Task complete"} = result
    end

    test "halt with extra top-level fields" do
      result = Output.coerce({:halt, stop_reason: "Done", system_message: "Halted"}, "Stop")
      assert %Output{continue: false, stop_reason: "Done", system_message: "Halted"} = result
    end
  end

  describe "coerce/2 — :block (UserPromptSubmit)" do
    test "block with reason" do
      result = Output.coerce({:block, reason: "Rate limited"}, "UserPromptSubmit")
      assert %Output{decision: "block", reason: "Rate limited"} = result
    end
  end

  describe "coerce/2 — :allow/:deny/:ask (PreToolUse)" do
    test "allow with no opts" do
      result = Output.coerce({:allow, []}, "PreToolUse")
      assert %Output{hook_specific_output: %Output.PreToolUse{permission_decision: "allow"}} = result
    end

    test "allow with updated_input" do
      result = Output.coerce({:allow, updated_input: %{"command" => "ls"}}, "PreToolUse")
      assert %Output{hook_specific_output: inner} = result
      assert %Output.PreToolUse{permission_decision: "allow", updated_input: %{"command" => "ls"}} = inner
    end

    test "deny with permission_decision_reason" do
      result = Output.coerce({:deny, permission_decision_reason: "Dangerous"}, "PreToolUse")
      assert %Output{hook_specific_output: inner} = result
      assert %Output.PreToolUse{permission_decision: "deny", permission_decision_reason: "Dangerous"} = inner
    end

    test "deny with additional_context" do
      result =
        Output.coerce(
          {:deny, permission_decision_reason: "No", additional_context: "Extra info"},
          "PreToolUse"
        )

      assert %Output{hook_specific_output: inner} = result
      assert inner.permission_decision == "deny"
      assert inner.additional_context == "Extra info"
    end

    test "ask with permission_decision_reason" do
      result = Output.coerce({:ask, permission_decision_reason: "Needs review"}, "PreToolUse")
      assert %Output{hook_specific_output: inner} = result

      assert %Output.PreToolUse{permission_decision: "ask", permission_decision_reason: "Needs review"} =
               inner
    end
  end

  describe "coerce/2 — :allow/:deny (PermissionRequest)" do
    test "allow with no opts" do
      result = Output.coerce({:allow, []}, "PermissionRequest")

      assert %Output{
               hook_specific_output: %Output.PermissionRequest{
                 decision: %Allow{}
               }
             } = result
    end

    test "allow with updated_input" do
      result = Output.coerce({:allow, updated_input: %{"command" => "ls"}}, "PermissionRequest")
      assert %Output{hook_specific_output: %Output.PermissionRequest{decision: decision}} = result
      assert %Allow{updated_input: %{"command" => "ls"}} = decision
    end

    test "allow with updated_permissions" do
      result = Output.coerce({:allow, updated_permissions: ["Bash"]}, "PermissionRequest")
      assert %Output{hook_specific_output: %Output.PermissionRequest{decision: decision}} = result
      assert %Allow{updated_permissions: ["Bash"]} = decision
    end

    test "deny with message" do
      result = Output.coerce({:deny, message: "Blocked"}, "PermissionRequest")
      assert %Output{hook_specific_output: %Output.PermissionRequest{decision: decision}} = result
      assert %Deny{message: "Blocked"} = decision
    end

    test "deny with message and interrupt" do
      result = Output.coerce({:deny, message: "No", interrupt: true}, "PermissionRequest")
      assert %Output{hook_specific_output: %Output.PermissionRequest{decision: decision}} = result
      assert %Deny{message: "No", interrupt: true} = decision
    end
  end

  describe "coerce_permission/1 (can_use_tool)" do
    import ExUnit.CaptureLog

    test "bare :allow" do
      assert %Allow{} = Output.coerce_permission(:allow)
    end

    test "bare :deny" do
      assert %Deny{} = Output.coerce_permission(:deny)
    end

    test "allow with opts" do
      assert %Allow{updated_input: %{"x" => 1}} =
               Output.coerce_permission({:allow, updated_input: %{"x" => 1}})
    end

    test "allow with updated_permissions" do
      perms = [%{"type" => "toolAlwaysAllow", "tool" => "Bash"}]

      assert %Allow{updated_permissions: ^perms} =
               Output.coerce_permission({:allow, updated_permissions: perms})
    end

    test "deny with message" do
      assert %Deny{message: "Nope"} = Output.coerce_permission({:deny, message: "Nope"})
    end

    test "deny with message and interrupt" do
      assert %Deny{message: "No", interrupt: true} =
               Output.coerce_permission({:deny, message: "No", interrupt: true})
    end

    test "Allow struct passes through" do
      allow = %Allow{updated_input: %{"x" => 1}}
      assert Output.coerce_permission(allow) == allow
    end

    test "Deny struct passes through" do
      deny = %Deny{message: "no"}
      assert Output.coerce_permission(deny) == deny
    end

    test ":ok logs warning and returns Deny" do
      log =
        capture_log(fn ->
          assert %Deny{} = Output.coerce_permission(:ok)
        end)

      assert log =~ "use :allow, :deny"
    end

    test "{:ok, opts} logs warning and returns Deny" do
      log =
        capture_log(fn ->
          assert %Deny{} = Output.coerce_permission({:ok, updated_input: %{"x" => 1}})
        end)

      assert log =~ "use :allow, :deny"
    end

    test "unrecognized value logs warning and returns Deny" do
      log =
        capture_log(fn ->
          assert %Deny{} = Output.coerce_permission(:bogus)
        end)

      assert log =~ "use :allow, :deny"
    end
  end

  describe "coerce/2 — {:ok, opts} (event-specific inner structs)" do
    test "PreToolUse with additional_context (no permission decision)" do
      result = Output.coerce({:ok, additional_context: "Extra info"}, "PreToolUse")

      assert %Output{hook_specific_output: %Output.PreToolUse{additional_context: "Extra info"}} = result
      assert result.hook_specific_output.permission_decision == nil
    end

    test "PreToolUse with updated_input (no permission decision)" do
      result = Output.coerce({:ok, updated_input: %{"command" => "ls"}}, "PreToolUse")

      assert %Output{hook_specific_output: inner} = result
      assert %Output.PreToolUse{updated_input: %{"command" => "ls"}, permission_decision: nil} = inner
    end

    test "PostToolUse with additional_context" do
      result = Output.coerce({:ok, additional_context: "Logged"}, "PostToolUse")
      assert %Output{hook_specific_output: %Output.PostToolUse{additional_context: "Logged"}} = result
    end

    test "PostToolUse with updated_mcp_tool_output" do
      result = Output.coerce({:ok, updated_mcp_tool_output: "new output"}, "PostToolUse")

      assert %Output{hook_specific_output: %Output.PostToolUse{updated_mcp_tool_output: "new output"}} =
               result
    end

    test "PostToolUseFailure with additional_context" do
      result = Output.coerce({:ok, additional_context: "Retrying"}, "PostToolUseFailure")

      assert %Output{hook_specific_output: %Output.PostToolUseFailure{additional_context: "Retrying"}} =
               result
    end

    test "UserPromptSubmit with additional_context" do
      result = Output.coerce({:ok, additional_context: "Validated"}, "UserPromptSubmit")

      assert %Output{hook_specific_output: %Output.UserPromptSubmit{additional_context: "Validated"}} =
               result
    end

    test "SessionStart with additional_context" do
      result = Output.coerce({:ok, additional_context: "Prod environment"}, "SessionStart")

      assert %Output{hook_specific_output: %Output.SessionStart{additional_context: "Prod environment"}} =
               result
    end

    test "Notification with additional_context" do
      result = Output.coerce({:ok, additional_context: "Noted"}, "Notification")

      assert %Output{hook_specific_output: %Output.Notification{additional_context: "Noted"}} =
               result
    end

    test "SubagentStart with additional_context" do
      result = Output.coerce({:ok, additional_context: "Spawned"}, "SubagentStart")

      assert %Output{hook_specific_output: %Output.SubagentStart{additional_context: "Spawned"}} =
               result
    end

    test "PreCompact with custom_instructions" do
      result = Output.coerce({:ok, custom_instructions: "Keep signatures"}, "PreCompact")

      assert %Output{hook_specific_output: %Output.PreCompact{custom_instructions: "Keep signatures"}} =
               result
    end

    test "{:ok, []} with unknown event falls back to empty Output" do
      result = Output.coerce({:ok, []}, "SomeUnknownEvent")
      assert %Output{} = result
    end
  end

  describe "Output.to_wire/1 - nested hook-specific outputs via dispatcher" do
    test "PreToolUse nested in Output" do
      result =
        Output.to_wire(%Output{
          hook_specific_output: %Output.PreToolUse{
            permission_decision: "deny",
            permission_decision_reason: "unsafe"
          }
        })

      assert result["hookSpecificOutput"]["hookEventName"] == "PreToolUse"
      assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
      assert result["hookSpecificOutput"]["permissionDecisionReason"] == "unsafe"
    end

    test "PostToolUse nested in Output" do
      result =
        Output.to_wire(%Output{
          hook_specific_output: %Output.PostToolUse{additional_context: "done"}
        })

      assert result["hookSpecificOutput"]["hookEventName"] == "PostToolUse"
      assert result["hookSpecificOutput"]["additionalContext"] == "done"
    end

    test "PermissionRequest nested in Output" do
      result =
        Output.to_wire(%Output{
          hook_specific_output: %Output.PermissionRequest{
            decision: %Allow{}
          }
        })

      assert result["hookSpecificOutput"]["hookEventName"] == "PermissionRequest"
      assert result["hookSpecificOutput"]["decision"]["behavior"] == "allow"
    end

    test "PreCompact nested in Output" do
      result =
        Output.to_wire(%Output{
          hook_specific_output: %Output.PreCompact{custom_instructions: "Keep it short"}
        })

      assert result["hookSpecificOutput"]["hookEventName"] == "PreCompact"
      assert result["hookSpecificOutput"]["customInstructions"] == "Keep it short"
    end
  end

  # -- Deprecated shorthand tests --

  describe "coerce/2 — deprecated shorthands" do
    import ExUnit.CaptureLog

    test "{:deny, \"reason\"} logs deprecation and produces deny PreToolUse output" do
      log =
        capture_log(fn ->
          result = Output.coerce({:deny, "Blocked"}, "PreToolUse")
          assert %Output{hook_specific_output: inner} = result
          assert inner.permission_decision == "deny"
          assert inner.permission_decision_reason == "Blocked"
        end)

      assert log =~ "deprecated"
      assert log =~ "permission_decision_reason"
    end

    test "{:allow, map} logs deprecation and produces allow PreToolUse output" do
      log =
        capture_log(fn ->
          result = Output.coerce({:allow, %{"cmd" => "ls"}}, "PreToolUse")
          assert %Output{hook_specific_output: inner} = result
          assert inner.permission_decision == "allow"
          assert inner.updated_input == %{"cmd" => "ls"}
        end)

      assert log =~ "deprecated"
      assert log =~ "updated_input"
    end

  end

  describe "coerce_permission/1 — deprecated shorthands" do
    import ExUnit.CaptureLog

    test "{:deny, \"reason\"} logs deprecation and produces Deny with message" do
      log =
        capture_log(fn ->
          result = Output.coerce_permission({:deny, "Blocked"})
          assert %Deny{message: "Blocked"} = result
        end)

      assert log =~ "deprecated"
    end

    test "{:allow, map} logs deprecation and produces Allow with updated_input" do
      log =
        capture_log(fn ->
          result = Output.coerce_permission({:allow, %{"cmd" => "ls"}})
          assert %Allow{updated_input: %{"cmd" => "ls"}} = result
        end)

      assert log =~ "deprecated"
    end
  end
end
