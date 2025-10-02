---
description: Update version number across the project
---

## Task
Update the version number to the specified value in all project files.

### Arguments
The version number (e.g., "0.4.0")

### Steps
1. Validate the version format (should match semantic versioning: X.Y.Z)
2. Search for all occurrences of the current version in:
   - `mix.exs` (the `@version` module attribute)
   - `README.md`
   - `CHANGELOG.md`
   - `docs/` directory
3. Update each occurrence with the new version
4. Confirm all updates were successful
