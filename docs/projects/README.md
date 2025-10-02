# ClaudeCode SDK v1.0 Projects

This directory contains the active development projects for reaching v1.0 release.

## Project Status

| Project | Priority | Effort | Status |
|---------|----------|--------|--------|
| [P0: Tool Control Fixes](./p0-tool-control-fixes/) | Critical | ~4h | Not Started |
| [P0: Production Features](./p0-production-features/) | Critical | ~5h | Not Started |
| [P1: Streaming & Forking](./p1-streaming-and-forking/) | High | ~8h | Not Started |
| [P2: Agents Support](./p2-agents-support/) | Nice-to-Have | ~3h | Not Started |

**Total Effort**: ~20 hours to v1.0

## Development Order

### Week 1: Critical Path (P0)
1. **Tool Control Fixes** - Fix bugs in existing features
   - Investigate CLI format for tool restrictions
   - Write tests, fix implementation
   - Verify permission-prompt-tool

2. **Production Features** - Add fallback model support
   - Implement `--fallback-model` option
   - Add production resilience examples

### Week 2: High Priority (P1)
3. **Streaming & Forking** - Complete parity with TypeScript SDK
   - Add partial message streaming for LiveView
   - Implement session forking for conversation branching
   - Consider team settings if time permits

### Week 2: Nice-to-Have (P2)
4. **Agents Support** - Custom subagent definitions
   - Add `--agents` flag support with JSON schema validation
   - Enable specialized agents (reviewers, debuggers, etc.)
   - Document agent definition patterns

## v1.0 Release Criteria

After completing all projects:

- [ ] All P0 + P1 features implemented
- [ ] Test coverage >95%
- [ ] All examples working
- [ ] Documentation complete
- [ ] Performance benchmarked
- [ ] Security audit passed

## Current SDK State

**Phase 4 Complete**: Options & Configuration system

**Have** (18 features):
- Core session management
- Streaming with backpressure
- Full message type parsing
- Options validation & precedence
- Query-level overrides

**Building** (7 features for v1.0):
- Fix: Tool control format bugs
- Add: Fallback model support
- Add: Partial message streaming
- Add: Session forking
- Add: Agents support
- Verify: Permission prompt tool
- Optional: Team settings

**Deferred** (3 features to v1.1+):
- Streaming input
- Strict MCP config
- Setting sources

## Project Structure

Each project folder contains:
- `README.md` - Objective, scope, success criteria
- Tasks created as needed during implementation
- Working code/test artifacts

## Questions?

See `/docs/proposals/FEATURE_MATRIX.md` for complete feature analysis.
