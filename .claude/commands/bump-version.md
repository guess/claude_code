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
   - Get the bundled CLI version from `@default_cli_version` in `lib/claude_code/installer.ex`
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
   - Create GitHub release: `gh release create vX.Y.Z --generate-notes --title "vX.Y.Z"`
