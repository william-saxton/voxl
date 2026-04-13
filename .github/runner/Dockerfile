FROM ubuntu:24.04

ARG RUNNER_VERSION=2.322.0
ARG GODOT_VERSION=4.6-stable

ENV DEBIAN_FRONTEND=noninteractive

# Core dependencies
RUN apt-get update && apt-get install -y \
    curl wget unzip git jq sudo \
    python3 python3-pip \
    build-essential gcc g++ pkg-config mingw-w64 \
    libx11-dev libxcursor-dev libxinerama-dev libxrandr-dev libxi-dev \
    libgl1-mesa-dev libasound2-dev libpulse-dev libfreetype6-dev \
    libssl-dev libfontconfig1-dev \
    ca-certificates gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install SCons
RUN pip3 install --break-system-packages scons

# Install Node.js (required by Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Godot (headless)
RUN wget -q https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip \
    && unzip -q Godot_v${GODOT_VERSION}_linux.x86_64.zip \
    && mv Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v${GODOT_VERSION}_linux.x86_64.zip

# Create runner user
RUN useradd -m -s /bin/bash runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install GitHub Actions runner
WORKDIR /home/runner/actions-runner
RUN curl -o actions-runner.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf actions-runner.tar.gz \
    && rm actions-runner.tar.gz \
    && ./bin/installdependencies.sh \
    && chown -R runner:runner /home/runner

USER runner
WORKDIR /home/runner/actions-runner

COPY --chmod=755 entrypoint.sh /home/runner/entrypoint.sh

ENTRYPOINT ["/home/runner/entrypoint.sh"]
