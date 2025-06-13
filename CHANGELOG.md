# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0-alpha.1] - 2025-01-13

### Added
- Initial project structure
- Development environment setup with Styler, Credo, Dialyzer
- Comprehensive documentation (README, ROADMAP, VISION, ARCHITECTURE)
- GitHub Actions CI workflow
- Test coverage with ExCoveralls
- **Phase 1 MVP Implementation:**
  - `ClaudeCode` main module with `start_link/1` and `query_sync/3`
  - `ClaudeCode.Session` GenServer for managing CLI subprocess
  - `ClaudeCode.CLI` for finding and validating the claude binary
  - `ClaudeCode.Message` for parsing JSON responses
  - Support for custom models and named sessions
  - Comprehensive test suite including unit and integration tests
  - Error handling for CLI not found, authentication failures, and timeouts

### Changed
- Updated README with current project status and usage examples
- Project status changed from "Pre-alpha" to "Alpha (Phase 1 Complete)"

### Security
- API keys are passed via environment variables, never in command arguments
- Uses Elixir Port with explicit argument lists to prevent command injection