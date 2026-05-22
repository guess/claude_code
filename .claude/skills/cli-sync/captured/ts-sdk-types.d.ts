import type { BetaMessage } from '@anthropic-ai/sdk/resources/beta/messages/messages.mjs';
import type { BetaRawMessageStreamEvent } from '@anthropic-ai/sdk/resources/beta/messages/messages.mjs';
import type { BetaUsage } from '@anthropic-ai/sdk/resources/beta/messages/messages.mjs';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import type { ElicitResult } from '@modelcontextprotocol/sdk/types.js';
import type { JSONRPCMessage } from '@modelcontextprotocol/sdk/types.js';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { MessageParam } from '@anthropic-ai/sdk/resources';
import type { Readable } from 'stream';
import type { ToolAnnotations } from '@modelcontextprotocol/sdk/types.js';
import type { UUID } from 'crypto';
import type { Writable } from 'stream';
import { z } from 'zod/v4';
import type { ZodRawShape } from 'zod';
import type { ZodRawShape as ZodRawShape_2 } from 'zod/v4';

export declare class AbortError extends Error {
}

/**
 * Information about the logged in user's account.
 */
export declare type AccountInfo = {
    email?: string;
    organization?: string;
    subscriptionType?: string;
    tokenSource?: string;
    apiKeySource?: string;
    /**
     * Active API backend. Anthropic OAuth login only applies when "firstParty"; for 3P providers the other fields are absent and auth is external (AWS creds, gcloud ADC, etc.). "gateway" means the CLI is authenticated against an enterprise gateway.
     */
    apiProvider?: 'firstParty' | 'bedrock' | 'vertex' | 'foundry' | 'anthropicAws' | 'mantle' | 'gateway';
};

/**
 * Definition for a custom subagent that can be invoked via the Agent tool.
 */
export declare type AgentDefinition = {
    /**
     * Natural language description of when to use this agent
     */
    description: string;
    /**
     * Array of allowed tool names. If omitted, inherits all tools from parent. Note: passing 'Skill' here is deprecated — use the `skills` field instead.
     */
    tools?: string[];
    /**
     * Array of tool names to explicitly disallow for this agent
     */
    disallowedTools?: string[];
    /**
     * The agent's system prompt
     */
    prompt: string;
    /**
     * Model alias (e.g. 'sonnet', 'opus', 'haiku') or full model ID (e.g. 'claude-opus-4-5'). If omitted or 'inherit', uses the main model
     */
    model?: string;
    mcpServers?: AgentMcpServerSpec[];
    /**
     * Experimental: Critical reminder added to system prompt
     */
    criticalSystemReminder_EXPERIMENTAL?: string;
    /**
     * Array of skill names to preload into the agent context
     */
    skills?: string[];
    /**
     * Auto-submitted as the first user turn when this agent is the main thread agent. Slash commands are processed. Prepended to any user-provided prompt.
     */
    initialPrompt?: string;
    /**
     * Maximum number of agentic turns (API round-trips) before stopping
     */
    maxTurns?: number;
    /**
     * Run this agent as a background task (non-blocking, fire-and-forget) when invoked
     */
    background?: boolean;
    /**
     * Scope for auto-loading agent memory files. 'user' - ~/.claude/agent-memory/<agentType>/, 'project' - .claude/agent-memory/<agentType>/, 'local' - .claude/agent-memory-local/<agentType>/
     */
    memory?: 'user' | 'project' | 'local';
    /**
     * Reasoning effort level for this agent. Either a named level or an integer
     */
    effort?: ('low' | 'medium' | 'high' | 'xhigh' | 'max') | number;
    /**
     * Permission mode controlling how tool executions are handled
     */
    permissionMode?: PermissionMode;
};

/**
 * Information about an available subagent that can be invoked via the Task tool.
 */
export declare type AgentInfo = {
    /**
     * Agent type identifier (e.g., "Explore")
     */
    name: string;
    /**
     * Description of when to use this agent
     */
    description: string;
    /**
     * Model alias this agent uses. If omitted, inherits the parent's model
     */
    model?: string;
};

export declare type AgentMcpServerSpec = string | Record<string, McpServerConfigForProcessTransport>;

export declare type AnyZodRawShape = ZodRawShape | ZodRawShape_2;

export declare type ApiKeySource = 'user' | 'project' | 'org' | 'temporary' | 'oauth';

export declare type AsyncHookJSONOutput = {
    async: true;
    asyncTimeout?: number;
};

export declare type BackgroundTaskSummary = {
    id: string;
    /**
     * Friendly task-type label (e.g. 'shell', 'subagent', 'monitor', 'workflow'). Falls back to the raw discriminant for unknown types.
     */
    type: string;
    status: string;
    /**
     * Free-text description. Capped at 1000 chars; clipped values append an in-string "… [+N chars]" marker.
     */
    description: string;
    /**
     * Shell command line. Only present for 'shell' tasks. Capped at 1000 chars with the same "… [+N chars]" marker.
     */
    command?: string;
    /**
     * Subagent type name. Only present for 'subagent' tasks.
     */
    agent_type?: string;
    /**
     * MCP server name. Only present for 'monitor' / 'MCP task' tasks.
     */
    server?: string;
    /**
     * MCP tool name. Only present for 'monitor' / 'MCP task' tasks.
     */
    tool?: string;
    /**
     * Workflow name. Only present for 'workflow' tasks.
     */
    name?: string;
};

export declare type BaseHookInput = {
    session_id: string;
    transcript_path: string;
    cwd: string;
    permission_mode?: string;
    /**
     * Subagent identifier. Present only when the hook fires from within a subagent (e.g., a tool called by an AgentTool worker). Absent for the main thread, even in --agent sessions. Use this field (not agent_type) to distinguish subagent calls from main-thread calls.
     */
    agent_id?: string;
    /**
     * Agent type name (e.g., "general-purpose", "code-reviewer"). Present when the hook fires from within a subagent (alongside agent_id), or on the main thread of a session started with --agent (without agent_id).
     */
    agent_type?: string;
    /**
     * Reasoning effort applied to the current turn. Same shape as StatusLineCommandInput.effort. Present for hooks that fire within a tool-use context (PreToolUse, PostToolUse, Stop, SubagentStop, etc.) on a model that supports the effort parameter; absent for session-lifecycle hooks and models without effort support.
     */
    effort?: {
        /**
         * Active effort level for the current turn (e.g., "low", "medium", "high", "xhigh", "max"), after any silent downgrade for the selected model. Also exposed to hook commands and Bash as the CLAUDE_EFFORT env var.
         */
        level: string;
    };
};

export declare type BaseOutputFormat = {
    type: OutputFormatType;
};

/**
 * Permission callback function for controlling tool usage.
 * Called before each tool execution to determine if it should be allowed.
 */
export declare type CanUseTool = (toolName: string, input: Record<string, unknown>, options: {
    /** Signaled if the operation should be aborted. */
    signal: AbortSignal;
    /**
     * Suggestions for updating permissions so that the user will not be
     * prompted again for this tool during this session.
     *
     * Typically if presenting the user an option 'always allow' or similar,
     * then this full set of suggestions should be returned as the
     * `updatedPermissions` in the PermissionResult.
     */
    suggestions?: PermissionUpdate[];
    /**
     * The file path that triggered the permission request, if applicable.
     * For example, when a Bash command tries to access a path outside allowed directories.
     */
    blockedPath?: string;
    /** Explains why this permission request was triggered. */
    decisionReason?: string;
    /**
     * Full permission prompt sentence rendered by the bridge (e.g.
     * "Claude wants to read foo.txt"). Use this as the primary prompt
     * text when present instead of reconstructing from toolName+input.
     */
    title?: string;
    /**
     * Short noun phrase for the tool action (e.g. "Read file"), suitable
     * for button labels or compact UI.
     */
    displayName?: string;
    /**
     * Human-readable subtitle from the bridge (e.g. "Claude will have
     * read and write access to files in ~/Downloads").
     */
    description?: string;
    /**
     * Unique identifier for this specific tool call within the assistant message.
     * Multiple tool calls in the same assistant message will have different toolUseIDs.
     */
    toolUseID: string;
    /** If running within the context of a sub-agent, the sub-agent's ID. */
    agentID?: string;
}) => Promise<PermissionResult>;

export declare type ConfigChangeHookInput = BaseHookInput & {
    hook_event_name: 'ConfigChange';
    source: 'user_settings' | 'project_settings' | 'local_settings' | 'policy_settings' | 'skills';
    file_path?: string;
};

/**
 * Config scope for settings.
 */
export declare type ConfigScope = 'local' | 'user' | 'project';

/**
 * Structured failure from connectRemoteControl.
 * @alpha
 */
export declare type ConnectRemoteControlError = {
    kind: 'conflict' | 'auth' | 'network' | 'unknown';
    detail: string;
};

/**
 * Options for connectRemoteControl.
 * @alpha
 */
export declare type ConnectRemoteControlOptions = {
    dir: string;
    /** Override directory sent to backend for env registration. */
    registrationDir?: string;
    name?: string;
    workerType?: string;
    branch?: string;
    gitRepoUrl?: string | null;
    getAccessToken: () => string | undefined;
    baseUrl: string;
    orgUUID: string;
    model: string;
    /** Reuse env+session across restarts (reads bridge-pointer.json). */
    perpetual?: boolean;
    /** SSE high-water mark so reconnect sends from_sequence_num. */
    initialSSESequenceNum?: number;
    /** Called on 401; return true after refreshing token to retry. */
    onAuth401?: (staleAccessToken: string) => Promise<boolean>;
    /** Called on 409 conflict; return 'takeover' to deregister + retry. */
    onConflict?: (detail: {
        machineName: string;
        message: string;
    }) => Promise<'takeover' | 'abort'>;
};

/**
 * Discriminated result from connectRemoteControl.
 * @alpha
 */
export declare type ConnectRemoteControlResult = {
    ok: true;
    handle: RemoteControlHandle;
} | {
    ok: false;
    error: ConnectRemoteControlError;
};

declare type ControlErrorResponse = {
    subtype: 'error';
    request_id: string;
    error: string;
    pending_permission_requests?: SDKControlRequest[];
};

declare type ControlResponse = {
    subtype: 'success';
    request_id: string;
    response?: Record<string, unknown>;
};

declare namespace coreTypes {
    export {
        SandboxFilesystemConfig,
        SandboxIgnoreViolations,
        SandboxNetworkConfig,
        SandboxSettings,
        NonNullableUsage,
        HOOK_EVENTS,
        EXIT_REASONS,
        SYSTEM_PROMPT_DYNAMIC_BOUNDARY,
        AccountInfo,
        AgentDefinition,
        AgentInfo,
        AgentMcpServerSpec,
        ApiKeySource,
        AsyncHookJSONOutput,
        BackgroundTaskSummary,
        BaseHookInput,
        BaseOutputFormat,
        ConfigChangeHookInput,
        ConfigScope,
        CwdChangedHookInput,
        CwdChangedHookSpecificOutput,
        ElicitationHookInput,
        ElicitationHookSpecificOutput,
        ElicitationResultHookInput,
        ElicitationResultHookSpecificOutput,
        ExitReason,
        FastModeState,
        FileChangedHookInput,
        FileChangedHookSpecificOutput,
        HookEvent,
        HookInput,
        HookJSONOutput,
        HookPermissionDecision,
        InstructionsLoadedHookInput,
        JsonSchemaOutputFormat,
        McpClaudeAIProxyServerConfig,
        McpHttpServerConfig,
        McpSSEServerConfig,
        McpSdkServerConfig,
        McpServerConfigForProcessTransport,
        McpServerStatusConfig,
        McpServerStatus,
        McpServerToolPolicy,
        McpSetServersResult,
        McpStdioServerConfig,
        ModelInfo,
        ModelUsage,
        NotificationHookInput,
        NotificationHookSpecificOutput,
        OutputFormat,
        OutputFormatType,
        PermissionBehavior,
        PermissionDecisionClassification,
        PermissionDeniedHookInput,
        PermissionDeniedHookSpecificOutput,
        PermissionMode,
        PermissionRequestHookInput,
        PermissionRequestHookSpecificOutput,
        PermissionResult,
        PermissionRuleValue,
        PermissionUpdateDestination,
        PermissionUpdate,
        PostCompactHookInput,
        PostToolBatchHookInput,
        PostToolBatchHookSpecificOutput,
        PostToolBatchToolCall,
        PostToolUseFailureHookInput,
        PostToolUseFailureHookSpecificOutput,
        PostToolUseHookInput,
        PostToolUseHookSpecificOutput,
        PreCompactHookInput,
        PreToolUseHookInput,
        PreToolUseHookSpecificOutput,
        RewindFilesResult,
        SDKAPIRetryMessage,
        SDKAssistantMessageError,
        SDKAssistantMessage,
        SDKAuthStatusMessage,
        SDKCompactBoundaryMessage,
        SDKDeferredToolUse,
        SDKElicitationCompleteMessage,
        SDKFilesPersistedEvent,
        SDKHookProgressMessage,
        SDKHookResponseMessage,
        SDKHookStartedMessage,
        SDKLocalCommandOutputMessage,
        SDKMemoryRecallMessage,
        SDKMessageOrigin,
        SDKMessage,
        SDKMirrorErrorMessage,
        SDKNotificationMessage,
        SDKPartialAssistantMessage,
        SDKPermissionDenial,
        SDKPermissionDeniedMessage,
        SDKPluginInstallMessage,
        SDKPromptSuggestionMessage,
        SDKRateLimitEvent,
        SDKRateLimitInfo,
        SDKResultError,
        SDKResultMessage,
        SDKResultSuccess,
        SDKSessionInfo,
        SDKSessionStateChangedMessage,
        SDKSettingsParseError,
        SDKStatusMessage,
        SDKStatus,
        SDKSystemMessage,
        SDKTaskNotificationMessage,
        SDKTaskProgressMessage,
        SDKTaskStartedMessage,
        SDKTaskUpdatedMessage,
        SDKToolProgressMessage,
        SDKToolUseSummaryMessage,
        SDKUserMessageReplay,
        SDKUserMessage,
        SdkBeta,
        SdkPluginConfig,
        SessionCronSummary,
        SessionEndHookInput,
        SessionStartHookInput,
        SessionStartHookSpecificOutput,
        SettingSource,
        SetupHookInput,
        SetupHookSpecificOutput,
        SlashCommand,
        StopFailureHookInput,
        StopHookInput,
        SubagentStartHookInput,
        SubagentStartHookSpecificOutput,
        SubagentStopHookInput,
        SyncHookJSONOutput,
        TaskCompletedHookInput,
        TaskCreatedHookInput,
        TeammateIdleHookInput,
        TerminalReason,
        ThinkingAdaptive,
        ThinkingConfig,
        ThinkingDisabled,
        ThinkingEnabled,
        UserPromptExpansionHookInput,
        UserPromptExpansionHookSpecificOutput,
        UserPromptSubmitHookInput,
        UserPromptSubmitHookSpecificOutput,
        WorktreeCreateHookInput,
        WorktreeCreateHookSpecificOutput,
        WorktreeRemoveHookInput
    }
}

/**
 * Creates an MCP server instance that can be used with the SDK transport.
 * This allows SDK users to define custom tools that run in the same process.
 *
 * If your SDK MCP calls will run longer than 60s, override CLAUDE_CODE_STREAM_CLOSE_TIMEOUT
 */
export declare function createSdkMcpServer(_options: CreateSdkMcpServerOptions): McpSdkServerConfigWithInstance;

declare type CreateSdkMcpServerOptions = {
    name: string;
    version?: string;
    /**
     * Server instructions returned from `initialize` and surfaced to the model
     * as an MCP instructions block. When proxying a real MCP server through the
     * SDK transport, pass the underlying server's `getInstructions()` here so
     * it isn't dropped.
     */
    instructions?: string;
    tools?: Array<SdkMcpToolDefinition<any>>;
    /**
     * When true, all tools from this server are always included in the prompt
     * and never deferred behind tool search. Applied via
     * `_meta['anthropic/alwaysLoad']` on each tool. Equivalent to
     * `defer_loading: false` on the API. Per-tool `tool({ alwaysLoad })` still
     * works and is OR'd with this.
     */
    alwaysLoad?: boolean;
};

export declare type CwdChangedHookInput = BaseHookInput & {
    hook_event_name: 'CwdChanged';
    old_cwd: string;
    new_cwd: string;
};

export declare type CwdChangedHookSpecificOutput = {
    hookEventName: 'CwdChanged';
    watchPaths?: string[];
};

/**
 * Delete a session.
 *
 * With `sessionStore`: calls `sessionStore.delete()` if implemented; no-op
 * otherwise (per the SessionStore contract — appropriate for WORM/append-only
 * backends).
 *
 * Without `sessionStore`: removes `{sessionId}.jsonl` and the `{sessionId}/`
 * subagent-transcript subdirectory from the local projects dir. Throws if the
 * session is not found.
 *
 * @param sessionId - UUID of the session
 * @param options - `{ dir?, sessionStore? }`
 */
export declare function deleteSession(_sessionId: string, _options?: SessionMutationOptions): Promise<void>;

/**
 * Effort level for controlling how much thinking/reasoning Claude applies.
 *
 * - `'low'` — Minimal thinking, fastest responses
 * - `'medium'` — Moderate thinking
 * - `'high'` — Deep reasoning (default)
 * - `'xhigh'` — Deeper than high (Opus 4.7 only; falls back to `'high'` elsewhere)
 * - `'max'` — Maximum effort (select models only)
 */
export declare type EffortLevel = 'low' | 'medium' | 'high' | 'xhigh' | 'max';

/**
 * Hook input for the Elicitation event. Fired when an MCP server requests user input. Hooks can auto-respond (accept/decline) instead of showing the dialog.
 */
export declare type ElicitationHookInput = BaseHookInput & {
    hook_event_name: 'Elicitation';
    mcp_server_name: string;
    message: string;
    mode?: 'form' | 'url';
    url?: string;
    elicitation_id?: string;
    requested_schema?: Record<string, unknown>;
};

/**
 * Hook-specific output for the Elicitation event. Return this to programmatically accept or decline an MCP elicitation request.
 */
export declare type ElicitationHookSpecificOutput = {
    hookEventName: 'Elicitation';
    action?: 'accept' | 'decline' | 'cancel';
    content?: Record<string, unknown>;
};

/**
 * Elicitation request from an MCP server, asking the SDK consumer for user input.
 */
export declare type ElicitationRequest = {
    /** Name of the MCP server requesting elicitation */
    serverName: string;
    /** Message to display to the user */
    message: string;
    /** Elicitation mode: 'form' for structured input, 'url' for browser-based auth */
    mode?: 'form' | 'url';
    /** URL to open (only for 'url' mode) */
    url?: string;
    /** Elicitation ID for correlating URL elicitations with completion notifications (URL mode only) */
    elicitationId?: string;
    /** JSON Schema for the requested input (only for 'form' mode) */
    requestedSchema?: Record<string, unknown>;
    /** Permission-display title from MCP `_meta['anthropic/permissionDisplay']` — header for elicitation-driven permission prompts */
    title?: string;
    /** Short tool/server label from MCP `_meta['anthropic/permissionDisplay'].displayName` */
    displayName?: string;
    /** Permission-display subtitle from MCP `_meta['anthropic/permissionDisplay'].description` */
    description?: string;
};

/**
 * Elicitation response from the SDK consumer.
 * Re-exported from the MCP SDK for convenience.
 */
export declare type ElicitationResult = ElicitResult;

/**
 * Hook input for the ElicitationResult event. Fired after the user responds to an MCP elicitation. Hooks can observe or override the response before it is sent to the server.
 */
export declare type ElicitationResultHookInput = BaseHookInput & {
    hook_event_name: 'ElicitationResult';
    mcp_server_name: string;
    elicitation_id?: string;
    mode?: 'form' | 'url';
    action: 'accept' | 'decline' | 'cancel';
    content?: Record<string, unknown>;
};

/**
 * Hook-specific output for the ElicitationResult event. Return this to override the action or content before the response is sent to the MCP server.
 */
export declare type ElicitationResultHookSpecificOutput = {
    hookEventName: 'ElicitationResult';
    action?: 'accept' | 'decline' | 'cancel';
    content?: Record<string, unknown>;
};

export declare const EXIT_REASONS: readonly ["clear", "resume", "logout", "prompt_input_exit", "other", "bypass_permissions_disabled"];

export declare type ExitReason = 'clear' | 'resume' | 'logout' | 'prompt_input_exit' | 'other' | 'bypass_permissions_disabled';

/**
 * Fast mode state: off, in cooldown after rate limit, or actively enabled.
 */
export declare type FastModeState = 'off' | 'cooldown' | 'on';

export declare type FileChangedHookInput = BaseHookInput & {
    hook_event_name: 'FileChanged';
    file_path: string;
    event: 'change' | 'add' | 'unlink';
};

export declare type FileChangedHookSpecificOutput = {
    hookEventName: 'FileChanged';
    watchPaths?: string[];
};

/**
 * Apply the same trust-tier filter the CLI applies before honoring escalating
 * permission modes from settings: if `permissions.defaultMode` is escalating
 * (`bypassPermissions`/`auto`/`acceptEdits`) AND was set by a repo-committed
 * tier (`project`), drop it from the returned `effective`.
 *
 * @alpha
 */
export declare function filterEscalatingDefaultMode(_resolved: ResolvedSettings): Settings;

/**
 * Fold a batch of appended entries into the running summary for `key`.
 *
 * Stores call this from inside `append()` to keep a {@link SessionSummaryEntry}
 * sidecar up to date without re-reading the transcript. `prev` is the previous
 * summary for the same key (or `undefined` for the first append). The returned
 * `data` blob is opaque to the store — persist it verbatim.
 *
 * Set-once fields (`isSidechain`, `createdAt`, `cwd`, `firstPrompt`) freeze on
 * first sight; last-wins fields (`customTitle`, `aiTitle`, `lastPrompt`,
 * `summaryHint`, `gitBranch`, `tag`) overwrite on every appearance.
 *
 * `mtime` is NOT derived from entry timestamps — the adapter MUST stamp it at
 * persist time using the same clock it uses for `listSessions().mtime`. Pass
 * it via `options.mtime`; when omitted, the previous summary's `mtime` is
 * preserved (use this only when re-folding the same sidecar without a new
 * persist). See {@link SessionSummaryEntry.mtime} for the contract.
 * @alpha
 */
export declare function foldSessionSummary(prev: SessionSummaryEntry | undefined, key: SessionKey, entries: SessionStoreEntry[], options?: {
    mtime?: number;
}): SessionSummaryEntry;

/**
 * Fork a session into a new branch with fresh UUIDs.
 *
 * Copies transcript messages from the source session into a new session file,
 * remapping every message UUID and preserving the parentUuid chain. Supports
 * `upToMessageId` for branching from a specific point in the conversation.
 *
 * Forked sessions start without undo history (file-history snapshots are not
 * copied).
 *
 * @param sessionId - UUID of the source session
 * @param options - `{ dir?, upToMessageId?, title? }`
 * @returns `{ sessionId }` — UUID of the new forked session
 */
export declare function forkSession(_sessionId: string, _options?: ForkSessionOptions): Promise<ForkSessionResult>;

/**
 * Options for forking a session into a new branch.
 */
export declare type ForkSessionOptions = SessionMutationOptions & {
    /** Slice transcript up to this message UUID (inclusive). If omitted, full copy. */
    upToMessageId?: string;
    /** Custom title for the fork. If omitted, derives from original title + " (fork)". */
    title?: string;
};

/**
 * Result of a fork operation.
 */
export declare type ForkSessionResult = {
    /** New session UUID. Resumable via `query({ options: { resume: sessionId } })`. */
    sessionId: string;
};

/**
 * Reads metadata for a single session by ID. Unlike `listSessions`, this only
 * reads the single session file rather than every session in the project.
 * Returns undefined if the session file is not found, is a sidechain session,
 * or has no extractable summary.
 *
 * @param sessionId - UUID of the session
 * @param options - `{ dir?: string }` project path; omit to search all project directories
 */
export declare function getSessionInfo(_sessionId: string, _options?: GetSessionInfoOptions): Promise<SDKSessionInfo | undefined>;

/**
 * Options for getSessionInfo.
 */
export declare type GetSessionInfoOptions = {
    /**
     * Project directory path (same semantics as `listSessions({ dir })`).
     * When omitted, all project directories are searched for the session file.
     */
    dir?: string;
    /**
     * When provided, load session info from this store instead of the local
     * filesystem.
     * @alpha
     */
    sessionStore?: SessionStore;
};

/**
 * Reads a session's conversation messages from its JSONL transcript file.
 *
 * Parses the transcript, builds the conversation chain via parentUuid links,
 * and returns user/assistant messages in chronological order. Set
 * `includeSystemMessages: true` in options to also include system messages.
 *
 * @param sessionId - UUID of the session to read
 * @param options - Optional dir, limit, offset, and includeSystemMessages
 * @returns Array of messages, or empty array if session not found
 */
export declare function getSessionMessages(_sessionId: string, _options?: GetSessionMessagesOptions): Promise<SessionMessage[]>;

/**
 * Options for retrieving session messages.
 */
export declare type GetSessionMessagesOptions = {
    /** Project directory to find the session in. If omitted, searches all projects. */
    dir?: string;
    /** Maximum number of messages to return. */
    limit?: number;
    /** Number of messages to skip from the start. */
    offset?: number;
    /**
     * When true, include system messages (e.g., compact boundaries, informational
     * notices) in the returned list alongside user/assistant messages.
     * Defaults to false for backwards compatibility.
     */
    includeSystemMessages?: boolean;
    /**
     * When provided, load session messages from this store instead of the
     * local filesystem.
     * @alpha
     */
    sessionStore?: SessionStore;
};

/**
 * Reads a subagent's conversation messages from its JSONL transcript file.
 *
 * Parses the subagent transcript, builds the conversation chain via parentUuid
 * links, and returns user/assistant messages in chronological order.
 *
 * @param sessionId - UUID of the parent session
 * @param agentId - ID of the subagent
 * @param options - Optional dir, limit, and offset
 * @returns Array of user/assistant messages, or empty array if not found
 */
export declare function getSubagentMessages(_sessionId: string, _agentId: string, _options?: GetSubagentMessagesOptions): Promise<SessionMessage[]>;

/**
 * Options for retrieving subagent messages.
 */
export declare type GetSubagentMessagesOptions = {
    /** Project directory to find the session in. If omitted, searches all projects. */
    dir?: string;
    /** Maximum number of messages to return. */
    limit?: number;
    /** Number of messages to skip from the start. */
    offset?: number;
    /**
     * When provided, load subagent messages from this store instead of the
     * local filesystem.
     * @alpha
     */
    sessionStore?: SessionStore;
};

export declare const HOOK_EVENTS: readonly ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PostToolBatch", "Notification", "UserPromptSubmit", "UserPromptExpansion", "SessionStart", "SessionEnd", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "PreCompact", "PostCompact", "PermissionRequest", "PermissionDenied", "Setup", "TeammateIdle", "TaskCreated", "TaskCompleted", "Elicitation", "ElicitationResult", "ConfigChange", "WorktreeCreate", "WorktreeRemove", "InstructionsLoaded", "CwdChanged", "FileChanged"];

/**
 * Hook callback function for responding to events during execution.
 */
export declare type HookCallback = (input: HookInput, toolUseID: string | undefined, options: {
    signal: AbortSignal;
}) => Promise<HookJSONOutput>;

/**
 * Hook callback matcher containing hook callbacks and optional pattern matching.
 */
export declare interface HookCallbackMatcher {
    matcher?: string;
    hooks: HookCallback[];
    /** Timeout in seconds for all hooks in this matcher */
    timeout?: number;
}

export declare type HookEvent = 'PreToolUse' | 'PostToolUse' | 'PostToolUseFailure' | 'PostToolBatch' | 'Notification' | 'UserPromptSubmit' | 'UserPromptExpansion' | 'SessionStart' | 'SessionEnd' | 'Stop' | 'StopFailure' | 'SubagentStart' | 'SubagentStop' | 'PreCompact' | 'PostCompact' | 'PermissionRequest' | 'PermissionDenied' | 'Setup' | 'TeammateIdle' | 'TaskCreated' | 'TaskCompleted' | 'Elicitation' | 'ElicitationResult' | 'ConfigChange' | 'WorktreeCreate' | 'WorktreeRemove' | 'InstructionsLoaded' | 'CwdChanged' | 'FileChanged';

export declare type HookInput = PreToolUseHookInput | PostToolUseHookInput | PostToolUseFailureHookInput | PostToolBatchHookInput | PermissionDeniedHookInput | NotificationHookInput | UserPromptSubmitHookInput | UserPromptExpansionHookInput | SessionStartHookInput | SessionEndHookInput | StopHookInput | StopFailureHookInput | SubagentStartHookInput | SubagentStopHookInput | PreCompactHookInput | PostCompactHookInput | PermissionRequestHookInput | SetupHookInput | TeammateIdleHookInput | TaskCreatedHookInput | TaskCompletedHookInput | ElicitationHookInput | ElicitationResultHookInput | ConfigChangeHookInput | InstructionsLoadedHookInput | WorktreeCreateHookInput | WorktreeRemoveHookInput | CwdChangedHookInput | FileChangedHookInput;

export declare type HookJSONOutput = AsyncHookJSONOutput | SyncHookJSONOutput;

export declare type HookPermissionDecision = 'allow' | 'deny' | 'ask' | 'defer';

/**
 * Copy a local JSONL session into a SessionStore.
 *
 * Reads the session file (and optionally subagent transcripts) from disk
 * and calls `store.append()` for each. Entries are appended in batches of
 * `batchSize` to avoid backend payload limits; the store's `append()` is
 * called multiple times per session. Useful for migrating existing local
 * sessions to a remote backend.
 *
 * @alpha
 * @param sessionId - UUID of the local session to import
 * @param store - Destination SessionStore
 * @param options - `{ dir?, includeSubagents?, batchSize? }`
 */
export declare function importSessionToStore(_sessionId: string, _store: SessionStore, _options?: ImportSessionToStoreOptions): Promise<void>;

/**
 * Options for importing a local JSONL session into a SessionStore.
 * @alpha
 */
export declare type ImportSessionToStoreOptions = {
    /**
     * Project directory path (same semantics as `listSessions({ dir })`).
     * When omitted, all project directories are searched for the session file
     * and the destination projectKey is derived from the resolved cwd.
     */
    dir?: string;
    /**
     * If true, also import subagent transcripts. Default: true.
     */
    includeSubagents?: boolean;
    /**
     * Maximum entries per `store.append()` call. Entries are appended in
     * batches of this size to avoid backend payload limits; the store's
     * `append()` is called multiple times per session. Default: 500.
     */
    batchSize?: number;
};

/**
 * A user message typed on claude.ai, extracted from the bridge WS.
 * @alpha
 */
export declare type InboundPrompt = {
    content: string | unknown[];
    uuid?: string;
};

export declare type InferShape<T extends AnyZodRawShape> = {
    [K in keyof T]: T[K] extends {
        _output: infer O;
    } ? O : never;
} & {};

/**
 * In-memory SessionStore implementation for testing and development.
 * Stores entries in a Map keyed by a composite string.
 * Not suitable for production -- data is lost when the process exits.
 * @alpha
 */
export declare class InMemorySessionStore implements SessionStore {
    private store;
    private mtimes;
    private summaries;
    private lastMtime;
    private keyToString;
    append(key: SessionKey, entries: SessionStoreEntry[]): Promise<void>;
    load(key: SessionKey): Promise<SessionStoreEntry[] | null>;
    listSessions(projectKey: string): Promise<Array<{
        sessionId: string;
        mtime: number;
    }>>;
    listSessionSummaries(projectKey: string): Promise<SessionSummaryEntry[]>;
    delete(key: SessionKey): Promise<void>;
    listSubkeys(key: {
        projectKey: string;
        sessionId: string;
    }): Promise<string[]>;
    /** Test helper -- get all entries for a key */
    getEntries(key: SessionKey): SessionStoreEntry[];
    /** Test helper -- number of stored sessions (main transcripts only) */
    get size(): number;
    /** Test helper -- clear all stored data */
    clear(): void;
}

export declare type InstructionsLoadedHookInput = BaseHookInput & {
    hook_event_name: 'InstructionsLoaded';
    file_path: string;
    memory_type: 'User' | 'Project' | 'Local' | 'Managed';
    load_reason: 'session_start' | 'nested_traversal' | 'path_glob_match' | 'include' | 'compact';
    globs?: string[];
    trigger_file_path?: string;
    parent_file_path?: string;
};

export declare type JsonSchemaOutputFormat = {
    type: 'json_schema';
    schema: Record<string, unknown>;
};

/**
 * List sessions with metadata.
 *
 * When `dir` is provided, returns sessions for that project directory
 * and its git worktrees. When omitted, returns sessions across all
 * projects.
 *
 * Use `limit` and `offset` for pagination.
 *
 * @example
 * ```typescript
 * // List sessions for a specific project
 * const sessions = await listSessions({ dir: '/path/to/project' })
 *
 * // Paginate
 * const page1 = await listSessions({ limit: 50 })
 * const page2 = await listSessions({ limit: 50, offset: 50 })
 * ```
 */
export declare function listSessions(_options?: ListSessionsOptions): Promise<SDKSessionInfo[]>;

/**
 * Options for listing sessions.
 */
export declare type ListSessionsOptions = {
    /**
     * Directory to list sessions for. When provided, returns sessions for
     * this project directory (and optionally its git worktrees). When omitted,
     * returns sessions across all projects.
     */
    dir?: string;
    /** Maximum number of sessions to return. */
    limit?: number;
    /**
     * Number of sessions to skip from the start of the sorted result set.
     * Use with `limit` for pagination. Defaults to 0.
     */
    offset?: number;
    /**
     * When `dir` is provided and the directory is inside a git repository,
     * include sessions from all git worktree paths. Defaults to `true`.
     *
     * Only applies when reading from the local filesystem.
     */
    includeWorktrees?: boolean;
    /**
     * When provided, list sessions from this store instead of the local
     * filesystem. Requires `store.listSessions` to be defined.
     * @alpha
     */
    sessionStore?: SessionStore;
};

/**
 * Lists subagent IDs for a given session by scanning the subagents directory.
 *
 * Subagent transcripts are stored at
 * `~/.claude/projects/<dir>/<sessionId>/subagents/agent-<agentId>.jsonl`.
 *
 * @param sessionId - UUID of the session
 * @param options - Optional dir to narrow the project search
 * @returns Array of subagent ID strings, or empty array if none found
 */
export declare function listSubagents(_sessionId: string, _options?: ListSubagentsOptions): Promise<string[]>;

/**
 * Options for listing subagents.
 */
export declare type ListSubagentsOptions = {
    /** Project directory to find the session in. If omitted, searches all projects. */
    dir?: string;
    /**
     * When provided, list subagents from this store instead of the local
     * filesystem. Requires `store.listSubkeys` to be defined.
     * @alpha
     */
    sessionStore?: SessionStore;
};

export declare type McpClaudeAIProxyServerConfig = {
    type: 'claudeai-proxy';
    url: string;
    id: string;
    /**
     * Per-server tool-call timeout in milliseconds. Overrides the MCP_TOOL_TIMEOUT environment variable for this server. Hard wall-clock limit per call; progress notifications do not extend it. Floored at 1000ms.
     */
    timeout?: number;
};

export declare type McpHttpServerConfig = {
    type: 'http';
    url: string;
    headers?: Record<string, string>;
    tools?: McpServerToolPolicy[];
    /**
     * Per-server tool-call timeout in milliseconds. Overrides the MCP_TOOL_TIMEOUT environment variable for this server. Hard wall-clock limit per call; progress notifications do not extend it. Floored at 1000ms.
     */
    timeout?: number;
    /**
     * When true, all tools from this server are always included in the prompt and never deferred behind tool search. Equivalent to setting defer_loading: false on the API. Default: tools are deferred when tool search is enabled. As a side effect this also blocks startup until the server is connected (capped at the standard 5s connect timeout) even though MCP startup is otherwise non-blocking by default, since the tools must be present when the turn-1 prompt is built.
     */
    alwaysLoad?: boolean;

};

export declare type McpSdkServerConfig = {
    type: 'sdk';
    name: string;
};

/**
 * MCP SDK server config with an actual McpServer instance.
 * Not serializable - contains a live McpServer object.
 */
export declare type McpSdkServerConfigWithInstance = McpSdkServerConfig & {
    instance: McpServer;
};

/**
 * Union of all MCP server config types, including those with non-serializable instances.
 */
export declare type McpServerConfig = McpStdioServerConfig | McpSSEServerConfig | McpHttpServerConfig | McpSdkServerConfigWithInstance;

export declare type McpServerConfigForProcessTransport = McpStdioServerConfig | McpSSEServerConfig | McpHttpServerConfig | McpSdkServerConfig;

/**
 * Status information for an MCP server connection.
 */
export declare type McpServerStatus = {
    /**
     * Server name as configured
     */
    name: string;
    /**
     * Current connection status
     */
    status: 'connected' | 'failed' | 'needs-auth' | 'pending' | 'disabled';
    /**
     * Server information (available when connected)
     */
    serverInfo?: {
        name: string;
        version: string;
    };
    /**
     * Error message (available when status is 'failed')
     */
    error?: string;
    /**
     * Server configuration (includes URL for HTTP/SSE servers)
     */
    config?: McpServerStatusConfig;
    /**
     * Configuration scope (e.g., project, user, local, claudeai, managed)
     */
    scope?: string;
    /**
     * Tools provided by this server (available when connected)
     */
    tools?: {
        name: string;
        description?: string;
        annotations?: {
            readOnly?: boolean;
            destructive?: boolean;
            openWorld?: boolean;
        };
    }[];

};

export declare type McpServerStatusConfig = McpServerConfigForProcessTransport | McpClaudeAIProxyServerConfig;

/**
 * Per-tool permission policy carried on mcp_set_servers for remote servers.
 */
export declare type McpServerToolPolicy = {
    name: string;
    permission_policy: 'always_allow' | 'always_ask' | 'always_deny';
};

/**
 * Result of a setMcpServers operation.
 */
export declare type McpSetServersResult = {
    /**
     * Names of servers that were added
     */
    added: string[];
    /**
     * Names of servers that were removed
     */
    removed: string[];
    /**
     * Map of server names to error messages for servers that failed to connect
     */
    errors: Record<string, string>;
};

export declare type McpSSEServerConfig = {
    type: 'sse';
    url: string;
    headers?: Record<string, string>;
    tools?: McpServerToolPolicy[];
    /**
     * Per-server tool-call timeout in milliseconds. Overrides the MCP_TOOL_TIMEOUT environment variable for this server. Hard wall-clock limit per call; progress notifications do not extend it. Floored at 1000ms.
     */
    timeout?: number;
    /**
     * When true, all tools from this server are always included in the prompt and never deferred behind tool search. Equivalent to setting defer_loading: false on the API. Default: tools are deferred when tool search is enabled. As a side effect this also blocks startup until the server is connected (capped at the standard 5s connect timeout) even though MCP startup is otherwise non-blocking by default, since the tools must be present when the turn-1 prompt is built.
     */
    alwaysLoad?: boolean;

};

export declare type McpStdioServerConfig = {
    type?: 'stdio';
    command: string;
    args?: string[];
    env?: Record<string, string>;
    /**
     * Per-server tool-call timeout in milliseconds. Overrides the MCP_TOOL_TIMEOUT environment variable for this server. Hard wall-clock limit per call; progress notifications do not extend it. Floored at 1000ms.
     */
    timeout?: number;
    /**
     * When true, all tools from this server are always included in the prompt and never deferred behind tool search. Equivalent to setting defer_loading: false on the API. Default: tools are deferred when tool search is enabled. As a side effect this also blocks startup until the server is connected (capped at the standard 5s connect timeout) even though MCP startup is otherwise non-blocking by default, since the tools must be present when the turn-1 prompt is built.
     */
    alwaysLoad?: boolean;

};

/**
 * Information about an available model.
 */
export declare type ModelInfo = {
    /**
     * Model identifier to use in API calls
     */
    value: string;
    /**
     * Human-readable display name
     */
    displayName: string;
    /**
     * Description of the model's capabilities
     */
    description: string;
    /**
     * Whether this model supports effort levels
     */
    supportsEffort?: boolean;
    /**
     * Available effort levels for this model
     */
    supportedEffortLevels?: ('low' | 'medium' | 'high' | 'xhigh' | 'max')[];
    /**
     * Whether this model supports adaptive thinking (Claude decides when and how much to think)
     */
    supportsAdaptiveThinking?: boolean;
    /**
     * Whether this model supports fast mode
     */
    supportsFastMode?: boolean;
    /**
     * Whether this model supports auto mode
     */
    supportsAutoMode?: boolean;
};

export declare type ModelUsage = {
    inputTokens: number;
    outputTokens: number;
    cacheReadInputTokens: number;
    cacheCreationInputTokens: number;
    webSearchRequests: number;
    costUSD: number;
    contextWindow: number;
    maxOutputTokens: number;
};

export declare type NonNullableUsage = {
    [K in keyof BetaUsage]: NonNullable<BetaUsage[K]>;
};

export declare type NotificationHookInput = BaseHookInput & {
    hook_event_name: 'Notification';
    message: string;
    title?: string;
    notification_type: string;
};

export declare type NotificationHookSpecificOutput = {
    hookEventName: 'Notification';
    additionalContext?: string;
};

/**
 * Callback for handling MCP elicitation requests.
 * Called when an MCP server requests user input and no hook handles it.
 */
export declare type OnElicitation = (request: ElicitationRequest, options: {
    signal: AbortSignal;
}) => Promise<ElicitationResult>;

/**
 * Options for the query function.
 * Contains callbacks and other non-serializable fields.
 */
export declare type Options = {
    /**
     * Controller for cancelling the query. When aborted, the query will stop
     * and clean up resources.
     */
    abortController?: AbortController;
    /**
     * Additional directories Claude can access beyond the current working directory.
     * Paths should be absolute.
     */
    additionalDirectories?: string[];
    /**
     * Agent name for the main thread. When specified, the agent's system prompt,
     * tool restrictions, and model will be applied to the main conversation.
     * The agent must be defined either in the `agents` option or in settings.
     *
     * This is equivalent to the `--agent` CLI flag.
     *
     * @example
     * ```typescript
     * agent: 'code-reviewer',
     * agents: {
     *   'code-reviewer': {
     *     description: 'Reviews code for best practices',
     *     prompt: 'You are a code reviewer...'
     *   }
     * }
     * ```
     */
    agent?: string;
    /**
     * Programmatically define custom subagents that can be invoked via the Agent tool.
     * Keys are agent names, values are agent definitions.
     *
     * @example
     * ```typescript
     * agents: {
     *   'test-runner': {
     *     description: 'Runs tests and reports results',
     *     prompt: 'You are a test runner...',
     *     tools: ['Read', 'Grep', 'Glob', 'Bash']
     *   }
     * }
     * ```
     */
    agents?: Record<string, AgentDefinition>;
    /**
     * List of tool names that are auto-allowed without prompting for permission.
     * These tools will execute automatically without asking the user for approval.
     * To restrict which tools are available, use the `tools` option instead.
     *
     * Note: passing `'Skill'` here is deprecated — use the `skills` option instead.
     */
    allowedTools?: string[];
    /**
     * Custom permission handler for controlling tool usage. Called before each
     * tool execution to determine if it should be allowed, denied, or prompt the user.
     */
    canUseTool?: CanUseTool;
    /**
     * Continue the most recent conversation in the current directory instead of starting a new one.
     * Mutually exclusive with `resume`.
     */
    continue?: boolean;
    /**
     * Current working directory for the session. Defaults to `process.cwd()`.
     */
    cwd?: string;
    /**
     * List of tool names that are disallowed. These tools will be removed
     * from the model's context and cannot be used, even if they would
     * otherwise be allowed.
     */
    disallowedTools?: string[];
    /**
     * Map of tool-name aliases applied before name resolution. When the
     * model emits a `tool_use` whose name is a key in this map, the tool
     * execution path resolves the mapped name instead.
     *
     * This lets SDK consumers redirect built-in tool names to their own
     * tools. For example, a host that runs Bash inside a remote sandbox via
     * an MCP tool can set `{ Bash: 'mcp__workspace__bash' }` so that if the
     * model emits `Bash` (e.g. because a skill document instructed it to),
     * the call is routed to the MCP tool instead of failing as unknown.
     *
     * The redirect is single-hop: an alias that points at another aliased
     * name resolves that target literally rather than following a chain, so
     * cycles like `{A: 'B', B: 'A'}` cannot loop.
     *
     * `toolAliases` is complementary to `disallowedTools`, not a replacement
     * for it: the alias only affects name-based lookup of model-emitted
     * `tool_use` blocks, whereas `disallowedTools` also blocks harness-internal
     * direct calls that hold the tool object without a name lookup.
     *
     * @example
     * ```typescript
     * toolAliases: { Bash: 'mcp__workspace__bash' }
     * ```
     */
    toolAliases?: Record<string, string>;
    /**
     * Specify the base set of available built-in tools.
     * - `string[]` - Array of specific tool names (e.g., `['Bash', 'Read', 'Edit']`)
     * - `[]` (empty array) - Disable all built-in tools
     * - `{ type: 'preset'; preset: 'claude_code' }` - Use all default Claude Code tools
     */
    tools?: string[] | {
        type: 'preset';
        preset: 'claude_code';
    };
    /**
     * Environment variables to pass to the Claude Code process.
     * Defaults to `process.env`.
     *
     * SDK consumers can identify their app/library to include in the User-Agent header by setting:
     * - `CLAUDE_AGENT_SDK_CLIENT_APP` - Your app/library identifier (e.g., "my-app/1.0.0", "my-library/2.1")
     *
     * @example
     * ```typescript
     * env: { CLAUDE_AGENT_SDK_CLIENT_APP: 'my-app/1.0.0' }
     * ```
     */
    env?: {
        [envVar: string]: string | undefined;
    };
    /**
     * JavaScript runtime to use for executing Claude Code.
     * Auto-detected if not specified.
     */
    executable?: 'bun' | 'deno' | 'node';
    /**
     * Additional arguments to pass to the JavaScript runtime executable.
     */
    executableArgs?: string[];
    /**
     * Additional CLI arguments to pass to Claude Code.
     * Keys are argument names (without --), values are argument values.
     * Use `null` for boolean flags.
     */
    extraArgs?: Record<string, string | null>;
    /**
     * Fallback model to use if the primary model fails or is unavailable.
     */
    fallbackModel?: string;
    /**
     * Enable file checkpointing to track file changes during the session.
     * When enabled, files can be rewound to their state at any user message
     * using `Query.rewindFiles()`.
     *
     * File checkpointing creates backups of files before they are modified,
     * allowing you to restore them to previous states.
     */
    enableFileCheckpointing?: boolean;
    /**
     * Per-tool configuration for built-in tools.
     *
     * @example
     * ```typescript
     * toolConfig: {
     *   askUserQuestion: { previewFormat: 'html' }
     * }
     * ```
     */
    toolConfig?: ToolConfig;
    /**
     * When true, resumed sessions will fork to a new session ID rather than
     * continuing the previous session. Use with `resume`.
     */
    forkSession?: boolean;
    /**
     * Enable beta features. Currently supported:
     * - `'context-1m-2025-08-07'` - Enable 1M token context window (Sonnet 4/4.5 only)
     *
     * @see https://docs.anthropic.com/en/api/beta-headers
     */
    betas?: SdkBeta[];
    /**
     * Hook callbacks for responding to various events during execution.
     * Hooks can modify behavior, add context, or implement custom logic.
     *
     * @example
     * ```typescript
     * hooks: {
     *   PreToolUse: [{
     *     hooks: [async (input) => ({ continue: true })]
     *   }]
     * }
     * ```
     */
    hooks?: Partial<Record<HookEvent, HookCallbackMatcher[]>>;
    /**
     * Callback for handling MCP elicitation requests.
     * Called when an MCP server requests user input (form fields, URL auth, etc.)
     * and no hook handles the request first.
     *
     * If not provided, elicitation requests that aren't handled by hooks will
     * be declined automatically.
     *
     * @example
     * ```typescript
     * onElicitation: async (request) => {
     *   if (request.mode === 'url') {
     *     // Handle URL-based auth
     *     return { action: 'accept' }
     *   }
     *   // Provide form values
     *   return { action: 'accept', content: { name: 'Test' } }
     * }
     * ```
     */
    onElicitation?: OnElicitation;
    /**
     * When false, disables session persistence to disk. Sessions will not be
     * saved to ~/.claude/projects/ and cannot be resumed later. Useful for
     * ephemeral or automated workflows where session history is not needed.
     *
     * @default true
     */
    persistSession?: boolean;
    /**
     * Mirror session transcripts to an external store. When set, the subprocess
     * still writes to CLAUDE_CONFIG_DIR (set it to /tmp for ephemeral local copy)
     * AND emits entries to this adapter via dual-write.
     *
     * Cannot be used with persistSession: false -- local writes are required
     * for the mirror to function (the mirror hook fires after local write success).
     *
     * Default: undefined (no mirroring, today's behavior).
     * @alpha
     */
    sessionStore?: SessionStore;
    /**
     * Controls how aggressively transcript entries are flushed to
     * {@link Options.sessionStore}. Defaults to `'batched'`. Ignored when
     * `sessionStore` is not set.
     *
     * @alpha
     */
    sessionStoreFlush?: SessionStoreFlush;
    /**
     * Timeout for each `sessionStore.load()` / `sessionStore.listSubkeys()` call
     * during resume materialization. If the adapter doesn't settle within this
     * window the query fails with a clear error instead of hanging the iterator
     * forever (the deferred-spawn path otherwise has no upper bound).
     *
     * @default 60_000
     * @alpha
     */
    loadTimeoutMs?: number;
    /**
     * Include hook lifecycle events in the output stream.
     * When true, `hook_started`, `hook_progress`, and `hook_response` system
     * messages will be emitted for all hook event types (PreToolUse, PostToolUse,
     * Stop, etc.). SessionStart and Setup hook events are always emitted
     * regardless of this setting.
     *
     * @default false
     */
    includeHookEvents?: boolean;
    /**
     * Include partial/streaming message events in the output.
     * When true, `SDKPartialAssistantMessage` events will be emitted during streaming.
     */
    includePartialMessages?: boolean;
    /**
     * Forward subagent text and thinking blocks as assistant/user messages with
     * `parent_tool_use_id` set. By default, only tool_use/tool_result blocks from
     * subagents are emitted (enough for a heartbeat counter). When true, the full
     * subagent conversation is forwarded so consumers can render a nested transcript.
     */
    forwardSubagentText?: boolean;
    /**
     * Controls Claude's thinking/reasoning behavior.
     *
     * - `{ type: 'adaptive' }` — Claude decides when and how much to think (Opus 4.6+).
     *   This is the default for models that support it.
     * - `{ type: 'enabled', budgetTokens: number }` — Fixed thinking token budget (older models)
     * - `{ type: 'disabled' }` — No extended thinking
     *
     * When set, takes precedence over the deprecated `maxThinkingTokens`.
     *
     * @see https://docs.anthropic.com/en/docs/build-with-claude/adaptive-thinking
     */
    thinking?: ThinkingConfig;
    /**
     * Controls how much effort Claude puts into its response.
     * Works with adaptive thinking to guide thinking depth.
     *
     * - `'low'` — Minimal thinking, fastest responses
     * - `'medium'` — Moderate thinking
     * - `'high'` — Deep reasoning (default)
     * - `'xhigh'` — Deeper than high (Opus 4.7 only)
     * - `'max'` — Maximum effort (Opus 4.6/4.7, Sonnet 4.6)
     *
     * @see https://docs.anthropic.com/en/docs/build-with-claude/effort
     */
    effort?: EffortLevel;
    /**
     * Maximum number of tokens the model can use for its thinking/reasoning process.
     * Helps control cost and latency for complex tasks.
     *
     * @deprecated Use `thinking` instead. On Opus 4.6, this is treated as on/off
     * (0 = disabled, any other value = adaptive). For explicit control, use
     * `thinking: { type: 'adaptive' }` or `thinking: { type: 'enabled', budgetTokens: N }`.
     */
    maxThinkingTokens?: number;
    /**
     * Maximum number of conversation turns before the query stops.
     * A turn consists of a user message and assistant response.
     */
    maxTurns?: number;
    /**
     * Maximum budget in USD for the query. The query will stop if this
     * budget is exceeded, returning an `error_max_budget_usd` result.
     */
    maxBudgetUsd?: number;
    /**
     * API-side task budget in tokens. When set, the model is made aware of
     * its remaining token budget so it can pace tool use and wrap up before
     * the limit. Sent as `output_config.task_budget` with the
     * `task-budgets-2026-03-13` beta header.
     * @alpha
     */
    taskBudget?: {
        total: number;
    };
    /**
     * MCP (Model Context Protocol) server configurations.
     * Keys are server names, values are server configurations.
     *
     * @example
     * ```typescript
     * mcpServers: {
     *   'my-server': {
     *     command: 'node',
     *     args: ['./my-mcp-server.js']
     *   }
     * }
     * ```
     */
    mcpServers?: Record<string, McpServerConfig>;
    /**
     * Claude model to use. Defaults to the CLI default model.
     * Examples: 'claude-sonnet-4-6', 'claude-opus-4-7'
     */
    model?: string;
    /**
     * Output format configuration for structured responses.
     * When specified, the agent will return structured data matching the schema.
     *
     * @example
     * ```typescript
     * outputFormat: {
     *   type: 'json_schema',
     *   schema: { type: 'object', properties: { result: { type: 'string' } } }
     * }
     * ```
     */
    outputFormat?: OutputFormat;
    /**
     * Path to the Claude Code executable. Uses the built-in executable if not specified.
     */
    pathToClaudeCodeExecutable?: string;
    /**
     * Permission mode for the session.
     * - `'default'` - Standard permission behavior, prompts for dangerous operations
     * - `'acceptEdits'` - Auto-accept file edit operations
     * - `'bypassPermissions'` - Bypass all permission checks (requires `allowDangerouslySkipPermissions`)
     * - `'plan'` - Planning mode, no execution of tools
     * - `'dontAsk'` - Don't prompt for permissions, deny if not pre-approved
     */
    permissionMode?: PermissionMode;
    /**
     * Custom workflow instructions for plan mode. When `permissionMode` is
     * `'plan'`, this string replaces the default code-implementation workflow
     * body in the plan-mode system reminder. The CLI still wraps it with the
     * read-only enforcement preamble and the ExitPlanMode protocol footer.
     */
    planModeInstructions?: string;
    /**
     * Must be set to `true` when using `permissionMode: 'bypassPermissions'`.
     * This is a safety measure to ensure intentional bypassing of permissions.
     */
    allowDangerouslySkipPermissions?: boolean;
    /**
     * MCP tool name to use for permission prompts. When set, permission requests
     * will be routed through this MCP tool instead of the default handler.
     */
    permissionPromptToolName?: string;
    /**
     * Load plugins for this session. Plugins provide custom commands, agents,
     * skills, and hooks that extend Claude Code's capabilities.
     *
     * Currently only local plugins are supported via the 'local' type.
     *
     * @example
     * ```typescript
     * plugins: [
     *   { type: 'local', path: './my-plugin' },
     *   { type: 'local', path: '/absolute/path/to/plugin' }
     * ]
     * ```
     */
    plugins?: SdkPluginConfig[];





    /**
     * Enable prompt suggestions. When true, the agent emits a `prompt_suggestion`
     * message after each turn with a predicted next user prompt.
     *
     * Delivery semantics:
     * - At most one `prompt_suggestion` per turn; arrives after the `result` message.
     * - Consumers must keep iterating the stream after `result` to receive it.
     * - Suppressed on the first turn, after API errors, in plan mode, and by the
     *   `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` env var.
     * - Suggestions piggyback on the parent's prompt cache, making them nearly free.
     */
    promptSuggestions?: boolean;
    /**
     * Enable periodic AI-generated progress summaries for running subagents. When
     * true, the subagent's conversation is forked every ~30s to produce a short
     * present-tense description (e.g. "Analyzing authentication module"), emitted
     * on `task_progress` events via the `summary` field. The fork reuses the
     * subagent's model and prompt cache, so cost is typically minimal.
     *
     * Applies to both foreground and background subagents. Defaults to false.
     */
    agentProgressSummaries?: boolean;
    /**
     * Session ID to resume. Loads the conversation history from the specified session.
     */
    resume?: string;
    /**
     * Use a specific session ID for the conversation instead of an auto-generated one.
     * Must be a valid UUID. Cannot be used with `continue` or `resume` unless
     * `forkSession` is also set (to specify a custom ID for the forked session).
     */
    sessionId?: string;
    /**
     * When resuming, only resume messages up to and including the message with this UUID.
     * Use with `resume`. This allows you to resume from a specific point in the conversation.
     * The message ID should be from `SDKAssistantMessage.uuid`.
     */
    resumeSessionAt?: string;
    /**
     * Sandbox settings for command execution isolation.
     *
     * When enabled, commands are executed in a sandboxed environment that restricts
     * filesystem and network access. This provides an additional security layer.
     *
     * **Important:** Filesystem and network restrictions are configured via permission
     * rules, not via these sandbox settings:
     * - Filesystem access: Use `Read` and `Edit` permission rules
     * - Network access: Use `WebFetch` permission rules
     *
     * These sandbox settings control sandbox behavior (enabled, auto-allow, etc.),
     * while the actual access restrictions come from your permission configuration.
     *
     * **Dependency check:** When `enabled: true` is passed via this option,
     * `failIfUnavailable` defaults to `true` — if sandbox dependencies are missing
     * (e.g. `bubblewrap` on Linux) or the platform is unsupported, `query()` will
     * emit an error result and exit rather than silently running commands
     * unsandboxed. Set `failIfUnavailable: false` to allow graceful degradation.
     *
     * @example Enable sandboxing with auto-allow
     * ```typescript
     * sandbox: {
     *   enabled: true,
     *   autoAllowBashIfSandboxed: true
     * }
     * ```
     *
     * @example Configure network options (not restrictions)
     * ```typescript
     * sandbox: {
     *   enabled: true,
     *   network: {
     *     allowLocalBinding: true,
     *     allowUnixSockets: ['/var/run/docker.sock']
     *   }
     * }
     * ```
     *
     * @see https://docs.anthropic.com/en/docs/claude-code/settings#sandbox-settings
     */
    sandbox?: SandboxSettings;
    /**
     * Additional settings to apply. Accepts either a path to a settings JSON file
     * or a settings object. These are loaded into the "flag settings" layer,
     * which has the highest priority among user-controlled settings.
     *
     * Equivalent to the `--settings` CLI flag.
     *
     * @example Inline settings object
     * ```typescript
     * settings: { model: 'claude-sonnet-4-6', permissions: { allow: ['Bash(*)'] } }
     * ```
     *
     * @example Path to settings file
     * ```typescript
     * settings: '/path/to/settings.json'
     * ```
     */
    settings?: string | Settings;
    /**
     * Policy-tier settings supplied by the spawning parent process. When an
     * IT-controlled managed-settings tier (server / MDM / managed-settings.json)
     * exists on the user's machine, these are **dropped by default** — they only
     * layer in if that admin opts in via `parentSettingsBehavior: 'merge'` in
     * their managed settings. Even when opted in, the value is filtered
     * restrictive-only: permissive arrays (`permissions.allow`,
     * `additionalDirectories`, `allowedMcpServers`, …) that would widen an
     * existing admin lock are silently dropped. With no admin tier present,
     * these apply as the sole policy tier (still filtered restrictive-only —
     * non-allowlisted keys are dropped regardless).
     *
     * Intended for embedding applications (e.g. desktop apps) that derive
     * lockdown settings from their own enterprise configuration and need to
     * enforce them on the spawned subprocess without writing root-owned files.
     *
     * @example
     * ```typescript
     * managedSettings: {
     *   sandbox: { network: { allowManagedDomainsOnly: true } }
     * }
     * ```
     */
    managedSettings?: Settings;
    /**
     * Control which filesystem settings to load.
     * - `'user'` - Global user settings (`~/.claude/settings.json`)
     * - `'project'` - Project settings (`.claude/settings.json`)
     * - `'local'` - Local settings (`.claude/settings.local.json`)
     *
     * When omitted, all sources are loaded (matches CLI defaults).
     * Pass `[]` to disable filesystem settings (SDK isolation mode).
     * Must include `'project'` to load CLAUDE.md files.
     */
    settingSources?: SettingSource[];
    /**
     * Skills to enable for the main session. This is the single place to turn
     * skills on; you do not need to add `'Skill'` to `allowedTools` yourself
     * when using this option.
     *
     * - omitted (default): no SDK auto-configuration. The CLI's own defaults
     *   still apply, so this is **not** "skills off."
     * - `'all'`: enable every discovered skill.
     * - `string[]`: enable only the listed skills. Names match the SKILL.md
     *   `name` / directory name, or `plugin:skill` for plugin-qualified skills.
     *
     * This is a context filter, not a sandbox: unlisted skills are hidden from
     * the model's listing and rejected by the Skill tool, but their files
     * remain on disk and are reachable via Read/Bash. Do not store secrets in
     * skill files.
     *
     * @example
     * ```typescript
     * skills: 'all'
     * skills: ['pdf', 'docx']
     * ```
     */
    skills?: string[] | 'all';
    /**
     * Enable debug mode for the Claude Code process.
     * When true, enables verbose debug logging (equivalent to `--debug` CLI flag).
     * Debug logs are written to a file (see `debugFile` option) or to stderr.
     *
     * You can also capture debug output via the `stderr` callback.
     */
    debug?: boolean;
    /**
     * Write debug logs to a specific file path.
     * Implicitly enables debug mode. Equivalent to `--debug-file <path>` CLI flag.
     */
    debugFile?: string;
    /**
     * Callback for stderr output from the Claude Code process.
     * Useful for debugging and logging.
     */
    stderr?: (data: string) => void;
    /**
     * Enforce strict validation of MCP server configurations.
     * When true, invalid configurations will cause errors instead of warnings.
     */
    strictMcpConfig?: boolean;
    /**
     * System prompt configuration.
     * - `string` - Use a custom system prompt
     * - `string[]` - Use a custom system prompt as an array of blocks; include
     *   `SYSTEM_PROMPT_DYNAMIC_BOUNDARY` as a standalone element to mark the
     *   split between the static (globally-cacheable) prefix and the dynamic
     *   (session-specific) suffix. Blocks before the marker are eligible for
     *   cross-session prompt caching; blocks after it are not.
     * - `{ type: 'preset', preset: 'claude_code' }` - Use Claude Code's default system prompt
     * - `{ type: 'preset', preset: 'claude_code', append: '...' }` - Use default prompt with appended instructions
     * - `{ type: 'preset', preset: 'claude_code', excludeDynamicSections: true }` -
     *   Strip per-user dynamic sections (working directory, auto-memory, git
     *   status) from the system prompt so it stays static and cacheable across
     *   users. The stripped content is re-injected as the first user message so
     *   the model still has access to it.
     *
     *   Use this when many users in your fleet share the same system prompt and
     *   you want the prompt-caching prefix to hit cross-user. Tradeoffs:
     *   - The working-directory, memory-path, and git-status context is
     *     marginally less authoritative for steering the model (it appears in
     *     a user message instead of the system prompt).
     *   - The first user message becomes slightly larger.
     *   - Has no effect when `systemPrompt` is a string (custom prompt).
     *
     * @example Custom prompt
     * ```typescript
     * systemPrompt: 'You are a helpful coding assistant.'
     * ```
     *
     * @example Custom prompt with cache boundary
     * ```typescript
     * import { SYSTEM_PROMPT_DYNAMIC_BOUNDARY } from '@anthropic-ai/claude-code'
     * systemPrompt: [
     *   staticInstructions,
     *   SYSTEM_PROMPT_DYNAMIC_BOUNDARY,
     *   sessionContext,
     * ]
     * ```
     *
     * @example Default with additions
     * ```typescript
     * systemPrompt: {
     *   type: 'preset',
     *   preset: 'claude_code',
     *   append: 'Always explain your reasoning.'
     * }
     * ```
     *
     * @example Cacheable prompt for multi-user fleets
     * ```typescript
     * systemPrompt: {
     *   type: 'preset',
     *   preset: 'claude_code',
     *   excludeDynamicSections: true,
     * }
     * ```
     */
    systemPrompt?: string | string[] | {
        type: 'preset';
        preset: 'claude_code';
        append?: string;
        excludeDynamicSections?: boolean;
    };
    /**
     * Custom title for a new session. When provided, the session uses this title
     * instead of auto-generating one from the first user message.
     *
     * When resuming via `resume` or `continue`, the resumed session's persisted
     * title takes precedence — use `renameSession()` to retitle an existing
     * session.
     */
    title?: string;


    /**
     * Custom function to spawn the Claude Code process.
     * Use this to run Claude Code in VMs, containers, or remote environments.
     *
     * When provided, this function is called instead of the default local spawn.
     * The default behavior checks if the executable exists before spawning.
     *
     * @example
     * ```typescript
     * spawnClaudeCodeProcess: (options) => {
     *   // Custom spawn logic for VM execution
     *   // options contains: command, args, cwd, env, signal
     *   // `signal` is forwarded — it aborts only AFTER the SDK's
     *   // stdin-EOF + ~2 s grace window, so passing it to spawn()/your
     *   // VM API is safe (force-kill fires after the graceful chance).
     *   return myVMProcess; // Must satisfy SpawnedProcess interface
     * }
     * ```
     */
    spawnClaudeCodeProcess?: (options: SpawnOptions) => SpawnedProcess;
};

export declare type OutputFormat = JsonSchemaOutputFormat;

export declare type OutputFormatType = 'json_schema';

export declare type PermissionBehavior = 'allow' | 'deny' | 'ask';

/**
 * Classification of this permission decision for telemetry. SDK hosts that prompt users (desktop apps, IDEs) should set this to reflect what actually happened: user_temporary for allow-once, user_permanent for always-allow (both the click and later cache hits), user_reject for deny. If unset, the CLI infers conservatively (temporary for allow, reject for deny). The vocabulary matches tool_decision OTel events (monitoring-usage docs).
 */
export declare type PermissionDecisionClassification = 'user_temporary' | 'user_permanent' | 'user_reject';

export declare type PermissionDeniedHookInput = BaseHookInput & {
    hook_event_name: 'PermissionDenied';
    tool_name: string;
    tool_input: unknown;
    tool_use_id: string;
    reason: string;
};

export declare type PermissionDeniedHookSpecificOutput = {
    hookEventName: 'PermissionDenied';
    retry?: boolean;
};

/**
 * Permission mode for controlling how tool executions are handled. 'default' - Standard behavior, prompts for dangerous operations. 'acceptEdits' - Auto-accept file edit operations. 'bypassPermissions' - Bypass all permission checks (requires allowDangerouslySkipPermissions). 'plan' - Planning mode, no actual tool execution. 'dontAsk' - Don't prompt for permissions, deny if not pre-approved. 'auto' - Use a model classifier to approve/deny permission prompts.
 */
export declare type PermissionMode = 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan' | 'dontAsk' | 'auto';

export declare type PermissionRequestHookInput = BaseHookInput & {
    hook_event_name: 'PermissionRequest';
    tool_name: string;
    tool_input: unknown;
    permission_suggestions?: PermissionUpdate[];
};

export declare type PermissionRequestHookSpecificOutput = {
    hookEventName: 'PermissionRequest';
    decision: {
        behavior: 'allow';
        updatedInput?: Record<string, unknown>;
        updatedPermissions?: PermissionUpdate[];
    } | {
        behavior: 'deny';
        message?: string;
        interrupt?: boolean;
    };
};

export declare type PermissionResult = {
    behavior: 'allow';
    updatedInput?: Record<string, unknown>;
    updatedPermissions?: PermissionUpdate[];
    toolUseID?: string;
    decisionClassification?: PermissionDecisionClassification;
} | {
    behavior: 'deny';
    message: string;
    interrupt?: boolean;
    toolUseID?: string;
    decisionClassification?: PermissionDecisionClassification;
};

export declare type PermissionRuleValue = {
    toolName: string;
    ruleContent?: string;
};

export declare type PermissionUpdate = {
    type: 'addRules';
    rules: PermissionRuleValue[];
    behavior: PermissionBehavior;
    destination: PermissionUpdateDestination;
} | {
    type: 'replaceRules';
    rules: PermissionRuleValue[];
    behavior: PermissionBehavior;
    destination: PermissionUpdateDestination;
} | {
    type: 'removeRules';
    rules: PermissionRuleValue[];
    behavior: PermissionBehavior;
    destination: PermissionUpdateDestination;
} | {
    type: 'setMode';
    mode: PermissionMode;
    destination: PermissionUpdateDestination;
} | {
    type: 'addDirectories';
    directories: string[];
    destination: PermissionUpdateDestination;
} | {
    type: 'removeDirectories';
    directories: string[];
    destination: PermissionUpdateDestination;
};

export declare type PermissionUpdateDestination = 'userSettings' | 'projectSettings' | 'localSettings' | 'session' | 'cliArg';

/**
 * Which policy sub-source supplied a `'managed'` value.
 * @alpha
 */
export declare type PolicySettingsOrigin = 'helper' | 'remote' | 'plist' | 'hklm' | 'file' | 'parent' | 'hkcu';

export declare type PostCompactHookInput = BaseHookInput & {
    hook_event_name: 'PostCompact';
    trigger: 'manual' | 'auto';
    /**
     * The conversation summary produced by compaction
     */
    compact_summary: string;
};

/**
 * Hook input for the PostToolBatch event. Fired once after every tool call in a batch has resolved, before the next model request. PostToolUse fires per-tool and may run concurrently for parallel tool calls; PostToolBatch fires exactly once with the full batch.
 */
export declare type PostToolBatchHookInput = BaseHookInput & {
    hook_event_name: 'PostToolBatch';
    tool_calls: PostToolBatchToolCall[];
};

export declare type PostToolBatchHookSpecificOutput = {
    hookEventName: 'PostToolBatch';
    additionalContext?: string;
};

export declare type PostToolBatchToolCall = {
    tool_name: string;
    tool_input: unknown;
    tool_use_id: string;
    tool_response?: unknown;
};

export declare type PostToolUseFailureHookInput = BaseHookInput & {
    hook_event_name: 'PostToolUseFailure';
    tool_name: string;
    tool_input: unknown;
    tool_use_id: string;
    error: string;
    is_interrupt?: boolean;
    /**
     * Tool execution time in milliseconds. Excludes permission-prompt and hook time.
     */
    duration_ms?: number;
};

export declare type PostToolUseFailureHookSpecificOutput = {
    hookEventName: 'PostToolUseFailure';
    additionalContext?: string;
};

export declare type PostToolUseHookInput = BaseHookInput & {
    hook_event_name: 'PostToolUse';
    tool_name: string;
    tool_input: unknown;
    tool_response: unknown;
    tool_use_id: string;
    /**
     * Tool execution time in milliseconds. Excludes permission-prompt and hook time.
     */
    duration_ms?: number;
};

export declare type PostToolUseHookSpecificOutput = {
    hookEventName: 'PostToolUse';
    additionalContext?: string;
    /**
     * Replaces the tool output before it is sent to the model
     */
    updatedToolOutput?: unknown;
    /**
     * Replaces the output for MCP tools only. Prefer updatedToolOutput, which works for all tools
     */
    updatedMCPToolOutput?: unknown;
};

export declare type PreCompactHookInput = BaseHookInput & {
    hook_event_name: 'PreCompact';
    trigger: 'manual' | 'auto';
    custom_instructions: string | null;
};

export declare type PreToolUseHookInput = BaseHookInput & {
    hook_event_name: 'PreToolUse';
    tool_name: string;
    tool_input: unknown;
    tool_use_id: string;
};

export declare type PreToolUseHookSpecificOutput = {
    hookEventName: 'PreToolUse';
    permissionDecision?: HookPermissionDecision;
    permissionDecisionReason?: string;
    updatedInput?: Record<string, unknown>;
    additionalContext?: string;
};

/**
 * Per-key provenance entry.
 * @alpha
 */
export declare type ProvenanceEntry = {
    source: ResolvedSettingSource;
    /** Absolute path to the settings file, for filesystem-backed sources. */
    path?: string;
    /** Which policy sub-source supplied the value, when `source === 'managed'`. */
    policyOrigin?: PolicySettingsOrigin;
};

/**
 * Query interface with methods for controlling query execution.
 * Extends AsyncGenerator and has methods, so not serializable.
 */
export declare interface Query extends AsyncGenerator<SDKMessage, void> {
    /**
     * Control Requests
     * The following methods are control requests, and are only supported when
     * streaming input/output is used.
     */
    /**
     * Interrupt the current query execution. The query will stop processing
     * and return control to the caller.
     */
    interrupt(): Promise<void>;
    /**
     * Change the permission mode for the current session.
     * Only available in streaming input mode.
     *
     * @param mode - The new permission mode to set
     */
    setPermissionMode(mode: PermissionMode): Promise<void>;
    /**
     * Change the model used for subsequent responses.
     * Only available in streaming input mode.
     *
     * @param model - The model identifier to use, or undefined to use the default
     */
    setModel(model?: string): Promise<void>;
    /**
     * Set the maximum number of thinking tokens the model is allowed to use
     * when generating its response. This can be used to limit the amount of
     * tokens the model uses for its response, which can help control cost and
     * latency.
     *
     * Use `null` to clear any previously set limit and allow the model to
     * use the default maximum thinking tokens.
     *
     * @deprecated Use the `thinking` option in `query()` instead. On Opus 4.6,
     * this is treated as on/off (0 = disabled, any other value = adaptive).
     * For explicit control, use `thinking: { type: 'adaptive' }` or
     * `thinking: { type: 'enabled', budgetTokens: N }`.
     *
     * @param maxThinkingTokens - Maximum tokens for thinking, or null to clear the limit
     */
    setMaxThinkingTokens(maxThinkingTokens: number | null): Promise<void>;
    /**
     * Merge the provided settings into the flag settings layer, dynamically
     * updating the active configuration. Equivalent to the inline `settings`
     * option of `query()`, but applies mid-session. Flag settings sit above
     * user/project/local settings and below managed policy settings in the
     * precedence order.
     *
     * Successive calls shallow-merge top-level keys — a second call with
     * `{permissions: {...}}` replaces the entire `permissions` object from a
     * prior call. Pass `null` for a key to clear it from the flag layer and
     * fall back to lower-precedence sources (`undefined` is dropped by JSON
     * serialization and has no effect).
     *
     * Only available in streaming input mode.
     *
     * @param settings - A partial settings object to merge into the flag settings.
     * Each top-level key also accepts `null` to clear it from the flag layer.
     */
    applyFlagSettings(settings: {
        [K in keyof Settings]?: Settings[K] | null;
    }): Promise<void>;
    /**
     * Get the full initialization result, including supported commands, models,
     * account info, and output style configuration.
     *
     * @returns The complete initialization response
     */
    initializationResult(): Promise<SDKControlInitializeResponse>;
    /**
     * Get the list of available skills for the current session.
     *
     * @returns Array of available skills with their names and descriptions
     */
    supportedCommands(): Promise<SlashCommand[]>;
    /**
     * Get the list of available models.
     *
     * @returns Array of model information including display names and descriptions
     */
    supportedModels(): Promise<ModelInfo[]>;
    /**
     * Get the list of available subagents for the current session.
     *
     * @returns Array of available agents with their names, descriptions, and configuration
     */
    supportedAgents(): Promise<AgentInfo[]>;
    /**
     * Get the current status of all configured MCP servers.
     *
     * @returns Array of MCP server statuses (connected, failed, needs-auth, pending)
     */
    mcpServerStatus(): Promise<McpServerStatus[]>;
    /**
     * Get a breakdown of current context window usage by category
     * (system prompt, tools, messages, MCP tools, memory files, etc.).
     *
     * @returns Context usage breakdown including token counts per category and total usage
     */
    getContextUsage(): Promise<SDKControlGetContextUsageResponse>;
    /**
     * Read a file from the session's filesystem for the remote sidebar
     * viewer. Path is resolved against cwd and gated by the same
     * read-permission rules as the Read tool. Returns null on permission
     * denial, missing file, or transport error.
     *
     * @param path - File path (relative to cwd or absolute)
     * @param options - Optional maxBytes cap (default 1MB) and encoding
     *   (default utf-8; pass 'base64' for binary files like images)
     */
    readFile(path: string, options?: {
        maxBytes?: number;
        encoding?: 'utf-8' | 'base64';
    }): Promise<SDKControlReadFileResponse | null>;
    /**
     * Reload plugins from disk and return the refreshed commands, agents,
     * plugins, and MCP server status.
     *
     * @returns The refreshed session components after plugin reload
     */
    reloadPlugins(): Promise<SDKControlReloadPluginsResponse>;
    /**
     * Get information about the authenticated account.
     *
     * @returns Account information including email, organization, and subscription type
     */
    accountInfo(): Promise<AccountInfo>;
    /**
     * Rewind tracked files to their state at a specific user message.
     * Requires file checkpointing to be enabled via the `enableFileCheckpointing` option.
     *
     * @param userMessageId - UUID of the user message to rewind to
     * @param options - Options object with optional `dryRun` boolean to preview changes without modifying files
     * @returns Object with canRewind boolean, optional error message, and file change statistics
     */
    rewindFiles(userMessageId: string, options?: {
        dryRun?: boolean;
    }): Promise<RewindFilesResult>;
    /**
     * Seed the CLI's readFileState cache with a path+mtime entry. Use when
     * the client observed a Read that has since been removed from context
     * (e.g. by snip), so a subsequent Edit won't fail "file not read yet".
     * If the file changed on disk since the given mtime, the seed is skipped
     * and Edit will correctly require a fresh Read.
     *
     * @param path - Path to the file that was previously Read
     * @param mtime - File mtime (floored ms) at the time of the observed Read
     */
    seedReadState(path: string, mtime: number): Promise<void>;






    /**
     * Reconnect an MCP server by name.
     * Throws on failure.
     *
     * @param serverName - The name of the MCP server to reconnect
     */
    reconnectMcpServer(serverName: string): Promise<void>;
    /**
     * Enable or disable an MCP server by name.
     * Throws on failure.
     *
     * @param serverName - The name of the MCP server to toggle
     * @param enabled - Whether the server should be enabled
     */
    toggleMcpServer(serverName: string, enabled: boolean): Promise<void>;






    /**
     * Dynamically set the MCP servers for this session.
     * This replaces the current set of dynamically-added MCP servers with the provided set.
     * Servers that are removed will be disconnected, and new servers will be connected.
     *
     * Supports both process-based servers (stdio, sse, http) and SDK servers (in-process).
     * SDK servers are handled locally in the SDK process, while process-based servers
     * are managed by the CLI subprocess.
     *
     * Note: This only affects servers added dynamically via this method or the SDK.
     * Servers configured via settings files are not affected.
     *
     * @param servers - Record of server name to configuration. Pass an empty object to remove all dynamic servers.
     * @returns Information about which servers were added, removed, and any connection errors
     */
    setMcpServers(servers: Record<string, McpServerConfig>): Promise<McpSetServersResult>;
    /**
     * Stream input messages to the query.
     * Used internally for multi-turn conversations.
     *
     * @param stream - Async iterable of user messages to send
     */
    streamInput(stream: AsyncIterable<SDKUserMessage>): Promise<void>;
    /**
     * Stop a running task. A task_notification with status 'stopped' will be emitted.
     * @param taskId - The task ID from task_notification events
     */
    stopTask(taskId: string): Promise<void>;
    /**
     * Background in-flight foreground tasks (Bash commands and subagents).
     * With `toolUseId`, targets the single task started by that tool_use
     * block; without it, backgrounds all foreground tasks — equivalent to
     * pressing Ctrl+B in the terminal. Each blocking tool call returns
     * immediately with a "running in the background" tool_result and the
     * turn continues; the task keeps running and emits a task_notification
     * when it settles.
     * @param toolUseId - Optional tool_use block id to target a single task
     * @returns true when at least one task was backgrounded; false only
     *   when `toolUseId` was given and it matched no foreground task
     */
    backgroundTasks(toolUseId?: string): Promise<boolean>;
    /**
     * Close the query and terminate the underlying process.
     * This forcefully ends the query, cleaning up all resources including
     * pending requests, MCP transports, and the CLI subprocess.
     *
     * Use this when you need to abort a query that is still running.
     * After calling close(), no further messages will be received.
     */
    close(): void;
}

export declare function query(_params: {
    prompt: string | AsyncIterable<SDKUserMessage>;
    options?: Options;
}): Query;

/**
 * Rename a session. Appends a custom-title entry to the session's JSONL file.
 * @param sessionId - UUID of the session
 * @param title - New title
 * @param options - `{ dir?: string }` project path; omit to search all projects
 */
export declare function renameSession(_sessionId: string, _title: string, _options?: SessionMutationOptions): Promise<void>;

/**
 * Result of {@link resolveSettings}.
 * @alpha
 */
export declare type ResolvedSettings = {
    /** Merged settings after applying all enabled sources in precedence order. */
    effective: Settings;
    /** For each top-level key in `effective`, which source supplied the value. */
    provenance: Partial<Record<keyof Settings, ProvenanceEntry>>;
    /**
     * Per-source raw settings, low→high precedence. Use this when per-top-level
     * provenance is too coarse (e.g. checking which tier set a nested key).
     */
    sources: Array<{
        source: ResolvedSettingSource;
        settings: Settings;
        path?: string;
        policyOrigin?: PolicySettingsOrigin;
    }>;
};

/**
 * Source that contributed an effective setting value. Filesystem sources use
 * the same names as {@link SettingSource}; `'managed'` is the policy tier
 * (managed-settings.json / `managedSettings` option); `'flag'` is the
 * `--settings` CLI flag tier.
 * @alpha
 */
export declare type ResolvedSettingSource = SettingSource | 'managed' | 'flag';

/**
 * Resolve the effective Claude Code settings for the given options using the
 * same merge engine as the CLI, without spawning the Claude CLI. Useful for
 * inspecting what configuration a `query()` call would see.
 *
 * @remarks
 * This reports the **raw settings cascade**, not a security decision. Two
 * caveats:
 *
 * - **The policy tier matches CLI startup** (managed-settings.json,
 *   remote-cached managed settings, MDM via macOS plist / Windows
 *   HKLM/HKCU, and `managedSettings`) **except** the admin-configured
 *   `policyHelper` subprocess is not executed. MDM resolution may invoke
 *   `plutil` (macOS, when an MDM plist exists) or `reg.exe` (Windows/WSL)
 *   on the first call per process. If your deployment relies on
 *   policyHelper to inject managed settings, results will differ.
 * - **`permissions.defaultMode` is reported as-is across all tiers**
 *   including project. The CLI applies a separate trust filter before
 *   honoring escalating modes (`bypassPermissions`, `auto`, `acceptEdits`)
 *   from repo-committed files; pass the result through
 *   {@link filterEscalatingDefaultMode} before acting on `defaultMode`.
 *
 * @alpha
 */
export declare function resolveSettings(_opts?: ResolveSettingsOptions): Promise<ResolvedSettings>;

/**
 * Options for {@link resolveSettings}.
 * @alpha
 */
export declare type ResolveSettingsOptions = {
    /**
     * Directory to resolve project/local settings relative to. Defaults to the
     * current process's working directory.
     */
    cwd?: string;
    /**
     * Which filesystem settings sources to load. When omitted, all sources are
     * loaded (matches CLI defaults). Pass `[]` to skip user/project/local
     * sources — the managed-settings policy tier is still read from disk.
     */
    settingSources?: SettingSource[];
    /**
     * Restrictive policy-tier settings — equivalent to `Options.managedSettings`
     * on `query()`. Feeds the lowest-precedence policy sub-source and is
     * filtered through a restrictive-key allowlist (`allowManaged*Only` locks,
     * `permissions.deny`/`ask`, sandbox restrictions); non-restrictive keys
     * such as `model`, `env`, `cleanupPeriodDays` are silently dropped.
     */
    managedSettings?: Settings;
    /**
     * Server-managed settings payload (the result of fetching
     * `/api/claude_code/settings`). Feeds the `'remote'` policy sub-source —
     * same trust level as the on-disk cache it replaces, so non-restrictive
     * keys flow through unfiltered. Use this when the embedding host has a
     * fresher result than the CLI's `~/.claude/remote-settings.json` cache.
     */
    serverManagedSettings?: Settings;
};

/**
 * Result of a rewindFiles operation.
 */
export declare type RewindFilesResult = {
    canRewind: boolean;
    error?: string;
    filesChanged?: string[];
    insertions?: number;
    deletions?: number;
};

export declare type SandboxFilesystemConfig = NonNullable<z.infer<ReturnType<typeof SandboxFilesystemConfigSchema>>>;

/**
 * Filesystem configuration schema for sandbox.
 */
declare const SandboxFilesystemConfigSchema: () => z.ZodOptional<z.ZodObject<{
    allowWrite: z.ZodOptional<z.ZodArray<z.ZodString>>;
    denyWrite: z.ZodOptional<z.ZodArray<z.ZodString>>;
    denyRead: z.ZodOptional<z.ZodArray<z.ZodString>>;
    allowRead: z.ZodOptional<z.ZodArray<z.ZodString>>;
    allowManagedReadPathsOnly: z.ZodOptional<z.ZodBoolean>;
}, z.core.$strip>>;

export declare type SandboxIgnoreViolations = NonNullable<SandboxSettings['ignoreViolations']>;

export declare type SandboxNetworkConfig = NonNullable<z.infer<ReturnType<typeof SandboxNetworkConfigSchema>>>;

/**
 * Network configuration schema for sandbox.
 */
declare const SandboxNetworkConfigSchema: () => z.ZodOptional<z.ZodObject<{
    allowedDomains: z.ZodOptional<z.ZodArray<z.ZodString>>;
    deniedDomains: z.ZodOptional<z.ZodArray<z.ZodString>>;
    allowManagedDomainsOnly: z.ZodOptional<z.ZodBoolean>;
    allowUnixSockets: z.ZodOptional<z.ZodArray<z.ZodString>>;
    allowAllUnixSockets: z.ZodOptional<z.ZodBoolean>;
    allowLocalBinding: z.ZodOptional<z.ZodBoolean>;
    allowMachLookup: z.ZodOptional<z.ZodArray<z.ZodString>>;
    httpProxyPort: z.ZodOptional<z.ZodNumber>;
    socksProxyPort: z.ZodOptional<z.ZodNumber>;
    tlsTerminate: z.ZodOptional<z.ZodObject<{
        caCertPath: z.ZodOptional<z.ZodString>;
        caKeyPath: z.ZodOptional<z.ZodString>;
    }, z.core.$strip>>;
}, z.core.$strip>>;

export declare type SandboxSettings = z.infer<ReturnType<typeof SandboxSettingsSchema>>;

/**
 * Sandbox settings schema.
 */
declare const SandboxSettingsSchema: () => z.ZodObject<{
    enabled: z.ZodOptional<z.ZodBoolean>;
    failIfUnavailable: z.ZodOptional<z.ZodBoolean>;
    autoAllowBashIfSandboxed: z.ZodOptional<z.ZodBoolean>;
    allowUnsandboxedCommands: z.ZodOptional<z.ZodBoolean>;
    network: z.ZodOptional<z.ZodObject<{
        allowedDomains: z.ZodOptional<z.ZodArray<z.ZodString>>;
        deniedDomains: z.ZodOptional<z.ZodArray<z.ZodString>>;
        allowManagedDomainsOnly: z.ZodOptional<z.ZodBoolean>;
        allowUnixSockets: z.ZodOptional<z.ZodArray<z.ZodString>>;
        allowAllUnixSockets: z.ZodOptional<z.ZodBoolean>;
        allowLocalBinding: z.ZodOptional<z.ZodBoolean>;
        allowMachLookup: z.ZodOptional<z.ZodArray<z.ZodString>>;
        httpProxyPort: z.ZodOptional<z.ZodNumber>;
        socksProxyPort: z.ZodOptional<z.ZodNumber>;
        tlsTerminate: z.ZodOptional<z.ZodObject<{
            caCertPath: z.ZodOptional<z.ZodString>;
            caKeyPath: z.ZodOptional<z.ZodString>;
        }, z.core.$strip>>;
    }, z.core.$strip>>;
    filesystem: z.ZodOptional<z.ZodObject<{
        allowWrite: z.ZodOptional<z.ZodArray<z.ZodString>>;
        denyWrite: z.ZodOptional<z.ZodArray<z.ZodString>>;
        denyRead: z.ZodOptional<z.ZodArray<z.ZodString>>;
        allowRead: z.ZodOptional<z.ZodArray<z.ZodString>>;
        allowManagedReadPathsOnly: z.ZodOptional<z.ZodBoolean>;
    }, z.core.$strip>>;
    ignoreViolations: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodArray<z.ZodString>>>;
    enableWeakerNestedSandbox: z.ZodOptional<z.ZodBoolean>;
    enableWeakerNetworkIsolation: z.ZodOptional<z.ZodBoolean>;
    excludedCommands: z.ZodOptional<z.ZodArray<z.ZodString>>;
    ripgrep: z.ZodOptional<z.ZodObject<{
        command: z.ZodString;
        args: z.ZodOptional<z.ZodArray<z.ZodString>>;
    }, z.core.$strip>>;
    bwrapPath: z.ZodCatch<z.ZodOptional<z.ZodPipe<z.ZodTransform<string, unknown>, z.ZodString>>>;
    socatPath: z.ZodCatch<z.ZodOptional<z.ZodPipe<z.ZodTransform<string, unknown>, z.ZodString>>>;
}, z.core.$loose>;

/**
 * Emitted when an API request fails with a retryable error and will be retried after a delay. error_status is null for connection errors (e.g. timeouts) that had no HTTP response.
 */
export declare type SDKAPIRetryMessage = {
    type: 'system';
    subtype: 'api_retry';
    attempt: number;
    max_retries: number;
    retry_delay_ms: number;
    error_status: number | null;
    error: SDKAssistantMessageError;
    uuid: UUID;
    session_id: string;
};

export declare type SDKAssistantMessage = {
    type: 'assistant';
    message: BetaMessage;
    parent_tool_use_id: string | null;
    error?: SDKAssistantMessageError;
    uuid: UUID;
    session_id: string;
    request_id?: string;
    /**
     * Subagent type that produced this message.
     */
    subagent_type?: string;
    /**
     * Description of the subagent task that produced this message.
     */
    task_description?: string;
};

export declare type SDKAssistantMessageError = 'authentication_failed' | 'oauth_org_not_allowed' | 'billing_error' | 'rate_limit' | 'invalid_request' | 'model_not_found' | 'server_error' | 'unknown' | 'max_output_tokens';

export declare type SDKAuthStatusMessage = {
    type: 'auth_status';
    isAuthenticating: boolean;
    output: string[];
    error?: string;
    uuid: UUID;
    session_id: string;
};

export declare type SdkBeta = 'context-1m-2025-08-07';

export declare type SDKCompactBoundaryMessage = {
    type: 'system';
    subtype: 'compact_boundary';
    compact_metadata: {
        trigger: 'manual' | 'auto';
        pre_tokens: number;
        post_tokens?: number;
        duration_ms?: number;
        /**
         * Relink info for messagesToKeep. Loaders splice the preserved segment at anchor_uuid (summary for suffix-preserving, boundary for prefix-preserving partial compact) so resume includes preserved content. Unset when compaction summarizes everything (no messagesToKeep).
         */
        preserved_segment?: {
            head_uuid: UUID;
            anchor_uuid: UUID;
            tail_uuid: UUID;
        };
        /**
         * Ordered messagesToKeep UUIDs. Supersedes preserved_segment — readers look up each UUID directly and relink uuids[i] to uuids[i-1] (uuids[0] to anchor_uuid) instead of walking the parentUuid chain. Unset when compaction summarizes everything.
         */
        preserved_messages?: {
            anchor_uuid: UUID;
            uuids: UUID[];
        };
    };
    uuid: UUID;
    session_id: string;
};

/**
 * Merges the provided settings into the flag settings layer, updating the active configuration.
 */
declare type SDKControlApplyFlagSettingsRequest = {
    subtype: 'apply_flag_settings';
    settings: Record<string, unknown>;
};

/**
 * Backgrounds in-flight foreground tasks (Bash commands and subagents). With tool_use_id, targets the single task started by that tool_use block; without it, backgrounds all foreground tasks — the control-request equivalent of pressing Ctrl+B in the terminal. Each blocking tool call returns immediately with a "running in the background" tool_result and the turn continues; the task keeps running and emits a task_notification when it settles.
 */
declare type SDKControlBackgroundTasksRequest = {
    subtype: 'background_tasks';
    /**
     * When set, backgrounds only the task whose originating tool_use block has this id. When omitted, backgrounds all foreground tasks (Ctrl+B semantics).
     */
    tool_use_id?: string;
};

/**
 * Drops a pending async user message from the command queue by uuid. No-op if already dequeued for execution.
 */
declare type SDKControlCancelAsyncMessageRequest = {
    subtype: 'cancel_async_message';
    message_uuid: string;
};

/**
 * Cancels a currently open control request.
 */
declare type SDKControlCancelRequest = {
    type: 'control_cancel_request';
    request_id: string;
};

/**
 * Requests the SDK consumer to handle an MCP elicitation (user input request).
 */
declare type SDKControlElicitationRequest = {
    subtype: 'elicitation';
    mcp_server_name: string;
    message: string;
    mode?: 'form' | 'url';
    url?: string;
    elicitation_id?: string;
    requested_schema?: Record<string, unknown>;
    /**
     * Permission-display title from the MCP server's _meta['anthropic/permissionDisplay']. Mirrors can_use_tool.title so SDK consumers can render elicitation-driven permission prompts with structured headers instead of parsing `message`.
     */
    title?: string;
    /**
     * Short tool/server label from _meta['anthropic/permissionDisplay'].displayName. Mirrors can_use_tool.display_name.
     */
    display_name?: string;
    /**
     * Permission-display subtitle from _meta['anthropic/permissionDisplay'].description. Mirrors can_use_tool.description.
     */
    description?: string;
};

/**
 * Requests at-mention file autocomplete suggestions for a partial path prefix. Returns the same fuzzy-matched results the TUI shows.
 */
declare type SDKControlFileSuggestionsRequest = {
    subtype: 'file_suggestions';
    query: string;
};

/**
 * Requests the responder's CLI binary version. Used by /version in --remote mode so the thin client can show both its own and the remote container's version.
 */
declare type SDKControlGetBinaryVersionRequest = {
    subtype: 'get_binary_version';
};

/**
 * Requests a breakdown of current context window usage by category.
 */
declare type SDKControlGetContextUsageRequest = {
    subtype: 'get_context_usage';
};

/**
 * Breakdown of current context window usage by category (system prompt, tools, messages, etc.).
 */
export declare type SDKControlGetContextUsageResponse = {
    categories: {
        name: string;
        tokens: number;
        color: string;
        isDeferred?: boolean;
    }[];
    totalTokens: number;
    maxTokens: number;
    rawMaxTokens: number;
    percentage: number;
    gridRows: {
        color: string;
        isFilled: boolean;
        categoryName: string;
        tokens: number;
        percentage: number;
        squareFullness: number;
    }[][];
    model: string;
    memoryFiles: {
        path: string;
        type: string;
        tokens: number;
    }[];
    mcpTools: {
        name: string;
        serverName: string;
        tokens: number;
        isLoaded?: boolean;
    }[];
    deferredBuiltinTools?: {
        name: string;
        tokens: number;
        isLoaded: boolean;
    }[];
    systemTools?: {
        name: string;
        tokens: number;
    }[];
    systemPromptSections?: {
        name: string;
        tokens: number;
    }[];
    agents: {
        agentType: string;
        source: string;
        tokens: number;
    }[];
    slashCommands?: {
        totalCommands: number;
        includedCommands: number;
        tokens: number;
    };
    skills?: {
        totalSkills: number;
        includedSkills: number;
        tokens: number;
        skillFrontmatter: {
            name: string;
            source: string;
            tokens: number;
        }[];
    };
    autoCompactThreshold?: number;
    isAutoCompactEnabled: boolean;
    messageBreakdown?: {
        toolCallTokens: number;
        toolResultTokens: number;
        attachmentTokens: number;
        assistantMessageTokens: number;
        userMessageTokens: number;
        redirectedContextTokens: number;
        unattributedTokens: number;
        toolCallsByType: {
            name: string;
            callTokens: number;
            resultTokens: number;
        }[];
        attachmentsByType: {
            name: string;
            tokens: number;
        }[];
    };
    apiUsage: {
        input_tokens: number;
        output_tokens: number;
        cache_creation_input_tokens: number;
        cache_read_input_tokens: number;
    } | null;
};

/**
 * Requests the formatted session cost summary (the same text /usage prints in non-interactive mode). Used by the thin-client /usage dialog to show the remote container cost instead of the local $0.00.
 */
declare type SDKControlGetSessionCostRequest = {
    subtype: 'get_session_cost';
};

/**
 * Returns the effective merged settings and the raw per-source settings.
 */
declare type SDKControlGetSettingsRequest = {
    subtype: 'get_settings';
};

/**
 * Initializes the SDK session with hooks, MCP servers, and agent configuration.
 */
declare type SDKControlInitializeRequest = {
    subtype: 'initialize';
    hooks?: Partial<Record<coreTypes.HookEvent, SDKHookCallbackMatcher[]>>;
    sdkMcpServers?: string[];
    jsonSchema?: Record<string, unknown>;
    systemPrompt?: string[];
    appendSystemPrompt?: string;
    /**
     * Custom workflow body for the plan-mode system reminder. Replaces the default code-implementation phases; the CLI still wraps it with the read-only enforcement preamble and the ExitPlanMode protocol footer.
     */
    planModeInstructions?: string;

    /**
     * Map of tool-name aliases applied before name resolution. When the model emits a tool_use whose name is a key in this map, the tool execution path resolves the mapped name instead. Single-hop (no chains). See Options.toolAliases.
     */
    toolAliases?: Record<string, string>;
    /**
     * When true, omit per-user dynamic sections (working directory, auto-memory path) from the cached system prompt and re-inject them as the first user message. Lets cross-user prompt caching hit on a static system prompt prefix. Tradeoff: the model sees this context slightly later in the prompt, so steering on the working directory and memory location is marginally less authoritative. Has no effect when a custom (non-preset) system prompt is in use.
     */
    excludeDynamicSections?: boolean;
    agents?: Record<string, coreTypes.AgentDefinition>;
    /**
     * Custom session title. When provided, the session uses this title and skips automatic title generation. Has no effect on the persisted title when resuming an existing session.
     */
    title?: string;
    /**
     * When provided, only skills whose names match an entry are loaded into the main session system prompt, using the same rules as AgentDefinition.skills: exact name, plugin-qualified name, or ":name" suffix. Omit to load every discovered skill. Applies to the main session only; subagents use AgentDefinition.skills.
     */
    skills?: string[];

    promptSuggestions?: boolean;
    agentProgressSummaries?: boolean;
    forwardSubagentText?: boolean;
};

/**
 * Response from session initialization with available commands, models, and account info.
 */
export declare type SDKControlInitializeResponse = {
    commands: coreTypes.SlashCommand[];
    agents: coreTypes.AgentInfo[];
    output_style: string;
    available_output_styles: string[];
    models: coreTypes.ModelInfo[];
    /**
     * Information about the logged in user's account.
     */
    account: coreTypes.AccountInfo;

    fast_mode_state?: coreTypes.FastModeState;
};

/**
 * Interrupts the currently running conversation turn.
 */
declare type SDKControlInterruptRequest = {
    subtype: 'interrupt';
};

/**
 * Invokes an MCP tool via the subprocess MCP client without a model turn. No permission check (control channel is trusted, same as other subtypes). SDK-type MCP servers (config.type === "sdk") are rejected — they are caller-provided, so the caller can invoke them directly without the subprocess round-trip. Result content passes through the same processing as model-turn MCP calls. Session expiry is not retried automatically; callers can mcp_reconnect and retry. UrlElicitationRequired (-32042) tries Elicitation hooks; if no hook resolves, the call errors with the URL in the message — open it out-of-band, then retry mcp_call.
 */
declare type SDKControlMcpCallRequest = {
    subtype: 'mcp_call';
    /**
     * Fully-qualified MCP tool name, e.g. mcp__server__tool_name.
     */
    tool: string;
    arguments?: Record<string, unknown>;
};

/**
 * Sends a JSON-RPC message to a specific MCP server.
 */
declare type SDKControlMcpMessageRequest = {
    subtype: 'mcp_message';
    server_name: string;
    message: JSONRPCMessage;
};

/**
 * Reconnects a disconnected or failed MCP server.
 */
declare type SDKControlMcpReconnectRequest = {
    subtype: 'mcp_reconnect';
    serverName: string;
};

/**
 * Replaces the set of dynamically managed MCP servers.
 */
declare type SDKControlMcpSetServersRequest = {
    subtype: 'mcp_set_servers';
    servers: Record<string, coreTypes.McpServerConfigForProcessTransport>;
};

/**
 * Requests the current status of all MCP server connections.
 */
declare type SDKControlMcpStatusRequest = {
    subtype: 'mcp_status';
};

/**
 * Enables or disables an MCP server.
 */
declare type SDKControlMcpToggleRequest = {
    subtype: 'mcp_toggle';
    serverName: string;
    enabled: boolean;
};

/**
 * Requests permission to use a tool with the given input.
 */
declare type SDKControlPermissionRequest = {
    subtype: 'can_use_tool';
    tool_name: string;
    input: Record<string, unknown>;
    permission_suggestions?: coreTypes.PermissionUpdate[];
    blocked_path?: string;
    decision_reason?: string;
    /**
     * Structured discriminator for why auto-mode escalated. Lets SDK hosts make policy (e.g. auto-deny safetyCheck) without parsing decision_reason text. For compound bash commands this is "subcommandResults" even when a safetyCheck is nested inside — check classifier_approvable for that case.
     */
    decision_reason_type?: 'rule' | 'mode' | 'subcommandResults' | 'permissionPromptTool' | 'hook' | 'asyncAgent' | 'sandboxOverride' | 'workingDir' | 'safetyCheck' | 'classifier' | 'other';
    /**
     * Set when a safetyCheck is present anywhere in the decision reason (including nested inside subcommandResults for compound bash). false = at least one safety check requires manual approval (e.g. Windows path bypass, dangerous rm); true = all safety checks MAY be classifier-approved (e.g. sensitive-file paths). Absent when no safetyCheck is involved.
     */
    classifier_approvable?: boolean;
    title?: string;
    display_name?: string;
    tool_use_id: string;
    agent_id?: string;
    description?: string;
};

/**
 * Read a file from the session filesystem for the remote sidebar viewer. Path is resolved against cwd and gated by the same read-permission rules as the Read tool.
 */
declare type SDKControlReadFileRequest = {
    subtype: 'read_file';
    path: string;
    max_bytes?: number;
    /**
     * How to encode the bytes in `contents`. Defaults to utf-8 (lossy for binary); pass 'base64' to read images.
     */
    encoding?: 'utf-8' | 'base64';
};

/**
 * File contents for the remote sidebar viewer.
 */
export declare type SDKControlReadFileResponse = {
    contents: string;
    absPath: string;
    truncated?: boolean;
    /**
     * Set when the request asked for base64. Absent means utf-8 — including when an older CLI ignored the request's encoding field.
     */
    encoding?: 'base64';
};

/**
 * Reloads plugins from disk and returns the refreshed session components.
 */
declare type SDKControlReloadPluginsRequest = {
    subtype: 'reload_plugins';
};

/**
 * Refreshed commands, agents, plugins, and MCP server status after reload.
 */
export declare type SDKControlReloadPluginsResponse = {
    commands: coreTypes.SlashCommand[];
    agents: coreTypes.AgentInfo[];
    plugins: {
        name: string;
        path: string;
        source?: string;
    }[];
    mcpServers: coreTypes.McpServerStatus[];
    error_count: number;
};

/**
 * Sets the user-facing title for the current session.
 */
declare type SDKControlRenameSessionRequest = {
    subtype: 'rename_session';
    title: string;
};

export declare type SDKControlRequest = {
    type: 'control_request';
    request_id: string;
    request: SDKControlRequestInner;
};

declare type SDKControlRequestInner = SDKControlInterruptRequest | SDKControlPermissionRequest | SDKControlInitializeRequest | SDKControlSetPermissionModeRequest | SDKControlSetModelRequest | SDKControlSetMaxThinkingTokensRequest | SDKControlRenameSessionRequest | SDKControlSetColorRequest | SDKControlMcpStatusRequest | SDKControlGetContextUsageRequest | SDKControlGetSessionCostRequest | SDKControlGetBinaryVersionRequest | SDKControlMcpCallRequest | SDKControlFileSuggestionsRequest | SDKHookCallbackRequest | SDKControlMcpMessageRequest | SDKControlRewindFilesRequest | SDKControlCancelAsyncMessageRequest | SDKControlReadFileRequest | SDKControlSeedReadStateRequest | SDKControlMcpSetServersRequest | SDKControlReloadPluginsRequest | SDKControlMcpReconnectRequest | SDKControlMcpToggleRequest | SDKControlChannelEnableRequest | SDKControlEndSessionRequest | SDKControlMcpAuthenticateRequest | SDKControlMcpClearAuthRequest | SDKControlMcpOAuthCallbackUrlRequest | SDKControlClaudeAuthenticateRequest | SDKControlClaudeOAuthCallbackRequest | SDKControlClaudeOAuthWaitForCompletionRequest | SDKControlRemoteControlRequest | SDKControlGenerateSessionTitleRequest | SDKControlSideQuestionRequest | SDKControlUltrareviewLaunchRequest | SDKControlMessageRatedRequest | SDKControlOAuthTokenRefreshRequest | SDKControlHostAuthTokenRefreshRequest | SDKControlStopTaskRequest | SDKControlBackgroundTasksRequest | SDKControlApplyFlagSettingsRequest | SDKControlGetSettingsRequest | SDKControlElicitationRequest | SDKControlRequestUserDialogRequest | SDKControlSubmitFeedbackRequest;

/**
 * Requests the SDK consumer to render a tool-driven blocking dialog and return the user choice. Used by tools that previously rendered Ink JSX via setToolJSX with an onDone callback.
 */
declare type SDKControlRequestUserDialogRequest = {
    subtype: 'request_user_dialog';
    /**
     * Identifier for the dialog the host should render. Open string union — known kinds include "it2_setup" and "computer_use_approval"; new kinds may be added without bumping the protocol.
     */
    dialog_kind: string;
    /**
     * Dialog-specific data passed to the host renderer. Shape is defined per dialog_kind; the protocol transports it opaquely.
     */
    payload: Record<string, unknown>;
    tool_use_id?: string;
};

export declare type SDKControlResponse = {
    type: 'control_response';
    response: ControlResponse | ControlErrorResponse;
};

/**
 * Rewinds file changes made since a specific user message.
 */
declare type SDKControlRewindFilesRequest = {
    subtype: 'rewind_files';
    user_message_id: string;
    dry_run?: boolean;
};

/**
 * Seeds the readFileState cache with a path+mtime entry. Use when a prior Read was removed from context so Edit validation would fail despite the client having observed the Read. The mtime lets the CLI detect if the file changed since the seeded Read — same staleness check as the normal path.
 */
declare type SDKControlSeedReadStateRequest = {
    subtype: 'seed_read_state';
    path: string;
    mtime: number;
};

/**
 * Sets the session accent color. Accepts an agent color name or "default" to reset.
 */
declare type SDKControlSetColorRequest = {
    subtype: 'set_color';
    color: string;
};

/**
 * Sets the maximum number of thinking tokens for extended thinking.
 */
declare type SDKControlSetMaxThinkingTokensRequest = {
    subtype: 'set_max_thinking_tokens';
    max_thinking_tokens: number | null;
};

/**
 * Sets the model to use for subsequent conversation turns.
 */
declare type SDKControlSetModelRequest = {
    subtype: 'set_model';
    model?: string;
};

/**
 * Sets the permission mode for tool execution handling.
 */
declare type SDKControlSetPermissionModeRequest = {
    subtype: 'set_permission_mode';
    /**
     * Permission mode for controlling how tool executions are handled. 'default' - Standard behavior, prompts for dangerous operations. 'acceptEdits' - Auto-accept file edit operations. 'bypassPermissions' - Bypass all permission checks (requires allowDangerouslySkipPermissions). 'plan' - Planning mode, no actual tool execution. 'dontAsk' - Don't prompt for permissions, deny if not pre-approved. 'auto' - Use a model classifier to approve/deny permission prompts.
     */
    mode: coreTypes.PermissionMode;

};

/**
 * Stops a running task.
 */
declare type SDKControlStopTaskRequest = {
    subtype: 'stop_task';
    task_id: string;
};

export declare type SDKDeferredToolUse = {
    id: string;
    name: string;
    input: Record<string, unknown>;
};

/**
 * Emitted when an MCP server confirms that a URL-mode elicitation is complete.
 */
export declare type SDKElicitationCompleteMessage = {
    type: 'system';
    subtype: 'elicitation_complete';
    mcp_server_name: string;
    elicitation_id: string;
    uuid: UUID;
    session_id: string;
};

export declare type SDKFilesPersistedEvent = {
    type: 'system';
    subtype: 'files_persisted';
    files: {
        filename: string;
        file_id: string;
    }[];
    failed: {
        filename: string;
        error: string;
    }[];
    processed_at: string;
    uuid: UUID;
    session_id: string;
};

/**
 * Configuration for matching and routing hook callbacks.
 */
declare type SDKHookCallbackMatcher = {
    matcher?: string;
    hookCallbackIds: string[];
    timeout?: number;
};

/**
 * Delivers a hook callback with its input data.
 */
declare type SDKHookCallbackRequest = {
    subtype: 'hook_callback';
    callback_id: string;
    input: coreTypes.HookInput;
    tool_use_id?: string;
};

export declare type SDKHookProgressMessage = {
    type: 'system';
    subtype: 'hook_progress';
    hook_id: string;
    hook_name: string;
    hook_event: string;
    stdout: string;
    stderr: string;
    output: string;
    uuid: UUID;
    session_id: string;
};

export declare type SDKHookResponseMessage = {
    type: 'system';
    subtype: 'hook_response';
    hook_id: string;
    hook_name: string;
    hook_event: string;
    output: string;
    stdout: string;
    stderr: string;
    exit_code?: number;
    outcome: 'success' | 'error' | 'cancelled';
    uuid: UUID;
    session_id: string;
};

export declare type SDKHookStartedMessage = {
    type: 'system';
    subtype: 'hook_started';
    hook_id: string;
    hook_name: string;
    hook_event: string;
    uuid: UUID;
    session_id: string;
};

/**
 * Keep-alive message to maintain WebSocket connection.
 */
declare type SDKKeepAliveMessage = {
    type: 'keep_alive';
};

/**
 * Output from a local slash command (e.g. /voice, /usage). Displayed as assistant-style text in the transcript.
 */
export declare type SDKLocalCommandOutputMessage = {
    type: 'system';
    subtype: 'local_command_output';
    content: string;
    uuid: UUID;
    session_id: string;
};

/**
 * MCP tool definition for SDK servers.
 * Contains a handler function, so not serializable.
 * Supports both Zod 3 and Zod 4 schemas.
 */
export declare type SdkMcpToolDefinition<Schema extends AnyZodRawShape = AnyZodRawShape> = {
    name: string;
    description: string;
    inputSchema: Schema;
    annotations?: ToolAnnotations;
    _meta?: Record<string, unknown>;
    handler: (args: InferShape<Schema>, extra: unknown) => Promise<CallToolResult>;
};

/**
 * Emitted when the memory recall supervisor surfaces relevant memories into the turn. Mirrors the CLI relevant_memories attachment so SDK renderers can show "Recalled from memory" inline.
 */
export declare type SDKMemoryRecallMessage = {
    type: 'system';
    subtype: 'memory_recall';
    /**
     * How memories were surfaced: 'select' returns full file bodies chosen by the parallel selector; 'synthesize' returns a Sonnet-authored paragraph distilled from many tiny memories.
     */
    mode: 'select' | 'synthesize';
    memories: {
        /**
         * Absolute path to the memory file, a synthesis sentinel of the form `<synthesis:DIR>` when mode is 'synthesize', or an https URL when scope is 'organization'.
         */
        path: string;
        scope: 'personal' | 'team' | 'organization';
        /**
         * The surfaced memory body. Always present for 'synthesize' mode and 'organization' scope (neither has an on-disk path to lazy-load from); absent for file-backed 'select' entries (renderers lazy-load from path).
         */
        content?: string;
    }[];
    uuid: UUID;
    session_id: string;
};

export declare type SDKMessage = SDKAssistantMessage | SDKUserMessage | SDKUserMessageReplay | SDKResultMessage | SDKSystemMessage | SDKPartialAssistantMessage | SDKCompactBoundaryMessage | SDKStatusMessage | SDKAPIRetryMessage | SDKLocalCommandOutputMessage | SDKHookStartedMessage | SDKHookProgressMessage | SDKHookResponseMessage | SDKPluginInstallMessage | SDKToolProgressMessage | SDKAuthStatusMessage | SDKTaskNotificationMessage | SDKTaskStartedMessage | SDKTaskUpdatedMessage | SDKTaskProgressMessage | SDKSessionStateChangedMessage | SDKNotificationMessage | SDKFilesPersistedEvent | SDKToolUseSummaryMessage | SDKMemoryRecallMessage | SDKRateLimitEvent | SDKElicitationCompleteMessage | SDKPermissionDeniedMessage | SDKPromptSuggestionMessage | SDKMirrorErrorMessage;

/**
 * Provenance of a user-role message (peer session, team lead, channel). Absent or `human` means keyboard input from the user.
 */
export declare type SDKMessageOrigin = {
    kind: 'human';
} | {
    kind: 'channel';
    server: string;
} | {
    kind: 'peer';
    from: string;
    name?: string;
} | {
    kind: 'task-notification';
} | {
    kind: 'coordinator';
};

/**
 * Emitted when SessionStore.append() rejects or times out for a transcript-mirror batch after bounded retry (3 attempts with short backoff; timeouts are not retried). The batch is then dropped; this surfaces the failure so consumers are not silent on data loss.
 */
export declare type SDKMirrorErrorMessage = {
    type: 'system';
    subtype: 'mirror_error';
    error: string;
    key: {
        projectKey: string;
        sessionId: string;
        subpath?: string;
    };
    uuid: UUID;
    session_id: string;
};

/**
 * Loop-side text notification. Mirrors the interactive REPL notification queue (key/priority/timeout). JSX notifications are not emitted on this channel.
 */
export declare type SDKNotificationMessage = {
    type: 'system';
    subtype: 'notification';
    key: string;
    text: string;
    priority: 'low' | 'medium' | 'high' | 'immediate';
    color?: string;
    timeout_ms?: number;
    uuid: UUID;
    session_id: string;
};

export declare type SDKPartialAssistantMessage = {
    type: 'stream_event';
    event: BetaRawMessageStreamEvent;
    parent_tool_use_id: string | null;
    uuid: UUID;
    session_id: string;
    ttft_ms?: number;
};

export declare type SDKPermissionDenial = {
    tool_name: string;
    tool_use_id: string;
    tool_input: Record<string, unknown>;
};

/**
 * Emitted when a tool call is auto-denied without an interactive permission prompt (e.g. auto-mode classifier, dontAsk mode, headless-agent auto-deny, or a deny rule). The 'ask' path surfaces via a can_use_tool control_request; this event covers the 'deny' short-circuit in canUseTool so SDK hosts can render the denial instead of only seeing an is_error tool_result. PreToolUse hook denies bypass canUseTool and are not covered here.
 */
export declare type SDKPermissionDeniedMessage = {
    type: 'system';
    subtype: 'permission_denied';
    tool_name: string;
    tool_use_id: string;
    /**
     * Subagent ID when the denied tool call originated inside a subagent. Mirrors can_use_tool for host-side routing.
     */
    agent_id?: string;
    /**
     * Discriminator from PermissionDecisionReason (e.g. 'classifier', 'asyncAgent', 'mode', 'rule').
     */
    decision_reason_type?: string;
    /**
     * Human-readable reason from the deciding component, when available.
     */
    decision_reason?: string;
    /**
     * The rejection message returned to the model in the tool_result.
     */
    message: string;
    uuid: UUID;
    session_id: string;
};

/**
 * Configuration for loading a plugin.
 */
export declare type SdkPluginConfig = {
    /**
     * Plugin type. Currently only 'local' is supported
     */
    type: 'local';
    /**
     * Absolute or relative path to the plugin directory
     */
    path: string;
};

/**
 * Headless plugin installation progress (CLAUDE_CODE_SYNC_PLUGIN_INSTALL). started/completed bracket the whole install; installed/failed carry a per-marketplace name.
 */
export declare type SDKPluginInstallMessage = {
    type: 'system';
    subtype: 'plugin_install';
    status: 'started' | 'installed' | 'failed' | 'completed';
    name?: string;
    error?: string;
    uuid: UUID;
    session_id: string;
};

/**
 * Predicted next user prompt, emitted after each turn when promptSuggestions is enabled.
 */
export declare type SDKPromptSuggestionMessage = {
    type: 'prompt_suggestion';
    suggestion: string;
    uuid: UUID;
    session_id: string;
};

/**
 * Rate limit event emitted when rate limit info changes.
 */
export declare type SDKRateLimitEvent = {
    type: 'rate_limit_event';
    /**
     * Rate limit information for claude.ai subscription users.
     */
    rate_limit_info: SDKRateLimitInfo;
    uuid: UUID;
    session_id: string;
};

/**
 * Rate limit information for claude.ai subscription users.
 */
export declare type SDKRateLimitInfo = {
    status: 'allowed' | 'allowed_warning' | 'rejected';
    resetsAt?: number;
    rateLimitType?: 'five_hour' | 'seven_day' | 'seven_day_opus' | 'seven_day_sonnet' | 'overage';
    utilization?: number;
    overageStatus?: 'allowed' | 'allowed_warning' | 'rejected';
    overageResetsAt?: number;
    overageDisabledReason?: 'overage_not_provisioned' | 'org_level_disabled' | 'org_level_disabled_until' | 'out_of_credits' | 'seat_tier_level_disabled' | 'member_level_disabled' | 'seat_tier_zero_credit_limit' | 'group_zero_credit_limit' | 'member_zero_credit_limit' | 'org_service_level_disabled' | 'no_limits_configured' | 'fetch_error' | 'unknown';
    isUsingOverage?: boolean;
    surpassedThreshold?: number;
};

export declare type SDKResultError = {
    type: 'result';
    subtype: 'error_during_execution' | 'error_max_turns' | 'error_max_budget_usd' | 'error_max_structured_output_retries';
    duration_ms: number;
    duration_api_ms: number;
    is_error: boolean;
    num_turns: number;
    stop_reason: string | null;
    total_cost_usd: number;
    usage: NonNullableUsage;
    modelUsage: Record<string, ModelUsage>;
    permission_denials: SDKPermissionDenial[];
    errors: string[];
    terminal_reason?: TerminalReason;
    fast_mode_state?: FastModeState;
    origin?: SDKMessageOrigin;
    uuid: UUID;
    session_id: string;
};

export declare type SDKResultMessage = SDKResultSuccess | SDKResultError;

export declare type SDKResultSuccess = {
    type: 'result';
    subtype: 'success';
    duration_ms: number;
    duration_api_ms: number;
    ttft_ms?: number;
    is_error: boolean;
    api_error_status?: number | null;
    num_turns: number;
    result: string;
    stop_reason: string | null;
    total_cost_usd: number;
    usage: NonNullableUsage;
    modelUsage: Record<string, ModelUsage>;
    permission_denials: SDKPermissionDenial[];
    structured_output?: unknown;
    deferred_tool_use?: SDKDeferredToolUse;
    terminal_reason?: TerminalReason;
    fast_mode_state?: FastModeState;
    origin?: SDKMessageOrigin;
    uuid: UUID;
    session_id: string;
};

/**
 * Session metadata returned by listSessions and getSessionInfo.
 */
export declare type SDKSessionInfo = {
    /**
     * Unique session identifier (UUID).
     */
    sessionId: string;
    /**
     * Display title for the session: custom title, auto-generated summary, or first prompt.
     */
    summary: string;
    /**
     * Last modified time in milliseconds since epoch.
     */
    lastModified: number;
    /**
     * File size in bytes. Only populated for local JSONL storage.
     */
    fileSize?: number;
    /**
     * User-set session title via /rename.
     */
    customTitle?: string;
    /**
     * First meaningful user prompt in the session.
     */
    firstPrompt?: string;
    /**
     * Git branch at the end of the session.
     */
    gitBranch?: string;
    /**
     * Working directory for the session.
     */
    cwd?: string;
    /**
     * User-set session tag.
     */
    tag?: string;
    /**
     * Creation time in milliseconds since epoch, extracted from the first entry's timestamp.
     */
    createdAt?: number;
};

/**
 * Mirrors notifySessionStateChanged. 'idle' fires after heldBackResult flushes and the bg-agent do-while exits — authoritative turn-over signal.
 */
export declare type SDKSessionStateChangedMessage = {
    type: 'system';
    subtype: 'session_state_changed';
    state: 'idle' | 'running' | 'requires_action';
    uuid: UUID;
    session_id: string;
};

/**
 * A settings file parse or validation error. When a settings.json file fails to parse (invalid JSON, JSON comments, schema mismatch), the file is skipped and any rules it contained — including permission allow/deny lists — are not applied.
 */
export declare type SDKSettingsParseError = {
    /**
     * Path to the settings file that failed to parse or validate.
     */
    file?: string;
    /**
     * Dot-notation path to the field with the error, or empty string for whole-file errors.
     */
    path: string;
    /**
     * Human-readable error message.
     */
    message: string;
};

export declare type SDKStatus = 'compacting' | 'requesting' | null;

export declare type SDKStatusMessage = {
    type: 'system';
    subtype: 'status';
    status: SDKStatus;
    permissionMode?: PermissionMode;
    compact_result?: 'success' | 'failed';
    compact_error?: string;
    uuid: UUID;
    session_id: string;
};

export declare type SDKSystemMessage = {
    type: 'system';
    subtype: 'init';
    agents?: string[];
    apiKeySource: ApiKeySource;
    betas?: string[];
    claude_code_version: string;
    cwd: string;
    tools: string[];
    mcp_servers: {
        name: string;
        status: string;
    }[];
    model: string;
    /**
     * Permission mode for controlling how tool executions are handled. 'default' - Standard behavior, prompts for dangerous operations. 'acceptEdits' - Auto-accept file edit operations. 'bypassPermissions' - Bypass all permission checks (requires allowDangerouslySkipPermissions). 'plan' - Planning mode, no actual tool execution. 'dontAsk' - Don't prompt for permissions, deny if not pre-approved. 'auto' - Use a model classifier to approve/deny permission prompts.
     */
    permissionMode: PermissionMode;
    slash_commands: string[];
    output_style: string;
    skills: string[];
    plugins: {
        name: string;
        path: string;

    }[];


    fast_mode_state?: FastModeState;


    uuid: UUID;
    session_id: string;
};

export declare type SDKTaskNotificationMessage = {
    type: 'system';
    subtype: 'task_notification';
    task_id: string;
    tool_use_id?: string;
    status: 'completed' | 'failed' | 'stopped';
    output_file: string;
    summary: string;
    usage?: {
        total_tokens: number;
        tool_uses: number;
        duration_ms: number;
    };
    skip_transcript?: boolean;
    uuid: UUID;
    session_id: string;
};

export declare type SDKTaskProgressMessage = {
    type: 'system';
    subtype: 'task_progress';
    task_id: string;
    tool_use_id?: string;
    description: string;
    /**
     * Subagent type for Task tool subagents.
     */
    subagent_type?: string;
    usage: {
        total_tokens: number;
        tool_uses: number;
        duration_ms: number;
    };
    last_tool_name?: string;
    summary?: string;

    uuid: UUID;
    session_id: string;
};

export declare type SDKTaskStartedMessage = {
    type: 'system';
    subtype: 'task_started';
    task_id: string;
    tool_use_id?: string;
    description: string;
    /**
     * Subagent type for Task tool subagents.
     */
    subagent_type?: string;
    task_type?: string;
    /**
     * meta.name from the workflow script (e.g. 'spec'). Only set when task_type is 'local_workflow'.
     */
    workflow_name?: string;
    prompt?: string;
    /**
     * Ambient/housekeeping task. Consumers should hide this from the inline transcript; it may still appear in a tasks panel.
     */
    skip_transcript?: boolean;
    uuid: UUID;
    session_id: string;
};

export declare type SDKTaskUpdatedMessage = {
    type: 'system';
    subtype: 'task_updated';
    task_id: string;
    /**
     * Wire-safe subset of TaskState fields that changed. Excludes abortController, messages, result. Clients merge into their local task map.
     */
    patch: {
        status?: 'pending' | 'running' | 'completed' | 'failed' | 'killed' | 'paused';
        description?: string;
        end_time?: number;
        total_paused_ms?: number;
        error?: string;
        is_backgrounded?: boolean;
    };
    uuid: UUID;
    session_id: string;
};

export declare type SDKToolProgressMessage = {
    type: 'tool_progress';
    tool_use_id: string;
    tool_name: string;
    parent_tool_use_id: string | null;
    elapsed_time_seconds: number;
    task_id?: string;
    uuid: UUID;
    session_id: string;
};

export declare type SDKToolUseSummaryMessage = {
    type: 'tool_use_summary';
    summary: string;
    preceding_tool_use_ids: string[];
    uuid: UUID;
    session_id: string;
};

export declare type SDKUserMessage = {
    type: 'user';
    message: MessageParam;
    parent_tool_use_id: string | null;
    isSynthetic?: boolean;
    tool_use_result?: unknown;
    priority?: 'now' | 'next' | 'later';
    origin?: SDKMessageOrigin;

    /**
     * When false, the message is appended to the transcript without triggering an assistant turn. It will be merged into the next user message that does query.
     */
    shouldQuery?: boolean;
    /**
     * ISO timestamp when the message was created on the originating process. Older emitters omit it; consumers should fall back to receive time.
     */
    timestamp?: string;
    uuid?: UUID;
    session_id?: string;
    /**
     * Subagent type that produced this message.
     */
    subagent_type?: string;
    /**
     * Description of the subagent task that produced this message.
     */
    task_description?: string;
};

export declare type SDKUserMessageReplay = {
    type: 'user';
    message: MessageParam;
    parent_tool_use_id: string | null;
    isSynthetic?: boolean;
    tool_use_result?: unknown;
    priority?: 'now' | 'next' | 'later';
    origin?: SDKMessageOrigin;

    /**
     * When false, the message is appended to the transcript without triggering an assistant turn. It will be merged into the next user message that does query.
     */
    shouldQuery?: boolean;
    /**
     * ISO timestamp when the message was created on the originating process. Older emitters omit it; consumers should fall back to receive time.
     */
    timestamp?: string;
    uuid: UUID;
    session_id: string;
    isReplay: true;
    file_attachments?: unknown[];
};

export declare type SessionCronSummary = {
    id: string;
    /**
     * Cron expression, e.g. "0 9 * * 1-5".
     */
    schedule: string;
    /**
     * False for one-shot wakeups whose cron field encodes a single fire time; true for tasks that re-fire on every match.
     */
    recurring: boolean;
    /**
     * Prompt text submitted when the cron fires. Capped at 1000 chars; clipped values append an in-string "… [+N chars]" marker.
     */
    prompt: string;
};

export declare type SessionEndHookInput = BaseHookInput & {
    hook_event_name: 'SessionEnd';
    reason: ExitReason;
};

/**
 * Identifies a session transcript or subagent transcript in the store.
 * Main transcripts have no subpath; subagent transcripts include a subpath
 * like 'subagents/agent-{id}' that mirrors the on-disk directory structure.
 * @alpha
 */
export declare type SessionKey = {
    /** Caller-defined scope. Default: sanitized cwd. Multi-tenant deployments
     *  should set this to a tenant ID or project name. Paths longer than 200
     *  characters are truncated and suffixed with a portable djb2 hash so the
     *  same path yields the same key under both Bun and Node.js. */
    projectKey: string;
    sessionId: string;
    /** Undefined = main transcript. Set for subagent files.
     *  Empty string is invalid — omit the field for the main transcript.
     *  Opaque to the adapter — just use it as a storage key suffix. */
    subpath?: string;
};

/**
 * A message from a session transcript.
 * Returned by `getSessionMessages` for reading historical session data.
 */
export declare type SessionMessage = {
    type: 'user' | 'assistant' | 'system';
    uuid: string;
    session_id: string;
    message: unknown;
    parent_tool_use_id: string | null;
};

/**
 * Options shared by session mutation functions (renameSession, tagSession,
 * deleteSession, forkSession).
 */
export declare type SessionMutationOptions = {
    /**
     * Project directory path (same semantics as `listSessions({ dir })`).
     * When omitted, all project directories are searched for the session file.
     */
    dir?: string;
    /**
     * When provided, read/write session data via this store instead of the
     * local filesystem.
     * @alpha
     */
    sessionStore?: SessionStore;
};

export declare type SessionStartHookInput = BaseHookInput & {
    hook_event_name: 'SessionStart';
    source: 'startup' | 'resume' | 'clear' | 'compact';
    agent_type?: string;
    model?: string;
};

export declare type SessionStartHookSpecificOutput = {
    hookEventName: 'SessionStart';
    additionalContext?: string;
    initialUserMessage?: string;
    watchPaths?: string[];
};

/**
 * Adapter for mirroring session transcripts to external storage.
 * The subprocess still writes to local disk (set CLAUDE_CONFIG_DIR=/tmp
 * for ephemeral local copy); the adapter receives a secondary copy.
 *
 * The SDK never deletes from your store unless you call deleteSession()
 * with delete? implemented. Retention is the adapter's responsibility —
 * implement TTL, S3 lifecycle policies, or scheduled cleanup according
 * to your compliance requirements (e.g., ZDR/HIPAA retention windows).
 * Local-disk transcripts under CLAUDE_CONFIG_DIR are swept by the
 * existing cleanupPeriodDays setting independently of this adapter.
 * @alpha
 */
export declare type SessionStore = {
    /**
     * Mirror a batch of transcript entries. Called AFTER the subprocess's
     * local write succeeds — durability is already guaranteed locally.
     *
     * Batches arrive at ~100ms cadence during active turns. Entries are
     * JSON-safe POJOs — one per line in the local JSONL file.
     *
     * Within a single process, persist entries in append-call order; across
     * concurrent processes, order is by storage commit time, not call time.
     *
     * Most entries carry a stable `uuid`. Adapters SHOULD treat `uuid` as an
     * idempotency key (upsert / ignore-duplicate) so that retries and
     * `importSessionToStore()` replays do not create duplicate rows. Entries
     * without a `uuid` (e.g. titles, tags, mode markers) should be appended
     * without dedup.
     *
     * Rejection is retried (3 attempts total) with short backoff; timeouts
     * (60s) are not retried since the in-flight call may still land. After
     * the final failure the batch is dropped and a `mirror_error` system
     * message is emitted. The subprocess continues unaffected.
     */
    append(key: SessionKey, entries: SessionStoreEntry[]): Promise<void>;
    /**
     * Load a full session for resume. Called once, in the SDK parent, before
     * subprocess spawn. The result is materialized to a temporary JSONL file;
     * the subprocess resumes from that file using its existing resume code.
     *
     * Return `null` for a key that was never written; adapters that cannot
     * distinguish "never written" from "emptied" (e.g. Redis LRANGE) may
     * return `null` for both. Returned entries must be deep-equal to what was
     * appended — byte-equal serialization is NOT required (e.g. Postgres
     * JSONB may reorder object keys); the SDK never hashes or byte-compares
     * entries.
     */
    load(key: SessionKey): Promise<SessionStoreEntry[] | null>;
    /**
     * List sessions for a projectKey. Returns IDs + modification times.
     * `mtime` is Unix epoch milliseconds; adapters without native modification
     * time (e.g. Redis) must maintain their own index. Result order is
     * unspecified — the SDK sorts by mtime descending.
     * Optional — if undefined, listSessions() with a sessionStore throws.
     */
    listSessions?(projectKey: string): Promise<Array<{
        sessionId: string;
        mtime: number;
    }>>;
    /**
     * Return incrementally-maintained summaries for all sessions in one call.
     *
     * Stores should maintain these via {@link foldSessionSummary} inside
     * `append()`. When implemented, `listSessions({ sessionStore })` reads
     * all summary metadata in a single round-trip; when undefined, it falls
     * back to `listSessions()` + per-session `load()`.
     *
     * @remarks
     * Stores that maintain summaries inside `append()` MUST serialize sidecar
     * writes if `append()` calls can race for the same session — e.g., wrap the
     * read-fold-write in a transaction/CAS or hold a per-session lock.
     * `foldSessionSummary` is pure; concurrency control is the store's responsibility.
     * @alpha
     */
    listSessionSummaries?(projectKey: string): Promise<SessionSummaryEntry[]>;
    /**
     * Delete a session. Optional — if undefined, deletion is a no-op
     * (appropriate for WORM/append-only backends like S3).
     */
    delete?(key: SessionKey): Promise<void>;
    /**
     * List all subpath keys under a session (e.g., subagent transcripts).
     * Used during resume to discover and materialize all subagent data.
     * If undefined, resume only materializes the main transcript.
     */
    listSubkeys?(key: {
        projectKey: string;
        sessionId: string;
    }): Promise<string[]>;
};

/**
 * One JSONL transcript line as observed by a {@link SessionStore} adapter.
 *
 * The concrete entry shape is the on-disk transcript format (a large
 * discriminated union over `type` covering user/assistant messages, summaries,
 * titles, tags, mode changes, etc.). That union is CLI-internal and not part
 * of the SDK API surface, so this is exposed as a minimal structural supertype
 * — every entry has a string `type` discriminant, most carry a `uuid` and ISO
 * `timestamp`, and the rest of the payload is opaque JSON. Adapters should
 * treat entries as pass-through blobs; round-tripping `JSON.stringify` /
 * `JSON.parse` is the only required invariant.
 * @alpha
 */
export declare type SessionStoreEntry = {
    type: string;
    uuid?: string;
    timestamp?: string;
    [k: string]: unknown;
};

/**
 * Flush strategy for {@link Options.sessionStore} transcript mirroring.
 *
 * - `'batched'` (default): buffer transcript_mirror frames and flush at
 *   end-of-turn or when pending thresholds are exceeded.
 * - `'eager'`: schedule a background flush after every frame, giving
 *   near-real-time delivery to {@link SessionStore.append}. Each frame
 *   becomes its own `append()` batch (no coalescing), so adapters should
 *   be cheap per call.
 *
 * @alpha
 */
export declare type SessionStoreFlush = 'batched' | 'eager';

/**
 * Incrementally-maintained session summary.
 *
 * Stores update this on {@link SessionStore.append} via
 * {@link foldSessionSummary} and return the full set from
 * {@link SessionStore.listSessionSummaries}. Adapters never re-read
 * previously appended entries.
 * @alpha
 */
export declare type SessionSummaryEntry = {
    sessionId: string;
    /**
     * Storage write time of the sidecar on the adapter. Must share a clock
     * source with the `mtime` returned by `listSessions()` for this session —
     * typically file mtime, S3 LastModified, Postgres `updated_at`, or whatever
     * native timestamp the adapter surfaces. Do not derive from entry ISO
     * timestamps — entry timestamps and storage write times can differ by
     * batching and network latency, and conflating them defeats the staleness
     * check.
     */
    mtime: number;
    /** Opaque SDK-owned state. Stores MUST persist verbatim and MUST NOT interpret. */
    data: Record<string, unknown>;
};

/**
 * AUTO-GENERATED - DO NOT EDIT
 *
 * This file is auto-generated from the settings JSON schema.
 * To modify these types, edit SettingsSchema in src/utils/settings/types.ts and run:
 *
 *   bun scripts/generate-sdk-types.ts
 */
export declare interface Settings {
    /**
     * JSON Schema reference for Claude Code settings
     */
    $schema?: 'https://json.schemastore.org/claude-code-settings.json';
    /**
     * Path to a script that outputs authentication values
     */
    apiKeyHelper?: string;
    /**
     * Shell command that outputs a Proxy-Authorization header value (EAP)
     */
    proxyAuthHelper?: string;
    /**
     * Path to a script that exports AWS credentials
     */
    awsCredentialExport?: string;
    /**
     * Path to a script that refreshes AWS authentication
     */
    awsAuthRefresh?: string;
    /**
     * Command to refresh GCP authentication (e.g., gcloud auth application-default login)
     */
    gcpAuthRefresh?: string;
    /**
     * Executable that computes managed settings at startup. Honored only from admin-controlled policy sources.
     */
    policyHelper?: {
        /**
         * Absolute path to the helper executable
         */
        path: string;
        timeoutMs?: number;
        refreshIntervalMs?: 0 | number;
    };
    /**
     * Custom file suggestion configuration for \@ mentions
     */
    fileSuggestion?: {
        type: 'command';
        command: string;
    };
    /**
     * Whether file picker should respect .gitignore files (default: true). Note: .ignore files are always respected.
     */
    respectGitignore?: boolean;
    /**
     * Number of days to retain chat transcripts before automatic cleanup (default: 30). Minimum 1. Use a large value for long retention; use --no-session-persistence to disable transcript writes entirely.
     */
    cleanupPeriodDays?: number;
    /**
     * Per-skill description character cap in the skill listing sent to Claude (default: 1536). Descriptions longer than this are truncated. Raise to opt in to higher per-turn context cost.
     */
    skillListingMaxDescChars?: number;
    /**
     * Fraction of the context window (in characters) reserved for the skill listing sent to Claude (default: 0.01 = 1%). When the listing exceeds this, descriptions are shortened to fit. Raise to opt in to higher per-turn context cost.
     */
    skillListingBudgetFraction?: number;
    /**
     * When set to true in either admin-only Windows source — the HKLM SOFTWARE/Policies/ClaudeCode registry key or C:/Program Files/ClaudeCode/managed-settings.json — WSL reads managed settings from the full Windows policy chain (HKLM, C:/Program Files/ClaudeCode via DrvFs, HKCU) in addition to /etc/claude-code. Windows sources take priority. The flag is also required in HKCU itself for HKCU policy to apply on WSL (double opt-in: admin enables the chain, user confirms HKCU). On native Windows the flag has no effect.
     */
    wslInheritsWindowsSettings?: boolean;
    /**
     * Environment variables to set for Claude Code sessions
     */
    env?: {
        [k: string]: string;
    };
    /**
     * Customize attribution text for commits and PRs. Each field defaults to the standard Claude Code attribution if not set.
     */
    attribution?: {
        /**
         * Attribution text for git commits, including any trailers. Empty string hides attribution.
         */
        commit?: string;
        /**
         * Attribution text for pull request descriptions. Empty string hides attribution.
         */
        pr?: string;
    };
    /**
     * Deprecated: Use attribution instead. Whether to include Claude's co-authored by attribution in commits and PRs (defaults to true)
     */
    includeCoAuthoredBy?: boolean;
    /**
     * Include built-in commit and PR workflow instructions in Claude's system prompt (default: true)
     */
    includeGitInstructions?: boolean;
    /**
     * Tool usage permissions configuration
     */
    permissions?: {
        /**
         * List of permission rules for allowed operations
         */
        allow?: string[];
        /**
         * List of permission rules for denied operations
         */
        deny?: string[];
        /**
         * List of permission rules that should always prompt for confirmation
         */
        ask?: string[];
        /**
         * Default permission mode when Claude Code needs access
         */
        defaultMode?: 'acceptEdits' | 'auto' | 'bypassPermissions' | 'default' | 'dontAsk' | 'plan';
        /**
         * Disable the ability to bypass permission prompts
         */
        disableBypassPermissionsMode?: 'disable';
        /**
         * Additional directories to include in the permission scope
         */
        additionalDirectories?: string[];
        [k: string]: unknown;
    };
    /**
     * Override the default model used by Claude Code
     */
    model?: string;
    /**
     * Allowlist of models that users can select. Accepts family aliases ("opus" allows any opus version), version prefixes ("opus-4-5" allows only that version), and full model IDs. If undefined, all models are available. If empty array, only the default model is available. Typically set in managed settings by enterprise administrators.
     */
    availableModels?: string[];
    /**
     * Override mapping from Anthropic model ID (e.g. "claude-opus-4-6") to provider-specific model ID (e.g. a Bedrock inference profile ARN). Typically set in managed settings by enterprise administrators.
     */
    modelOverrides?: {
        [k: string]: string;
    };
    /**
     * Whether to automatically approve all MCP servers in the project
     */
    enableAllProjectMcpServers?: boolean;
    /**
     * List of approved MCP servers from .mcp.json
     */
    enabledMcpjsonServers?: string[];
    /**
     * List of rejected MCP servers from .mcp.json
     */
    disabledMcpjsonServers?: string[];
    /**
     * Per-skill listing overrides keyed by skill name. "name-only" lists the skill without its description; "user-invocable-only" hides it from the model but keeps /name; "off" hides it from both. Absent = on.
     */
    skillOverrides?: {
        [k: string]: 'on' | 'name-only' | 'user-invocable-only' | 'off';
    };
    /**
     * Enterprise allowlist of MCP servers that can be used. Applies to all scopes including enterprise servers from managed-mcp.json. If undefined, all servers are allowed. If empty array, no servers are allowed. Denylist takes precedence - if a server is on both lists, it is denied.
     */
    allowedMcpServers?: {
        /**
         * Name of the MCP server that users are allowed to configure
         */
        serverName?: string;
        /**
         * Command array [command, ...args] to match exactly for allowed stdio servers
         *
         * \@minItems 1
         */
        serverCommand?: [string, ...string[]];
        /**
         * URL pattern with wildcard support (e.g., "https://*.example.com/*") for allowed remote MCP servers
         */
        serverUrl?: string;
    }[];
    /**
     * Enterprise denylist of MCP servers that are explicitly blocked. If a server is on the denylist, it will be blocked across all scopes including enterprise. Denylist takes precedence over allowlist - if a server is on both lists, it is denied.
     */
    deniedMcpServers?: {
        /**
         * Name of the MCP server that is explicitly blocked
         */
        serverName?: string;
        /**
         * Command array [command, ...args] to match exactly for blocked stdio servers
         *
         * \@minItems 1
         */
        serverCommand?: [string, ...string[]];
        /**
         * URL pattern with wildcard support (e.g., "https://*.example.com/*") for blocked remote MCP servers
         */
        serverUrl?: string;
    }[];
    /**
     * Custom commands to run before/after tool executions
     */
    hooks?: {
        [k: string]: {
            /**
             * String pattern to match (e.g. tool names like "Write")
             */
            matcher?: string;
            /**
             * List of hooks to execute when the matcher matches
             */
            hooks: ({
                /**
                 * Shell command hook type
                 */
                type: 'command';
                /**
                 * Shell command to execute
                 */
                command: string;
                /**
                 * Argument list for exec form. When present, `command` is resolved as an executable and spawned directly with these arguments — no shell. Path placeholders like ${CLAUDE_PLUGIN_ROOT} are substituted per-element as plain strings, so paths with quotes, $, or backticks never reach a shell parser. When absent, `command` runs through a shell (bash on POSIX, PowerShell on Windows without Git Bash).
                 */
                args?: string[];
                /**
                 * Permission rule syntax to filter when this hook runs (e.g., "Bash(git *)"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.
                 */
                if?: string;
                /**
                 * Shell interpreter. 'bash' uses your $SHELL (bash/zsh/sh); 'powershell' uses pwsh. Defaults to bash (powershell on Windows without Git Bash).
                 */
                shell?: 'bash' | 'powershell';
                /**
                 * Timeout in seconds for this specific command
                 */
                timeout?: number;
                /**
                 * Custom status message to display in spinner while hook runs
                 */
                statusMessage?: string;
                /**
                 * If true, hook runs once and is removed after execution
                 */
                once?: boolean;
                /**
                 * If true, hook runs in background without blocking
                 */
                async?: boolean;
                /**
                 * If true, hook runs in background and wakes the model on exit code 2 (blocking error). Implies async.
                 */
                asyncRewake?: boolean;


            } | {
                /**
                 * LLM prompt hook type
                 */
                type: 'prompt';
                /**
                 * Prompt to evaluate with LLM. Use $ARGUMENTS placeholder for hook input JSON.
                 */
                prompt: string;
                /**
                 * Permission rule syntax to filter when this hook runs (e.g., "Bash(git *)"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.
                 */
                if?: string;
                /**
                 * Timeout in seconds for this specific prompt evaluation
                 */
                timeout?: number;
                /**
                 * Model to use for this prompt hook (e.g., "claude-sonnet-4-6"). If not specified, uses the default small fast model.
                 */
                model?: string;
                /**
                 * Sets the continue value for the decision:"block" produced when ok is false. Default false (turn ends). Whether continue:true lets the turn proceed depends on the event's decision:"block" semantics. On PostToolUse, the reason is fed back to Claude and the turn continues.
                 */
                continueOnBlock?: boolean;
                /**
                 * Custom status message to display in spinner while hook runs
                 */
                statusMessage?: string;
                /**
                 * If true, hook runs once and is removed after execution
                 */
                once?: boolean;
            } | {
                /**
                 * Agentic verifier hook type
                 */
                type: 'agent';
                /**
                 * Prompt describing what to verify (e.g. "Verify that unit tests ran and passed."). Use $ARGUMENTS placeholder for hook input JSON.
                 */
                prompt: string;
                /**
                 * Permission rule syntax to filter when this hook runs (e.g., "Bash(git *)"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.
                 */
                if?: string;
                /**
                 * Timeout in seconds for agent execution (default 60)
                 */
                timeout?: number;
                /**
                 * Model to use for this agent hook (e.g., "claude-sonnet-4-6"). If not specified, uses Haiku.
                 */
                model?: string;
                /**
                 * Custom status message to display in spinner while hook runs
                 */
                statusMessage?: string;
                /**
                 * If true, hook runs once and is removed after execution
                 */
                once?: boolean;
            } | {
                /**
                 * HTTP hook type
                 */
                type: 'http';
                /**
                 * URL to POST the hook input JSON to
                 */
                url: string;
                /**
                 * Permission rule syntax to filter when this hook runs (e.g., "Bash(git *)"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.
                 */
                if?: string;
                /**
                 * Timeout in seconds for this specific request
                 */
                timeout?: number;
                /**
                 * Additional headers to include in the request. Values may reference environment variables using $VAR_NAME or ${VAR_NAME} syntax (e.g., "Authorization": "Bearer $MY_TOKEN"). Only variables listed in allowedEnvVars will be interpolated.
                 */
                headers?: {
                    [k: string]: string;
                };
                /**
                 * Explicit list of environment variable names that may be interpolated in header values. Only variables listed here will be resolved; all other $VAR references are left as empty strings. Required for env var interpolation to work.
                 */
                allowedEnvVars?: string[];
                /**
                 * Custom status message to display in spinner while hook runs
                 */
                statusMessage?: string;
                /**
                 * If true, hook runs once and is removed after execution
                 */
                once?: boolean;
            } | {
                /**
                 * MCP tool hook type
                 */
                type: 'mcp_tool';
                /**
                 * Name of an already-configured MCP server to invoke
                 */
                server: string;
                /**
                 * Name of the tool on that server to call
                 */
                tool: string;
                /**
                 * Arguments passed to the MCP tool. String values support ${path} interpolation from the hook input JSON (e.g. "${tool_input.file_path}").
                 */
                input?: {
                    [k: string]: unknown;
                };
                /**
                 * Permission rule syntax to filter when this hook runs (e.g., "Bash(git *)"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.
                 */
                if?: string;
                /**
                 * Timeout in seconds for this specific tool call
                 */
                timeout?: number;
                /**
                 * Custom status message to display in spinner while hook runs
                 */
                statusMessage?: string;
                /**
                 * If true, hook runs once and is removed after execution
                 */
                once?: boolean;
            })[];
        }[];
    };
    /**
     * Git worktree configuration for --worktree flag.
     */
    worktree?: {
        /**
         * Directories to symlink from main repository to worktrees to avoid disk bloat. Must be explicitly configured - no directories are symlinked by default. Common examples: "node_modules", ".cache", ".bin"
         */
        symlinkDirectories?: string[];
        /**
         * Directories to include when creating worktrees, via git sparse-checkout (cone mode). Dramatically faster in large monorepos — only the listed paths are written to disk.
         */
        sparsePaths?: string[];
        /**
         * Which ref new worktrees branch from. 'fresh' (default) branches from origin/<default-branch> for a clean tree. 'head' branches from your current local HEAD so unpushed commits and feature-branch state are present. Applies to --worktree, EnterWorktree, and agent isolation.
         */
        baseRef?: 'fresh' | 'head';
        /**
         * Isolation mode for background sessions in this repo. 'worktree' (default) blocks Edit/Write in the main checkout until EnterWorktree is called. 'none' lets background jobs edit the working copy directly.
         */
        bgIsolation?: 'worktree' | 'none';
    };
    /**
     * Disable all hooks and statusLine execution
     */
    disableAllHooks?: boolean;
    /**
     * Disable agent view (`claude agents`, `--bg`, /background, the on-demand daemon). Typically set in managed settings. Equivalent to CLAUDE_CODE_DISABLE_AGENT_VIEW=1.
     */
    disableAgentView?: boolean;
    /**
     * Disable Remote Control (claude.ai/code, `claude remote-control`, `--remote-control`/`--rc`, auto-start, and the in-session toggle). Typically set in managed settings.
     */
    disableRemoteControl?: boolean;
    /**
     * Disable inline shell execution in skills and custom slash commands from user, project, or plugin sources. Commands are replaced with a placeholder instead of being run.
     */
    disableSkillShellExecution?: boolean;
    /**
     * Default shell for input-box ! commands. Defaults to 'bash' on all platforms (no Windows auto-flip).
     */
    defaultShell?: 'bash' | 'powershell';
    /**
     * When true (and set in managed settings), only hooks from managed settings run. User, project, and local hooks are ignored.
     */
    allowManagedHooksOnly?: boolean;
    /**
     * Allowlist of URL patterns that HTTP hooks may target. Supports * as a wildcard (e.g. "https://hooks.example.com/*"). When set, HTTP hooks with non-matching URLs are blocked. If undefined, all URLs are allowed. If empty array, no HTTP hooks are allowed. Arrays merge across settings sources (same semantics as allowedMcpServers).
     */
    allowedHttpHookUrls?: string[];
    /**
     * Allowlist of environment variable names HTTP hooks may interpolate into headers. When set, each hook's effective allowedEnvVars is the intersection with this list. If undefined, no restriction is applied. Arrays merge across settings sources (same semantics as allowedMcpServers).
     */
    httpHookAllowedEnvVars?: string[];
    /**
     * When true (and set in managed settings), only permission rules (allow/deny/ask) from managed settings are respected. User, project, local, and CLI argument permission rules are ignored.
     */
    allowManagedPermissionRulesOnly?: boolean;
    /**
     * When true (and set in managed settings), allowedMcpServers is only read from managed settings. deniedMcpServers still merges from all sources, so users can deny servers for themselves. Users can still add their own MCP servers, but only the admin-defined allowlist applies.
     */
    allowManagedMcpServersOnly?: boolean;
    /**
     * When set in managed settings, blocks non-plugin customization sources for the listed surfaces. Array form locks specific surfaces (e.g. ["skills", "hooks"]); `true` locks all four; `false` is an explicit no-op. Blocked: ~/.claude/{surface}/, .claude/{surface}/ (project), settings.json hooks, .mcp.json. NOT blocked: managed (policySettings) sources, plugin-provided customizations. Composes with strictKnownMarketplaces for end-to-end admin control — plugins gated by marketplace allowlist, everything else blocked here.
     */
    strictPluginOnlyCustomization?: boolean | ('skills' | 'agents' | 'hooks' | 'mcp')[];
    /**
     * Custom status line display configuration
     */
    statusLine?: {
        type: 'command';
        command: string;
        padding?: number;
        /**
         * Re-run the status line command every N seconds in addition to event-driven updates
         */
        refreshInterval?: number;
        /**
         * Hide the built-in `-- INSERT --` / `-- VISUAL --` indicator below the prompt. Use this when your status line script renders `vim.mode` itself.
         */
        hideVimModeIndicator?: boolean;
    };
    /**
     * URL template for PR links in the footer badge and inline messages. Placeholders: {host} {owner} {repo} {number} {url}. Example: "https://reviews.example.com/{owner}/{repo}/pull/{number}"
     */
    prUrlTemplate?: string;
    /**
     * Custom per-subagent status line shown in the agent panel; receives row context as JSON on stdin
     */
    subagentStatusLine?: {
        type: 'command';
        command: string;
    };
    /**
     * Enabled plugins using plugin-id\@marketplace-id format. Example: { "formatter\@anthropic-tools": true }. Also supports extended format with version constraints. Settings precedence is user < project < local < flag < policy, so to disable a plugin that project settings enable, set it to false in .claude/settings.local.json — setting false in ~/.claude/settings.json is overridden by the project.
     */
    enabledPlugins?: {
        [k: string]: string[] | boolean | {
            [k: string]: unknown;
        };
    };
    /**
     * Additional marketplaces to make available for this repository. Typically used in repository .claude/settings.json to ensure team members have required plugin sources.
     */
    extraKnownMarketplaces?: {
        [k: string]: {
            /**
             * Where to fetch the marketplace from
             */
            source: {
                source: 'url';
                /**
                 * Direct URL to marketplace.json file
                 */
                url: string;
                /**
                 * Custom HTTP headers (e.g., for authentication)
                 */
                headers?: {
                    [k: string]: string;
                };
            } | {
                source: 'github';
                /**
                 * GitHub repository in owner/repo format
                 */
                repo: string;
                /**
                 * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                 */
                ref?: string;
                /**
                 * Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)
                 */
                path?: string;
                /**
                 * Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [".claude-plugin", "plugins"]. If omitted, the full repository is cloned.
                 */
                sparsePaths?: string[];
            } | {
                source: 'git';
                /**
                 * Full git repository URL
                 */
                url: string;
                /**
                 * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                 */
                ref?: string;
                /**
                 * Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)
                 */
                path?: string;
                /**
                 * Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [".claude-plugin", "plugins"]. If omitted, the full repository is cloned.
                 */
                sparsePaths?: string[];
            } | {
                source: 'npm';
                /**
                 * NPM package containing marketplace.json
                 */
                package: string;
            } | {
                source: 'file';
                /**
                 * Local file path to marketplace.json
                 */
                path: string;
            } | {
                source: 'directory';
                /**
                 * Local directory containing .claude-plugin/marketplace.json
                 */
                path: string;
            } | {
                source: 'skills-dir';
            } | {
                source: 'hostPattern';
                /**
                 * Regex pattern to match the host/domain extracted from any marketplace source type. For github sources, matches against "github.com". For git sources (SSH or HTTPS), extracts the hostname from the URL. Use in strictKnownMarketplaces to allow all marketplaces from a specific host (e.g., "^github\.mycompany\.com$").
                 */
                hostPattern: string;
            } | {
                source: 'pathPattern';
                /**
                 * Regex pattern matched against the .path field of file and directory sources. Use in strictKnownMarketplaces to allow filesystem-based marketplaces alongside hostPattern restrictions for network sources. Use ".*" to allow all filesystem paths, or a narrower pattern (e.g., "^/opt/approved/") to restrict to specific directories.
                 */
                pathPattern: string;
            } | {
                source: 'settings';
                /**
                 * Marketplace name. Must match the extraKnownMarketplaces key (enforced); the synthetic manifest is written under this name. Same validation as PluginMarketplaceSchema plus reserved-name rejection — validateOfficialNameSource runs after the disk write, too late to clean up.
                 */
                name: string;
                /**
                 * Plugin entries declared inline in settings.json
                 */
                plugins: {
                    /**
                     * Plugin name as it appears in the target repository
                     */
                    name: string;
                    /**
                     * Where to fetch the plugin from. Must be a remote source — relative paths have no marketplace repository to resolve against.
                     */
                    source: string | {
                        source: 'npm';
                        /**
                         * Package name (or url, or local path, or anything else that can be passed to `npm` as a package)
                         */
                        package: string;
                        /**
                         * Specific version or version range (e.g., ^1.0.0, ~2.1.0)
                         */
                        version?: string;
                        /**
                         * Custom NPM registry URL (defaults to using system default, likely npmjs.org)
                         */
                        registry?: string;
                    } | {
                        source: 'url';
                        /**
                         * Full git repository URL (https:// or git\@)
                         */
                        url: string;
                        /**
                         * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                         */
                        ref?: string;
                        /**
                         * Specific commit SHA to use
                         */
                        sha?: string;
                    } | {
                        source: 'github';
                        /**
                         * GitHub repository in owner/repo format
                         */
                        repo: string;
                        /**
                         * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                         */
                        ref?: string;
                        /**
                         * Specific commit SHA to use
                         */
                        sha?: string;
                    } | {
                        source: 'git-subdir';
                        /**
                         * Git repository: GitHub owner/repo shorthand, https://, or git\@ URL
                         */
                        url: string;
                        /**
                         * Subdirectory within the repo containing the plugin (e.g., "tools/claude-plugin"). Cloned sparsely using partial clone (--filter=tree:0) to minimize bandwidth for monorepos.
                         */
                        path: string;
                        /**
                         * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                         */
                        ref?: string;
                        /**
                         * Specific commit SHA to use
                         */
                        sha?: string;
                    } | {
                        source: 'unsupported';
                    };
                    description?: string;
                    version?: string;
                    strict?: boolean;
                }[];
                owner?: {
                    /**
                     * Display name of the plugin author or organization
                     */
                    name: string;
                    /**
                     * Contact email for support or feedback
                     */
                    email?: string;
                    /**
                     * Website, GitHub profile, or organization URL
                     */
                    url?: string;
                };
            };
            /**
             * Local cache path where marketplace manifest is stored (auto-generated if not provided)
             */
            installLocation?: string;
            /**
             * Whether to automatically update this marketplace and its installed plugins on startup
             */
            autoUpdate?: boolean;
        };
    };
    /**
     * Enterprise strict list of allowed marketplace sources. When set in managed settings, ONLY these exact sources can be added as marketplaces. The check happens BEFORE downloading, so blocked sources never touch the filesystem. Note: this is a policy gate only — it does NOT register marketplaces. To pre-register allowed marketplaces for users, also set extraKnownMarketplaces.
     */
    strictKnownMarketplaces?: ({
        source: 'url';
        /**
         * Direct URL to marketplace.json file
         */
        url: string;
        /**
         * Custom HTTP headers (e.g., for authentication)
         */
        headers?: {
            [k: string]: string;
        };
    } | {
        source: 'github';
        /**
         * GitHub repository in owner/repo format
         */
        repo: string;
        /**
         * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
         */
        ref?: string;
        /**
         * Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)
         */
        path?: string;
        /**
         * Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [".claude-plugin", "plugins"]. If omitted, the full repository is cloned.
         */
        sparsePaths?: string[];
    } | {
        source: 'git';
        /**
         * Full git repository URL
         */
        url: string;
        /**
         * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
         */
        ref?: string;
        /**
         * Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)
         */
        path?: string;
        /**
         * Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [".claude-plugin", "plugins"]. If omitted, the full repository is cloned.
         */
        sparsePaths?: string[];
    } | {
        source: 'npm';
        /**
         * NPM package containing marketplace.json
         */
        package: string;
    } | {
        source: 'file';
        /**
         * Local file path to marketplace.json
         */
        path: string;
    } | {
        source: 'directory';
        /**
         * Local directory containing .claude-plugin/marketplace.json
         */
        path: string;
    } | {
        source: 'skills-dir';
    } | {
        source: 'hostPattern';
        /**
         * Regex pattern to match the host/domain extracted from any marketplace source type. For github sources, matches against "github.com". For git sources (SSH or HTTPS), extracts the hostname from the URL. Use in strictKnownMarketplaces to allow all marketplaces from a specific host (e.g., "^github\.mycompany\.com$").
         */
        hostPattern: string;
    } | {
        source: 'pathPattern';
        /**
         * Regex pattern matched against the .path field of file and directory sources. Use in strictKnownMarketplaces to allow filesystem-based marketplaces alongside hostPattern restrictions for network sources. Use ".*" to allow all filesystem paths, or a narrower pattern (e.g., "^/opt/approved/") to restrict to specific directories.
         */
        pathPattern: string;
    } | {
        source: 'settings';
        /**
         * Marketplace name. Must match the extraKnownMarketplaces key (enforced); the synthetic manifest is written under this name. Same validation as PluginMarketplaceSchema plus reserved-name rejection — validateOfficialNameSource runs after the disk write, too late to clean up.
         */
        name: string;
        /**
         * Plugin entries declared inline in settings.json
         */
        plugins: {
            /**
             * Plugin name as it appears in the target repository
             */
            name: string;
            /**
             * Where to fetch the plugin from. Must be a remote source — relative paths have no marketplace repository to resolve against.
             */
            source: string | {
                source: 'npm';
                /**
                 * Package name (or url, or local path, or anything else that can be passed to `npm` as a package)
                 */
                package: string;
                /**
                 * Specific version or version range (e.g., ^1.0.0, ~2.1.0)
                 */
                version?: string;
                /**
                 * Custom NPM registry URL (defaults to using system default, likely npmjs.org)
                 */
                registry?: string;
            } | {
                source: 'url';
                /**
                 * Full git repository URL (https:// or git\@)
                 */
                url: string;
                /**
                 * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                 */
                ref?: string;
                /**
                 * Specific commit SHA to use
                 */
                sha?: string;
            } | {
                source: 'github';
                /**
                 * GitHub repository in owner/repo format
                 */
                repo: string;
                /**
                 * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                 */
                ref?: string;
                /**
                 * Specific commit SHA to use
                 */
                sha?: string;
            } | {
                source: 'git-subdir';
                /**
                 * Git repository: GitHub owner/repo shorthand, https://, or git\@ URL
                 */
                url: string;
                /**
                 * Subdirectory within the repo containing the plugin (e.g., "tools/claude-plugin"). Cloned sparsely using partial clone (--filter=tree:0) to minimize bandwidth for monorepos.
                 */
                path: string;
                /**
                 * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                 */
                ref?: string;
                /**
                 * Specific commit SHA to use
                 */
                sha?: string;
            } | {
                source: 'unsupported';
            };
            description?: string;
            version?: string;
            strict?: boolean;
        }[];
        owner?: {
            /**
             * Display name of the plugin author or organization
             */
            name: string;
            /**
             * Contact email for support or feedback
             */
            email?: string;
            /**
             * Website, GitHub profile, or organization URL
             */
            url?: string;
        };
    })[];
    /**
     * Enterprise blocklist of marketplace sources. When set in managed settings, these exact sources are blocked from being added as marketplaces. The check happens BEFORE downloading, so blocked sources never touch the filesystem.
     */
    blockedMarketplaces?: ({
        source: 'url';
        /**
         * Direct URL to marketplace.json file
         */
        url: string;
        /**
         * Custom HTTP headers (e.g., for authentication)
         */
        headers?: {
            [k: string]: string;
        };
    } | {
        source: 'github';
        /**
         * GitHub repository in owner/repo format
         */
        repo: string;
        /**
         * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
         */
        ref?: string;
        /**
         * Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)
         */
        path?: string;
        /**
         * Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [".claude-plugin", "plugins"]. If omitted, the full repository is cloned.
         */
        sparsePaths?: string[];
    } | {
        source: 'git';
        /**
         * Full git repository URL
         */
        url: string;
        /**
         * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
         */
        ref?: string;
        /**
         * Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)
         */
        path?: string;
        /**
         * Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [".claude-plugin", "plugins"]. If omitted, the full repository is cloned.
         */
        sparsePaths?: string[];
    } | {
        source: 'npm';
        /**
         * NPM package containing marketplace.json
         */
        package: string;
    } | {
        source: 'file';
        /**
         * Local file path to marketplace.json
         */
        path: string;
    } | {
        source: 'directory';
        /**
         * Local directory containing .claude-plugin/marketplace.json
         */
        path: string;
    } | {
        source: 'skills-dir';
    } | {
        source: 'hostPattern';
        /**
         * Regex pattern to match the host/domain extracted from any marketplace source type. For github sources, matches against "github.com". For git sources (SSH or HTTPS), extracts the hostname from the URL. Use in strictKnownMarketplaces to allow all marketplaces from a specific host (e.g., "^github\.mycompany\.com$").
         */
        hostPattern: string;
    } | {
        source: 'pathPattern';
        /**
         * Regex pattern matched against the .path field of file and directory sources. Use in strictKnownMarketplaces to allow filesystem-based marketplaces alongside hostPattern restrictions for network sources. Use ".*" to allow all filesystem paths, or a narrower pattern (e.g., "^/opt/approved/") to restrict to specific directories.
         */
        pathPattern: string;
    } | {
        source: 'settings';
        /**
         * Marketplace name. Must match the extraKnownMarketplaces key (enforced); the synthetic manifest is written under this name. Same validation as PluginMarketplaceSchema plus reserved-name rejection — validateOfficialNameSource runs after the disk write, too late to clean up.
         */
        name: string;
        /**
         * Plugin entries declared inline in settings.json
         */
        plugins: {
            /**
             * Plugin name as it appears in the target repository
             */
            name: string;
            /**
             * Where to fetch the plugin from. Must be a remote source — relative paths have no marketplace repository to resolve against.
             */
            source: string | {
                source: 'npm';
                /**
                 * Package name (or url, or local path, or anything else that can be passed to `npm` as a package)
                 */
                package: string;
                /**
                 * Specific version or version range (e.g., ^1.0.0, ~2.1.0)
                 */
                version?: string;
                /**
                 * Custom NPM registry URL (defaults to using system default, likely npmjs.org)
                 */
                registry?: string;
            } | {
                source: 'url';
                /**
                 * Full git repository URL (https:// or git\@)
                 */
                url: string;
                /**
                 * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                 */
                ref?: string;
                /**
                 * Specific commit SHA to use
                 */
                sha?: string;
            } | {
                source: 'github';
                /**
                 * GitHub repository in owner/repo format
                 */
                repo: string;
                /**
                 * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                 */
                ref?: string;
                /**
                 * Specific commit SHA to use
                 */
                sha?: string;
            } | {
                source: 'git-subdir';
                /**
                 * Git repository: GitHub owner/repo shorthand, https://, or git\@ URL
                 */
                url: string;
                /**
                 * Subdirectory within the repo containing the plugin (e.g., "tools/claude-plugin"). Cloned sparsely using partial clone (--filter=tree:0) to minimize bandwidth for monorepos.
                 */
                path: string;
                /**
                 * Git branch or tag to use (e.g., "main", "v1.0.0"). Defaults to repository default branch.
                 */
                ref?: string;
                /**
                 * Specific commit SHA to use
                 */
                sha?: string;
            } | {
                source: 'unsupported';
            };
            description?: string;
            version?: string;
            strict?: boolean;
        }[];
        owner?: {
            /**
             * Display name of the plugin author or organization
             */
            name: string;
            /**
             * Contact email for support or feedback
             */
            email?: string;
            /**
             * Website, GitHub profile, or organization URL
             */
            url?: string;
        };
    })[];
    /**
     * Force a specific login method: "claudeai" for Claude Pro/Max, "console" for Console billing
     */
    forceLoginMethod?: 'claudeai' | 'console';
    /**
     * Controls whether the SDK parent tier (Options.managedSettings / --managed-settings) layers under this admin tier. "first-wins" (default): parent is dropped — admin tiers are the only policy source. "merge": parent's restrictive-only-filtered settings union under the admin winner. Has no effect when no admin tier exists (parent applies as the sole policy tier, still filtered restrictive-only).
     */
    parentSettingsBehavior?: 'first-wins' | 'merge';
    /**
     * Organization UUID to require for OAuth login. Accepts a single UUID string or an array of UUIDs (any one is permitted). When set in managed settings, login fails if the authenticated account does not belong to a listed organization.
     */
    forceLoginOrgUUID?: string | string[];
    /**
     * When set in managed settings, the CLI blocks startup until remote managed settings are freshly fetched, and exits if the fetch fails
     */
    forceRemoteSettingsRefresh?: boolean;
    /**
     * Path to a script that outputs OpenTelemetry headers
     */
    otelHeadersHelper?: string;
    /**
     * Controls the output style for assistant responses
     */
    outputStyle?: string;
    /**
     * Default transcript view mode on startup
     */
    viewMode?: 'default' | 'verbose' | 'focus';
    /**
     * Preferred language for Claude responses and voice dictation (e.g., "japanese", "spanish")
     */
    language?: string;
    /**
     * Skip the WebFetch blocklist check for enterprise environments with restrictive security policies
     */
    skipWebFetchPreflight?: boolean;
    sandbox?: {
        enabled?: boolean;
        /**
         * Exit with an error at startup if sandbox.enabled is true but the sandbox cannot start (missing dependencies or unsupported platform). When false (default), a warning is shown and commands run unsandboxed. Intended for managed-settings deployments that require sandboxing as a hard gate.
         */
        failIfUnavailable?: boolean;
        autoAllowBashIfSandboxed?: boolean;
        /**
         * Allow commands to run outside the sandbox via the dangerouslyDisableSandbox parameter. When false, the dangerouslyDisableSandbox parameter is completely ignored and all commands must run sandboxed. Default: true.
         */
        allowUnsandboxedCommands?: boolean;
        network?: {
            allowedDomains?: string[];
            /**
             * Domains that are always blocked, even if matched by allowedDomains. Supports the same wildcard syntax as allowedDomains. Merged from all settings sources regardless of allowManagedDomainsOnly.
             */
            deniedDomains?: string[];
            /**
             * When true (and set in managed settings), only allowedDomains and WebFetch(domain:...) allow rules from managed settings are respected. User, project, local, and flag settings domains are ignored. Denied domains are still respected from all sources.
             */
            allowManagedDomainsOnly?: boolean;
            /**
             * macOS only: Unix socket paths to allow. Ignored on Linux (seccomp cannot filter by path).
             */
            allowUnixSockets?: string[];
            /**
             * If true, allow all Unix sockets (disables blocking on both platforms).
             */
            allowAllUnixSockets?: boolean;
            allowLocalBinding?: boolean;
            /**
             * macOS only: Additional XPC/Mach service names to allow looking up. Supports trailing-wildcard prefix matching (e.g., "com.apple.coresimulator.*"). Needed for tools that communicate via XPC such as the iOS Simulator or Playwright.
             */
            allowMachLookup?: string[];
            httpProxyPort?: number;
            socksProxyPort?: number;
            /**
             * [EXPERIMENTAL] Enable in-process TLS termination so the per-request filter can see HTTPS request bodies. Provide a CA cert+key, or omit both to have sandbox-runtime generate an ephemeral one for the session.
             */
            tlsTerminate?: {
                caCertPath?: string;
                caKeyPath?: string;
            };
        };
        filesystem?: {
            /**
             * Additional paths to allow writing within the sandbox. Merged with paths from Edit(...) allow permission rules.
             */
            allowWrite?: string[];
            /**
             * Additional paths to deny writing within the sandbox. Merged with paths from Edit(...) deny permission rules.
             */
            denyWrite?: string[];
            /**
             * Additional paths to deny reading within the sandbox. Merged with paths from Read(...) deny permission rules.
             */
            denyRead?: string[];
            /**
             * Paths to re-allow reading within denyRead regions. Takes precedence over denyRead for matching paths.
             */
            allowRead?: string[];
            /**
             * When true (set in managed settings), only allowRead paths from policySettings are used.
             */
            allowManagedReadPathsOnly?: boolean;
        };
        ignoreViolations?: {
            [k: string]: string[];
        };
        enableWeakerNestedSandbox?: boolean;
        /**
         * macOS only: Allow access to com.apple.trustd.agent in the sandbox. Needed for Go-based CLI tools (gh, gcloud, terraform, etc.) to verify TLS certificates when using httpProxyPort with a MITM proxy and custom CA. **Reduces security** — opens a potential data exfiltration vector through the trustd service. Default: false
         */
        enableWeakerNetworkIsolation?: boolean;
        excludedCommands?: string[];
        /**
         * Custom ripgrep configuration for bundled ripgrep support
         */
        ripgrep?: {
            command: string;
            args?: string[];
        };
        /**
         * Linux/WSL only: Absolute path to the bwrap (bubblewrap) binary. Overrides auto-detection via PATH. Only honored from admin-controlled managed settings.
         */
        bwrapPath?: string;
        /**
         * Linux/WSL only: Absolute path to the socat binary used for the sandbox network proxy. Overrides auto-detection via PATH. Only honored from admin-controlled managed settings.
         */
        socatPath?: string;
        [k: string]: unknown;
    };
    /**
     * Probability (0–1) that the session quality survey appears when eligible. 0.05 is a reasonable starting point.
     */
    feedbackSurveyRate?: number;
    /**
     * Whether to show tips in the spinner
     */
    spinnerTipsEnabled?: boolean;
    /**
     * Customize spinner verbs. mode: "append" adds verbs to defaults, "replace" uses only your verbs.
     */
    spinnerVerbs?: {
        mode: 'append' | 'replace';
        verbs: string[];
    };
    /**
     * Override spinner tips. tips: array of tip strings. excludeDefault: if true, only show custom tips (default: false).
     */
    spinnerTipsOverride?: {
        excludeDefault?: boolean;
        tips: string[];
    };
    /**
     * Whether to disable syntax highlighting in diffs
     */
    syntaxHighlightingDisabled?: boolean;
    /**
     * Whether /rename updates the terminal tab title (defaults to true). Set to false to keep auto-generated topic titles.
     */
    terminalTitleFromRename?: boolean;
    /**
     * When false, thinking is disabled. When absent or true, thinking is enabled automatically for supported models.
     */
    alwaysThinkingEnabled?: boolean;
    /**
     * Persisted effort level for supported models.
     */
    effortLevel?: 'low' | 'medium' | 'high' | 'xhigh';
    /**
     * Auto-compact window size
     */
    autoCompactWindow?: number;
    /**
     * Advisor model for the server-side advisor tool.
     */
    advisorModel?: string;
    /**
     * When true, fast mode is enabled. When absent or false, fast mode is off.
     */
    fastMode?: boolean;
    /**
     * When true, fast mode does not persist across sessions. Each session starts with fast mode off.
     */
    fastModePerSessionOptIn?: boolean;
    /**
     * When false, prompt suggestions are disabled. When absent or true, prompt suggestions are enabled.
     */
    promptSuggestionEnabled?: boolean;

    /**
     * When true, the plan-approval dialog offers a "clear context" option. Defaults to false.
     */
    showClearContextOnPlanAccept?: boolean;
    /**
     * Name of an agent (built-in or custom) to use for the main thread. Applies the agent's system prompt, tool restrictions, and model.
     */
    agent?: string;
    /**
     * Company announcements to display at startup (one will be randomly selected if multiple are provided)
     */
    companyAnnouncements?: string[];
    /**
     * Per-plugin configuration including MCP server user configs, keyed by plugin ID (plugin\@marketplace format)
     */
    pluginConfigs?: {
        [k: string]: {
            /**
             * User configuration values for MCP servers keyed by server name
             */
            mcpServers?: {
                [k: string]: {
                    [k: string]: string | number | boolean | string[];
                };
            };
            /**
             * Non-sensitive option values from plugin manifest userConfig, keyed by option name. Sensitive values go to secure storage instead.
             */
            options?: {
                [k: string]: string | number | boolean | string[];
            };
        };
    };
    /**
     * Remote session configuration
     */
    remote?: {
        /**
         * Default environment ID to use for remote sessions
         */
        defaultEnvironmentId?: string;
    };
    /**
     * Release channel for auto-updates (latest or stable)
     */
    autoUpdatesChannel?: 'latest' | 'stable' | 'rc';
    /**
     * Minimum version to stay on - prevents downgrades when switching to stable channel
     */
    minimumVersion?: string;
    /**
     * Custom directory for plan files, relative to project root. If not set, defaults to ~/.claude/plans/
     */
    plansDirectory?: string;
    /**
     * Terminal UI renderer. "fullscreen" uses the flicker-free alt-screen renderer with virtualized scrollback (equivalent to CLAUDE_CODE_NO_FLICKER=1). "default" uses the classic main-screen renderer.
     */
    tui?: 'default' | 'fullscreen';
    /**
     * Voice mode settings (hold-to-talk / tap-to-toggle dictation)
     */
    voice?: {
        enabled?: boolean;
        /**
         * 'hold' (default): hold to talk. 'tap': tap to start, tap to stop+submit.
         */
        mode?: 'hold' | 'tap';
        /**
         * Submit the prompt when hold-to-talk is released (hold mode only)
         */
        autoSubmit?: boolean;
    };
    /**
     * Managed-org opt-in for channel notifications (MCP servers with the claude/channel capability pushing inbound messages). claude.ai Teams/Enterprise: default off. Console: default on unless managed settings exist. Set true to allow; users then select servers via --channels.
     */
    channelsEnabled?: boolean;
    /**
     * Managed-org allowlist of channel plugins. When set, replaces the default Anthropic allowlist — admins decide which plugins may push inbound messages. Undefined falls back to the default. Requires channelsEnabled: true.
     */
    allowedChannelPlugins?: {
        marketplace: string;
        plugin: string;
    }[];
    /**
     * Reduce or disable animations for accessibility (spinner shimmer, flash effects, etc.)
     */
    prefersReducedMotion?: boolean;

    /**
     * Enable auto-memory for this project. When false, Claude will not read from or write to the auto-memory directory.
     */
    autoMemoryEnabled?: boolean;
    /**
     * Custom directory path for auto-memory storage. Supports ~/ prefix for home directory expansion. Ignored if set in projectSettings (checked-in .claude/settings.json) for security. When unset, defaults to ~/.claude/projects/<sanitized-cwd>/memory/.
     */
    autoMemoryDirectory?: string;
    /**
     * Enable background memory consolidation (auto-dream). When set, overrides the server-side default.
     */
    autoDreamEnabled?: boolean;
    /**
     * Show thinking summaries in the transcript view (ctrl+o). Default: false.
     */
    showThinkingSummaries?: boolean;
    /**
     * Whether the user has accepted the bypass permissions mode dialog
     */
    skipDangerousModePermissionPrompt?: boolean;
    /**
     * Disable auto mode
     */
    disableAutoMode?: 'disable';
    /**
     * SSH connection configurations for remote environments. Typically set in managed settings by enterprise administrators to pre-configure SSH connections for team members.
     */
    sshConfigs?: {
        /**
         * Unique identifier for this SSH config. Used to match configs across settings sources.
         */
        id: string;
        /**
         * Display name for the SSH connection
         */
        name: string;
        /**
         * SSH host in format "user\@hostname" or "hostname", or a host alias from ~/.ssh/config
         */
        sshHost: string;
        /**
         * SSH port (default: 22)
         */
        sshPort?: number;
        /**
         * Path to SSH identity file (private key)
         */
        sshIdentityFile?: string;
        /**
         * Default working directory on the remote host. Supports tilde expansion (e.g. ~/projects). If not specified, defaults to the remote user home directory. Can be overridden by the [dir] positional argument in `claude ssh <config> [dir]`.
         */
        startDirectory?: string;
    }[];
    /**
     * CLAUDE.md-style instructions injected as organization-managed memory. Only honored from managed/policy settings.
     */
    claudeMd?: string;
    /**
     * Glob patterns or absolute paths of CLAUDE.md files to exclude from loading. Patterns are matched against absolute file paths using picomatch. Only applies to User, Project, and Local memory types (Managed/policy files cannot be excluded). Examples: "/home/user/monorepo/CLAUDE.md", "** /code/CLAUDE.md", "** /some-dir/.claude/rules/**"
     */
    claudeMdExcludes?: string[];
    /**
     * Custom message to append to the plugin trust warning shown before installation. Only read from policy settings (managed-settings.json / MDM). Useful for enterprise administrators to add organization-specific context (e.g., "All plugins from our internal marketplace are vetted and approved.").
     */
    pluginTrustMessage?: string;
    /**
     * Color theme for the UI
     */
    theme?: ('auto' | 'dark' | 'light' | 'light-daltonized' | 'dark-daltonized' | 'light-ansi' | 'dark-ansi') | string;
    /**
     * Key binding mode for the prompt input
     */
    editorMode?: 'normal' | 'vim';
    /**
     * Show full tool output instead of truncated summaries
     */
    verbose?: boolean;
    /**
     * Preferred OS notification channel
     */
    preferredNotifChannel?: 'auto' | 'iterm2' | 'iterm2_with_bell' | 'terminal_bell' | 'kitty' | 'ghostty' | 'notifications_disabled';
    /**
     * Automatically compact conversation when context fills
     */
    autoCompactEnabled?: boolean;
    /**
     * Auto-scroll the conversation view to bottom (fullscreen mode only)
     */
    autoScrollEnabled?: boolean;
    /**
     * Snapshot files before edits so /rewind can restore them
     */
    fileCheckpointingEnabled?: boolean;
    /**
     * Show "Cooked for Nm Ns" after each assistant turn
     */
    showTurnDuration?: boolean;
    /**
     * Stamp each assistant message with its arrival time
     */
    showMessageTimestamps?: boolean;
    /**
     * Emit OSC 9;4 progress sequences during long operations
     */
    terminalProgressBarEnabled?: boolean;
    /**
     * Enable the todo / task tracking panel
     */
    todoFeatureEnabled?: boolean;
    /**
     * How spawned teammates execute (tmux, in-process, auto)
     */
    teammateMode?: 'auto' | 'tmux' | 'in-process';
    /**
     * Start Remote Control bridge automatically each session
     */
    remoteControlAtStartup?: boolean;
    /**
     * Require explicit approval before SendMessage can reach a peer session on another machine via Remote Control
     */
    isolatePeerMachines?: boolean;
    /**
     * When no background service is running: 'transient' spawns one for this login session; 'ask' offers to install it persistently
     */
    daemonColdStart?: 'transient' | 'ask';
    /**
     * Mirror local sessions to claude.ai as view-only (no remote control)
     */
    autoUploadSessions?: boolean;
    /**
     * Push to mobile when a permission prompt or question is waiting
     */
    inputNeededNotifEnabled?: boolean;
    /**
     * Allow Claude to push proactive mobile notifications
     */
    agentPushNotifEnabled?: boolean;
    /**
     * Prevent claude-cli:// protocol handler registration with the OS
     */
    disableDeepLinkRegistration?: 'disable';
    /**
     * Default transcript view: chat (SendUserMessage checkpoints only) or transcript (full)
     */
    defaultView?: 'chat' | 'transcript';
    [k: string]: unknown;
}

/**
 * Source for loading filesystem-based settings. 'user' - Global user settings (~/.claude/settings.json). 'project' - Project settings (.claude/settings.json). 'local' - Local settings (.claude/settings.local.json).
 */
export declare type SettingSource = 'user' | 'project' | 'local';

export declare type SetupHookInput = BaseHookInput & {
    hook_event_name: 'Setup';
    trigger: 'init' | 'maintenance';
};

export declare type SetupHookSpecificOutput = {
    hookEventName: 'Setup';
    additionalContext?: string;
};

/**
 * Information about an available skill (invoked via /command syntax).
 */
export declare type SlashCommand = {
    /**
     * Skill name (without the leading slash)
     */
    name: string;
    /**
     * Description of what the skill does
     */
    description: string;
    /**
     * Hint for skill arguments (e.g., "<file>")
     */
    argumentHint: string;
    /**
     * Alternate names that resolve to this command (e.g., /cost and /stats both resolve to /usage)
     */
    aliases?: string[];
};

/**
 * Represents a spawned process with stdin/stdout streams and lifecycle management.
 * Implementers provide this interface to abstract the process spawning mechanism.
 * ChildProcess already satisfies this interface.
 */
export declare interface SpawnedProcess {
    /** Writable stream for sending data to the process stdin */
    stdin: Writable;
    /** Readable stream for receiving data from the process stdout */
    stdout: Readable;
    /** Whether the process has been killed */
    readonly killed: boolean;
    /** Exit code if the process has exited, null otherwise */
    readonly exitCode: number | null;
    /**
     * Kill the process with the given signal
     * @param signal - The signal to send (e.g., 'SIGTERM', 'SIGKILL')
     */
    kill(signal: NodeJS.Signals): boolean;
    /**
     * Register a callback for when the process exits
     * @param event - Must be 'exit'
     * @param listener - Callback receiving exit code and signal
     */
    on(event: 'exit', listener: (code: number | null, signal: NodeJS.Signals | null) => void): void;
    /**
     * Register a callback for process errors
     * @param event - Must be 'error'
     * @param listener - Callback receiving the error
     */
    on(event: 'error', listener: (error: Error) => void): void;
    /**
     * Register a one-time callback for when the process exits
     */
    once(event: 'exit', listener: (code: number | null, signal: NodeJS.Signals | null) => void): void;
    once(event: 'error', listener: (error: Error) => void): void;
    /**
     * Remove an event listener
     */
    off(event: 'exit', listener: (code: number | null, signal: NodeJS.Signals | null) => void): void;
    off(event: 'error', listener: (error: Error) => void): void;
}

/**
 * Options passed to the spawn function.
 */
export declare interface SpawnOptions {
    /** Command to execute */
    command: string;
    /** Arguments to pass to the command */
    args: string[];
    /** Working directory */
    cwd?: string;
    /** Environment variables */
    env: {
        [envVar: string]: string | undefined;
    };
    /**
     * Abort signal for cancellation.
     *
     * This is a **forwarded** signal owned by `ProcessTransport`, not the
     * caller's `Options.abortController.signal` directly. It aborts only
     * after the SDK's graceful-close path has run: stdin EOF →
     * `GRACEFUL_EXIT_TIMEOUT_MS` (~2 s) grace window. Anything you hang on
     * it (Node `spawn({signal})` → `child.kill()`, VM/container teardown,
     * fetch cancellation) fires **after** the child has had a chance to
     * shut down cleanly via stdin close.
     *
     * Why: passing the caller's raw signal to Node `spawn()` registers
     * Node's own abort listener that calls `child.kill()` — on Windows
     * that's `TerminateProcess` (instant, uncatchable), and AbortSignal
     * listeners fire synchronously in registration order, so it would race
     * ahead of the SDK's stdin-EOF + grace path and the CLI's
     * `gracefulShutdown` would never run.
     *
     * If you need the caller's *immediate* signal (no grace), it's the
     * `AbortController` you passed to `Options.abortController` — capture
     * it in closure.
     */
    signal: AbortSignal;
}

/**
 * Pre-warms the CLI subprocess so the first `query()` resolves immediately.
 * Returns a {@link WarmQuery} handle.
 */
export declare function startup(_params?: {
    options?: Options;
    initializeTimeoutMs?: number;
}): Promise<WarmQuery>;

declare type StdoutMessage = coreTypes.SDKMessage | coreTypes.SDKPostTurnSummaryMessage | coreTypes.SDKTaskSummaryMessage | coreTypes.SDKTranscriptMirrorMessage | SDKControlResponse | SDKControlRequest | SDKControlCancelRequest | SDKKeepAliveMessage;

export declare type StopFailureHookInput = BaseHookInput & {
    hook_event_name: 'StopFailure';
    error: SDKAssistantMessageError;
    error_details?: string;
    last_assistant_message?: string;
};

export declare type StopHookInput = BaseHookInput & {
    hook_event_name: 'Stop';
    stop_hook_active: boolean;
    /**
     * Text content of the last assistant message before stopping. Avoids the need to read and parse the transcript file.
     */
    last_assistant_message?: string;
    /**
     * In-flight background work (running/pending + backgrounded) registered in this session. Lets hooks distinguish "session is done" from "session is paused waiting for background work to wake it". Empty array when nothing is in flight.
     */
    background_tasks?: BackgroundTaskSummary[];
    /**
     * Session-scoped cron tasks (CronCreate, ScheduleWakeup, /loop) that will wake this session later. Empty array when none are scheduled.
     */
    session_crons?: SessionCronSummary[];


};

export declare type SubagentStartHookInput = BaseHookInput & {
    hook_event_name: 'SubagentStart';
    agent_id: string;
    agent_type: string;
};

export declare type SubagentStartHookSpecificOutput = {
    hookEventName: 'SubagentStart';
    additionalContext?: string;
};

export declare type SubagentStopHookInput = BaseHookInput & {
    hook_event_name: 'SubagentStop';
    stop_hook_active: boolean;
    agent_id: string;
    agent_transcript_path: string;
    agent_type: string;
    /**
     * Text content of the last assistant message before stopping. Avoids the need to read and parse the transcript file.
     */
    last_assistant_message?: string;
    /**
     * In-flight background work (running/pending + backgrounded) registered in this session. Lets hooks distinguish "session is done" from "session is paused waiting for background work to wake it". Empty array when nothing is in flight.
     */
    background_tasks?: BackgroundTaskSummary[];
    /**
     * Session-scoped cron tasks (CronCreate, ScheduleWakeup, /loop) that will wake this session later. Empty array when none are scheduled.
     */
    session_crons?: SessionCronSummary[];


};

export declare type SyncHookJSONOutput = {
    continue?: boolean;
    suppressOutput?: boolean;
    stopReason?: string;
    decision?: 'approve' | 'block';
    systemMessage?: string;
    /**
     * A terminal escape sequence (e.g. OSC 9 / OSC 777 desktop-notification) for Claude Code to emit on your behalf. Only notification/title OSCs (0, 1, 2, 9, 99, 777) and BEL are permitted; anything else is dropped.
     */
    terminalSequence?: string;
    reason?: string;


    hookSpecificOutput?: PreToolUseHookSpecificOutput | UserPromptSubmitHookSpecificOutput | UserPromptExpansionHookSpecificOutput | SessionStartHookSpecificOutput | SetupHookSpecificOutput | SubagentStartHookSpecificOutput | PostToolUseHookSpecificOutput | PostToolUseFailureHookSpecificOutput | PostToolBatchHookSpecificOutput | PermissionDeniedHookSpecificOutput | NotificationHookSpecificOutput | PermissionRequestHookSpecificOutput | ElicitationHookSpecificOutput | ElicitationResultHookSpecificOutput | CwdChangedHookSpecificOutput | FileChangedHookSpecificOutput | WorktreeCreateHookSpecificOutput;
};

/**
 * Marker string that splits a custom `systemPrompt` into a static prefix
 * (eligible for cross-session prompt caching) and a dynamic suffix
 * (session-specific, not globally cached). Include this literal as a
 * standalone element of a `string[]` `systemPrompt` to opt in; blocks
 * before it get global cache scope, blocks after do not. See
 * `splitSysPromptPrefix` in `src/utils/api.ts`.
 */
export declare const SYSTEM_PROMPT_DYNAMIC_BOUNDARY = "__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__";

/**
 * Tag a session. Pass null to clear the tag.
 * @param sessionId - UUID of the session
 * @param tag - Tag string, or null to clear
 * @param options - `{ dir?: string }` project path; omit to search all projects
 */
export declare function tagSession(_sessionId: string, _tag: string | null, _options?: SessionMutationOptions): Promise<void>;

export declare type TaskCompletedHookInput = BaseHookInput & {
    hook_event_name: 'TaskCompleted';
    task_id: string;
    task_subject: string;
    task_description?: string;
    teammate_name?: string;
    team_name?: string;
};

export declare type TaskCreatedHookInput = BaseHookInput & {
    hook_event_name: 'TaskCreated';
    task_id: string;
    task_subject: string;
    task_description?: string;
    teammate_name?: string;
    team_name?: string;
};

export declare type TeammateIdleHookInput = BaseHookInput & {
    hook_event_name: 'TeammateIdle';
    teammate_name: string;
    team_name: string;
};

/**
 * Why the query loop terminated. Unset when the loop was bypassed (local slash command) or interrupted externally (budget/retry limits checked between yields).
 */
export declare type TerminalReason = 'blocking_limit' | 'rapid_refill_breaker' | 'prompt_too_long' | 'image_error' | 'model_error' | 'aborted_streaming' | 'aborted_tools' | 'stop_hook_prevented' | 'hook_stopped' | 'tool_deferred' | 'max_turns' | 'completed';

/**
 * Claude decides when and how much to think (Opus 4.6+).
 */
export declare type ThinkingAdaptive = {
    type: 'adaptive';
    display?: 'summarized' | 'omitted';
};

/**
 * Controls Claude's thinking/reasoning behavior. When set, takes precedence over the deprecated maxThinkingTokens.
 */
export declare type ThinkingConfig = ThinkingAdaptive | ThinkingEnabled | ThinkingDisabled;

/**
 * No extended thinking
 */
export declare type ThinkingDisabled = {
    type: 'disabled';
};

/**
 * Fixed thinking token budget (older models)
 */
export declare type ThinkingEnabled = {
    type: 'enabled';
    budgetTokens?: number;
    display?: 'summarized' | 'omitted';
};

export declare function tool<Schema extends AnyZodRawShape>(_name: string, _description: string, _inputSchema: Schema, _handler: (args: InferShape<Schema>, extra: unknown) => Promise<CallToolResult>, _extras?: {
    annotations?: ToolAnnotations;
    searchHint?: string;
    alwaysLoad?: boolean;
}): SdkMcpToolDefinition<Schema>;

/**
 * Per-tool configuration for built-in tools. Allows SDK consumers to
 * customize tool behavior that the CLI hardcodes.
 */
export declare type ToolConfig = {
    askUserQuestion?: {
        /**
         * Content format for the `preview` field on question options.
         * Controls what the model is instructed to emit and how the field is
         * described in the tool schema.
         *
         * - `'markdown'` — Markdown/ASCII content (CLI default, rendered in a monospace box)
         * - `'html'` — Self-contained HTML fragments (for web-based SDK consumers)
         *
         * @default 'markdown'
         */
        previewFormat?: 'markdown' | 'html';
    };
};

/**
 * Transport interface for Claude Code SDK communication
 * Abstracts the communication layer to support both process and WebSocket transports
 */
export declare interface Transport {
    /**
     * Write data to the transport
     * May be async for network-based transports
     */
    write(data: string): void | Promise<void>;
    /**
     * Close the transport connection and clean up resources
     * This also closes stdin if still open (eliminating need for endInput)
     */
    close(): void;
    /**
     * Check if transport is ready for communication
     */
    isReady(): boolean;
    /**
     * Read and parse messages from the transport
     * Each transport handles its own protocol and error checking
     */
    readMessages(): AsyncGenerator<StdoutMessage, void, unknown>;
    /**
     * End the input stream
     */
    endInput(): void;
    /**
     * Optional Disposable support. All built-in transports implement this
     * (delegating to close()), so `using transport = new ProcessTransport(...)`
     * works. Kept optional on the interface to avoid a breaking change for
     * external `implements Transport` consumers.
     */
    [Symbol.dispose]?(): void;
}

export declare type UserPromptExpansionHookInput = BaseHookInput & {
    hook_event_name: 'UserPromptExpansion';
    expansion_type: 'slash_command' | 'mcp_prompt';
    command_name: string;
    command_args: string;
    command_source?: string;
    prompt: string;
};

export declare type UserPromptExpansionHookSpecificOutput = {
    hookEventName: 'UserPromptExpansion';
    additionalContext?: string;
};

export declare type UserPromptSubmitHookInput = BaseHookInput & {
    hook_event_name: 'UserPromptSubmit';
    prompt: string;
    session_title?: string;
};

export declare type UserPromptSubmitHookSpecificOutput = {
    hookEventName: 'UserPromptSubmit';
    additionalContext?: string;
    sessionTitle?: string;
    /**
     * When decision is "block", omit the original prompt from the block message
     */
    suppressOriginalPrompt?: boolean;
};

/**
 * A pre-warmed query handle returned by `startup()`. The subprocess has
 * already been spawned and completed its initialize handshake, so calling
 * `query()` writes the prompt directly to a ready process — no startup
 * latency.
 */
export declare interface WarmQuery extends AsyncDisposable {
    /**
     * Send a prompt to the pre-warmed subprocess and return the Query.
     * Can only be called once per WarmQuery.
     */
    query(prompt: string | AsyncIterable<SDKUserMessage>): Query;
    /**
     * Close the subprocess without sending a prompt. Use this to discard a
     * warm query you no longer need.
     */
    close(): void;
}

export declare type WorktreeCreateHookInput = BaseHookInput & {
    hook_event_name: 'WorktreeCreate';
    name: string;
};

/**
 * Hook-specific output for the WorktreeCreate event. Provides the absolute path to the created worktree directory. Command hooks print the path on stdout instead.
 */
export declare type WorktreeCreateHookSpecificOutput = {
    hookEventName: 'WorktreeCreate';
    worktreePath: string;
};

export declare type WorktreeRemoveHookInput = BaseHookInput & {
    hook_event_name: 'WorktreeRemove';
    worktree_path: string;
};

export { }
