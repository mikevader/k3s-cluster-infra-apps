# Plan: regroup and rename the app-of-apps folders

Status: **not started** · Created 2026-11-28 · Last updated 2026-11-28 (revised after PR #3280, app-of-apps charts extracted)

This file is the single source of truth for this piece of work. A new session should be able to
continue from here without the original conversation. **Update the Progress checkboxes and the
Log at the end of every work session.**

---

## 1. Goal

Replace the current `cluster-*` group folders with numbered, layer-ordered groups under
`apps/`, and move apps to the group that matches their dependency layer and shared policy.

Why:

- The prefix `cluster-` reads like "a Kubernetes cluster".
- The folders should sort in layer order so people can see it (this has no technical effect).
- Five of the eight group files (critical, platform, utility, media, rpg) are the same
  copy-paste. Only `init` (`onRemoval: preserve`, manual sync for argo-cd) and `test` (quotas,
  network policy, scoped Vault, `onRemoval: delete`) use the group for real policy. Grouping
  should follow dependency layer and policy, not how "critical" something feels.
- Observability is spread over critical, platform and utility. `rpg` has one app.
  `cluster-apps-apps` is empty.

## 2. Target layout (decided)

| Folder | Argo group name | Parent Application / AppProject | Apps |
|---|---|---|---|
| `apps/00-init/` | `init` | `init-apps` | argo-cd, etcd, cluster-resources (+ `bootstrap` entry pointing at `apps-root-config/bootstrap`) |
| `apps/10-core/` | `core` | `core-apps` | cert-manager, democratic-csi, error-pages, longhorn-system, metallb-system, nginx, nvidia, snapshot-controller, traefik |
| `apps/20-platform/` | `platform` | `platform-apps` | authentik, cnpg-system, external-secrets, headlamp, reloader, renovate, vault, vault-operator |
| `apps/30-observability/` | `observability` | `observability-apps` | monitoring-stack, loki, promtail, sloth, uptime-kuma, minio, opnsense |
| `apps/40-media/` | `media` | `media-apps` | plex, jellyfin, arr, filebrowser, ffmpeg, sabnzbd, tautulli, torrent (all in namespace `plex`) |
| `apps/50-home/` | `home` | `home-apps` | actual, mealie, homepage, dmw |
| `apps/90-test/` | `test` | `test-apps` | foundryvtt, hermes, httpbin, openclaw, paperless |

Where each app comes from today:

| App | From | To |
|---|---|---|
| argo-cd, etcd, cluster-resources | cluster-init-apps | 00-init |
| cert-manager, democratic-csi, error-pages, longhorn-system, metallb-system, nginx, nvidia, snapshot-controller, traefik | cluster-critical-apps | 10-core |
| monitoring-stack, loki, promtail, minio, opnsense | cluster-critical-apps | 30-observability |
| authentik, cnpg-system, external-secrets, headlamp, reloader, renovate, vault, vault-operator | cluster-platform-apps | 20-platform |
| sloth | cluster-platform-apps | 30-observability |
| actual, mealie, homepage | cluster-utility-apps | 50-home |
| uptime-kuma | cluster-utility-apps | 30-observability |
| dmw | cluster-rpg-apps | 50-home |
| media apps | cluster-media-apps | 40-media |
| test apps | cluster-test | 90-test |

### Decisions

- **D1 — The number is only in the folder name.** Argo names (group file, parent Application,
  AppProject) have no number: `apps-root-config/applications/<group>.yaml` and parent
  `<group>-apps`. This way renumbering a folder doesn't rename Argo objects. Needs a new
  `folder` field per entry in `apps-root-config/bootstrap/values.yaml` (or just `subFolder` in
  the group file, which already exists; see Phase 2).
- **D2 — `00-init`, not `00-bootstrap`.** An Application called `bootstrap` already exists (the
  chart in `apps-root-config/bootstrap`). Calling the group `bootstrap` too would give
  `bootstrap` plus `bootstrap-apps`, which is confusing.
- **D3 — Keep the namespace label `client: cluster-test`.** It is a label, not a path. It is
  matched by the Vault role `test-namespace`
  (`cluster-platform-apps/vault/templates/cr-raft.yaml`, `bound_service_account_namespace_selector`)
  and excluded in `cluster-platform-apps/external-secrets/templates/secret-store.yaml`.
  Renaming it is a separate, security-relevant change and is out of scope.
- **D4 — Steps of 10** leave room for new layers (e.g. `15-network`). `90-` keeps test at the
  end.
- **D5 — The folder and homepage groupings are independent.** Homepage tabs and groups come
  from `gethomepage.dev/*` annotations. dmw stays in homepage group "RPG" even though its
  folder is `50-home`.
- **D6 — Vault/ESO dependency of core apps is accepted.** Core apps (democratic-csi, longhorn,
  traefik, monitoring, loki, promtail) read secrets via ESO from Vault (platform). There is no
  startup deadlock: Vault's PVC uses Longhorn (the default class), Longhorn only needs
  `minio2-secret` for backups, bank-vaults keeps the unseal keys in a k8s Secret, and ESO
  reaches Vault in-cluster. The real risk is disaster recovery of Vault itself: the Longhorn
  backup credentials live in Vault. This is handled in Phase 6, not by the folder layout.

### Open questions (ask the user before the phase that needs them)

- Q1 (Phase 1): Can `cluster-init-apps/flux/` and `cluster-init-apps/root/` be deleted? Neither
  is listed in any group file. `root` looks like an old app-of-apps that
  `apps-root-config/bootstrap` replaced, and its values only have commented-out entries.
- Q2 (Phase 3): Should `homepage` go into `50-home` (proposed) or `30-observability`?
- Q3 (Phase 5, optional): Should `home` and `media` get stricter defaults (no `*`
  clusterResourceWhitelist, `podSecurity: restricted`)?

## 3. How the app-of-apps works (needed context)

**Since PR #3280 (2026-11-28) the templates are no longer in this repo.** They live in
published charts in the sibling `charts` repo (`../charts`, published to
`https://mikevader.github.io/charts`):

- `charts/stable/app-of-apps-bootstrap`: dependency of `apps-root-config/bootstrap/Chart.yaml`
- `charts/stable/app-of-apps`: dependency of `apps-root-config/applications/Chart.yaml`; it
  holds the chart defaults (`values.yaml`: podSecurity, onRemoval, guardrail defaults) and the
  templates `00-appprojects`, `01-namespace-resources`, `02-application`

Both dependencies are pinned (`version: 1.0.0`) and aliased `config`, so **every setting in
`bootstrap/values.yaml` and in each group file sits under a top-level `config:` key**. The
`charts/` subfolders are gitignored. Run `helm dependency build` in both folders before
`helm template`.

- `apps-root-config/bootstrap` (Application `bootstrap`, in group init, project `default`)
  renders one parent Application per entry in `config.bootstrap`: name `{{ .name }}-apps`,
  path `config.path` (default `apps-root-config/applications`), valueFiles `{{ .name }}.yaml`,
  automated prune + selfHeal, **no finalizer, no sync-wave** (checked in app-of-apps-bootstrap
  1.0.0).
- `apps-root-config/applications` is rendered once per group. Its Helm release name is the
  parent Application name (e.g. `cluster-media-apps-apps`), so the **AppProject name is the
  parent name** (app-of-apps `templates/00-appprojects.yaml`, `{{ .Release.Name }}`).
- For every entry in `applications:`, it creates an Application named after the key (wave 10,
  project = release name, path `<subFolder>/<key>` unless `path:` is set). It also creates a
  Namespace (unless `disableNamespaceCreation`) with PSA labels, onRemoval sync-options and
  optional LimitRange/ResourceQuota/NetworkPolicy/Vault SecretStore.
- `onRemoval` (app-of-apps chart `values.yaml`): `confirm` by default, `preserve` for init, `delete` for test.
  With `confirm`, removing an app from a group makes the old parent wait for approval. Moving
  an app to another group is safe: the new parent adopts the Application and Namespace.
- Child Application names = keys, so they **don't change** when moving groups. Only
  `spec.project` and `spec.source.path` change.
- `hack/argocd-sync-window.py` (untracked, local) pauses or resumes auto-sync per AppProject
  with an always-open deny/allow window. The `default` project holds `bootstrap` and all
  parents.
- `hack/sync-apps.py` (untracked, local) adds new app folders to group files. It already
  expects the `config:` wrapper, so it matches the current layout. It reads the group list
  from `bootstrap/values.yaml` and each group's `subFolder`, so it should keep working after
  the rename (check it once in Phase 4).

## 4. Things a new session must know

- **Unrelated staged changes exist** in the main working tree (`git status` on 2026-11-28):
  `cluster-critical-apps/democratic-csi/nfs.yaml`, `longhorn-system/fio-cmp*.yaml`,
  `longhorn-system/kustomization copy.yaml`, `longhorn-system/values copy.yaml`,
  `docs/Performance.numbers`, `docs/multicluster-setup.excalidraw`, `docs/network.drawio`.
  These are the user's own work. **Do not commit them with this work and do not delete them.**
  Work in a separate worktree or branch off `master`, and ask the user what to do with them
  before `git mv` touches `cluster-critical-apps/longhorn-system` (the staged files would move
  along).
- Main branch is `master`. Never push or merge without the user asking.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. PR body ends with
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- `.claude/worktrees/*` contain old copies of the repo. Ignore them in greps
  (`--exclude-dir=.claude`).
- Homepage annotation rules are in `AGENTS.md` and `docs/apps/homepage.md`. Apps in the test
  group keep the `🧪 Test · ` description prefix.

## 5. Phases

Each phase is one PR, unless noted. Phases 1–2 change nothing at runtime. Phase 3 is the
cutover.

### Phase 0 — Read-only checks against the live cluster

- [ ] `kubectl -n argocd-system get applications -o custom-columns=NAME:.metadata.name,PROJECT:.spec.project,PATH:.spec.source.path,SYNC:.status.sync.status,HEALTH:.status.health.status`
      and save the output in the Log (baseline). Everything should be Synced/Healthy before
      the cutover.
- [ ] `kubectl -n argocd-system get appprojects`: note the current names
      (expected `cluster-*-apps-apps`, `cluster-test-apps`, `default`).
- [ ] Check that nothing outside this repo depends on AppProject or parent names: Argo RBAC
      `policy.csv` in `cluster-init-apps/argo-cd/values.yaml` (today only
      `g, fb-admins, role:admin`, no project scopes), homepage Argo widget config
      (`cluster-utility-apps/homepage`), any alerts that filter on project names in
      `monitoring-stack`.
- [ ] Check that `hack/argocd-sync-window.py` works (`status` only).

### Phase 1 — Cleanup (no moves)

- [ ] Ask Q1. If yes, delete `cluster-init-apps/flux/` and `cluster-init-apps/root/`.
- [ ] Remove the empty group: `apps-root-config/applications/cluster-apps-apps.yaml` and its
      entry in `apps-root-config/bootstrap/values.yaml`. Parent `cluster-apps-apps-apps` and
      its AppProject get pruned by `bootstrap`. It has no apps, so this is safe.
- [ ] `cluster-critical-apps/descheduler/` is an empty, untracked directory: `rmdir` it
      locally (no commit needed).
- [ ] `cluster-critical-apps/minio/dashboard-minio-server-metrics-cm copy.yaml` is the **only**
      server-metrics dashboard (there is no file without " copy"). **Rename** it to
      `dashboard-minio-server-metrics-cm.yaml`, don't delete it. The resource name inside
      stays the same, so there is no runtime change.
- [ ] Verify: after merge, the parent `cluster-apps-apps-apps` is gone, and no other app has
      changed.

### Phase 2 — Template prep (optional; render must not change)

Goal: the cutover PR only moves files and changes values. This phase is **optional**. The
cutover works without it, because `subFolder` per group file is already enough to separate
the folder name from the group name (D1). Don't add a `folder` field.

- [ ] Parent sync-waves. This is now a change in the **charts repo**, not here:
      1. `../charts/charts/stable/app-of-apps-bootstrap/templates/`: add an optional
         per-entry `syncWave` (annotation `argocd.argoproj.io/sync-wave`). Without a value,
         nothing is rendered. Bump the chart version (minor), regenerate the README
         (`./hack/gen-helm-docs.sh stable app-of-apps-bootstrap`), add or extend the Minitest
         in `test/stable/app-of-apps-bootstrap/`. Separate PR in the charts repo; wait for it
         to be published.
      2. Here: bump `apps-root-config/bootstrap/Chart.yaml` to the new version and set
         `syncWave` per entry (init 0, core 10, platform 20, observability 30, media 40,
         home 50, test 90).
      Note: waves only order the apply step inside the `bootstrap` sync. They don't wait for
      children to be healthy. Nice to have, so skip it if the charts round trip isn't worth it.
- [ ] Verify with a render diff (should be empty apart from the wave annotation):
      ```sh
      (cd apps-root-config/applications && helm dependency build)
      (cd apps-root-config/bootstrap && helm dependency build)
      for g in apps-root-config/applications/cluster-*.yaml; do
        n=$(basename $g .yaml)
        helm template "$n-apps" apps-root-config/applications -f "$g" > "$SCRATCH/before-$n.yaml"   # on master
      done
      helm template bootstrap apps-root-config/bootstrap > "$SCRATCH/before-bootstrap.yaml"
      # repeat on the branch, then diff
      ```
      `$SCRATCH` = the session's scratchpad directory (not `/tmp`).

### Phase 3 — Cutover (one PR, one merge, done during a maintenance window)

Make the changes on a branch:

- [ ] Ask Q2.
- [ ] Ask the user about the staged files in `cluster-critical-apps/longhorn-system` and
      `democratic-csi` (see §4) before moving those folders.
- [ ] `mkdir apps` and `git mv` every app folder to its target (table in §2). Example:
      `git mv cluster-critical-apps/traefik apps/10-core/traefik`.
- [ ] Create the new group files `apps-root-config/applications/{init,core,platform,observability,media,home,test}.yaml`
      from the old ones (`git mv` the closest old file so history is kept). Everything stays
      under the top-level `config:` key (`config.subFolder`, `config.applications`, …); YAML
      anchors work inside it.
      - `cluster-init-apps.yaml` → `init.yaml`, `subFolder: apps/00-init`. Keep
        `onRemoval: preserve` and the `bootstrap` entry (`path: apps-root-config/bootstrap`,
        project `default`).
      - `cluster-critical-apps.yaml` → `core.yaml`, `subFolder: apps/10-core`. Remove
        monitoring-stack, loki, promtail, minio, opnsense. Keep the `&privileged` anchor for
        democratic-csi, longhorn, metallb, nvidia.
      - new `observability.yaml` (copy of `core.yaml` header), `subFolder: apps/30-observability`.
        Move these entries over **with their settings**: `monitoring-stack` (helmServerSideApply,
        privileged PSA), `loki` (helmServerSideApply, serverSideDiff), `promtail` (privileged
        PSA), `minio: {}`, `opnsense: {}`, `sloth: {}`, `uptime-kuma: {}`. Define the
        `&privileged` anchor again in this file (YAML anchors don't work across files).
      - `cluster-platform-apps.yaml` → `platform.yaml`, `subFolder: apps/20-platform`, without
        sloth.
      - `cluster-media-apps.yaml` → `media.yaml`, `subFolder: apps/40-media`.
      - `cluster-utility-apps.yaml` → `home.yaml`, `subFolder: apps/50-home`, without
        uptime-kuma, plus `dmw: {}`.
      - `cluster-test.yaml` → `test.yaml`, `subFolder: apps/90-test`. Keep the
        `client: cluster-test` label (D3) and all guardrails. Update the commented `path:`
        examples to `apps/90-test/...`.
      - Delete `cluster-rpg-apps.yaml`.
- [ ] `apps-root-config/bootstrap/values.yaml`: replace `config.bootstrap` with
      `init, core, platform, observability, media, home, test` (+ syncWave if Phase 2 added it).
- [ ] Don't bump the app-of-apps chart versions in the same PR. If Renovate has an open PR for
      `app-of-apps` / `app-of-apps-bootstrap`, merge or hold it **before** the cutover, so
      only one thing changes at a time.
- [ ] Update every path reference (find with
      `grep -rIn --exclude-dir=.git --exclude-dir=.claude --exclude-dir=.disabled -E "cluster-(init|critical|platform|utility|media|rpg|apps)-apps|cluster-test/" .`).
      Known places on 2026-11-28:
      - `.github/renovate.json5:13`: `'/cluster-platform-apps/renovate/.+\\.yaml$/'` →
        `'/apps/20-platform/renovate/.+\\.yaml$/'`
      - comments in the test group file header, `vault/templates/cr-raft.yaml` (comments only; the label stays),
        `external-secrets/templates/secret-store.yaml` (comments only),
        `traefik/values.yaml:153`, `paperless/README.md:51`
      - `hack/argocd-sync-window.py` usage examples (parent names), `hack/sync-apps.py`
- [ ] Verify the render before merging:
      - `helm template` each new group: each app appears exactly once across all groups, with
        `path: apps/NN-<group>/<app>`. Compare against the Phase 0 baseline (same app names,
        same destination namespaces, same Namespace labels/annotations apart from the
        tracking).
      - Every `path:` points at an existing folder: script it with `yq` or `grep` and `test -d`.
      - `helm template bootstrap apps-root-config/bootstrap` lists the 7 new parents.

Cutover procedure (needs the user, it touches the live cluster; get confirmation for each step):

1. Pause auto-sync for everything: `hack/argocd-sync-window.py pause --all` (includes
   `default`, which holds `bootstrap` and the parents). Manual sync stays allowed.
2. Merge the PR.
3. Sync `bootstrap` manually. Expected: 7 new parents created, old `cluster-*-apps` parents
   pruned. The old parents have **no finalizer**, so deleting them does not cascade and the
   children stay in place. Check this before syncing:
   `kubectl -n argocd-system get application cluster-media-apps-apps -o jsonpath='{.metadata.finalizers}'`
   must be empty. **If it isn't, stop**: remove the finalizer first, or pruning cascades
   and deletes all apps of that group.
4. Sync each new parent manually, in layer order (init → core → platform → observability →
   media → home → test). Each one creates its AppProject (no sync window there, so its
   children start auto-syncing again), adopts the Namespaces and updates the child
   Applications (`project`, `path`). The content is the same, so children should show
   Synced with no changes.
5. `init` contains `argo-cd` with `disableAutoSync`: after its path changes, sync it by hand
   and check that the diff is empty first.
6. Check: every Application is Synced/Healthy, with the new project and path. Compare against
   the Phase 0 baseline.
7. Delete the orphaned old AppProjects (`cluster-*-apps-apps`, `cluster-test-apps`). They
   still carry the deny window. First check that no Application references them:
   `kubectl -n argocd-system get applications -o json | jq -r '.items[].spec.project' | sort | uniq -c`.
8. Resume: `hack/argocd-sync-window.py resume --all`. Check `status` shows all projects as
   running.

Rollback: revert the merge commit, pause again, sync `bootstrap`, then sync the old parents.
This is the same procedure in reverse; names and paths are symmetrical.

### Phase 4 — Docs and conventions

- [ ] `AGENTS.md`: Overview/GitOps section describes `apps/NN-<group>/<app>/`. The homepage
      rule "Apps under `cluster-test/`" → "Apps under `apps/90-test/`". (Load the
      `writing-for-agents` skill before editing AGENTS.md.)
- [ ] `docs/getting-started/architecture.md` (tree around lines 234–264, plus the mermaid
      layers; already outdated today, e.g. it puts MetalLB in init),
      `docs/getting-started/quickstart.md:164`, `docs/cluster-core/argocd.md:199`,
      `docs/cluster-core/vault.md:150-219`, `docs/apps/homepage.md`,
      `docs/adr/homepage-dashboard.md` (ADR: add a note, don't rewrite history),
      `docs/platform/external-secrets.md` ("cluster-test" there means the group or label;
      keep it as the label name, say "test group" for the group).
- [ ] Write a short ADR `docs/adr/app-group-layout.md` with the decisions D1–D6.
- [ ] Check `hack/sync-apps.py --check` works with the new layout (it reads `subFolder`, so it
      should).
- [ ] Optional, charts repo: comments in `charts/stable/app-of-apps/values.yaml` use
      `cluster-platform-apps.yaml` / `cluster-*` paths as examples. Update them on the next
      chart change; there's no need for a release just for this.
- [ ] Same idea for `../k3s-cluster-dev-apps`? It mirrors this structure (AGENTS.md). Ask the
      user; it's out of scope by default.

### Phase 5 — Optional hardening of groups

- [ ] Ask Q3. If yes: `home` and `media` get no `*` `clusterResourceWhitelist` (list only what
      they need; check with `helm template` of each app for cluster-scoped kinds) and stricter
      `podSecurity`. Do this per app, after checking each app's pods actually pass.

### Phase 6 — Vault disaster-recovery gaps (independent of the folder layout)

- [ ] Ask the user whether break-glass copies already exist outside the cluster for: minio2
      credentials (Longhorn backup target), Vault unseal keys + root token (bank-vaults k8s
      Secret), TrueNAS API credentials (democratic-csi driver config).
- [ ] Optional: scheduled Vault raft snapshots to minio2 or the NAS (none are configured in
      `vault/templates/cr-raft.yaml` today).
- [ ] Runbook `docs/runbooks/vault-cold-restore.md`: restore Vault on an empty cluster.
- [ ] Comment in the Vault chart: Vault, ESO and authentik must never depend on storage or
      secrets that come from Vault (e.g. never put them on the democratic-csi NFS class).

## 6. Progress

| Phase | State | PR | Notes |
|---|---|---|---|
| 0 Live checks | todo | – | |
| 1 Cleanup | todo | | |
| 2 Template prep (optional) | todo | | needs a charts-repo release (app-of-apps-bootstrap) |
| 3 Cutover | todo | | |
| 4 Docs | todo | | |
| 5 Hardening (optional) | todo | | |
| 6 Vault DR (optional) | todo | | |

## 7. Log

Add a dated entry for each session: what was done, what was verified, what's next, and
anything surprising.

- **2026-11-28** — Analysis and plan written (no code changes). Current groups, dependencies
  and references were looked at; the findings are in §2–§5. Next: Phase 0.
- **2026-11-28** — Revised after PR #3280: the templates now live in the published charts
  `app-of-apps` / `app-of-apps-bootstrap` 1.0.0 (charts repo), aliased `config`. The behaviour
  the plan relies on is unchanged (AppProject = release name, parents without finalizer,
  `subFolder`, `<name>-apps`). Changes to the plan: values sit under `config:`; Phase 2
  sync-waves need a charts-repo release (now optional); render checks need
  `helm dependency build`; hold Renovate bumps of those charts during the cutover;
  `hack/sync-apps.py` matches the layout now.
