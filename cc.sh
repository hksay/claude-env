#!/bin/bash

# Claude Code Docker Runner
# Unified script to run Claude Code in Docker with multiple providers
#
# Usage:
#   ./cc.sh                             # Use GLM provider (default)
#   ./cc.sh -p minimax                  # Use MiniMax provider (short form)
#   ./cc.sh --provider kimi             # Use Kimi provider
#   ./cc.sh --workspace                 # Workspace mode (default provider)
#   ./cc.sh --rebuild                   # Rebuild Docker image (default provider)
#   ./cc.sh -p minimax --rebuild        # Rebuild MiniMax Docker image
#   ./cc.sh --provider kimi --path /path/to/project
#   ./cc.sh -p minimax -s dev          # Multiple sessions (short forms)
#   ./cc.sh --provider minimax --session test # Another session (same provider/folder)

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Default configuration
DOCKERFILE_DIR="/Volumes/Dev/claude-env/docker"
DEFAULT_PROVIDER="glm"
DEFAULT_API_TIMEOUT_MS="300000"

# Parse arguments
PROVIDER="$DEFAULT_PROVIDER"
WORKSPACE_MODE=false
REBUILD=false
PROJECT_DIR="$(pwd)"
SESSION_ID=""

# Parse all arguments
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --provider|-p)
            if [ $((i+1)) -le $# ]; then
                next_idx=$((i+1))
                PROVIDER="${!next_idx}"
                i=$((i+1))  # Skip next argument as it's the provider value
            fi
            ;;
        --workspace)
            WORKSPACE_MODE=true
            PROJECT_DIR="$(pwd)"
            ;;
        --path)
            if [ $((i+1)) -le $# ]; then
                next_idx=$((i+1))
                PROJECT_DIR="${!next_idx}"
                i=$((i+1))  # Skip next argument as it's the path value
            fi
            ;;
        --rebuild)
            REBUILD=true
            ;;
        --session|-s)
            if [ $((i+1)) -le $# ]; then
                next_idx=$((i+1))
                SESSION_ID="${!next_idx}"
                i=$((i+1))  # Skip next argument as it's the session value
            fi
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --provider, -p PROVIDER  Provider to use: glm, minimax, or kimi (default: glm)"
            echo "                           Can be omitted - defaults to glm"
            echo "  --workspace             Workspace mode (use current directory)"
            echo "  --path PATH             Specific project directory"
            echo "  --rebuild               Force rebuild Docker image (works with or without --provider)"
            echo "  --session, -s ID        Session identifier for multiple sessions of same provider"
            echo "                          Allows running multiple containers with same provider/folder"
            echo "  --help, -h              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Run with GLM (default)"
            echo "  $0 --rebuild                         # Rebuild GLM image"
            echo "  $0 -p minimax                        # Run with MiniMax (short form)"
            echo "  $0 --provider kimi --rebuild        # Rebuild Kimi image"
            echo "  $0 -p minimax -s dev                # Run MiniMax with 'dev' session (short forms)"
            echo "  $0 --provider minimax --session test # Run another MiniMax session"
            echo ""
            echo "The script reads API keys and endpoints from $ENV_FILE"
            echo "Expected format:"
            echo "  GLM_API_KEY=your_key"
            echo "  GLM_API_BASE_URL=your_url"
            echo "  MINIMAX_API_KEY=your_key"
            echo "  MINIMAX_API_BASE_URL=your_url"
            echo "  KIMI_API_KEY=your_key"
            echo "  KIMI_API_BASE_URL=your_url"
            exit 0
            ;;
    esac
    i=$((i+1))
done

# Validate provider
if [[ ! "$PROVIDER" =~ ^(glm|minimax|kimi)$ ]]; then
    echo "❌ Error: Invalid provider '$PROVIDER'. Must be one of: glm, minimax, kimi"
    exit 1
fi

# Load environment variables from .env file
if [ -f "$ENV_FILE" ]; then
    # Export variables from .env file, handling comments and empty lines
    set -a
    # Create a temporary file with filtered content (no comments, no empty lines)
    TEMP_ENV=$(mktemp)
    grep -v '^[[:space:]]*#' "$ENV_FILE" | grep -v '^[[:space:]]*$' > "$TEMP_ENV"
    # Source the temporary file
    source "$TEMP_ENV"
    # Clean up
    rm -f "$TEMP_ENV"
    set +a
else
    echo "⚠️  Warning: .env file not found at $ENV_FILE"
    echo "   Creating a template .env file..."
    cat > "$ENV_FILE" << 'EOF'
# Claude Code Provider Configuration
# Extracted from cc.sh, cc-minimax.sh, and cc-kimi.sh
# Update these values with your actual API keys and endpoints

# GLM Provider
GLM_API_KEY=your_glm_api_key_here
GLM_API_BASE_URL=https://open.bigmodel.cn/api/anthropic
GLM_IMAGE_NAME=claude-dev-container
GLM_API_TIMEOUT_MS=300000

# MiniMax Provider
MINIMAX_API_KEY=your_minimax_api_key_here
MINIMAX_API_BASE_URL=https://api.minimaxi.com/anthropic
MINIMAX_IMAGE_NAME=claude-kimi-container
MINIMAX_API_TIMEOUT_MS=3000000
MINIMAX_MODEL=MiniMax-M2.1

# Kimi Provider
KIMI_API_KEY=your_kimi_api_key_here
KIMI_API_BASE_URL=https://api.kimi.com/coding/
KIMI_IMAGE_NAME=claude-kimi-container
KIMI_API_TIMEOUT_MS=300000
EOF
    echo "✅ Created template .env file at $ENV_FILE"
    echo "   Please update it with your API keys and endpoints, then run the script again."
    exit 1
fi

# Load provider-specific configuration
PROVIDER_UPPER=$(echo "$PROVIDER" | tr '[:lower:]' '[:upper:]')
API_KEY_VAR="${PROVIDER_UPPER}_API_KEY"
API_BASE_URL_VAR="${PROVIDER_UPPER}_API_BASE_URL"
IMAGE_NAME_VAR="${PROVIDER_UPPER}_IMAGE_NAME"
API_TIMEOUT_VAR="${PROVIDER_UPPER}_API_TIMEOUT_MS"

# Get values from environment (with defaults)
API_KEY="${!API_KEY_VAR}"
API_BASE_URL="${!API_BASE_URL_VAR}"
IMAGE_NAME="${!IMAGE_NAME_VAR:-claude-dev-container}"
API_TIMEOUT_MS="${!API_TIMEOUT_VAR:-$DEFAULT_API_TIMEOUT_MS}"

# Validate required variables
if [ -z "$API_KEY" ]; then
    echo "❌ Error: ${API_KEY_VAR} not found in .env file"
    exit 1
fi

if [ -z "$API_BASE_URL" ]; then
    echo "❌ Error: ${API_BASE_URL_VAR} not found in .env file"
    exit 1
fi

# Load MiniMax-specific model variables if provider is minimax
if [ "$PROVIDER" = "minimax" ]; then
    MINIMAX_MODEL="${MINIMAX_MODEL:-MiniMax-M2.1}"
    ANTHROPIC_MODEL="$MINIMAX_MODEL"
    ANTHROPIC_SMALL_FAST_MODEL="$MINIMAX_MODEL"
    ANTHROPIC_DEFAULT_SONNET_MODEL="$MINIMAX_MODEL"
    ANTHROPIC_DEFAULT_OPUS_MODEL="$MINIMAX_MODEL"
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$MINIMAX_MODEL"
fi

# Ensure .claude.json exists as a file with valid JSON
if [ ! -s "$PROJECT_DIR/.claude.json" ]; then
    echo "{}" > "$PROJECT_DIR/.claude.json"
fi

# Show mode
if [ "$WORKSPACE_MODE" = true ]; then
    echo "🚀 Starting Claude in WORKSPACE mode: $PROJECT_DIR"
    echo "   Provider: $PROVIDER"
    echo "   You can work with multiple projects from here"
    echo ""
else
    echo "🚀 Starting Claude in PROJECT mode: $PROJECT_DIR"
    echo "   Provider: $PROVIDER"
    echo ""
fi

# Generate container name with provider prefix to ensure uniqueness
FOLDER_NAME=$(basename "$PROJECT_DIR")
# Sanitize folder name: replace spaces and special chars with dashes
SANITIZED_FOLDER="${FOLDER_NAME//[^a-zA-Z0-9_-]/-}"
# Use provider as prefix to ensure different providers on same folder get different containers
# Add session ID if provided to allow multiple sessions of same provider
if [ -n "$SESSION_ID" ]; then
    SANITIZED_SESSION="${SESSION_ID//[^a-zA-Z0-9_-]/-}"
    CONTAINER_NAME="${PROVIDER}-${SANITIZED_FOLDER}-${SANITIZED_SESSION}"
else
    CONTAINER_NAME="${PROVIDER}-${SANITIZED_FOLDER}"
fi

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
        echo "❌ Cancelled. To run multiple sessions:"
        echo "   - Use a different provider: --provider minimax/kimi/glm"
        echo "   - Use a session identifier: --session <name>"
        echo "   - Or stop the existing container"
        exit 1
    fi
fi

echo "📦 Container name: $CONTAINER_NAME"
echo "🔑 Provider: $PROVIDER"
if [ -n "$SESSION_ID" ]; then
    echo "🔖 Session: $SESSION_ID"
fi
echo ""

# Build Docker image if it doesn't exist or --rebuild is specified
if [ "$REBUILD" = true ] || ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    if [ "$REBUILD" = true ]; then
        echo "🔨 Rebuilding Docker image '$IMAGE_NAME'..."
    else
        echo "📦 Docker image '$IMAGE_NAME' not found. Building..."
    fi
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

# Prepare docker run command with base environment variables
DOCKER_ENV_ARGS=(
    -e "ANTHROPIC_AUTH_TOKEN=$API_KEY"
    -e "ANTHROPIC_BASE_URL=$API_BASE_URL"
    -e "API_TIMEOUT_MS=$API_TIMEOUT_MS"
    -e "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
    -e "CLAUDE_CODE_CONTAINER_MODE=1"
    -e "BYPASS_ALL_CONFIRMATIONS=1"
)

# Add MiniMax-specific model environment variables if provider is minimax
if [ "$PROVIDER" = "minimax" ]; then
    DOCKER_ENV_ARGS+=(
        -e "ANTHROPIC_MODEL=$ANTHROPIC_MODEL"
        -e "ANTHROPIC_SMALL_FAST_MODEL=$ANTHROPIC_SMALL_FAST_MODEL"
        -e "ANTHROPIC_DEFAULT_SONNET_MODEL=$ANTHROPIC_DEFAULT_SONNET_MODEL"
        -e "ANTHROPIC_DEFAULT_OPUS_MODEL=$ANTHROPIC_DEFAULT_OPUS_MODEL"
        -e "ANTHROPIC_DEFAULT_HAIKU_MODEL=$ANTHROPIC_DEFAULT_HAIKU_MODEL"
    )
fi

# Run Claude Code in Docker
docker run -it --rm \
    --name "$CONTAINER_NAME" \
    "${DOCKER_ENV_ARGS[@]}" \
    -v "$PROJECT_DIR:/workspace" \
    -v "$PROJECT_DIR/.claude:/home/node/.claude" \
    -v "$PROJECT_DIR/.claude.json:/home/node/.claude.json" \
    -w /workspace \
    --network host \
    "$IMAGE_NAME" \
    claude --dangerously-skip-permissions
