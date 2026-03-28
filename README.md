# Claude Docker Environment

A portable Docker-based development environment for [Claude Code](https://claude.ai/code) with multi-provider support, project-local Claude config in Docker, automatic container naming, and Playwright browsers for automation.

## Features

- 🚀 **Multi-provider support** - GLM, MiniMax, Kimi, Qwen (DashScope), and Volcengine (Ark)
- 🔧 **Unified script** - Single `cc.sh` script for all providers
- 🐳 **Shared Docker image** - All providers use the same `claude-dev-container` image
- 📁 **Project-local Claude (Docker)** - Only the repo’s `.claude/` and `.claude.json` are mounted; host `~/.claude` is not used in the container
- 🐳 **Smart container naming** - Containers named by provider and folder (e.g., `minimax-myapp`, `qwen-myapp`)
- 🔄 **Multiple sessions** - Run multiple containers of the same provider on the same folder (`--session`)
- 🌳 **Git worktrees** - `--worktree` / `-w` with optional `--tmux` for parallel work
- 🖥 **Native mode** - `--native` runs host `claude` with temporary `~/.claude` / `~/.claude.json` override (restored on exit)
- 🌐 **Playwright** - Chromium, Firefox, and WebKit installed in the image
- 📦 **Persistent npm packages** - Global npm installs survive container restarts
- 🔒 **Network host mode** - Full access to localhost services
- ⚙️ **Environment-based config** - `~/.env` preferred, else repo `.env`; `CC_DOCKERFILE_DIR` when `cc.sh` lives outside the repo

## Quick Start

### 1. Clone this repository

```bash
git clone git@github.com:hksay/claude-env.git
cd claude-env
```

### 2. Configure your API keys

Bootstrap a repo-local `.env` from the tracked template (fails if `.env` already exists):

```bash
./cc.sh --init-env
```

**Where config is loaded:** if `~/.env` exists, it is used; otherwise the script uses `<repo>/.env` (next to `cc.sh`). You can copy `.env.example` to `~/.env` for a user-wide config.

Edit your `.env` and set keys for the providers you use. Global defaults and per-provider blocks match [`.env.example`](.env.example); abbreviated example:

```bash
# Global (optional overrides for every provider)
DEFAULT_PROVIDER=glm
API_TIMEOUT_MS=3000000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Per provider: PREFIX = GLM, MINIMAX, KIMI, QWEN, VOLCENGINE
# PREFIX_API_KEY, PREFIX_API_BASE_URL, PREFIX_MODEL (optional)
# Optional: PREFIX_API_TIMEOUT_MS, PREFIX_CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC

GLM_API_KEY=...
GLM_API_BASE_URL=https://open.bigmodel.cn/api/anthropic
GLM_MODEL=glm-5.1

MINIMAX_API_KEY=...
MINIMAX_API_BASE_URL=https://api.minimaxi.com/anthropic
MINIMAX_MODEL=MiniMax-M2.7

# Kimi, Qwen, Volcengine — see .env.example for base URLs and model names
```

If `PREFIX_MODEL` is unset or empty, `cc.sh` does not pass `ANTHROPIC_*` model environment variables into the container (or native settings).

**Copy `cc.sh` without the repo:** set `CC_DOCKERFILE_DIR` in `.env` to the absolute path of this repository’s `docker/` directory so the image can build.

### 3. Create a symlink (optional)

Create a symlink in your home directory for easy access:

```bash
ln -sf /Volumes/Dev/claude-env/cc.sh ~/cc.sh
```

### 4. Use in your projects

Run the script from any project directory:

```bash
cd /path/to/your-project
~/cc.sh                    # DEFAULT_PROVIDER from .env, or glm
~/cc.sh -b minimax         # MiniMax
~/cc.sh -b kimi            # Kimi
~/cc.sh -b qwen            # Qwen (DashScope coding endpoint)
~/cc.sh -b volcengine     # Volcengine Ark coding API
```

## Usage

### Basic Usage

```bash
# Default provider (DEFAULT_PROVIDER in .env, else glm)
~/cc.sh

# Specify provider (-b avoids claude’s -p / --print)
~/cc.sh --provider minimax
~/cc.sh -b kimi

# Workspace / path / rebuild
~/cc.sh --workspace
~/cc.sh --path /path/to/project
~/cc.sh --rebuild
~/cc.sh -b minimax --rebuild

# Git worktree (requires a Git repo); optional name and tmux
~/cc.sh --worktree
~/cc.sh -w feature-auth
~/cc.sh -b minimax --worktree bugfix-123 --tmux

# Native host CLI (not Docker); backs up and restores ~/.claude/settings.json and ~/.claude.json
~/cc.sh --native -b minimax

# Bootstrap repo .env from .env.example
~/cc.sh --init-env

# Forward args to claude (put cc.sh flags first); use -- to disambiguate
~/cc.sh -b minimax -p "fix lint"
~/cc.sh -b glm -- --help
```

### Multiple Sessions

Run multiple containers of the same provider on the same folder:

```bash
# First session (default)
~/cc.sh -b minimax
# → Container: minimax-project

# Second session with session ID
~/cc.sh -b minimax -s dev
# → Container: minimax-project-dev

# Third session
~/cc.sh -b minimax -s test
# → Container: minimax-project-test
```

### Different Providers on Same Folder

Run different providers simultaneously on the same folder:

```bash
# Terminal 1
~/cc.sh -b minimax
# → Container: minimax-project

# Terminal 2
~/cc.sh -b kimi
# → Container: kimi-project

# Terminal 3
~/cc.sh -b glm
# → Container: glm-project

# Qwen / Volcengine on the same folder get their own names, e.g. qwen-project, volcengine-project
```

All can run simultaneously with isolated containers; each project uses its own `.claude/` on disk.

## Command Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--provider PROVIDER` | `-b` | Provider: `glm`, `minimax`, `kimi`, `qwen`, or `volcengine`. Default: `DEFAULT_PROVIDER` from env, else `glm`. Use `-b` (not `-p`: Claude uses `-p` for `--print`). |
| `--workspace` | | Workspace mode (use current directory) |
| `--path PATH` | | Specific project directory |
| `--rebuild` | | Force rebuild Docker image |
| `--session ID` | `-s` | Session identifier for multiple sessions |
| `--worktree [NAME]` | `-w` | Git worktree mode; optional name, else auto-generated |
| `--tmux` | | Pass `--tmux` through to `claude` (typical with `--worktree`) |
| `--native` | | Run host `claude`; temporarily override global `~/.claude` / `~/.claude.json`, restore on exit |
| `--init-env` | | Copy `.env.example` to repo `.env` and exit (refuses if `.env` exists) |
| `--` | | End of `cc.sh` options; remaining args go only to `claude` |
| `--help` | `-h` | Show help message |

Any other arguments are forwarded to `claude` inside the container (after script options). Docker runs: `claude --dangerously-skip-permissions …`.

## Usage Modes

### Single Project Mode (Default)

```bash
cd /path/to/project
~/cc.sh
# Output: 🚀 Starting Claude in PROJECT mode: /path/to/project
#         Provider: glm
#         Model: …
#         📦 Image: …  🐳 Container: glm-project
```

Each project uses its own `.claude/` on disk, mounted into the container.

### Workspace Mode (Multi-project)

```bash
cd /path/to/workspace
~/cc.sh --workspace
# Output: 🚀 Starting Claude in WORKSPACE mode: /path/to/workspace
#         Provider: glm
#         Model: …
#         (container name is glm-<basename of workspace directory>)
```

Work with multiple projects from a single container.

### Custom Path Mode

```bash
~/cc.sh --path /absolute/path/to/project
```

### Git Worktree Mode

Requires a Git repository at the project directory. Forwards `--worktree` (and optional name) to `claude`. Combine with `-b` / `--session` / `--tmux` as needed.

```bash
cd /path/to/git/repo
~/cc.sh --worktree
~/cc.sh -w my-feature --tmux
~/cc.sh -b minimax -w api-refactor
```

### Native Mode (host CLI)

Runs `claude` on the host (not Docker). Requires `jq` and `claude` in `PATH`. Backs up existing `~/.claude/settings.json` and `~/.claude.json`, writes provider env into settings, ensures onboarding flags, then restores backups (or removes created files) when `claude` exits. `--rebuild` is ignored.

## Project Structure

```
your-project/
├── .claude/              ← Project-specific Claude settings (optional)
│   ├── commands/         ← Custom commands
│   ├── skills/           ← Custom skills
│   ├── plugins/          ← MCP servers
│   └── settings.json     ← Claude configuration
├── .claude.json          ← Project config (optional)
└── .npm-global/          ← Persistent npm packages (auto-created)
```

**Docker behavior:** The container mounts **only** this project’s `.claude/` and `.claude.json` (paths under the project root). If they are missing, `cc.sh` creates a minimal layout (including the plugin directory structure Claude expects). Host `~/.claude` is **not** mounted or merged into the container.

## Container Naming

Containers are named using the pattern: `{provider}-{folder}-{session}`

| Scenario | Container Name |
|----------|---------------|
| GLM provider, folder `project` | `glm-project` |
| MiniMax provider, folder `project` | `minimax-project` |
| Kimi provider, folder `project` | `kimi-project` |
| Qwen provider, folder `project` | `qwen-project` |
| Volcengine provider, folder `project` | `volcengine-project` |
| MiniMax with session `dev` | `minimax-project-dev` |
| MiniMax with session `test` | `minimax-project-test` |

This ensures:
- Different providers on the same folder get different containers
- Multiple sessions of the same provider get different containers
- No conflicts between containers

## Container Management

### List running Claude containers

```bash
docker ps --filter "name=glm-\|minimax-\|kimi-\|qwen-\|volcengine-"
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
| `$PROJECT_DIR/.claude` | `/home/node/.claude` | Project Claude settings only |
| `$PROJECT_DIR/.claude.json` | `/home/node/.claude.json` | Project Claude config only |
| `$PROJECT_DIR/.npm-global` | `/usr/local/share/npm-global` | Global npm packages |

If `settings.json` contains `env` or `hooks`, `cc.sh` strips those sections before run so provider environment from Docker wins.

## Configuration

### Environment File (.env)

Load order: **`~/.env` if it exists**, else **`<repo>/.env`** next to `cc.sh`. You can export variables in the shell instead if no file exists.

**Per provider** (prefix `GLM`, `MINIMAX`, `KIMI`, `QWEN`, `VOLCENGINE`):

- `{PREFIX}_API_KEY` (required)
- `{PREFIX}_API_BASE_URL` (required)
- `{PREFIX}_MODEL` (optional; if empty, model-related `ANTHROPIC_*` vars are not passed)
- `{PREFIX}_API_TIMEOUT_MS` (optional; overrides global `API_TIMEOUT_MS` for that provider)
- `{PREFIX}_CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` (optional; overrides global for that provider)

**Global defaults** (see `.env.example`):

- `DEFAULT_PROVIDER` — default when you run `cc.sh` with no `-b`
- `API_TIMEOUT_MS`
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`

All providers share the image `claude-dev-container`; only runtime env differs.

### Environment Variables in Container

Always set:

- `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `API_TIMEOUT_MS`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`
- `CLAUDE_CODE_CONTAINER_MODE=1`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, `BYPASS_ALL_CONFIRMATIONS=1`

If `{PREFIX}_MODEL` is set, the script also sets `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, and `ANTHROPIC_DEFAULT_OPUS_MODEL` to that value.

## Copy Settings into the Project (Docker)

The container only sees files under the project root. To reuse commands, skills, or plugins from your machine:

```bash
mkdir -p .claude
cp -r ~/.claude/commands .claude/ 2>/dev/null || true
cp -r ~/.claude/skills .claude/ 2>/dev/null || true
cp -r ~/.claude/plugins .claude/ 2>/dev/null || true
cp ~/.claude/settings.json .claude/ 2>/dev/null || true
```

`cc.sh` may remove `env` and `hooks` from project `settings.json` so API keys and base URL come from the container environment, not from stale file content.

### Native mode vs Docker

- **Docker (default):** project `.claude/` and `.claude.json` only; consistent team setups.
- **`--native`:** uses your global `~/.claude` / `~/.claude.json` with a temporary provider overlay (restored after exit).

## Docker Image Details

Build args include `CLAUDE_CODE_VERSION` (default `latest`), `GIT_DELTA_VERSION`, `ZSH_IN_DOCKER_VERSION`, `LAZYGIT_VERSION`, and optional `TZ`.

The image includes:

- **Base**: `node:20` (Debian Bookworm)
- **Shell / CLI**: zsh (zsh-in-docker), git, [git-delta](https://github.com/dandavison/delta), [Starship](https://starship.rs), [zoxide](https://github.com/ajeetdsouza/zoxide), [lazygit](https://github.com/jesseduffield/lazygit), fzf, ripgrep, `fd`, tmux, gh, vim, nano, jq, Python 3 + pip/venv
- **Node tooling**: global `pnpm`, `yarn`, [Bun](https://bun.sh)
- **Playwright**: Chromium, Firefox, and WebKit (optional mirror env commented in Dockerfile for China)
- **Claude Code**: `@anthropic-ai/claude-code` from npm (version via build arg)
- **Firewall helper**: `init-firewall.sh` with passwordless sudo for the `node` user
- **User**: non-root `node`; persistent shell history under `/commandhistory`

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
~/cc.sh -b minimax
# → Container: minimax-agent

# Terminal 2 - Kimi
cd ~/dev/ai/agent
~/cc.sh -b kimi
# → Container: kimi-agent

# Terminal 3 - GLM
cd ~/dev/ai/agent
~/cc.sh -b glm
# → Container: glm-agent
```

All three run independently as separate containers; each still uses the same project directory’s `.claude/` on disk.

### Multiple Sessions of Same Provider

```bash
# Terminal 1 - Main session
cd ~/dev/ai/agent
~/cc.sh -b minimax
# → Container: minimax-agent

# Terminal 2 - Dev session
cd ~/dev/ai/agent
~/cc.sh -b minimax -s dev
# → Container: minimax-agent-dev

# Terminal 3 - Test session
cd ~/dev/ai/agent
~/cc.sh -b minimax -s test
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
  - Use a different provider: e.g. `~/cc.sh -b kimi` or `~/cc.sh -b qwen`
  - Use a session ID: `~/cc.sh -b minimax -s dev`
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

Make sure `~/.env` or the `.env` next to `cc.sh` exists and sets `{PREFIX}_API_KEY` and `{PREFIX}_API_BASE_URL` for the provider you use with `-b`. Run `./cc.sh --init-env` in the repo once to create the repo `.env` from `.env.example`, or copy that file to `~/.env` for user-wide config.

### Permission issues

The script runs containers as the `node` user. Ensure your project files are readable:

```bash
chmod +r .claude/settings.json
```

## License

MIT

## Contributing

Contributions welcome! Feel free to open issues or PRs.
