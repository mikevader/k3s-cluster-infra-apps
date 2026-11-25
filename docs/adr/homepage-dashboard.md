# ADR: Homepage as the cluster dashboard

**Date:** 2026-11-25
**Status:** Accepted

## Context

We want one start page listing every service on the cluster, with these requirements:

- secured by Authentik (built-in OIDC or forward-auth middleware)
- new services appear without logging into the dashboard. GitOps resources are fine
- open source and actively maintained
- deployed in `cluster-utility-apps`
- nice to have: users only see the services they can access

Several dashboards had been tried in `cluster-test` (Homepage, Homarr, Hajimari, Forecastle, Homer). Heimdall runs
in `cluster-utility-apps` but has to be configured by hand.

## Options

| Tool | Maintained | Kubernetes auto-discovery | Auth | Per-user view |
| --- | --- | --- | --- | --- |
| **Homepage (gethomepage)** | yes, ~monthly releases | yes: Ingress, IngressRoute, HTTPRoute annotations | forward-auth middleware | no (only via separate instances) |
| Homarr v1 | yes | no: Kubernetes integration shows workloads, apps are added in the UI | built-in OIDC | partly, groups managed inside Homarr |
| Hajimari | no (stale) | yes (Ingress annotations) | middleware | no |
| Forecastle | slow | yes (Ingress, `ForecastleApp` CRD) | middleware | no |
| Homer / Heimdall / Dashy | mixed | no: static config | middleware / OIDC (Dashy) | Dashy: group rules in config |
| Authentik "My applications" | yes | no: every app is an Authentik application (blueprints) | built-in | yes |

No maintained tool does both auto-discovery and per-user filtering.

## Decision

Use **Homepage** with a single instance behind the `authentik-authentik@kubernetescrd` forward-auth middleware.

- Services opt in with `gethomepage.dev/*` annotations committed alongside the app. No operator (e.g. Kyverno) is
  needed. The annotations are explicit and already existed on several apps.
- Its own chart (`cluster-utility-apps/homepage`) instead of a third-party chart. Renovate keeps the image pin current.

## Consequences

- **Shared view:** every authenticated user sees all listed services. Clicking one they can't use ends at that
  service's own Authentik or app login.
- **Annotations are a convention:** a new app without them doesn't appear. This is noted in `AGENTS.md` and
  [docs/apps/homepage.md](../apps/homepage.md).
- **Widgets need API keys:** each key is a manual one-time step in Vault (`secret/framsburg/homepage`).
- **Revisit if per-user visibility becomes a must:**
  - Option 1: one Homepage instance per group, using `gethomepage.dev/instance.<name>.*` annotations, with each instance's
    ingress bound to an Authentik group.
  - Option 2: switch to Authentik's application library and manage apps with blueprints.
