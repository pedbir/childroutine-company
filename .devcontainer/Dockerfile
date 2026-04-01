FROM node:20-bookworm

# Install pnpm globally
RUN corepack enable && corepack prepare pnpm@9.15.0 --activate

# Install useful dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    vim \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Allow the "node" user to use sudo without password
RUN echo "node ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER node
WORKDIR /workspace
