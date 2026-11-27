# AGENTS.md

## Overview

This is a multi-repo workspace for a home k3s cluster ecosystem. Six repos work together:

- **`charts/`** — Custom Helm charts repo published to `mikevader.github.io/charts`. Charts in `charts/stable/` depend on a shared `charts/library/common` library chart.
- **`container-images/`** — Custom Docker images (built from `ghcr.io/mikevader/` base images) for apps like plex, airprint, wireguard.
- **`k3s-cluster-infra-apps/`** — GitOps (ArgoCD) manifests for the production k3s cluster (Raspberry Pi + Lenovo Thinkcentre nodes).
- **`k3s-cluster-dev-apps/`** — GitOps manifests for the dev/test cluster, mirrors infra-apps structure.
- **`gitops-private/`** — Flux CD Kustomizations for private/sensitive apps deployed to a `hidden` namespace.
- **`monitoring/`** — Ansible playbooks for provisioning and monitoring cluster nodes.

## Charts Repo (`charts/`)

- Every stable chart depends on the `common` library chart (`charts/library/common`). Check `Chart.yaml` `dependencies` section.
- `appVersion` in `Chart.yaml` uses a `# renovate:` comment for automated image version bumps (e.g., `# renovate: image=ghcr.io/mikevader/plex`).
- Generate chart README docs: `./hack/gen-helm-docs.sh [stable|incubator] [chart-name]` (requires `helm-docs` CLI).
- Generate chart summary: `./hack/gen-chart-summary.sh`. Generate `.helmignore`: `./hack/gen-helmignore.sh`.
- Tests use Ruby Minitest with `helm template` rendering, defined in `test/`. Run via `bundle exec` after `bundle install` from the Gemfile.
- Chart test files go in `test/stable/<chart-name>/` mirroring `charts/stable/<chart-name>/`.

## Container Images (`container-images/`)

- Each app has: `Dockerfile`, `VERSION` (current version), `PLATFORM` (target arch), `latest-version.sh` (checks upstream), `goss.yaml` (container tests).
- Dockerfiles use `COPY ./apps/<name>/...` paths — images are built from the repo root.
- Base images live in `base/` (alpine, ubuntu variants) and are referenced as `ghcr.io/mikevader/<base>`.

## GitOps Repos

- **Infra/Dev apps**: ArgoCD Application pattern. Each app is a Helm chart in its own directory under `cluster-*-apps/<app>/` with `Chart.yaml`, `values.yaml`, and `templates/`.
- **Private apps** (`gitops-private/`): Flux CD Kustomization pattern. Each app has `ks.yaml` (Flux Kustomization) + `app/` subdirectory with k8s manifests. All live under `apps/hidden/` namespace.
- Infra-apps addons chart (`addons/`) provides shared Helm templates via `addons/templates/`.

### App-of-apps groups (`k3s-cluster-infra-apps/`)

- Each group is `apps-root-config/applications/cluster-*.yaml` over the chart defaults in `values.yaml`; the chart renders each app's Application, Namespace and guardrails (LimitRange, ResourceQuota, NetworkPolicies, Vault SecretStore, AppProject limits).
  Before adding, moving or resizing an app, or when an app is blocked by quota, network policy or the AppProject, read `docs/cluster-core/app-groups.md`.
- Raise a guardrail per application in the group file (overlaid on the group value), with a comment explaining why. `cluster-test` apps can't ship their own ResourceQuota, LimitRange, NetworkPolicy or SecretStore (blacklisted in the AppProject).

### Vault secrets (`k3s-cluster-infra-apps/`)

- Workloads read only, under `secret/framsburg/`: production apps via ClusterSecretStore `vault-backend` at `framsburg/<app>`, `cluster-test` apps via their namespace's SecretStore `vault` at `framsburg/test/<namespace>` or `framsburg/test/shared/`.
  Before adding a secret, an ExternalSecret, or a Vault policy or role, read `docs/platform/external-secrets.md`.
- Move, rename or copy secrets with `hack/vault-kv-mv.sh` (`--help`).
- Vault commands need the user's login: give them the command to run instead of running it.

## Monitoring (`monitoring/`)

- Ansible-managed. Entry point: `ansible-playbook site.yml` (runs system, webserver, monitoring, airprint playbooks).
- Vault credentials: `~/.vault-credentials` file (chmod 0600).
- First-time setup: `ansible-galaxy install -r requirements.yml && pip3 install -r requirements.txt`.
- Hosts defined in `hosts.yaml` / `hosts_rancher.yaml`. Group vars in `group_vars/`.

## Key Conventions

- GitHub user/org: `mikevader`. Container registry: `ghcr.io/mikevader/`.
- Helm repo URL: `https://mikevader.github.io/charts/`
- Timezone: `Europe/Zurich`
- Cluster domain: `framsburg.ch` (e.g., `k3s.framsburg.ch`, `rancher.framsburg.ch`)
- Infrastructure: k3s with etcd, MetalLB for load balancing, Longhorn for storage, cert-manager for TLS, nginx ingress
- Dashboard: every user-facing Ingress/IngressRoute gets `gethomepage.dev/*` annotations (`enabled`, `name`, `group`, `icon`, `description`) so it appears on `home.framsburg.ch`.
  Groups: Infrastructure, Platform, Media, Utilities, RPG. See `docs/apps/homepage.md`.
