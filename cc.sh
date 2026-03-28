#!/bin/bash

# Claude Code Docker Runner
# Unified script to run Claude Code in Docker with multiple providers
#
# Usage:
#   ./cc.sh                             # DEFAULT_PROVIDER from .env or environment (default: glm)
#   ./cc.sh -b minimax                  # Use MiniMax provider (-b: avoid claude -p/--print)
#   ./cc.sh --provider kimi             # Use Kimi provider
#   ./cc.sh --workspace                 # Workspace mode (default provider)
#   ./cc.sh --rebuild                   # Rebuild Docker image (default provider)
#   ./cc.sh -b minimax --rebuild        # Rebuild MiniMax Docker image
#   ./cc.sh --provider kimi --path /path/to/project
#   ./cc.sh -b minimax -s dev          # Multiple sessions (short forms)
#   ./cc.sh --provider minimax --session test # Another session (same provider/folder)
#   ./cc.sh --worktree                  # Git worktree mode (auto-generated name)
#   ./cc.sh -w feature-auth             # Git worktree with custom name (shorthand)
#   ./cc.sh --worktree bugfix-123 --tmux # Git worktree with tmux session
#   ./cc.sh --init-env                   # Create .env from .env.example (repo dir only)
#   ./cc.sh -b minimax -p "fix lint"     # Script flags first; rest forwarded to claude (e.g. -p/--print)
#   ./cc.sh --native -b minimax          # Run host claude (not Docker); backup/restore ~/.claude/settings.json and ~/.claude.json

# Directory containing this script (resolve symlinks so ~/cc.sh -> repo/cc.sh finds repo/docker/)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    _dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    _link="$(readlink "$SOURCE")"
    case "$_link" in
        /*) SOURCE="$_link" ;;
        *) SOURCE="$_dir/$_link" ;;
    esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
SCRIPT_ENV_FILE="$SCRIPT_DIR/.env"
USER_ENV_FILE="$HOME/.env"
EXAMPLE_ENV_FILE="$SCRIPT_DIR/.env.example"

# Prefer ~/.env, fallback to local script .env when user-level is missing
if [ -f "$USER_ENV_FILE" ]; then
    ENV_FILE="$USER_ENV_FILE"
elif [ -f "$SCRIPT_ENV_FILE" ]; then
    ENV_FILE="$SCRIPT_ENV_FILE"
else
    ENV_FILE="$SCRIPT_ENV_FILE"
fi

# Default configuration (image build context next to this script)
DOCKERFILE_DIR="$SCRIPT_DIR/docker"
DEFAULT_API_TIMEOUT_MS="3000000"
DEFAULT_PROVIDER="glm"

# Load .env when present (~/.env preferred, else repo .env); if missing, rely on the current environment
if [ -f "$ENV_FILE" ]; then
    set -a
    TEMP_ENV=$(mktemp)
    grep -v '^[[:space:]]*#' "$ENV_FILE" | grep -v '^[[:space:]]*$' > "$TEMP_ENV"
    source "$TEMP_ENV"
    rm -f "$TEMP_ENV"
    set +a
fi
# Optional: set CC_DOCKERFILE_DIR in ~/.env if cc.sh lives outside the repo (copy without docker/)
if [ -n "${CC_DOCKERFILE_DIR:-}" ]; then
    DOCKERFILE_DIR="$CC_DOCKERFILE_DIR"
fi
DEFAULT_PROVIDER="${DEFAULT_PROVIDER:-glm}"

# Parse arguments
PROVIDER="$DEFAULT_PROVIDER"
WORKSPACE_MODE=false
REBUILD=false
PROJECT_DIR="$(pwd)"
SESSION_ID=""
USE_TMUX=false
INIT_ENV=false
NATIVE_MODE=false
# WORKTREE_NAME is intentionally unset by default - only set when --worktree is used
CLAUDE_FORWARD_ARGS=()

# Parse all arguments
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --native)
            NATIVE_MODE=true
            ;;
        --init-env)
            INIT_ENV=true
            ;;
        --provider|-b)
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
        --worktree|-w)
            next_idx=$((i+1))
            if [ $next_idx -le $# ] && [[ ! "${!next_idx}" =~ ^- ]]; then
                WORKTREE_NAME="${!next_idx}"
                i=$((i+1))  # Skip next argument as it's the worktree name
            else
                # Auto-generate worktree name if not provided
                WORKTREE_NAME=""
            fi
            ;;
        --tmux)
            USE_TMUX=true
            ;;
        --)
            i=$((i+1))
            while [ $i -le $# ]; do
                CLAUDE_FORWARD_ARGS+=("${!i}")
                i=$((i+1))
            done
            break
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --provider, -b PROVIDER  Provider to use: glm, minimax, kimi, qwen, or volcengine"
            echo "                           (short -b, not -p: claude uses -p for --print)"
            echo "                           Default: DEFAULT_PROVIDER from .env/environment, or glm if unset"
            echo "  --workspace             Workspace mode (use current directory)"
            echo "  --path PATH             Specific project directory"
            echo "  --rebuild               Force rebuild Docker image (works with or without --provider)"
            echo "  --session, -s ID        Session identifier for multiple sessions of same provider"
            echo "                          Allows running multiple containers with same provider/folder"
            echo "  --worktree, -w [NAME]   Git worktree mode for isolated parallel development"
            echo "                          Auto-generates name if not provided"
            echo "                          Worktrees created at <repo>/.claude/worktrees/<name>/"
            echo "  --tmux                  Launch in tmux session (use with --worktree)"
            echo "  --init-env              Copy .env.example to $SCRIPT_ENV_FILE and exit"
            echo "  --native                Run claude on the host (not Docker). Backs up then overrides"
            echo "                          ~/.claude/settings.json and ~/.claude.json with this script's"
            echo "                          provider env; restores them when claude exits."
            echo "  --help, -h              Show this help message"
            echo "  --                      End of cc.sh options; all following args go to claude only (native: avoids ambiguity)"
            echo "  ...                     Any other flags/args are forwarded to claude (use after cc.sh options)"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Run with GLM (default)"
            echo "  $0 --rebuild                         # Rebuild GLM image"
            echo "  $0 -b minimax                        # Run with MiniMax (short form)"
            echo "  $0 --provider kimi --rebuild        # Rebuild Kimi image"
            echo "  $0 -b qwen                           # Run with Qwen (short form)"
            echo "  $0 -b volcengine                     # Run with Volcengine/Ark (short form)"
            echo "  $0 -b minimax -s dev                # Run MiniMax with 'dev' session (short forms)"
            echo "  $0 --provider minimax --session test # Run another MiniMax session"
            echo "  $0 --worktree                        # Git worktree mode (auto-generated name)"
            echo "  $0 -w feature-auth                   # Git worktree with custom name (shorthand)"
            echo "  $0 --worktree bugfix-123 --tmux      # Git worktree with tmux session"
            echo "  $0 -b minimax -w refactor-api        # MiniMax provider with worktree"
            echo "  $0 --init-env                        # Bootstrap .env from .env.example"
            echo "  $0 --native -b minimax               # Host claude + MiniMax env in ~/.claude (restored after exit)"
            echo ""
            echo "Config: loads ~/.env if present, else $SCRIPT_ENV_FILE if present; otherwise use exported variables."
            echo "Global defaults (override per provider with PREFIX_* when needed):"
            echo "  DEFAULT_PROVIDER  API_TIMEOUT_MS  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
            echo "Each provider (PREFIX = GLM, MINIMAX, KIMI, QWEN, VOLCENGINE):"
            echo "  \${PREFIX}_API_KEY  \${PREFIX}_API_BASE_URL"
            echo "  optional: \${PREFIX}_API_TIMEOUT_MS  \${PREFIX}_CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC  \${PREFIX}_MODEL"
            echo "  \${PREFIX}_MODEL — if unset or empty, Anthropic model env vars are not passed to the container"
            echo ""
            echo "Any other arguments are passed through to claude inside the container (after script options)."
            echo "Put cc.sh flags first; e.g. $0 -b minimax -p \"prompt\" runs claude with --print."
            exit 0
            ;;
        *)
            CLAUDE_FORWARD_ARGS+=("$arg")
            ;;
    esac
    i=$((i+1))
done

if [ "$INIT_ENV" = true ]; then
    if [ ! -f "$EXAMPLE_ENV_FILE" ]; then
        echo "❌ Error: $EXAMPLE_ENV_FILE not found (cannot bootstrap .env)"
        exit 1
    fi
    if [ -f "$SCRIPT_ENV_FILE" ]; then
        echo "⚠️  $SCRIPT_ENV_FILE already exists. Remove or rename it, then run again."
        exit 1
    fi
    cp "$EXAMPLE_ENV_FILE" "$SCRIPT_ENV_FILE"
    echo "✅ Created $SCRIPT_ENV_FILE from .env.example"
    echo "   Fill in API keys for the provider(s) you use, then run: $0 -b <provider>"
    echo "   cc.sh prefers ~/.env when present; copy there if you want a user-wide config."
    exit 0
fi

# --- --native: backup/restore global Claude config (~/.claude/settings.json, ~/.claude.json) ---
NATIVE_RESTORE_RAN=0

native_restore() {
    [ "$NATIVE_RESTORE_RAN" = 1 ] && return
    NATIVE_RESTORE_RAN=1
    trap - EXIT INT TERM HUP
    local gs="$HOME/.claude/settings.json"
    local gj="$HOME/.claude.json"
    if [ -n "${NATIVE_SETTINGS_BACKUP:-}" ]; then
        mv -f "$NATIVE_SETTINGS_BACKUP" "$gs" 2>/dev/null || true
    elif [ "${NATIVE_SETTINGS_CREATED:-0}" = 1 ]; then
        rm -f "$gs" 2>/dev/null || true
    fi
    if [ -n "${NATIVE_CLAUDE_JSON_BACKUP:-}" ]; then
        mv -f "$NATIVE_CLAUDE_JSON_BACKUP" "$gj" 2>/dev/null || true
    elif [ "${NATIVE_CLAUDE_JSON_CREATED:-0}" = 1 ]; then
        rm -f "$gj" 2>/dev/null || true
    fi
}

native_backup_global_file() {
    local f="$1"
    local b="${f}.cc-sh-backup.$(date +%Y%m%d%H%M%S).$$"
    cp -p "$f" "$b" || return 1
    printf '%s\n' "$b"
}

# Absolute path: Docker resolves relative bind mounts from the client cwd; post-build `cd` must not break --path
if ! PROJECT_DIR_RESOLVED=$(cd "$PROJECT_DIR" && pwd); then
    echo "❌ Error: Cannot access project directory: $PROJECT_DIR"
    exit 1
fi
PROJECT_DIR="$PROJECT_DIR_RESOLVED"

# Validate provider
if [[ ! "$PROVIDER" =~ ^(glm|minimax|kimi|qwen|volcengine)$ ]]; then
    echo "❌ Error: Invalid provider '$PROVIDER'. Must be one of: glm, minimax, kimi, qwen, volcengine"
    exit 1
fi

# Provider settings: from .env if sourced above, else from the parent process environment

# Load provider-specific configuration (${PROVIDER_UPPER}_* from .env or environment)
PROVIDER_UPPER=$(echo "$PROVIDER" | tr '[:lower:]' '[:upper:]')
API_KEY_VAR="${PROVIDER_UPPER}_API_KEY"
API_BASE_URL_VAR="${PROVIDER_UPPER}_API_BASE_URL"
API_TIMEOUT_VAR="${PROVIDER_UPPER}_API_TIMEOUT_MS"
DISABLE_NONESSENTIAL_VAR="${PROVIDER_UPPER}_CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
MODEL_VAR="${PROVIDER_UPPER}_MODEL"

# All providers share the same Docker image (only runtime env vars differ)
IMAGE_NAME="claude-dev-container"
API_KEY="${!API_KEY_VAR}"
API_BASE_URL="${!API_BASE_URL_VAR}"
PROVIDER_MODEL="${!MODEL_VAR}"
if [ -n "$PROVIDER_MODEL" ]; then
    MODEL_DISPLAY="$PROVIDER_MODEL"
else
    MODEL_DISPLAY="(unset — $MODEL_VAR empty)"
fi

# API_TIMEOUT_MS: global default, unless PREFIX_API_TIMEOUT_MS is set
PROVIDER_API_TIMEOUT_MS="${!API_TIMEOUT_VAR}"
if [ -n "$PROVIDER_API_TIMEOUT_MS" ]; then
    API_TIMEOUT_MS="$PROVIDER_API_TIMEOUT_MS"
else
    API_TIMEOUT_MS="${API_TIMEOUT_MS:-$DEFAULT_API_TIMEOUT_MS}"
fi

# CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: global default, unless PREFIX_CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC is set
PROVIDER_DISABLE_NONESSENTIAL="${!DISABLE_NONESSENTIAL_VAR}"
if [ -n "$PROVIDER_DISABLE_NONESSENTIAL" ]; then
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="$PROVIDER_DISABLE_NONESSENTIAL"
else
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}"
fi

# Validate required variables
if [ -z "$API_KEY" ]; then
    echo "❌ Error: ${API_KEY_VAR} is not set (add to .env or export it before running)"
    exit 1
fi

if [ -z "$API_BASE_URL" ]; then
    echo "❌ Error: ${API_BASE_URL_VAR} is not set (add to .env or export it before running)"
    exit 1
fi

if [ "$NATIVE_MODE" = true ]; then
    if [ "$REBUILD" = true ]; then
        echo "ℹ️  --rebuild is ignored in --native mode."
    fi
    if ! command -v jq &> /dev/null; then
        echo "❌ Error: --native requires jq to write ~/.claude/settings.json."
        exit 1
    fi
    if ! command -v claude &> /dev/null; then
        echo "❌ Error: claude not found in PATH (install Claude Code CLI for --native)."
        exit 1
    fi
fi

# Project-local Claude only: never read, mount, or copy from ~/.claude
CLAUDE_DIR="$PROJECT_DIR/.claude"
CLAUDE_JSON="$PROJECT_DIR/.claude.json"

if [ "$NATIVE_MODE" != true ]; then
    echo "📁 Project-local Claude: $CLAUDE_DIR and $CLAUDE_JSON (host ~/.claude is unused)"

    # Minimal .claude.json stub if missing or empty — no import from global settings
    if [ ! -s "$CLAUDE_JSON" ]; then
        echo "{}" > "$CLAUDE_JSON"
    fi

    # Ensure plugins directory structure exists for Claude Code plugin installation
    # Claude Code expects: .claude/plugins/marketplaces/claude-plugins-official/external_plugins/
    if [ ! -d "$CLAUDE_DIR" ]; then
        echo "📁 Creating Claude directory: $CLAUDE_DIR"
        mkdir -p "$CLAUDE_DIR"
    fi

    # Create the full plugins directory structure that Claude Code expects
    PLUGINS_BASE_DIR="$CLAUDE_DIR/plugins"
    PLUGINS_MARKETPLACES_DIR="$PLUGINS_BASE_DIR/marketplaces"
    PLUGINS_OFFICIAL_DIR="$PLUGINS_MARKETPLACES_DIR/claude-plugins-official"
    PLUGINS_EXTERNAL_DIR="$PLUGINS_OFFICIAL_DIR/external_plugins"

    if [ ! -d "$PLUGINS_EXTERNAL_DIR" ]; then
        echo "📦 Creating plugins directory structure for Claude Code..."
        mkdir -p "$PLUGINS_EXTERNAL_DIR"
        # Ensure proper permissions (readable/writable by owner, readable by group/others)
        # This allows the node user in Docker to write to it
        chmod -R u+rwX "$PLUGINS_BASE_DIR" 2>/dev/null || true
        echo "✅ Created: $PLUGINS_EXTERNAL_DIR"
    fi

    # Remove env/hooks from project settings.json so Docker-supplied env wins
    CLAUDE_SETTINGS_JSON="$CLAUDE_DIR/settings.json"
    if [ -f "$CLAUDE_SETTINGS_JSON" ]; then
    # Check if jq is available
    if command -v jq &> /dev/null; then
        # Use jq to remove env and hooks sections
        if jq -e '.env or .hooks' "$CLAUDE_SETTINGS_JSON" &> /dev/null; then
            echo "🧹 Cleaning .claude/settings.json: removing env and hooks sections..."
            jq 'del(.env, .hooks)' "$CLAUDE_SETTINGS_JSON" > "${CLAUDE_SETTINGS_JSON}.tmp" && \
            mv "${CLAUDE_SETTINGS_JSON}.tmp" "$CLAUDE_SETTINGS_JSON"
            echo "✅ Settings cleaned - environment variables will be loaded from Docker"
        fi
    elif command -v python3 &> /dev/null; then
        # Fallback to Python if jq is not available
        if python3 -c "import json, sys; data=json.load(open('$CLAUDE_SETTINGS_JSON')); sys.exit(0 if ('env' in data or 'hooks' in data) else 1)" 2>/dev/null; then
            echo "🧹 Cleaning .claude/settings.json: removing env and hooks sections..."
            TEMP_PY_SCRIPT=$(mktemp)
            cat > "$TEMP_PY_SCRIPT" << 'PYEOF'
import json
import sys

settings_file = sys.argv[1]
try:
    with open(settings_file, 'r') as f:
        data = json.load(f)
    
    # Remove env and hooks sections if they exist
    if 'env' in data:
        del data['env']
    if 'hooks' in data:
        del data['hooks']
    
    # Write back
    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f'Warning: Could not clean settings.json: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF
            python3 "$TEMP_PY_SCRIPT" "$CLAUDE_SETTINGS_JSON"
            PY_EXIT_CODE=$?
            rm -f "$TEMP_PY_SCRIPT"
            if [ $PY_EXIT_CODE -eq 0 ]; then
                echo "✅ Settings cleaned - environment variables will be loaded from Docker"
            fi
        fi
    else
        echo "⚠️  Warning: Neither jq nor python3 found. Cannot clean settings.json automatically."
        echo "   Please manually remove 'env' and 'hooks' sections from $CLAUDE_SETTINGS_JSON"
    fi
    fi
fi

# Validate Git repository when using worktree mode (linked worktrees use a .git file, not a directory)
if [ -n "${WORKTREE_NAME+x}" ]; then
    if [ ! -e "$PROJECT_DIR/.git" ]; then
        echo "❌ Error: Git worktree mode requires a Git repository"
        echo "   Project directory '$PROJECT_DIR' is not a Git repository"
        echo "   Please initialize a Git repository first: git init"
        exit 1
    fi
fi

# Build Claude CLI arguments (worktree/tmux). Docker always prepends --dangerously-skip-permissions.
# Native runs: forwarded args first, then these, so user claude flags are not overridden by script flags.
CLAUDE_ARGS=()
if [ -n "${WORKTREE_NAME+x}" ]; then
    if [ -n "$WORKTREE_NAME" ]; then
        CLAUDE_ARGS+=("--worktree" "$WORKTREE_NAME")
    else
        CLAUDE_ARGS+=("--worktree")
    fi
fi
if [ "$USE_TMUX" = true ]; then
    CLAUDE_ARGS+=("--tmux")
fi

# Show mode
if [ "$NATIVE_MODE" = true ]; then
    echo "🖥 Native mode: $PROJECT_DIR"
    echo "   Provider: $PROVIDER  |  Model: $MODEL_DISPLAY"
    echo "   ~/.claude/settings.json + ~/.claude.json: backup → override → restore on exit"
    if [ -n "$SESSION_ID" ]; then
        echo "🔖 Session: $SESSION_ID (informational; no separate container in native mode)"
    fi
    if [ -n "$WORKTREE_NAME" ]; then
        echo "🌳 Worktree: $WORKTREE_NAME"
    elif [ "$WORKTREE_NAME" = "" ] && [ -n "${WORKTREE_NAME+x}" ]; then
        echo "🌳 Worktree: auto-generated"
    fi
    if [ "$USE_TMUX" = true ]; then
        echo "📺 Tmux: enabled"
    fi
    echo ""
elif [ "$WORKSPACE_MODE" = true ]; then
    echo "🚀 Starting Claude in WORKSPACE mode: $PROJECT_DIR"
    echo "   Provider: $PROVIDER"
    echo "   Model: $MODEL_DISPLAY"
    echo "   You can work with multiple projects from here"
    echo ""
else
    echo "🚀 Starting Claude in PROJECT mode: $PROJECT_DIR"
    echo "   Provider: $PROVIDER"
    echo "   Model: $MODEL_DISPLAY"
    echo ""
fi

if [ "$NATIVE_MODE" = true ]; then
    NATIVE_SETTINGS_BACKUP=""
    NATIVE_SETTINGS_CREATED=0
    NATIVE_CLAUDE_JSON_BACKUP=""
    NATIVE_CLAUDE_JSON_CREATED=0
    GLOBAL_SETTINGS="$HOME/.claude/settings.json"
    GLOBAL_CLAUDE_JSON="$HOME/.claude.json"
    if [ -f "$GLOBAL_SETTINGS" ]; then
        NATIVE_SETTINGS_BACKUP=$(native_backup_global_file "$GLOBAL_SETTINGS") || exit 1
        echo "📋 Backed up $GLOBAL_SETTINGS → $NATIVE_SETTINGS_BACKUP"
    else
        NATIVE_SETTINGS_CREATED=1
    fi
    mkdir -p "$HOME/.claude" || exit 1
    SETTINGS_TMP=$(mktemp) || exit 1
    if [ -n "$PROVIDER_MODEL" ]; then
        jq -n \
            --arg token "$API_KEY" \
            --arg base "$API_BASE_URL" \
            --arg timeout "$API_TIMEOUT_MS" \
            --arg cdt "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}" \
            --arg model "$PROVIDER_MODEL" \
            '{
                env: {
                    ANTHROPIC_BASE_URL: $base,
                    ANTHROPIC_AUTH_TOKEN: $token,
                    API_TIMEOUT_MS: $timeout,
                    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: (if $cdt == "" then 1 else ($cdt | tonumber) end),
                    ANTHROPIC_MODEL: $model,
                    ANTHROPIC_SMALL_FAST_MODEL: $model,
                    ANTHROPIC_DEFAULT_SONNET_MODEL: $model,
                    ANTHROPIC_DEFAULT_OPUS_MODEL: $model,
                    ANTHROPIC_DEFAULT_HAIKU_MODEL: $model
                }
            }' > "$SETTINGS_TMP" || { rm -f "$SETTINGS_TMP"; exit 1; }
    else
        jq -n \
            --arg token "$API_KEY" \
            --arg base "$API_BASE_URL" \
            --arg timeout "$API_TIMEOUT_MS" \
            --arg cdt "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}" \
            '{
                env: {
                    ANTHROPIC_BASE_URL: $base,
                    ANTHROPIC_AUTH_TOKEN: $token,
                    API_TIMEOUT_MS: $timeout,
                    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: (if $cdt == "" then 1 else ($cdt | tonumber) end)
                }
            }' > "$SETTINGS_TMP" || { rm -f "$SETTINGS_TMP"; exit 1; }
    fi
    mv "$SETTINGS_TMP" "$GLOBAL_SETTINGS" || exit 1
    echo "✅ Wrote provider env to $GLOBAL_SETTINGS"

    if [ -f "$GLOBAL_CLAUDE_JSON" ]; then
        NATIVE_CLAUDE_JSON_BACKUP=$(native_backup_global_file "$GLOBAL_CLAUDE_JSON") || exit 1
        echo "📋 Backed up $GLOBAL_CLAUDE_JSON → $NATIVE_CLAUDE_JSON_BACKUP"
        JSON_TMP=$(mktemp) || exit 1
        jq '. + {"hasCompletedOnboarding": true}' "$NATIVE_CLAUDE_JSON_BACKUP" > "$JSON_TMP" && \
            mv "$JSON_TMP" "$GLOBAL_CLAUDE_JSON" || { rm -f "$JSON_TMP"; exit 1; }
    else
        NATIVE_CLAUDE_JSON_CREATED=1
        echo '{"hasCompletedOnboarding": true}' > "$GLOBAL_CLAUDE_JSON" || exit 1
    fi
    echo "✅ Ensured hasCompletedOnboarding in $GLOBAL_CLAUDE_JSON"
    echo ""

    NATIVE_RESTORE_RAN=0
    trap native_restore EXIT INT TERM HUP
    cd "$PROJECT_DIR" || { native_restore; trap - EXIT INT TERM HUP; exit 1; }
    claude "${CLAUDE_FORWARD_ARGS[@]}" "${CLAUDE_ARGS[@]}"
    exit $?
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
        echo "   - Use a different provider: --provider minimax/kimi/glm/qwen/volcengine"
        echo "   - Use a session identifier: --session <name>"
        echo "   - Or stop the existing container"
        exit 1
    fi
fi

echo "📦 Image: $IMAGE_NAME (shared across all providers)"
echo "🐳 Container: $CONTAINER_NAME"
echo "🔑 Provider: $PROVIDER"
echo "🤖 Model: $MODEL_DISPLAY"
if [ -n "$SESSION_ID" ]; then
    echo "🔖 Session: $SESSION_ID"
fi
if [ -n "$WORKTREE_NAME" ]; then
    echo "🌳 Worktree: $WORKTREE_NAME"
elif [ "$WORKTREE_NAME" = "" ] && [ -n "${WORKTREE_NAME+x}" ]; then
    echo "🌳 Worktree: auto-generated"
fi
if [ "$USE_TMUX" = true ]; then
    echo "📺 Tmux: enabled"
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
        cd "$DOCKERFILE_DIR" || exit 1
        docker build -t "$IMAGE_NAME" . || exit 1
        echo "✅ Build complete!"
        cd "$PROJECT_DIR" || exit 1
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
    -e "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
    -e "CLAUDE_CODE_CONTAINER_MODE=1"
    -e "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
    -e "BYPASS_ALL_CONFIRMATIONS=1"
)

if [ -n "$PROVIDER_MODEL" ]; then
    DOCKER_ENV_ARGS+=(
        -e "ANTHROPIC_MODEL=$PROVIDER_MODEL"
        -e "ANTHROPIC_SMALL_FAST_MODEL=$PROVIDER_MODEL"
        -e "ANTHROPIC_DEFAULT_HAIKU_MODEL=$PROVIDER_MODEL"
        -e "ANTHROPIC_DEFAULT_SONNET_MODEL=$PROVIDER_MODEL"
        -e "ANTHROPIC_DEFAULT_OPUS_MODEL=$PROVIDER_MODEL"
    )
fi

# Bind project workspace and project-only Claude paths (same host dirs as /workspace/.claude*)
DOCKER_VOLUME_ARGS=(
    -v "$PROJECT_DIR:/workspace"
    -v "$CLAUDE_DIR:/home/node/.claude"
    -v "$CLAUDE_JSON:/home/node/.claude.json"
)

# Run Claude Code in Docker
docker run -it --rm \
    --name "$CONTAINER_NAME" \
    "${DOCKER_ENV_ARGS[@]}" \
    "${DOCKER_VOLUME_ARGS[@]}" \
    -w /workspace \
    --network host \
    "$IMAGE_NAME" \
    claude --dangerously-skip-permissions "${CLAUDE_ARGS[@]}" "${CLAUDE_FORWARD_ARGS[@]}"
