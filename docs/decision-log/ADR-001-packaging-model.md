# ADR-001: Packaging & Dependency Model

- **Status:** Accepted
- **Date:** 2026-06-17
- **Deciders:** Architect hat (CCB + Consumer App Lead consulted)

> **Exercises:** planning-development-models (maturity ladder), releasing-packaging-strategy
> (managed vs. unmanaged vs. unlocked, package dependencies),
> operating-managing-common-release-artifacts (immutable artifacts as rollback targets).
> **JD lines:** "reusable components in support of business products"; "supporting multiple
> application teams"; "versioning"; "scalable patterns."
> **Constrains:** NFR-8 (API stability), NFR-11 (recoverability with consumers). **RTM
> design coverage:** NFR-8, NFR-11.

## Context

The todo-app's `ADR-003-packaging` chose a **single unlocked package** and explicitly
deferred splitting: *"splitting (e.g. core/audit) is deliberately deferred… revisit only with
a real dependency-management motive (would be a new ADR)."* **This project is that motive.**
A platform layer exists to be *depended upon* by multiple application teams — so the package
architecture must model a real base ← consumer dependency, or the "reusable for multiple
teams" claim (the JD's core mission) is unproven.

## Options

| Option | For | Against |
|---|---|---|
| **One package containing platform + app** | Simplest; no dependency mgmt | Doesn't model reuse at all; a consumer can't take the platform without the app; defeats the project's entire thesis |
| **Platform code as a shared git module / copy-paste** | No packaging overhead | Org-development maturity (below the ladder the JD sits above); no versioned artifact, no rollback target, drift between "copies" — exactly what a platform team must not do |
| **Base unlocked package + extension unlocked package(s) that declare a dependency (chosen)** | Models real reuse: consumers install the base and depend on its versioned public API; immutable versioned artifacts = rollback targets (NFR-11); dependency-ordered install is a genuine release-ops exercise; top of the maturity ladder | Dependency-management discipline required (install ordering, version pinning, API stability) — but that discipline *is* the learning target |

## Decision

Two-tier **unlocked package** model, **no namespace** (internal platform; a namespace adds
friction with no benefit here — recorded so the omission is a decision, not an oversight):

- **Base package** — the platform layer (`Logger`, `EventPublisher`, `CalloutService`,
  inbound resource, Platform Events, Named Credential metadata). Owns the **public API**
  governed by `api-governance.md`. Its own GitLab repo (`sf-platform-enablement`).
- **Consumer packages** — the **todo-app** (consumer #1) declares a dependency on the base
  package version and calls its public API; a **stub consumer #2** (Phase 9) proves the base
  is reusable with zero base changes.
- `sfdx-project.json` is the configuration source of truth, including the `dependencies`
  entry (subscriber package version id) on the consumer side. CI creates **base** versions on
  `main` only; "prod" receives **package installs exclusively**, **dependency-ordered** (base
  before consumer). `sf project deploy` against prod is forbidden after v0.1.0.

## Consequences

- **Rollback** = `sf package install` of base version N-1 — mechanical, timeable against the
  30-minute RTO (NFR-11), rehearsable **with the consumer installed** (Phase 8), which is the
  harder, more realistic case the todo-app couldn't exercise.
- The **additive-only public-API + schema rule** (api-governance, change-management) becomes
  load-bearing: it's what keeps base version N-1 installable under a consumer built against N,
  and lets a consumer upgrade across a minor with zero changes (NFR-8).
- **Dependency ordering** is now a real release-runbook step (Phase 8), and **API stability**
  is now testable (consumer-compatibility test, Phase 7) — both net-new vs. the todo-app.
- Cost: more packaging ceremony (two repos, version pinning, dependency declaration). Accepted
  — modeling reuse is the point. Phase 5 keeps the base package tiny so this friction is felt
  while it's cheap, exactly as the todo-app used its Phase 5 to feel packaging friction early.

## Relationship to todo-app ADR-003

This ADR supersedes the deferral clause in todo-app `ADR-003-packaging` for the *platform*
context only. The todo-app remains a single package; it simply gains a **dependency** on this
base package when it becomes consumer #1 (a Minor change on the todo-app side, classified and
recorded there).
