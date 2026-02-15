# Claude Docker Environment

A portable Docker-based development environment for [Claude Code](https://claude.ai/code) with multi-provider support, per-project configuration isolation, automatic container naming, and Chrome/Playwright support for browser automation.

## Features

- 🚀 **Multi-provider support** - GLM, MiniMax, and Kimi providers
- 🔧 **Unified script** - Single `cc.sh` script for all providers
- 📁 **Per-project settings** - Each project has isolated `.claude/` configuration
- 🐳 **Smart container naming** - Containers named by provider and folder (e.g., `minimax-project`, `kimi-project`)
- 🔄 **Multiple sessions** - Run multiple containers of the same provider on the same folder
- 🌐 **Chrome/Playwright** - Browser automation support built-in
- 📦 **Persistent npm packages** - Global npm installs survive container restarts
- 🔒 **Network host mode** - Full access to localhost services
- ⚙️ **Environment-based config** - Configuration via `.env` file

## Quick Start

### 1. Clone this repository

```bash
git clone git@github.com:hksay/claude-env.git
cd claude-env
```

### 2. Configure your API keys

The script uses a `.env` file for configuration. On first run, it will create a template:

```bash
./cc.sh
# Creates /Volumes/Dev/claude-env/.env with template values
```

Edit `/Volumes/Dev/claude-env/.env` and update the API keys:

```bash
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
```

### 3. Create a symlink (optional)

Create a symlink in your home directory for easy access:

```bash
ln -sf /Volumes/Dev/claude-env/cc.sh ~/cc.sh
```

### 4. Use in your projects

Run the script from any project directory:

```bash
cd /path/to/your-project
~/cc.sh                    # Use GLM provider (default)
~/cc.sh -p minimax         # Use MiniMax provider
~/cc.sh -p kimi            # Use Kimi provider
```

## Usage

### Basic Usage

```bash
# Default provider (GLM)
~/cc.sh

# Specify provider
~/cc.sh --provider minimax
~/cc.sh -p kimi              # Short form

# Workspace mode
~/cc.sh --workspace

# Custom project path
~/cc.sh --path /path/to/project

# Rebuild Docker image
~/cc.sh --rebuild
~/cc.sh -p minimax --rebuild
```

### Multiple Sessions

Run multiple containers of the same provider on the same folder:

```bash
# First session (default)
~/cc.sh -p minimax
# → Container: minimax-project

# Second session with session ID
~/cc.sh -p minimax -s dev
# → Container: minimax-project-dev

# Third session
~/cc.sh -p minimax -s test
# → Container: minimax-project-test
```

### Different Providers on Same Folder

Run different providers simultaneously on the same folder:

```bash
# Terminal 1
~/cc.sh -p minimax
# → Container: minimax-project

# Terminal 2
~/cc.sh -p kimi
# → Container: kimi-project

# Terminal 3
~/cc.sh -p glm
# → Container: glm-project
```

All three can run simultaneously with isolated settings.

## Command Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--provider PROVIDER` | `-p` | Provider to use: `glm`, `minimax`, or `kimi` (default: `glm`) |
| `--workspace` | | Workspace mode (use current directory) |
| `--path PATH` | | Specific project directory |
| `--rebuild` | | Force rebuild Docker image |
| `--session ID` | `-s` | Session identifier for multiple sessions |
| `--help` | `-h` | Show help message |

## Usage Modes

### Single Project Mode (Default)

```bash
cd /path/to/project
~/cc.sh
# Output: 🚀 Starting Claude in PROJECT mode: /path/to/project
#         🔑 Provider: glm
#         📦 Container name: glm-project
```

Each project gets its own isolated environment with per-project `.claude/` settings.

### Workspace Mode (Multi-project)

```bash
cd /path/to/workspace
~/cc.sh --workspace
# Output: 🚀 Starting Claude in WORKSPACE mode: /path/to/workspace
#         🔑 Provider: glm
#         📦 Container name: glm-workspace
```

Work with multiple projects from a single container.

### Custom Path Mode

```bash
~/cc.sh --path /absolute/path/to/project
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
└── .npm-global/          ← Persistent npm packages (auto-created)
```

## Container Naming

Containers are named using the pattern: `{provider}-{folder}-{session}`

| Scenario | Container Name |
|----------|---------------|
| GLM provider, folder `project` | `glm-project` |
| MiniMax provider, folder `project` | `minimax-project` |
| Kimi provider, folder `project` | `kimi-project` |
| MiniMax with session `dev` | `minimax-project-dev` |
| MiniMax with session `test` | `minimax-project-test` |

This ensures:
- Different providers on the same folder get different containers
- Multiple sessions of the same provider get different containers
- No conflicts between containers

## Container Management

### List running Claude containers

```bash
docker ps --filter "name=glm-\|minimax-\|kimi-"
```

### Stop a specific container

```bash
docker stop minimax-project
docker stop minimax-project-dev
```

### View container logs

```bash
docker logs minimax-project
```

### Attach to running container

If you try to run the same provider/folder/session combination, the script offers to attach to the existing container.

## Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `$PROJECT_DIR` | `/workspace` | Project files |
| `$PROJECT_DIR/.claude` | `/home/node/.claude` | Claude settings |
| `$PROJECT_DIR/.claude.json` | `/home/node/.claude.json` | Claude config |
| `$PROJECT_DIR/.npm-global` | `/usr/local/share/npm-global` | Global npm packages |

## Configuration

### Environment File (.env)

The script reads configuration from `/Volumes/Dev/claude-env/.env` (same directory as the script). This is a global shared configuration file used by all projects.

**Required variables for each provider:**

- `{PROVIDER}_API_KEY` - API key for the provider
- `{PROVIDER}_API_BASE_URL` - API endpoint URL
- `{PROVIDER}_IMAGE_NAME` - Docker image name (optional, defaults to `claude-dev-container`)
- `{PROVIDER}_API_TIMEOUT_MS` - API timeout in milliseconds (optional)

**MiniMax-specific:**

- `MINIMAX_MODEL` - Model name (e.g., `MiniMax-M2.1`)

### Environment Variables in Container

The script sets these environment variables in the container:

- `ANTHROPIC_AUTH_TOKEN` - Your API key
- `ANTHROPIC_BASE_URL` - Custom API endpoint
- `API_TIMEOUT_MS` - API timeout
- `CLAUDE_CODE_CONTAINER_MODE=1` - Enable container mode
- `BYPASS_ALL_CONFIRMATIONS=1` - Auto-confirm prompts
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` - Disable telemetry

**MiniMax-specific variables:**

- `ANTHROPIC_MODEL` - Model name
- `ANTHROPIC_SMALL_FAST_MODEL` - Fast model
- `ANTHROPIC_DEFAULT_SONNET_MODEL` - Sonnet model
- `ANTHROPIC_DEFAULT_OPUS_MODEL` - Opus model
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` - Haiku model

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
# Or use the script:
~/cc.sh --rebuild
```

## Examples

### Multiple Providers Simultaneously

```bash
# Terminal 1 - MiniMax
cd ~/dev/ai/agent
~/cc.sh -p minimax
# → Container: minimax-agent

# Terminal 2 - Kimi
cd ~/dev/ai/agent
~/cc.sh -p kimi
# → Container: kimi-agent

# Terminal 3 - GLM
cd ~/dev/ai/agent
~/cc.sh -p glm
# → Container: glm-agent
```

All three run independently with isolated settings on the same folder.

### Multiple Sessions of Same Provider

```bash
# Terminal 1 - Main session
cd ~/dev/ai/agent
~/cc.sh -p minimax
# → Container: minimax-agent

# Terminal 2 - Dev session
cd ~/dev/ai/agent
~/cc.sh -p minimax -s dev
# → Container: minimax-agent-dev

# Terminal 3 - Test session
cd ~/dev/ai/agent
~/cc.sh -p minimax -s test
# → Container: minimax-agent-test
```

## Troubleshooting

### Container name already exists

```
⚠️  Container 'minimax-project' is already running!
Do you want to attach to the running container? (y/N):
```

- Press `y` to attach to the existing container
- Press `N` to cancel, then:
  - Use a different provider: `~/cc.sh -p kimi`
  - Use a session ID: `~/cc.sh -p minimax -s dev`
  - Or stop the existing container: `docker stop minimax-project`

### Docker image not found

The script auto-builds the image if missing. If that fails:

```bash
cd docker/
docker build -t claude-dev-container .
# Or use the script:
~/cc.sh --rebuild
```

### API key not found

Make sure your `.env` file exists and contains the required variables:

```bash
cat /Volumes/Dev/claude-env/.env
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
