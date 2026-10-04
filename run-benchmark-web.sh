#!/bin/bash
# run-benchmark-web.sh — Provision a Claude Code on the web (cloud) session and
# launch the benchmark there instead of on a laptop / Sprite VM.
#
# Usage:
#   ./run-benchmark-web.sh --setup-only          # provision the sandbox, run nothing
#   ./run-benchmark-web.sh --tasks 11 --models haiku45 --modes bash,default
#   ./run-benchmark-web.sh --resume 2026-07-28_120000 --models haiku45
#
# Everything except --setup-only is forwarded verbatim to runner.py.
#
# Why a separate script from run-benchmark.sh: a cloud session differs from a
# laptop in five ways that each break the laptop script.
#
#   1. Docker is installed but the daemon is NOT running (no init system), so
#      `act` — and therefore every v3+ task — fails until dockerd is started.
#   2. The session runs as root, and `claude --dangerously-skip-permissions`
#      refuses to start as root unless IS_SANDBOX=1 (runner.py sets it).
#   3. All egress is forced through a TLS-terminating proxy. The host trusts its
#      CA already; containers started by act do not, so the CA is baked into the
#      act runner image and the proxy is handed to act via ~/.config/act/actrc.
#   4. api.github.com is blocked by egress policy, so tools are pinned to exact
#      release URLs rather than resolved through the GitHub API.
#   5. pwsh, act, actionlint, shellcheck and bats are absent (bun/node are not).
#
# Everything here is idempotent — re-running skips what is already in place.

set -eo pipefail
cd "$(dirname "$0")"

# Pinned because api.github.com (used by the upstream "latest" installers) is
# blocked by the sandbox egress policy. Bump deliberately.
ACTIONLINT_VERSION="${ACTIONLINT_VERSION:-1.7.9}"
SHELLCHECK_VERSION="${SHELLCHECK_VERSION:-0.10.0}"
ACT_VERSION="${ACT_VERSION:-0.2.89}"

ACT_IMAGE="act-ubuntu-pwsh:latest"
ACT_BASE_IMAGE="gha-bench-act-base:ca"
CA_BUNDLE="${CCR_CA_BUNDLE:-/root/.ccr/ca-bundle.crt}"
BIN="$HOME/.local/bin"

mkdir -p "$BIN"
export PATH="$BIN:$PATH"

SETUP_ONLY=0
if [ "$1" = "--setup-only" ]; then SETUP_ONLY=1; shift; fi

step() { echo; echo "=== $* ==="; }

step "Environment"
if [ -z "$CLAUDE_CODE_REMOTE" ] && [ -z "$CLAUDE_CODE_CONTAINER_ID" ]; then
    echo "WARNING: no Claude-Code-on-the-web markers in the environment."
    echo "         This script is for cloud sessions; use ./run-benchmark.sh on a laptop."
fi
echo "os: $(. /etc/os-release && echo "$PRETTY_NAME")  cpus: $(nproc)  mem: $(free -g | awk '/^Mem:/{print $2"GB"}')"
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found"; exit 1; }
command -v claude  >/dev/null 2>&1 || { echo "ERROR: claude CLI not found"; exit 1; }
echo "claude: $(claude --version)"
echo "python: $(python3 --version)"
echo "bun: $(bun --version 2>/dev/null || echo 'MISSING — typescript-bun cells will fail')"

step "Docker daemon"
if docker info >/dev/null 2>&1; then
    echo "already running: $(docker --version)"
else
    echo "starting dockerd (no init system in the sandbox — act needs it)..."
    mkdir -p "$HOME/.local/state"
    nohup dockerd >"$HOME/.local/state/dockerd.log" 2>&1 &
    for _ in $(seq 1 30); do
        docker info >/dev/null 2>&1 && break
        sleep 1
    done
    if docker info >/dev/null 2>&1; then
        echo "dockerd up: $(docker --version)"
    else
        echo "ERROR: dockerd failed to start; see $HOME/.local/state/dockerd.log"
        tail -20 "$HOME/.local/state/dockerd.log" || true
        exit 1
    fi
fi

step "Host tools"
if ! command -v actionlint &>/dev/null; then
    echo "installing actionlint ${ACTIONLINT_VERSION}..."
    curl -sSL --fail \
        "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
        | tar xz -C "$BIN" actionlint
    chmod +x "$BIN/actionlint"
fi
echo "actionlint: $(actionlint --version 2>&1 | head -1)"

if ! command -v shellcheck &>/dev/null; then
    echo "installing shellcheck ${SHELLCHECK_VERSION}..."
    tmp=$(mktemp -d)
    curl -sSL --fail \
        "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
        -o "$tmp/sc.tar.xz"
    tar xf "$tmp/sc.tar.xz" -C "$tmp"
    install -m 0755 "$tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "$BIN/shellcheck"
    rm -rf "$tmp"
fi
echo "shellcheck: $(shellcheck --version 2>&1 | grep '^version:' | head -1)"

if ! command -v act &>/dev/null; then
    echo "installing act ${ACT_VERSION}..."
    curl -sSL --fail \
        "https://github.com/nektos/act/releases/download/v${ACT_VERSION}/act_Linux_x86_64.tar.gz" \
        | tar xz -C "$BIN" act
    chmod +x "$BIN/act"
fi
echo "act: $(act --version 2>&1)"

if ! command -v bats &>/dev/null; then
    echo "installing bats-core..."
    npm install -g --silent bats
fi
echo "bats: $(bats --version)"

step "PowerShell + Pester (host)"
if ! command -v pwsh &>/dev/null; then
    . /etc/os-release
    deb="/tmp/packages-microsoft-prod.deb"
    if curl -sSL --fail "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" -o "$deb"; then
        dpkg -i "$deb" >/dev/null 2>&1 || true
        rm -f "$deb"
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq powershell || true
    fi
fi
if command -v pwsh &>/dev/null; then
    echo "pwsh: $(pwsh --version)"
    pwsh -NoProfile -Command "if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0')) { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope AllUsers }" || true
    echo "Pester: $(pwsh -NoProfile -Command '(Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()' 2>/dev/null || echo 'not found')"
else
    echo "WARNING: pwsh unavailable — powershell cells will fail"
fi

step "act runner image"
# Containers cannot reach the host-local egress proxy's CA store, so the CA is
# baked into a base layer and the proxy is passed at build time. On a laptop
# CA_BUNDLE does not exist and Dockerfile.act builds on its stock base.
BASE_ARG=()
if [ -s "$CA_BUNDLE" ]; then
    if ! docker image inspect "$ACT_BASE_IMAGE" >/dev/null 2>&1; then
        echo "building $ACT_BASE_IMAGE (egress-proxy CA trusted inside containers)..."
        ctx=$(mktemp -d)
        cp "$CA_BUNDLE" "$ctx/ca-bundle.crt"
        cat > "$ctx/Dockerfile" <<'DOCKERFILE'
FROM catthehacker/ubuntu:act-latest
COPY ca-bundle.crt /usr/local/share/ca-certificates/egress-proxy.crt
RUN update-ca-certificates
# The egress proxy only serves HTTPS CONNECT — a plain-HTTP request through it
# comes back 405, which is how apt fails inside a container. Point every apt
# source at https:// so the proxy can tunnel it.
RUN find /etc/apt -name '*.list' -o -name '*.sources' | xargs -r sed -i 's|http://|https://|g'
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/egress-proxy.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
DOCKERFILE
        docker build --network host -t "$ACT_BASE_IMAGE" "$ctx"
        rm -rf "$ctx"
    fi
    BASE_ARG=(--build-arg "BASE_IMAGE=$ACT_BASE_IMAGE")
fi

if docker image inspect "$ACT_IMAGE" >/dev/null 2>&1; then
    echo "$ACT_IMAGE already built"
else
    echo "building $ACT_IMAGE (pwsh + Pester preinstalled)..."
    # https_proxy only — setting http_proxy makes apt send plain-HTTP requests
    # that the egress proxy answers with 405.
    docker build --network host \
        --build-arg "https_proxy=$HTTPS_PROXY" \
        --build-arg "no_proxy=$NO_PROXY" \
        "${BASE_ARG[@]}" \
        -t "$ACT_IMAGE" -f Dockerfile.act .
fi

step "act configuration"
mkdir -p "$HOME/.config/act"
{
    echo "-P ubuntu-latest=$ACT_IMAGE"
    echo "--network host"
    # act >= 0.2.8x force-pulls the runner image; ours is built locally and has
    # no registry to pull from, so every job would die in "Set up job".
    echo "--pull=false"
    if [ -n "$HTTPS_PROXY" ]; then
        # Workflow steps that fetch anything (apt, npm, actions/setup-*) need the
        # egress proxy; --network host makes its 127.0.0.1 address reachable.
        echo "--env HTTPS_PROXY=$HTTPS_PROXY"
        echo "--env https_proxy=$HTTPS_PROXY"
        echo "--env NO_PROXY=${NO_PROXY:-localhost,127.0.0.1}"
        echo "--env no_proxy=${NO_PROXY:-localhost,127.0.0.1}"
    fi
} > "$HOME/.config/act/actrc"
cat "$HOME/.config/act/actrc"

step "Ready"
python3 -c "from runner import detect_execution_environment as d; print('execution environment:', d())"

if [ "$SETUP_ONLY" = "1" ]; then
    echo "Setup complete (--setup-only); not starting a run."
    exit 0
fi

step "Starting benchmark"
echo "Note: a cloud session is reclaimed after inactivity. runner.py commits and"
echo "pushes results/ after every completed cell, so an interrupted run resumes"
echo "with: ./run-benchmark-web.sh --resume <run-dir> ..."
echo ""
exec python3 runner.py "$@"
