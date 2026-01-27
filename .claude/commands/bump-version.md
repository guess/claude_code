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
   - `CHANGELOG.md` → convert Unreleased to `[X.Y.Z] - YYYY-MM-DD`

4. Verify no old versions remain (except CHANGELOG history)
