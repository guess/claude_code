# Upstream Type Mapping

Cross-reference between Elixir SDK modules and their TypeScript/Python SDK equivalents.
Use this table when running `/cli-sync` to locate upstream type definitions for comparison.

## Message Types

| Elixir Module | TS SDK Type | Python SDK Type | Notes |
|---|---|---|---|
| `Message.SystemMessage.Init` | `SDKSystemMessage` | `SystemMessage` | Init subtype; `SystemMessage` is the namespace module |
| `Message.AssistantMessage` | `SDKAssistantMessage` | `AssistantMessage` | |
| `Message.UserMessage` | `SDKUserMessage` / `SDKUserMessageReplay` | `UserMessage` | `SDKUserMessageReplay` handled via `is_replay` field |
| `Message.ResultMessage` | `SDKResultMessage` (`SDKResultSuccess \| SDKResultError`) | `ResultMessage` | |
| `Message.PartialAssistantMessage` | `SDKPartialAssistantMessage` | `StreamEvent` | Python uses different name |
| `Message.SystemMessage.CompactBoundary` | `SDKCompactBoundaryMessage` | -- | TS only |
| `Message.SystemMessage.Status` | `SDKStatusMessage` | -- | TS only |
| `Message.AuthStatusMessage` | `SDKAuthStatusMessage` | -- | TS only |
| `Message.RateLimitEvent` | `SDKRateLimitEvent` | -- | TS only |
| `Message.SystemMessage.FilesPersisted` | `SDKFilesPersistedEvent` | -- | TS only |
| `Message.ToolProgressMessage` | `SDKToolProgressMessage` | -- | TS only |
| `Message.ToolUseSummaryMessage` | `SDKToolUseSummaryMessage` | -- | TS only |
| `Message.PromptSuggestionMessage` | `SDKPromptSuggestionMessage` | -- | TS only |
| `Message.SystemMessage.LocalCommandOutput` | `SDKLocalCommandOutputMessage` | -- | TS only |
| `Message.SystemMessage.ElicitationComplete` | `SDKElicitationCompleteMessage` | -- | TS only |
| `Message.SystemMessage.HookStarted` | `SDKHookStartedMessage` | -- | TS only |
| `Message.SystemMessage.HookProgress` | `SDKHookProgressMessage` | -- | TS only |
| `Message.SystemMessage.HookResponse` | `SDKHookResponseMessage` | -- | TS only |
| `Message.SystemMessage.TaskStarted` | `SDKTaskStartedMessage` | `TaskStartedMessage` | |
| `Message.SystemMessage.TaskProgress` | `SDKTaskProgressMessage` | `TaskProgressMessage` | |
| `Message.SystemMessage.TaskNotification` | `SDKTaskNotificationMessage` | `TaskNotificationMessage` | |

## Content Block Types

Content blocks come from the Anthropic API types (`BetaContentBlock` in TS SDK). The CLI passes
these through in assistant/user message `content` arrays. The Anthropic API type definitions are
in `captured/anthropic-api-messages.d.ts`.

| Elixir Module | Anthropic API Type (TS) | Python SDK Type | Notes |
|---|---|---|---|
| `Content.TextBlock` | `BetaTextBlock` | `TextBlock` | |
| `Content.ThinkingBlock` | `BetaThinkingBlock` | `ThinkingBlock` | |
| `Content.RedactedThinkingBlock` | `BetaRedactedThinkingBlock` | -- | |
| `Content.ToolUseBlock` | `BetaToolUseBlock` | `ToolUseBlock` | |
| `Content.ToolResultBlock` | `BetaToolResultBlockParam` | `ToolResultBlock` | Round-tripped in user messages |
| `Content.ServerToolUseBlock` | `BetaServerToolUseBlock` | -- | Web search, code execution, etc. |
| `Content.ServerToolResultBlock` | *(various: `BetaWebSearchToolResultBlock`, `BetaCodeExecutionToolResultBlock`, etc.)* | -- | Elixir uses single generic struct |
| `Content.MCPToolUseBlock` | `BetaMCPToolUseBlock` | -- | |
| `Content.MCPToolResultBlock` | `BetaMCPToolResultBlock` | -- | |
| `Content.ImageBlock` | `BetaImageBlockParam` | -- | Input-only (user messages) |
| `Content.DocumentBlock` | `BetaDocumentBlock` / `BetaRequestDocumentBlock` | -- | PDF/text documents |
| `Content.ContainerUploadBlock` | `BetaContainerUploadBlock` | -- | Code execution container files |
| `Content.CompactionBlock` | `BetaCompactionBlock` | -- | Context compaction summaries |

## Other Structs

| Elixir Module | TS SDK Type | Python SDK Type | Notes |
|---|---|---|---|
| `ClaudeCode.Sandbox` | `SandboxSettings` | `SandboxSettings` | |
| `ClaudeCode.Sandbox.Network` | `SandboxNetworkConfig` | `SandboxNetworkConfig` | |
| `ClaudeCode.Sandbox.Filesystem` | `SandboxFilesystemConfig` | -- | FS write/read allow/deny lists |
| `ClaudeCode.Agent` | `AgentDefinition` | `AgentDefinition` | Input config for custom agents |
| `ClaudeCode.ModelInfo` | `ModelInfo` | -- | From `SDKControlInitializeResponse.models` |
| `ClaudeCode.AgentInfo` | `AgentInfo` | -- | From `SDKControlInitializeResponse.agents` |
| `ClaudeCode.AccountInfo` | `AccountInfo` | -- | From `SDKControlInitializeResponse.account` |
| `ClaudeCode.SlashCommand` | `SlashCommand` | -- | From `SDKControlInitializeResponse.commands` |
| `ClaudeCode.PermissionDenial` | `SDKPermissionDenial` | -- | In `SDKResultSuccess.permission_denials` |
| `ClaudeCode.ModelUsage` | `ModelUsage` | -- | Per-model token/cost breakdown |
| `ClaudeCode.MCP.ServerStatus` | `McpServerStatus` | -- | Returned by `mcpServerStatus()` |
| `ClaudeCode.CLI.Control.Types.set_servers_result` | `McpSetServersResult` | -- | Type spec only (raw map); returned by `setMcpServers()` |
| `ClaudeCode.CLI.Control.Types.rewind_files_result` | `RewindFilesResult` | -- | Type spec only (raw map); returned by `rewindFiles()` |
| `ClaudeCode.CLI.Control.Types.initialize_response` | `SDKControlInitializeResponse` | -- | Type spec only (raw map); parsed in `Adapter.Port` |

## Union Types

| Elixir Type | TS SDK Type | Python SDK Type |
|---|---|---|
| `ClaudeCode.Message.t/0` | `SDKMessage` | `Message` |
| `ClaudeCode.Content.t/0` | `BetaContentBlock` | `ContentBlock` |
| `ClaudeCode.Content.delta/0` | `BetaRawContentBlockDelta` | -- |

## Control Protocol Coverage

The control protocol uses bidirectional JSON messages over stdin/stdout. The CLI can send
`control_request` messages to the SDK, and the SDK can send `control_request` messages to the CLI.

### SDK → CLI Requests (outbound)

| TS SDK Type | TS Public Method | Elixir Builder | Elixir Public API | Status |
|---|---|---|---|---|
| `SDKControlInitializeRequest` | *(automatic)* | `Control.initialize_request/5` | *(automatic)* | Implemented |
| `SDKControlInterruptRequest` | `Query.interrupt()` | `Control.interrupt_request/1` | `ClaudeCode.interrupt/1` | Implemented |
| `SDKControlSetModelRequest` | `Query.setModel()` | `Control.set_model_request/2` | `ClaudeCode.set_model/2` | Implemented |
| `SDKControlSetPermissionModeRequest` | `Query.setPermissionMode()` | `Control.set_permission_mode_request/2` | `ClaudeCode.Session.set_permission_mode/2` | Implemented |
| `SDKControlSetMaxThinkingTokensRequest` | `Query.setMaxThinkingTokens()` | -- | -- | **Removed** — deprecated in TS SDK; use `thinking` option instead |
| `SDKControlRewindFilesRequest` | `Query.rewindFiles()` | `Control.rewind_files_request/2` | `ClaudeCode.Session.rewind_files/2` | Implemented |
| `SDKControlMcpStatusRequest` | `Query.mcpServerStatus()` | `Control.mcp_status_request/1` | `ClaudeCode.Session.mcp_status/1` | Implemented |
| `SDKControlMcpReconnectRequest` | `Query.reconnectMcpServer()` | `Control.mcp_reconnect_request/2` | `ClaudeCode.Session.mcp_reconnect/2` | Implemented |
| `SDKControlMcpToggleRequest` | `Query.toggleMcpServer()` | `Control.mcp_toggle_request/3` | `ClaudeCode.Session.mcp_toggle/3` | Implemented |
| `SDKControlStopTaskRequest` | `Query.stopTask()` | `Control.stop_task_request/2` | `ClaudeCode.Session.stop_task/2` | Implemented |
| `SDKControlMcpSetServersRequest` | `Query.setMcpServers()` | `Control.mcp_set_servers_request/2` | `ClaudeCode.Session.set_mcp_servers/2` | Implemented |
| `SDKControlMcpMessageRequest` | *(internal)* | -- | -- | **Skipped** — no public TS method; internal SDK MCP transport |
| `SDKControlApplyFlagSettingsRequest` | *(internal)* | -- | -- | **Skipped** — no public TS method; internal settings plumbing |
| `SDKControlGetSettingsRequest` | *(internal)* | -- | -- | **Skipped** — no public TS method; internal settings plumbing |
| `SDKControlElicitationRequest` | *(inbound only)* | -- | -- | **Not implemented** — CLI asks SDK for user input |
| `SDKControlMcpAuthenticateRequest` | *(no type def)* | -- | -- | **Deferred** — no type definition in TS SDK |
| `SDKControlMcpClearAuthRequest` | *(no type def)* | -- | -- | **Deferred** — no type definition in TS SDK |
| `SDKControlMcpOAuthCallbackUrlRequest` | *(no type def)* | -- | -- | **Deferred** — no type definition in TS SDK |
| `SDKControlRemoteControlRequest` | *(no type def)* | -- | -- | **Deferred** — no type definition in TS SDK |
| `SDKControlSetProactiveRequest` | *(no type def)* | -- | -- | **Deferred** — no type definition in TS SDK |

### CLI → SDK Requests (inbound)

| TS SDK Type | Elixir Handling | Status |
|---|---|---|
| `SDKControlPermissionRequest` (`can_use_tool`) | Handled in `Adapter.Port` | Implemented |
| `SDKHookCallbackRequest` | Handled in `Adapter.Port` | Implemented |
| `SDKControlElicitationRequest` | Logged in `Adapter.Port` | **Partial** — logged, returns error; full callback not yet implemented |
| `SDKControlCancelRequest` | Handled in `Adapter.Port` | Implemented — cancels pending requests |

### Response Parsing

| TS SDK Type | Elixir | Status |
|---|---|---|
| `SDKControlInitializeResponse` | `Control.parse_control_response/1` + `Adapter.Port.parse_initialize_response/1` | Implemented — parses `models`, `agents`, `account` into typed structs |
| `ControlResponse` / `ControlErrorResponse` | `Control.parse_control_response/1` | Implemented |

### Initialize Response Accessors

The TS SDK exposes convenience methods on `Query` that read from the cached `SDKControlInitializeResponse`.

| TS Public Method | Elixir Public API | Status |
|---|---|---|
| `Query.initializationResult()` | `ClaudeCode.Session.server_info/1` | Implemented (returns raw map) |
| `Query.supportedModels()` | `ClaudeCode.Session.supported_models/1` | Implemented |
| `Query.supportedAgents()` | `ClaudeCode.Session.supported_agents/1` | Implemented |
| `Query.supportedCommands()` | `ClaudeCode.supported_commands/1` | Implemented |
| `Query.accountInfo()` | `ClaudeCode.account_info/1` | Implemented |

## Lookup by TS SDK Name

Reverse index for quickly finding the Elixir module from an upstream type name.

| SDK Type Name | Elixir Module |
|---|---|
| `AccountInfo` | `ClaudeCode.AccountInfo` |
| `AgentDefinition` | `ClaudeCode.Agent` |
| `AgentInfo` | `ClaudeCode.AgentInfo` |
| `BetaCompactionBlock` | `Content.CompactionBlock` |
| `BetaContainerUploadBlock` | `Content.ContainerUploadBlock` |
| `BetaDocumentBlock` | `Content.DocumentBlock` |
| `BetaImageBlockParam` | `Content.ImageBlock` |
| `BetaMCPToolResultBlock` | `Content.MCPToolResultBlock` |
| `BetaMCPToolUseBlock` | `Content.MCPToolUseBlock` |
| `BetaRedactedThinkingBlock` | `Content.RedactedThinkingBlock` |
| `BetaServerToolUseBlock` | `Content.ServerToolUseBlock` |
| `BetaTextBlock` | `Content.TextBlock` |
| `BetaThinkingBlock` | `Content.ThinkingBlock` |
| `BetaToolResultBlockParam` | `Content.ToolResultBlock` |
| `BetaToolUseBlock` | `Content.ToolUseBlock` |
| `McpServerStatus` | `ClaudeCode.MCP.ServerStatus` |
| `McpSetServersResult` | `ClaudeCode.CLI.Control.Types.set_servers_result` (type spec) |
| `ModelInfo` | `ClaudeCode.ModelInfo` |
| `ModelUsage` | `ClaudeCode.ModelUsage` |
| `RewindFilesResult` | `ClaudeCode.CLI.Control.Types.rewind_files_result` (type spec) |
| `SandboxFilesystemConfig` | `ClaudeCode.Sandbox.Filesystem` |
| `SandboxNetworkConfig` | `ClaudeCode.Sandbox.Network` |
| `SandboxSettings` | `ClaudeCode.Sandbox` |
| `SDKAssistantMessage` | `Message.AssistantMessage` |
| `SDKAuthStatusMessage` | `Message.AuthStatusMessage` |
| `SDKCompactBoundaryMessage` | `Message.SystemMessage.CompactBoundary` |
| `SDKControlInitializeResponse` | `ClaudeCode.CLI.Control.Types.initialize_response` (type spec) |
| `SDKElicitationCompleteMessage` | `Message.SystemMessage.ElicitationComplete` |
| `SDKFilesPersistedEvent` | `Message.SystemMessage.FilesPersisted` |
| `SDKHookProgressMessage` | `Message.SystemMessage.HookProgress` |
| `SDKHookResponseMessage` | `Message.SystemMessage.HookResponse` |
| `SDKHookStartedMessage` | `Message.SystemMessage.HookStarted` |
| `SDKLocalCommandOutputMessage` | `Message.SystemMessage.LocalCommandOutput` |
| `SDKPartialAssistantMessage` | `Message.PartialAssistantMessage` |
| `SDKPermissionDenial` | `ClaudeCode.PermissionDenial` |
| `SDKPromptSuggestionMessage` | `Message.PromptSuggestionMessage` |
| `SDKRateLimitEvent` | `Message.RateLimitEvent` |
| `SDKResultMessage` | `Message.ResultMessage` |
| `SDKStatusMessage` | `Message.SystemMessage.Status` |
| `SDKSystemMessage` | `Message.SystemMessage.Init` |
| `SDKTaskNotificationMessage` | `Message.SystemMessage.TaskNotification` |
| `SDKTaskProgressMessage` | `Message.SystemMessage.TaskProgress` |
| `SDKTaskStartedMessage` | `Message.SystemMessage.TaskStarted` |
| `SDKToolProgressMessage` | `Message.ToolProgressMessage` |
| `SDKToolUseSummaryMessage` | `Message.ToolUseSummaryMessage` |
| `SDKUserMessage` | `Message.UserMessage` |
| `SDKUserMessageReplay` | `Message.UserMessage` (via `is_replay` field) |
| `SlashCommand` | `ClaudeCode.SlashCommand` |
