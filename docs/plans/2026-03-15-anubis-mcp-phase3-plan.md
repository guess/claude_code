# AnubisMCP Migration — Phase 3: Remove Hermes

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the `hermes_mcp` dependency and all Hermes-related code from the codebase.

**Architecture:** Delete `Backend.Hermes`, remove the Hermes detection branch from `backend_for/1`, remove `hermes_mcp` from `mix.exs`, and clean up any remaining Hermes references in tests or docs.

**Tech Stack:** Elixir, ExUnit

---

## Context for the Implementer

After Phase 2, Hermes is only used in two places:
1. `lib/claude_code/mcp/backend/hermes.ex` — legacy backend (only `compatible?/1` is referenced by `backend_for/1`)
2. `mix.exs` — `{:hermes_mcp, "~> 0.14", optional: true}`

The Router uses `Backend.Anubis`, the macro generates standalone modules, and all SDK servers go through the Anubis path.

---

### Task 1: Remove `Backend.Hermes` and Its Tests

**Files:**
- Delete: `lib/claude_code/mcp/backend/hermes.ex`
- Delete: `test/claude_code/mcp/backend/hermes_test.exs`

**Step 1: Delete the files**

```bash
rm lib/claude_code/mcp/backend/hermes.ex
rm test/claude_code/mcp/backend/hermes_test.exs
```

**Step 2: Compile to find any remaining references**

Run: `mix compile`
Expected: Compilation errors pointing to references that need cleanup

**Step 3: Commit (after fixing references in subsequent tasks)**

This commit happens after Task 2.

---

### Task 2: Remove Hermes Detection from `backend_for/1`

**Files:**
- Modify: `lib/claude_code/mcp.ex`
- Modify: `test/claude_code/mcp/mcp_test.exs`

**Step 1: Update `backend_for/1`**

In `lib/claude_code/mcp.ex`, remove the `Backend.Hermes` branch:

```elixir
def backend_for(module) when is_atom(module) do
  cond do
    Server.sdk_server?(module) -> :sdk
    Backend.Anubis.compatible?(module) -> {:subprocess, Backend.Anubis}
    true -> :unknown
  end
end
```

Remove the `Backend.Hermes` alias if it exists.

**Step 2: Update tests**

Remove any `Backend.Hermes` references from `test/claude_code/mcp/mcp_test.exs`.

**Step 3: Compile and test**

Run: `mix compile && mix test`
Expected: All pass

**Step 4: Commit**

```
git add -A
git commit -m "Remove Backend.Hermes and Hermes detection

Backend.Hermes is no longer needed — all SDK servers use
Backend.Anubis and the macro generates standalone modules."
```

---

### Task 3: Remove `hermes_mcp` Dependency

**Files:**
- Modify: `mix.exs`

**Step 1: Remove from deps**

In `mix.exs`, delete the line:

```elixir
{:hermes_mcp, "~> 0.14", optional: true},
```

**Step 2: Clean deps**

Run: `mix deps.clean hermes_mcp && mix deps.get`

**Step 3: Compile**

Run: `mix compile`
Expected: Compiles with no errors. If Peri was only a transitive dep from hermes_mcp and is still needed, add it as a direct dependency. Check if `anubis_mcp` also brings in Peri (it does — both use Peri).

**Step 4: Run tests**

Run: `mix test`
Expected: All pass

**Step 5: Commit**

```
git add mix.exs mix.lock
git commit -m "Remove hermes_mcp dependency"
```

---

### Task 4: Clean Up Any Remaining Hermes References

**Step 1: Search for Hermes references**

Run: `grep -rn "Hermes\|hermes_mcp\|hermes" lib/ test/ docs/ --include="*.ex" --include="*.exs" --include="*.md" | grep -iv "changelog\|CHANGELOG"`

Expected: Zero hits. If any remain, fix them.

**Step 2: Run full quality checks**

Run: `mix quality`
Expected: All pass

**Step 3: Run full test suite with coverage**

Run: `mix test`
Expected: All pass

**Step 4: Commit if any cleanup was needed**

```
git add -A
git commit -m "Clean up remaining Hermes references"
```

---

### Task 5: Final Verification

**Step 1: Verify hermes_mcp is not in mix.lock**

Run: `grep hermes mix.lock`
Expected: No output

**Step 2: Run full quality checks**

Run: `mix quality`
Expected: All pass

**Step 3: Run full test suite**

Run: `mix test`
Expected: All pass

**Step 4: Verify clean dependency tree**

Run: `mix deps.tree | head -20`
Expected: `anubis_mcp` present, no `hermes_mcp`
