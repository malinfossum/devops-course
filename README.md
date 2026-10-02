# DevOps Course

My work for the two-week DevOps mini course in GET Prepared (21 September to 2 October 2026): a containerised .NET API with PostgreSQL, then CI/CD with GitHub Actions.

## Stack

- .NET 10
- PostgreSQL in a container
- Docker with Compose
- GitHub Actions and GHCR (week 2)

## Environment

The course material uses Podman locally. My machine cannot run a hypervisor, so I work in GitHub Codespaces, where Docker is built in. The devcontainer aliases `podman` to `docker` so the course commands run as written.

Open the repo in a Codespace; `.devcontainer/post-create.sh` prints the toolchain versions when it is ready.

## Contents

One `NOTATER.md` per day (in Norwegian), with the commands I ran, the real terminal output and my reflections.

| Week | Folder | Topic |
|------|--------|-------|
| Week 1 | `uke-1/` | Containers, multi-stage Dockerfile, Compose with PostgreSQL, my own project in containers |
| Week 2 | `uke-2/` | CI with GitHub Actions, quality gates, images in GHCR, local deploy, rollback and troubleshooting |

From Thursday in week 1 the practical work moved to my own project, [Varde](https://github.com/malinfossum/varde). The notes here link to the pull requests there.

## Runbook

The runbooks live in the Varde README, next to the code they describe:

- [Run the API in containers](https://github.com/malinfossum/varde#runbook-the-api-in-containers): start, stop, logs, reset
- [Deploy and rollback](https://github.com/malinfossum/varde#runbook-deploy-and-rollback-prod-sim): prod-sim on a tagged image from GHCR
