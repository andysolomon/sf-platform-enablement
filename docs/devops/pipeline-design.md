# Pipeline Design

> **Exercises:** system-design-deployment-strategy, operating-managing-common-release-artifacts.
> **JD lines:** "develops/maintains automation for deployments"; GitLab CI/CD; "supporting
> multiple application teams" (this project is the *second team* adopting the template).
> **Constrains:** NFR-9 (quality gates), NFR-10 (reproducibility & CI reuse). **Written
> before** `.gitlab-ci.yml` (the todo-app discipline: design the pipeline before the YAML).

## 1. Goal

Stand up CI for the `frs-platform` base package by **consuming the todo-app's reusable CI
template** (`ci-templates/salesforce-pipeline.yml`) — proving NFR-10 and validating the
template's own "a second app team adopts it" acceptance criterion. Anything the adoption
exposes is a **finding**, not an annoyance.

## 2. Stages & jobs

Reuses the template's six hidden jobs, plus consumer-specific extensions:

| Stage | Job | Source | Scratch cost |
|---|---|---|---|
| validate | `scan` (Code Analyzer) | `.sf-scan` (unconditional) | 0 |
| validate | `lwc-test` (Jest) | `.sf-lwc-test` | 0 |
| test | `apex-test` (scratch + RunLocalTests + coverage ≥85) | `.sf-apex-test` | 1 |
| test | **`contract-test`** (HttpCalloutMock + contract assertions vs deployed Vercel mock) | **consumer-added** (template has none) | 0–1 |
| package | `version` (2GP build) | `.sf-package` | 1 (pkg-create) |
| test-release | `staging-install` (install artifact + seed + e2e) | `.sf-staging-install` | 1 |
| release | `prod-install` (manual gate) | `.sf-prod-install` | 0 |

## 3. Key design decisions

### 3.1 Cross-project include (the reuse mechanism + a finding)

The todo-app template lives **inside** the `sf-todo` repo, so a *different* repo cannot
`include: local:` it. We consume it cross-project:

```yaml
include:
  - project: 'andysolomon/sf-todo'
    file: 'ci-templates/salesforce-pipeline.yml'
    ref: main
```

> **FINDING (NFR-10):** the template's own README recommends, for true multi-team use,
> hosting it in a **dedicated repo** consumed via `include: project: … ref: <tag>` so teams
> adopt upgrades on their own schedule. Consuming it from `sf-todo@main` couples this project
> to the todo-app's default branch — a template change there can break this pipeline without
> warning. **Recommended remediation (logged, deferred):** extract `ci-templates/` into a
> dedicated `sf-ci-templates` repo and pin `ref:` to a tag. For now we pin to `main` and
> accept the coupling, documented here. *This is exactly the kind of real adoption gap the
> "second team" test is supposed to surface — and it did.*

### 3.2 `contract-test` is consumer-added

The reusable template covers scan/unit/apex/package/staging/prod — it has **no integration
testing**, because the todo-app had no integration. This project adds a `contract-test` job
that runs `HttpCalloutMock` unit cases (cost 0) and, when wired (Phase 7), asserts the
deployed Vercel mock satisfies `integration-contract.md` (cost 0–1, depending on whether it
needs a scratch org). Added as a thin job in the `test` stage; **does not** modify the shared
template (a consumer must not edit the platform's template — it requests a feature instead).
*Follow-up: if integration testing proves generally useful, propose a `.sf-contract-test`
template back to the shared repo.*

### 3.3 Conditional execution & scheduled exclusion

Inherited from the template's `.sf-rules-code-gated` / `.sf-rules-release-gated`: org-burning
jobs run only when code/config paths change (docs-only MRs skip them), and never on
`schedule` pipelines. `scan` stays **unconditional** so a docs-only MR still has one passing
job under `only_allow_merge_if_pipeline_succeeds` (per the template README note).

### 3.4 Secrets

Same model as todo-app (reuse the lessons):

| Variable | Scope | Why |
|---|---|---|
| `SFDX_AUTH_URL_DEVHUB_B64` | masked, **unprotected** | MR pipelines must create scratch orgs |
| `SFDX_AUTH_URL_PROD_B64` | masked, **protected** | prod install only on `main`/`hotfix/*` |

Base64-encode `sf org auth show-sfdx-auth-url` (GitLab masking rejects the raw `force://`
charset). Protect `hotfix/*` so the protected prod var reaches hotfix pipelines.

**Integration secrets are NOT CI secrets:** the outbound OAuth secret lives in the org's
**External Credential**, and the inbound JWT cert in the **Connected App** — both are org
config/metadata, set up per ADR-005, not GitLab variables. The Vercel mock has its **own**
deploy (Vercel's git integration) with its own secrets, independent of this pipeline.

### 3.5 Scratch-org lifecycle & budget

Each `apex-test` and `staging-install` burns 1 scratch create; `version` burns 1 package-
version build (a **separate** 6/day limit). Budget is **shared with todo-app** (same Dev Hub)
— count before pushing. Scratch orgs are deleted in `after_script` (template behavior).

### 3.6 Dependency-ordered release spans two pipelines

This is a **base** package. Its pipeline builds + installs `frs-platform` to prod. The
**consumer** (todo-app) installs separately *after* the base, from its own pipeline (it
declares the dependency, `package-dependency.md` §3). The release runbook (Phase 8)
coordinates the order across the two repos — a real platform-team release concern the
todo-app's single pipeline never had.

## 4. CI image

Start on the template default (`node:22`, installs tools per job). The todo-app measured a
prebaked image at only ~5s savings on shared runners (noise), so it's not adopted; same
default here unless measurement says otherwise (Phase 9).

## 5. Open items (need orgs/repo — see progress.txt Phase 4)

- 4.2 **USER:** create GitLab project `sf-platform-enablement`, protect `main` (MR-only).
- 4.1 register the `frs-platform` package in the Dev Hub (`sf package create`) → populates
  `packageAliases` in `sfdx-project.json` (separate from the 6/day scratch budget).
- 4.4 build + deploy the Vercel mock per `integration-contract.md`.
- 4.5 set the CI variables above.
- 4.7 verify gates bite: a planted failing integration test goes red then green.
