# Claude Code Transport Server Container
#
# This Dockerfile creates a container with:
# - Node.js 20 LTS
# - Claude CLI (latest)
# - Transport server
#
# Usage:
#   docker build -t claude-code-transport .
#   docker run -p 8080:8080 -e ANTHROPIC_API_KEY=sk-ant-... claude-code-transport
#
# Or with docker-compose:
#   docker-compose up

FROM node:20-slim

# Install dependencies for Claude CLI
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Claude CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Create app directory
WORKDIR /app

# Copy package files
COPY package.json ./

# Install transport server dependencies
RUN npm install --production

# Copy server code
COPY server.js ./

# Expose WebSocket port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "const ws = new (require('ws'))('ws://localhost:8080'); ws.on('open', () => { ws.close(); process.exit(0); }); ws.on('error', () => process.exit(1)); setTimeout(() => process.exit(1), 5000);"

# Run as non-root user for security
RUN useradd -m -s /bin/bash claude
USER claude

# Start the transport server
CMD ["node", "server.js"]
