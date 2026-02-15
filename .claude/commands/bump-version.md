---
description: Update version number across the project
---

Update version to the specified X.Y.Z value.

### Steps

1. Get current version from `mix.exs`

2. Search for **both** version patterns (replace X.Y with actual current major.minor):
   ```bash
   grep -rn "X\.Y" --include="*.md" --include="*.ex" --include="*.exs" . | grep -v deps/ | grep -v _build/ | grep -v CHANGELOG
   ```

3. Update all matches (preserve existing format):
   - Full versions `"X.Y.Z"` → new full version
   - Dependency specs `"~> X.Y"` → new major.minor

4. Update `CHANGELOG.md`:
   - Get the bundled CLI version from `@default_cli_version` in `lib/claude_code/adapter/local/installer.ex`
   - Convert Unreleased to `[X.Y.Z] - YYYY-MM-DD | CC A.B.C` where A.B.C is the CLI version
   - Example: `## [0.18.0] - 2026-02-08 | CC 2.1.37`

5. Verify no old versions remain (except CHANGELOG history)

6. Check if CLI version needs updating:
   - Run `claude --version` to get latest CLI version
   - Compare with `@default_cli_version` in `lib/claude_code/installer.ex`
   - Update if newer version available and tested

7. Tag and release:
   - Create git tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`
   - Push tag: `git push origin vX.Y.Z`
   - Extract the release section from `CHANGELOG.md` (everything between the new version header and the previous version header, excluding the headers themselves)
   - Create GitHub release with CC version in title and changelog as body:
     ```bash
     gh release create vX.Y.Z --title "vX.Y.Z | CC A.B.C" --notes "<changelog section content>"
     ```

### Reference

**Files that contain version numbers** (6 files + CHANGELOG):
- `mix.exs` — `@version "X.Y.Z"`
- `lib/claude_code.ex` — version string
- `README.md` — `{:claude_code, "~> X.Y"}`
- `docs/guides/custom-tools.md` — `{:claude_code, "~> X.Y"}`
- `docs/reference/troubleshooting.md` — `{:claude_code, "~> X.Y"}`
- `lib/claude_code/mcp.ex` — `{:claude_code, "~> X.Y"}`

**Creating retroactive releases** (if needed for missed versions):
1. Find version bump commits: `git log --oneline --all --grep='version' -- mix.exs`
2. Create annotated tags: `git tag -a vX.Y.Z <commit> -m "vX.Y.Z"`
3. Push all tags: `git push origin --tags`
4. Create releases oldest-to-newest, extracting changelog sections as body
