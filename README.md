# Claude Docker Environment

A portable Docker-based development environment for [Claude Code](https://claude.ai/code) with per-project configuration isolation, automatic container naming, and Chrome/Playwright support for browser automation.

## Features

- 🚀 **Auto-build** - Builds Docker image automatically if not found
- 📁 **Per-project settings** - Each project has isolated `.claude/` configuration
- 🐳 **Smart container naming** - Containers named after folder (e.g., `c-claude-workspace`)
- 🔄 **Duplicate detection** - Prevents accidental duplicate containers
- 🌐 **Chrome/Playwright** - Browser automation support built-in
- 📦 **Persistent npm packages** - Global npm installs survive container restarts
- 🔒 **Network host mode** - Full access to localhost services

## Quick Start

### 1. Clone this repository

```bash
git clone git@github.com:hksay/claude-env.git
cd claude-env
```

### 2. Configure your API key

Edit `claude.sh` and update the `API_KEY` variable:

```bash
# Line 12: Replace with your actual API key
API_KEY="your-api-key-here"
```

### 3. Build the Docker image

```bash
# Build manually (or let the script auto-build on first run)
docker build -t claude-dev-container docker/
```

### 4. Use in your projects

Copy `claude.sh` to any project directory and run it:

```bash
cp claude.sh /path/to/your-project/
cd /path/to/your-project
./claude.sh
```

## Usage Modes

### Single Project Mode (Default)

```bash
cd /path/to/project
./claude.sh
# Output: 🚀 Starting Claude in PROJECT mode: /path/to/project
#         📦 Container name: c-claude-project
```

Each project gets its own isolated environment with per-project `.claude/` settings.

### Workspace Mode (Multi-project)

```bash
cd /path/to/workspace
./claude.sh --workspace
# Output: 🚀 Starting Claude in WORKSPACE mode: /path/to/workspace
#         📦 Container name: c-claude-workspace
```

Work with multiple projects from a single container.

### Custom Path Mode

```bash
./claude.sh --path /absolute/path/to/project
```

## Project Structure

```
your-project/
├── .claude/              ← Project-specific Claude settings
│   ├── commands/         ← Custom commands
│   ├── skills/           ← Custom skills
│   ├── plugins/          ← MCP servers
│   └── settings.json     ← Claude configuration
├── .claude.json          ← Project config
├── .npm-global/          ← Persistent npm packages (auto-created)
└── claude.sh             ← This script
```

## Container Management

### List running Claude containers

```bash
docker ps --filter "name=c-claude-"
```

### Stop a specific container

```bash
docker stop c-claude-workspace
```

### View container logs

```bash
docker logs c-claude-workspace
```

### Attach to running container

If you try to run the same project twice, the script offers to attach to the existing container.

## Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `$PROJECT_DIR` | `/workspace` | Project files |
| `$PROJECT_DIR/.claude` | `/home/node/.claude` | Claude settings |
| `$PROJECT_DIR/.claude.json` | `/home/node/.claude.json` | Claude config |
| `$PROJECT_DIR/.npm-global` | `/usr/local/share/npm-global` | Global npm packages |

## Copy Settings from Global Claude

To copy your existing global Claude settings to a project:

```bash
# From global to current project
cp -r ~/.claude/commands .claude/
cp -r ~/.claude/skills .claude/
cp -r ~/.claude/plugins .claude/
cp ~/.claude/settings.json .claude/
```

## Docker Image Details

The Dockerfile includes:

- **Base**: `node:20`
- **Dev tools**: git, zsh, fzf, vim, nano, jq, gh (GitHub CLI)
- **Playwright + Chromium**: For webapp-testing skill
- **Claude Code**: Latest version from npm
- **User**: Runs as non-root `node` user

### Rebuild with changes

```bash
cd docker/
docker build -t claude-dev-container .
```

## Configuration

Edit `claude.sh` to customize:

```bash
API_KEY="your-api-key-here"              # Your Anthropic API key
API_BASE_URL="https://..."                 # Custom API endpoint
IMAGE_NAME="claude-dev-container"          # Docker image name
```

### Environment Variables

The script sets these environment variables in the container:

- `ANTHROPIC_AUTH_TOKEN` - Your API key
- `ANTHROPIC_BASE_URL` - Custom API endpoint
- `CLAUDE_CODE_CONTAINER_MODE=1` - Enable container mode
- `BYPASS_ALL_CONFIRMATIONS=1` - Auto-confirm prompts
- `API_TIMEOUT_MS=300000` - 5-minute timeout
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` - Disable telemetry

## Examples

### Multiple Projects Simultaneously

```bash
# Terminal 1
cd ~/dev/ai/agent
./claude.sh
# → Container: c-claude-agent

# Terminal 2
cd ~/dev/ai/workspace
./claude.sh
# → Container: c-claude-workspace

# Terminal 3
cd ~/dev/bolthk/vibeocr
./claude.sh
# → Container: c-claude-vibeocr
```

All three run independently with isolated settings.

### Container Name Examples

| Folder | Container Name |
|--------|---------------|
| `/Users/kato/dev/ai/workspace` | `c-claude-workspace` |
| `/Users/kato/dev/ai/agent` | `c-claude-agent` |
| `/Users/kato/dev/my project` | `c-claude-my-project` |
| `/Users/kato/dev/test-123` | `c-claude-test-123` |

## Troubleshooting

### Container name already exists

```
⚠️  Container 'c-claude-workspace' is already running!
Do you want to attach to the running container? (y/N):
```

- Press `y` to attach to the existing container
- Press `N` to cancel (then stop the existing container if needed)

### Docker image not found

The script auto-builds the image if missing. If that fails:

```bash
cd docker/
docker build -t claude-dev-container .
```

### Permission issues

The script runs containers as the `node` user. Ensure your project files are readable:

```bash
chmod +r .claude/settings.json
```

## License

MIT

## Contributing

Contributions welcome! Feel free to open issues or PRs.
