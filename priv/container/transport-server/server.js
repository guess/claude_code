#!/usr/bin/env node

/**
 * Claude Code Transport Server
 *
 * WebSocket server that bridges remote connections to the Claude CLI.
 * Each WebSocket connection spawns a Claude CLI subprocess and streams
 * stdin/stdout bidirectionally.
 *
 * Usage:
 *   node server.js [options]
 *
 * Options:
 *   --port <port>     Port to listen on (default: 8080, or PORT env var)
 *   --host <host>     Host to bind to (default: 0.0.0.0)
 *   --claude <path>   Path to claude binary (default: 'claude' from PATH)
 *
 * Environment Variables:
 *   PORT              Server port (default: 8080)
 *   HOST              Server host (default: 0.0.0.0)
 *   CLAUDE_PATH       Path to claude binary
 *   ANTHROPIC_API_KEY API key for Claude (passed to subprocess)
 */

const { WebSocketServer } = require('ws');
const { spawn } = require('child_process');
const { parseArgs } = require('util');

// Parse command line arguments
const { values: args } = parseArgs({
  options: {
    port: { type: 'string', default: process.env.PORT || '8080' },
    host: { type: 'string', default: process.env.HOST || '0.0.0.0' },
    claude: { type: 'string', default: process.env.CLAUDE_PATH || 'claude' },
  },
});

const PORT = parseInt(args.port, 10);
const HOST = args.host;
const CLAUDE_PATH = args.claude;

// Track active connections for graceful shutdown
const activeConnections = new Map();

/**
 * Spawns a Claude CLI subprocess with streaming JSON mode.
 */
function spawnClaude() {
  const cliArgs = [
    '--output-format', 'stream-json',
    '--input-format', 'stream-json',
    '--verbose'
  ];

  const env = { ...process.env };

  // Ensure SDK identification
  env.CLAUDE_CODE_ENTRYPOINT = 'sdk-ex-remote';

  console.log(`[CLI] Spawning: ${CLAUDE_PATH} ${cliArgs.join(' ')}`);

  const proc = spawn(CLAUDE_PATH, cliArgs, {
    env,
    stdio: ['pipe', 'pipe', 'pipe']
  });

  return proc;
}

/**
 * Handles a new WebSocket connection.
 */
function handleConnection(ws, req) {
  const clientId = `${req.socket.remoteAddress}:${req.socket.remotePort}`;
  console.log(`[WS] New connection from ${clientId}`);

  // Spawn Claude CLI subprocess
  const claude = spawnClaude();
  let isClosing = false;

  activeConnections.set(ws, { claude, clientId });

  // Forward CLI stdout to WebSocket
  claude.stdout.on('data', (data) => {
    if (ws.readyState === ws.OPEN) {
      // Data may contain multiple lines; send each as a separate message
      const lines = data.toString().split('\n');
      for (const line of lines) {
        if (line.trim()) {
          ws.send(line);
        }
      }
    }
  });

  // Forward CLI stderr to WebSocket (as diagnostic messages)
  claude.stderr.on('data', (data) => {
    console.error(`[CLI ${clientId}] stderr: ${data}`);
    // Don't forward stderr to WebSocket - it's not valid JSON
  });

  // Handle CLI exit
  claude.on('close', (code, signal) => {
    console.log(`[CLI ${clientId}] Exited with code ${code}, signal ${signal}`);
    if (!isClosing && ws.readyState === ws.OPEN) {
      ws.close(1000, `CLI exited with code ${code}`);
    }
    activeConnections.delete(ws);
  });

  claude.on('error', (err) => {
    console.error(`[CLI ${clientId}] Error: ${err.message}`);
    if (ws.readyState === ws.OPEN) {
      ws.close(1011, `CLI error: ${err.message}`);
    }
    activeConnections.delete(ws);
  });

  // Forward WebSocket messages to CLI stdin
  ws.on('message', (data) => {
    const message = data.toString();
    console.log(`[WS ${clientId}] Received: ${message.slice(0, 100)}...`);

    if (claude.stdin.writable) {
      claude.stdin.write(message);
      // Add newline if not present (CLI expects newline-delimited JSON)
      if (!message.endsWith('\n')) {
        claude.stdin.write('\n');
      }
    } else {
      console.warn(`[WS ${clientId}] CLI stdin not writable`);
    }
  });

  // Handle WebSocket close
  ws.on('close', (code, reason) => {
    console.log(`[WS ${clientId}] Connection closed: ${code} ${reason}`);
    isClosing = true;

    // Terminate CLI subprocess
    if (!claude.killed) {
      claude.kill('SIGTERM');

      // Force kill if not terminated after 5 seconds
      setTimeout(() => {
        if (!claude.killed) {
          console.log(`[CLI ${clientId}] Force killing subprocess`);
          claude.kill('SIGKILL');
        }
      }, 5000);
    }

    activeConnections.delete(ws);
  });

  // Handle WebSocket errors
  ws.on('error', (err) => {
    console.error(`[WS ${clientId}] Error: ${err.message}`);
    if (!claude.killed) {
      claude.kill('SIGTERM');
    }
    activeConnections.delete(ws);
  });

  // Send connection acknowledgment
  ws.send(JSON.stringify({ type: 'connected', clientId }));
}

/**
 * Creates and starts the WebSocket server.
 */
function startServer() {
  const wss = new WebSocketServer({
    host: HOST,
    port: PORT,
    // Allow large messages for long conversations
    maxPayload: 100 * 1024 * 1024 // 100 MB
  });

  wss.on('connection', handleConnection);

  wss.on('error', (err) => {
    console.error(`[Server] Error: ${err.message}`);
  });

  wss.on('listening', () => {
    console.log(`[Server] Claude Code Transport Server listening on ws://${HOST}:${PORT}`);
    console.log(`[Server] Claude CLI path: ${CLAUDE_PATH}`);
    console.log(`[Server] Press Ctrl+C to stop`);
  });

  // Graceful shutdown
  const shutdown = (signal) => {
    console.log(`\n[Server] Received ${signal}, shutting down...`);

    // Close all active connections
    for (const [ws, { claude, clientId }] of activeConnections) {
      console.log(`[Server] Closing connection ${clientId}`);
      if (!claude.killed) {
        claude.kill('SIGTERM');
      }
      ws.close(1001, 'Server shutting down');
    }

    wss.close(() => {
      console.log('[Server] Server closed');
      process.exit(0);
    });

    // Force exit after 10 seconds
    setTimeout(() => {
      console.error('[Server] Forced exit after timeout');
      process.exit(1);
    }, 10000);
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  return wss;
}

// Start the server
startServer();
