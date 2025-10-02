---
description: Update CHANGELOG.md with entries from recent commits
---

# Update Changelog

This command automatically updates the CHANGELOG.md file by analyzing git commits since the last changelog update.

## Usage

```
/update-changelog
```

## Description

This command will:

1. Check if a CHANGELOG.md file exists
   - If not found, create one with the standard Keep a Changelog header
2. Find the last commit referenced in the changelog (or start from the beginning if none)
3. Fetch all commits since that reference
4. Parse each commit message to extract:
   - The gitmoji and/or conventional commit type (feat, fix, chore, etc.)
   - The commit description
   - The commit hash (short form)
5. Group commits by type into changelog sections:
   - ✨ feat → Added
   - 🐛 fix, 🚑️ hotfix → Fixed
   - ♻️ refactor, 🎨 style → Changed
   - 🗑️ deprecate → Deprecated
   - 🔥 remove → Removed
   - 🔒️ security → Security
   - All other types → Other Changes
6. Add entries to the "Unreleased" section at the top of the changelog
7. Format entries as: `- Description ([commit-hash])`

## Changelog Format

The CHANGELOG follows the [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New feature description ([abc123])

### Fixed
- Bug fix description ([def456])

## [1.0.0] - 2024-01-15

### Added
- Initial release features
```

## Implementation Details

1. **Read existing CHANGELOG.md** or create with standard header
2. **Get the last referenced commit** by finding the most recent commit hash in the changelog
3. **Fetch commits** using `git log <last-commit>..HEAD --oneline` (or all commits if no last-commit)
4. **Parse each commit**:
   - Extract gitmoji emoji if present
   - Extract conventional commit type if present (feat, fix, chore, etc.)
   - Get commit description (remove gitmoji and type prefix)
   - Get short commit hash
5. **Group commits** by their type into appropriate changelog sections
6. **Update Unreleased section**:
   - Find or create the "## [Unreleased]" section
   - Add subsections (### Added, ### Fixed, etc.) as needed
   - Add commit entries in the format: `- Description ([hash])`
7. **Write updated CHANGELOG.md**

## Notes

- This command only updates the "Unreleased" section
- Version releases and tagging should be handled by a separate `/release` command
- Commits are processed in chronological order (oldest to newest)
- Merge commits and commits without meaningful messages may be filtered out
- The command is idempotent - running it multiple times will only add new commits
