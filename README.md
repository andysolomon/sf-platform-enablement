# frs-platform — Salesforce Platform Enablement Layer

The **second** learning project in `canvaser`, built in the same spirit as `../todo-app/`.
Where the todo-app is an **application team**, this is the **platform team that serves it**:
a reusable Salesforce base package (logging, eventing, governed callouts) plus a
bidirectional integration to an external SaaS — pointed at the same Federal Reserve
**Senior Salesforce Platform Engineer** JD, going deeper on the two "Must have" lines the
todo-app left thin: **integration patterns** and **reusable platform enablers**.

> The product is the reusable layer; the integration is the proof. The todo-app becomes
> consumer #1 (declares a dependency on this package and calls its public API).

## Layout

| Path | What |
|---|---|
| `docs/IMPLEMENTATION_PLAN.md` | The 9-rung plan + JD traceability |
| `progress.txt` | Rung-by-rung progress tracker |
| `docs/governance/` | Charter, **api-governance** (public-API + deprecation), change mgmt, DoD |
| `docs/requirements/` | Landscape discovery, FRs, NFRs, integration contract, RTM, risks |
| `docs/architecture/` | Integration architecture, sequence diagrams, trust boundary, package dependency, public-API spec |
| `docs/decision-log/` | ADR-001 (packaging) … ADR-005 (auth) |
| `docs/devops/` | `pipeline-design.md` |
| `force-app/` | Base unlocked package source (Apex, Platform Events, objects, Named/External Credentials) |
| `config/project-scratch-def.json` | Scratch org definition |
| `.gitlab-ci.yml` | CI that **consumes the todo-app's reusable CI template** (NFR-10 reuse proof) |

## Status

Phases 1–3 complete (governance, requirements, architecture — design on paper first).
Phase 4 (delivery platform) in progress. See `progress.txt`.

## Stack & environment

Salesforce DX (sf CLI), Apex (+ minimal LWC for the Phase 9 monitoring surface), unlocked
package (2GP, base of a base←consumer dependency), Named Credentials + External Services,
Platform Events, GitLab CI. External integration peer: a self-built mock SaaS on Vercel
implementing `docs/requirements/integration-contract.md`.

**Reuses todo-app assets:** the two Developer Edition orgs (Dev Hub + "prod"), the reusable
CI template, and the documented glab/auth + base64-secret + scratch-budget lessons. Scratch
budget (6 creates/day) is **shared** with any todo-app work — count before pushing.

> **API version note:** `sourceApiVersion` is pinned to **66.0** to match what the shared
> org farm currently accepts (the todo-app hit `v67 deploys rejected` on the same orgs, per
> its ADR-004). Bump to 67.0 only after confirming the orgs accept it (Summer '26 rollout).
