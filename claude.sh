#!/bin/bash

# Claude Code Docker Runner
# Quick script to run Claude Code in Docker with custom API
#
# Usage:
#   ./claude.sh              # Single project mode (current directory)
#   ./claude.sh --workspace  # Workspace mode (use parent directory)
#   ./claude.sh --path /path/to/project  # Specific directory

# Configuration - Update these values
API_KEY="your-api-key-here"
API_BASE_URL="https://open.bigmodel.cn/api/anthropic"
IMAGE_NAME="claude-dev-container"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE_DIR="$SCRIPT_DIR/docker"

# Parse arguments
WORKSPACE_MODE=false
if [ "$1" = "--workspace" ]; then
    WORKSPACE_MODE=true
    PROJECT_DIR="$(pwd)"
elif [ "$1" = "--path" ] && [ -n "$2" ]; then
    PROJECT_DIR="$2"
else
    PROJECT_DIR="$(pwd)"
fi

# Ensure .claude.json exists as a file with valid JSON
if [ ! -s "$PROJECT_DIR/.claude.json" ]; then
    echo "{}" > "$PROJECT_DIR/.claude.json"
fi

# Show mode
if [ "$WORKSPACE_MODE" = true ]; then
    echo "🚀 Starting Claude in WORKSPACE mode: $PROJECT_DIR"
    echo "   You can work with multiple projects from here"
    echo ""
else
    echo "🚀 Starting Claude in PROJECT mode: $PROJECT_DIR"
    echo ""
fi

# Generate container name from folder name
FOLDER_NAME=$(basename "$PROJECT_DIR")
# Sanitize: replace spaces and special chars with dashes
CONTAINER_NAME="claude-${FOLDER_NAME//[^a-zA-Z0-9_-]/-}"
# Ensure name starts with letter
CONTAINER_NAME="${CONTAINER_NAME#^[-0-9]}"
CONTAINER_NAME="c-${CONTAINER_NAME}"

# Check if container with this name is already running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "⚠️  Container '$CONTAINER_NAME' is already running!"
    echo ""
    docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}"
    echo ""
    read -p "Do you want to attach to the running container? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🔗 Attaching to $CONTAINER_NAME..."
        docker attach "$CONTAINER_NAME"
        exit 0
    else
        echo "❌ Cancelled. To run multiple sessions, use a different folder or stop the existing container."
        exit 1
    fi
fi

echo "📦 Container name: $CONTAINER_NAME"
echo ""

# Build Docker image if it doesn't exist
if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    echo "📦 Docker image '$IMAGE_NAME' not found. Building..."
    if [ -f "$DOCKERFILE_DIR/Dockerfile" ]; then
        cd "$DOCKERFILE_DIR"
        docker build -t "$IMAGE_NAME" .
        echo "✅ Build complete!"
        cd "$PROJECT_DIR"
    else
        echo "❌ Error: Dockerfile not found at $DOCKERFILE_DIR/Dockerfile"
        exit 1
    fi
fi

# Run Claude Code in Docker
docker run -it --rm \
    --name "$CONTAINER_NAME" \
    -e ANTHROPIC_AUTH_TOKEN="$API_KEY" \
    -e ANTHROPIC_BASE_URL="$API_BASE_URL" \
    -e CLAUDE_CODE_CONTAINER_MODE=1 \
    -e BYPASS_ALL_CONFIRMATIONS=1 \
    -e API_TIMEOUT_MS=300000 \
    -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    -v "$PROJECT_DIR:/workspace" \
    -v "$PROJECT_DIR/.claude:/home/node/.claude" \
    -v "$PROJECT_DIR/.claude.json:/home/node/.claude.json" \
    -v "$PROJECT_DIR/.npm-global:/usr/local/share/npm-global" \
    -w /workspace \
    --network host \
    "$IMAGE_NAME" \
    claude --dangerously-skip-permissions
