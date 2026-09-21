# DevOps Course

My work for the two-week DevOps mini course in GET Prepared (September 2026): a containerised .NET API with PostgreSQL, then CI/CD with GitHub Actions.

## Stack

- .NET 10
- PostgreSQL in a container
- Docker with Compose
- GitHub Actions and GHCR (week 2)

## Environment

The course material uses Podman locally. My machine cannot run a hypervisor, so I work in GitHub Codespaces, where Docker is built in. The devcontainer aliases `podman` to `docker` so the course commands run as written.

Open the repo in a Codespace; `.devcontainer/post-create.sh` prints the toolchain versions when it is ready.

## Runbook

Filled in during week 1: start, stop, logs, reset.
