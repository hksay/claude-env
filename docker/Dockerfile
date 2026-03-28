# Official Node.js 20 (Debian 12 Bookworm) - Stable, no tag issues
FROM node:20

# --------------------------
# Centralized Version Variables (Easy Updates)
# --------------------------
ARG TZ
ARG CLAUDE_CODE_VERSION=latest
ARG GIT_DELTA_VERSION=0.18.2
ARG ZSH_IN_DOCKER_VERSION=1.2.1
ARG LAZYGIT_VERSION=0.44.1

# --------------------------
# Environment Configuration
# --------------------------
ENV TZ="$TZ"
ENV DEVCONTAINER=true
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin:/home/node/.bun/bin:/home/node/.local/bin:/home/node/.cargo/bin

# --------------------------
# System Dependencies (Optimized Single Layer)
# --------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    less git procps sudo fzf zsh man-db unzip gnupg2 gh \
    iptables ipset iproute2 dnsutils aggregate jq \
    nano vim tmux \
    python3 python3-pip python3-venv python3-dev build-essential \
    ripgrep fd-find \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libdbus-1-3 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libasound2 libxshmfence1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    # Fix: Symlink fdfind to fd (Debian/Ubuntu naming conflict)
    && ln -sf /usr/bin/fdfind /usr/bin/fd

# --------------------------
# User & Directory Initialization
# --------------------------
ARG USERNAME=node
RUN mkdir -p \
    /usr/local/share/npm-global \
    /commandhistory \
    /workspace \
    /home/node/.claude \
    /home/node/.config \
    && touch /commandhistory/.bash_history /commandhistory/.zsh_history \
    && chown -R $USERNAME:$USERNAME \
    /usr/local/share/npm-global \
    /commandhistory \
    /workspace \
    /home/node/.claude \
    /home/node/.config

# Persist shell history system-wide
RUN echo 'export PROMPT_COMMAND="history -a" && export HISTFILE=/commandhistory/.bash_history' >> /etc/bash.bashrc \
    && echo 'export HISTFILE=/commandhistory/.zsh_history' >> /etc/zsh/zshenv

# --------------------------
# Install Git Delta (Git Diff Enhancement)
# --------------------------
RUN ARCH=$(dpkg --print-architecture) \
    && wget -O /tmp/git-delta.deb "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
    && dpkg -i /tmp/git-delta.deb \
    && rm /tmp/git-delta.deb

# --------------------------
# 【ROOT】Install Starship (Cross-shell prompt)
# --------------------------
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y

# --------------------------
# Switch to Non-Root User (Security Best Practice)
# --------------------------
USER node

# --------------------------
# Install All Node.js Package Managers
# --------------------------
RUN npm install -g pnpm yarn

# --------------------------
# Install Bun Runtime
# --------------------------
RUN curl -fsSL https://bun.sh/install | bash \
    && echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.zshrc \
    && echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc

# --------------------------
# Configure Starship for Node User
# --------------------------
RUN echo 'eval "$(starship init zsh)"' >> ~/.zshrc \
    && echo 'eval "$(starship init bash)"' >> ~/.bashrc

# --------------------------
# Install Zoxide (Smarter cd Navigation)
# --------------------------
RUN curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash \
    && echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc \
    && echo 'eval "$(zoxide init bash)"' >> ~/.bashrc

# --------------------------
# Install Lazygit (Terminal Git UI)
# --------------------------
RUN ARCH=$(dpkg --print-architecture) \
    && wget -O /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${ARCH}.tar.gz" \
    && mkdir -p /tmp/lazygit \
    && tar -xzf /tmp/lazygit.tar.gz -C /tmp/lazygit \
    && mv /tmp/lazygit/lazygit /home/node/.local/bin/ \
    && rm -rf /tmp/lazygit /tmp/lazygit.tar.gz

# --------------------------
# 【Core】Install Claude Code via Official NPM Package (No Region Lock)
# --------------------------
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# --------------------------
# Python Symlinks (Convenience)
# --------------------------
USER root
RUN ln -sf /usr/bin/python3 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# --------------------------
# Zsh Environment Setup
# --------------------------
USER node
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
    -p git \
    -p fzf \
    -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
    -a "source /usr/share/doc/fzf/examples/completion.zsh" \
    -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    -x

# --------------------------
# 【Optimized】Install Playwright with Fast CDN
# --------------------------
# Use Playwright's OFFICIAL, globally reliable Azure CDN (default, fastest for most regions)
# Uncomment the mirror line below ONLY if you are in China and need faster speeds
# ENV PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright/
RUN npx playwright install chromium firefox webkit

# --------------------------
# Verify All Critical Installations
# --------------------------
RUN node --version && npm --version && pnpm --version && yarn --version && bun --version \
    && python --version && pip --version \
    && rg --version && fd --version \
    && starship --version && zoxide --version && lazygit --version \
    && claude --version

# --------------------------
# Firewall Script Setup
# --------------------------
USER root
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh \
    && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
    && chmod 0440 /etc/sudoers.d/node-firewall

# --------------------------
# Final User & Workspace Configuration
# --------------------------
USER node
WORKDIR /workspace