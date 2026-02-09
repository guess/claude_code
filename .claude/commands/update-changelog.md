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
5. **Filter commits** to include ONLY user-facing changes (see filtering rules below)
6. Group commits by type into changelog sections:
   - ✨ feat → Added
   - 🐛 fix, 🚑️ hotfix → Fixed
   - ♻️ refactor, 🎨 style → Changed
   - 🗑️ deprecate → Deprecated
   - 🔥 remove → Removed
   - 🔒️ security → Security
   - All other types → Other Changes
7. Add entries to the "Unreleased" section at the top of the changelog
8. Format entries as: `- Description ([commit-hash])`

## What to Include vs Exclude

**IMPORTANT**: The changelog is for library USERS, not developers. Only document changes that affect how users interact with or use the library.

### ✅ SHOULD Include

Changes that affect library users:
- **New features** - New public APIs, functions, modules, options
- **Bug fixes** - Fixes to public API behavior or user-facing issues
- **Breaking changes** - Changes to public APIs, function signatures, behavior
- **Deprecations** - Deprecated public APIs or features
- **Performance improvements** - User-visible performance changes
- **Documentation** - Updates to README, guides, or public API docs that help users
- **Dependencies** - Changes to runtime dependencies that users need to know about

### ❌ SHOULD NOT Include

Internal changes that don't affect library users:
- **Internal tooling** - Changes to `.claude/` configs, slash commands, AI prompts
- **Development infrastructure** - CI/CD configs, test scripts, build tools
- **Internal refactoring** - Code reorganization without API changes
- **Development dependencies** - Changes to dev/test-only dependencies
- **Proposals and planning** - Design docs, proposals, roadmaps in `docs/`
- **Internal documentation** - CLAUDE.md, development notes, architecture docs for contributors
- **Code style/formatting** - Formatting changes, linting fixes without functional changes
- **Test code** - Test additions or changes (unless they reveal new features)

**Rule of thumb**: If a library user updates to the new version, would they notice this change? If no, exclude it from the changelog.

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

## [1.0.0] - 2024-01-15 | CC 2.1.37

### Added
- Initial release features
```

**Version header format**: `## [X.Y.Z] - YYYY-MM-DD | CC A.B.C` where `CC A.B.C` is the bundled Claude Code CLI version from `@default_cli_version` in `lib/claude_code/installer.ex`. This helps users know which CLI version each SDK release was tested against.

## Implementation Details

1. **Read existing CHANGELOG.md** or create with standard header
2. **Get the last referenced commit** by finding the most recent commit hash in the changelog
3. **Fetch commits** using `git log <last-commit>..HEAD --oneline` (or all commits if no last-commit)
4. **Parse each commit**:
   - Extract gitmoji emoji if present
   - Extract conventional commit type if present (feat, fix, chore, etc.)
   - Get commit description (remove gitmoji and type prefix)
   - Get short commit hash
5. **Filter commits** - CRITICALLY IMPORTANT:
   - Exclude commits that only affect internal tooling (`.claude/`, CI configs, etc.)
   - Exclude commits for proposals, planning docs, internal documentation
   - Exclude pure test changes, dev dependency updates, formatting-only changes
   - Keep only commits that affect the public API, features, behavior, or user-facing documentation
   - When in doubt, ask: "Would a library user care about this change?"
6. **Group commits** by their type into appropriate changelog sections
7. **Update Unreleased section**:
   - Find or create the "## [Unreleased]" section
   - Add subsections (### Added, ### Fixed, etc.) as needed
   - Add commit entries in the format: `- Description ([hash])`
8. **Write updated CHANGELOG.md**

## Notes

- This command only updates the "Unreleased" section
- Version releases and tagging should be handled by a separate `/release` command
- Commits are processed in chronological order (oldest to newest)
- Merge commits and commits without meaningful messages may be filtered out
- The command is idempotent - running it multiple times will only add new commits
- **CRITICAL**: Always review commits and exclude internal tooling changes (`.claude/` configs, proposals, dev tools, etc.)
- Focus on what library users need to know, not internal development changes
