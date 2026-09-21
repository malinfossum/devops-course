#!/usr/bin/env bash
# Runs once when the Codespace is created.
# The course is written for Podman; my machine cannot run a hypervisor, so I work
# in Codespaces with Docker and let the course commands run as written.
set -euo pipefail

cat >> "$HOME/.bashrc" <<'EOF'

# devops-course: the course material says `podman`, this Codespace has Docker.
alias podman='docker'
EOF

echo "== toolchain =="
docker --version
docker compose version
dotnet --version
git --version
