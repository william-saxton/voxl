#!/bin/bash
set -euo pipefail

# ── Fix volume permissions ──
# Docker volumes mount as root; the runner process needs ownership
sudo chown -R runner:runner /home/runner/actions-runner/_work 2>/dev/null || true
sudo chown -R runner:runner /home/runner/.claude 2>/dev/null || true

# ── Check Claude auth ──
if [ ! -d "$HOME/.claude" ] || [ -z "$(ls -A $HOME/.claude 2>/dev/null)" ]; then
  echo ""
  echo "=============================================="
  echo "  Claude Code is not yet authenticated."
  echo "  Run this command from the TrueNAS shell:"
  echo ""
  echo "  docker exec -it voxl-claude-runner claude login"
  echo ""
  echo "  The auth will persist in the claude-config"
  echo "  volume across restarts."
  echo "=============================================="
  echo ""
  echo "The runner will start anyway — Claude commands"
  echo "will fail until you complete login."
  echo ""
fi

# ── Configure the GitHub Actions runner ──
if [ ! -f .credentials ]; then
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "ERROR: GITHUB_TOKEN is required for runner registration."
    echo "Set it in the TrueNAS Custom App environment variables."
    exit 1
  fi

  REPO_URL="https://github.com/${GITHUB_REPOSITORY}"

  echo "Requesting runner registration token..."
  REG_TOKEN=$(curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners/registration-token" \
    | jq -r '.token')

  if [ "$REG_TOKEN" = "null" ] || [ -z "$REG_TOKEN" ]; then
    echo "ERROR: Failed to get registration token. Check your GITHUB_TOKEN permissions."
    exit 1
  fi

  echo "Registering runner for ${REPO_URL}..."
  ./config.sh \
    --url "$REPO_URL" \
    --token "$REG_TOKEN" \
    --name "${RUNNER_NAME:-voxl-truenas}" \
    --labels "self-hosted,linux,x64,claude" \
    --unattended \
    --replace
fi

# ── Deregister on shutdown ──
cleanup() {
  echo "Removing runner..."
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    REG_TOKEN=$(curl -s -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners/registration-token" \
      | jq -r '.token')
    ./config.sh remove --token "$REG_TOKEN" 2>/dev/null || true
  fi
}
trap cleanup SIGTERM SIGINT

# ── Start the runner ──
echo "Starting GitHub Actions runner..."
./run.sh &
wait $!
