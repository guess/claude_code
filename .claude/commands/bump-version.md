---
description: Update version number across the project
---

## Task
Update the version number to the specified value in all project files.

### Arguments
The version number (e.g., "0.4.0")

### Steps
1. Validate the version format (should match semantic versioning: X.Y.Z)
2. Use `grep -rn "CURRENT_VERSION" --include="*.md" --include="*.ex" --include="*.exs" . | grep -v deps/` to find ALL occurrences of the current version
3. Update each occurrence with the new version in:
   - `mix.exs` (the `@version` module attribute)
   - `README.md`
   - `CHANGELOG.md`
   - `docs/` directory (dependency examples like `{:claude_code, "~> X.Y"}`)
4. Confirm all updates were successful by running grep again with the new version
