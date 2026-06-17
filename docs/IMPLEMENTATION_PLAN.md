# Platform Enablement Layer — Salesforce Integration & Reusable Components Project

The **second** learning project in `canvaser`, built in the same spirit as
`projects/todo-app/`: a deliberately small set of platform components wrapped in a
deliberately rigorous delivery process. Where the todo-app was an **application team**,
this project is the **platform team that serves it** — it builds the reusable enablers
and integrations the todo-app deliberately deferred, modeled on the same
**Senior Salesforce Platform Engineer JD** (`platform-engineer-jd.txt`, Federal Reserve
System context) and grounded in the
`study/architect-certification-guides/integration/` material (Integration Architect deck —
3 decks / 86 slides — plus `integration/references.html`), with the delivery/ALM rungs still
grounded in `study/architect-certification-guides/development-lifecycle-and-deployment/`.

> **Study grounding (as of 2026-06-16):** the integration deck currently covers the
> *discovery* topics — `evaluate-current-system-landscape`,
> `analyze-system-landscape-constraints-and-pain-points`,
> `evaluate-authentication-and-authorization-needs` — plus a references page on the
> decision framework, outbound callouts/endpoint management, and auth/connected-apps. These
> ground Phases 2–3 below (landscape discovery → auth/trust-boundary design). As more deck
> topics (design patterns, error handling, async) are ingested, wire them into Phases 6–7.

> **The thesis:** *The todo-app was the cargo; the pipeline was the product.* Here, the
> **reusable platform layer is the product, and the integration is the proof.** This
> project enacts the JD's core sentence verbatim — *"delivery of platform enablers
> including the design, build, security and operationalization of reusable components in
> support of business products… supporting multiple Salesforce application teams."* The
> todo-app becomes the first consuming "app team"; a stub second consumer proves the
> abstraction is reusable, not bespoke.

## Why this project, and why now

The todo-app proved DevOps & CI/CD mastery (the ~80% of the role) end-to-end: 5 prod
releases in 7 days, hotfix + rollback drills, reusable CI templates. It deliberately
left **two "Must have" JD lines and the literal core-mission line** thin:

1. **"Must have experience in Salesforce Integration patterns"** — todo-app status:
   *Deferred (its Phase 10)*. Never built.
2. **"reusable components in support of business products" / "explicit APIs and
   abstractions for application developers" / "patterns for logging, monitoring,
   alerting, backup, encryption"** — todo-app status: *grazed in its Phase 9*.

This project closes both, and does so by **consuming** the todo-app's Phase 9 reusable
CI template — validating that template's acceptance criterion ("prove it by having a
second team adopt it") as a side effect.

## JD Traceability

Every line below is one the todo-app left under-exercised. Each maps to at least one rung.

| JD requirement | Where exercised here |
|---|---|
| **Must have** Salesforce integration patterns; "Creates Integrations/Connectors… 3rd party"; "integrating Salesforce with 3rd party solutions"; "heterogeneous datacenter, cloud, and SaaS" | Phases 3, 5, 6, 7 (Named Credential + External Services outbound callout, inbound Apex REST, Platform Events / async, retry + idempotency, contract tests) |
| "delivery of platform enablers… reusable components in support of business products" | Phases 2, 5, 6, 9 (base unlocked package: Logger API, event publisher, callout framework — consumed by app teams) |
| "Deliver explicit APIs and abstractions… for application developers" | Phases 2, 6, 8 (public Apex API surface with a published contract + semver + deprecation policy) |
| "patterns for common platform needs (logging, monitoring, alerting, backup, encryption, tooling)" | Phases 6, 9 (Platform-Event-backed logging framework, monitoring/alerting surface, backup + encryption design docs) |
| "supporting multiple Salesforce application teams" / reusable, not bespoke | Phases 4, 9 (todo-app = consumer #1 via cross-package dependency; stub consumer #2 proves reuse) |
| **Must have** Salesforce security model; "Partner with InfoSec on security configs"; "Manages core security model" | Phases 3, 6 (Named Credential auth, secrets handling, least-priv for callouts/inbound, trust-boundary diagram, InfoSec partnership artifact) |
| Apex async/batch, governor limits, secure coding | Phases 6, 7 (callouts in async context, 100-callout limit discipline, Queueable/Platform Event chaining, bulkified) |
| Versioning, branching, "scalable patterns," multi-package architecture | Phases 3, 4, 8 (base ← extension package dependency, dependency-ordered install, semver of a *public API*) |
| Automated/SFDX testing, static analysis, E2E | Phases 4, 7 (HttpCalloutMock, Platform Event test bus, contract + resilience tests, cross-boundary e2e) |
| "Performs new Salesforce release evaluations"; Tier 3 support; deployment automation | Phase 8 (integration-failure drill, breaking-change/deprecation drill, secrets-rotation runbook) |
| Scripting (shell), GitLab CI/CD | Phases 4, 9 (pipeline + the consumed reusable CI template, env/secret automation) |
| SAFe (desired) | Phase 1 (platform-as-product cadence, consumer-contract governance) |
| Data Cloud (preferred) | Out of scope (honest gap; see Deferred) |

## Objective and Scope Boundaries

**Objective:** Design, build, secure, and operate a **reusable Salesforce platform
package** plus a **bidirectional integration** to an external SaaS, through the same full
auditable ALM cycle the todo-app used — so the integration and platform-enabler concepts
the JD marks "Must have" are exercised hands-on against the real platform.

**In scope:** a base unlocked package exposing a public Apex API (logging/error
framework + generic event publisher + outbound callout framework); Named Credentials +
External Services; Platform Events and/or inbound Apex REST; idempotency + retry +
resilience; a self-built **mock SaaS on Vercel** as the 3rd-party counterpart;
cross-package dependency (todo-app consumes the base package); integration test pyramid
(HttpCalloutMock → Platform Event bus → contract → e2e); integration-failure /
breaking-change / secrets-rotation runbooks with executed drills; observability
(monitoring + alerting surface) and backup/encryption design.

**Out of scope:** real middleware (MuleSoft/Boomi), Data Cloud, paid Shield (design-only),
real enterprise SSO federation, load/stress testing, real multi-team SAFe ceremonies.
See "Deferred".

**Stack:** Salesforce DX (sf CLI), Apex (+ minimal LWC for the monitoring surface),
unlocked packages (2GP, base + dependency), Named Credentials + External Services,
Platform Events, GitLab CI (consuming the todo-app's reusable CI template), Salesforce
Code Analyzer (PMD), Apex tests + `HttpCalloutMock` + Platform Event test bus + Playwright
e2e, Mermaid diagrams. **External peer:** a tiny Next.js/serverless "FRS mock service" on
Vercel (REST endpoints for SF outbound; receives SF webhooks/events; calls back into SF).

**Environment constraint (known limitation):** no paid org and no real middleware. Free
substitutes keep the *concepts* intact — and the substitution reasoning is itself the
JD-relevant artifact:

| Real-world / JD concept | This project |
|---|---|
| 3rd-party FRS / external SaaS system | Self-built mock service on Vercel (we control both ends + the failure modes) |
| Enterprise middleware (MuleSoft) | Direct Named Credential callout + Platform Events; document where middleware *would* sit |
| Production org | Developer Edition org #1 ("prod") — same orgs as todo-app |
| Dev Hub | Developer Edition org #2 (Dev Hub enabled) |
| Sandboxes (dev / QA / staging) | Scratch orgs (per-branch / seeded / RC-built) — same model as todo-app |
| Secrets vault / rotation | Named Credential + GitLab CI variables; rotation rehearsed as a drill |
| Shield Platform Encryption | Classic encrypted fields + a documented Shield design (no paid Shield) |

The real integration architecture (middleware placement, mTLS, enterprise SSO, event bus
sizing) is still *documented* in Phase 3 as if for the real FRS estate — that's the
JD-relevant artifact even where the free tier can't run it.

## Current Baseline

Greenfield. `projects/platform-enablement/` contains this plan and `progress.txt` only.
Reuses the proven assets and gotchas from `projects/todo-app/` (org farm, glab/CI auth
patterns, scratch-budget discipline, Summer '26 API pin). The two Developer Edition orgs
and the GitLab account already exist from the todo-app.

## Capability Map (greenfield)

1. Governance — platform-as-product charter, consumer-contract & breaking-change control
2. Requirements — platform-component APIs + integration FRs/NFRs + traceability
3. Architecture — integration + trust-boundary + package-dependency diagrams, ADRs (before code)
4. Delivery platform — base-package DX project, Vercel mock service, GitLab CI via the reusable template
5. Walking skeleton — base package v0.1.0 + one event + one proven callout end-to-end
6. Core platform components & integration — Logger framework, event publisher, bidirectional integration with retry/idempotency
7. Test strategy — HttpCalloutMock, event bus, contract, resilience, e2e; consumer-compat tests
8. Release & operations — dependency-ordered release, integration-failure / deprecation / secrets-rotation drills
9. Platform deepening — observability (monitor/alert), metrics/SLOs, second consumer, backup/encryption design

---

## Phase 1 — Governance and Platform Charter

**Study tie-in:** planning-governance, application-lifecycle-management.
**JD tie-in:** "change-management controls, auditability, release governance"; "platform
patterns and technical best-practices… to increase adoption."

**Goal:** Decide how a *platform team* works — which differs from an app team in one key
way: it has **consumers**, so its public API is a contract.

**Deliverables (in `docs/governance/`):**
- `charter.md` — purpose; platform-as-product framing; simulated roles (Platform Engineer,
  Release Manager, Consumer App Lead, InfoSec partner, CCB); segregation-of-duties for who
  approves an API change vs. a release.
- `api-governance.md` — **the differentiator vs. todo-app**: what counts as the package's
  *public* API (annotated `global`/`public`) vs. internal; semver rules for that API
  (additive = minor, breaking = major); a **deprecation policy** (deprecate → warn →
  remove over N versions); consumer-notification procedure.
- `change-management.md` — change classes mapped to release paths, including a new class:
  **breaking API change** (requires consumer sign-off).
- `definition-of-done.md` — reviewed, tests pass, static analysis clean, RTM updated,
  **public-API doc + contract updated**, consumer impact assessed.
- `decision-log/ADR-001-packaging-model.md` — base package + extension package(s) vs.
  monolith; why a dependency model proves "reusable for multiple teams."

**Dependencies:** none. **Risks:** over-engineering paperwork — each doc ~1 page; reuse
todo-app governance verbatim where it already fits.

**Acceptance criteria:** all docs exist; each cites the study topic + JD line; API
governance defines public-surface rules and a deprecation timeline; change table includes
the breaking-API class.

## Phase 2 — Requirements (Platform Capabilities + Integration)

**Study tie-in:** ALM Plan stage, testing-methodologies (RTM); integration deck
`evaluate-current-system-landscape` + `analyze-system-landscape-constraints-and-pain-points`
(the discovery step the deck puts *before* design).
**JD tie-in:** "explicit APIs and abstractions"; "Must have integration patterns"; "Works
with business/technology partners to identify, define… scope of Salesforce integrations."

**Goal:** Requirements precise enough to test against — for both the **reusable API** and
the **integration behavior** — preceded by the deck's landscape discovery so the
integration is *justified*, not assumed.

**Deliverables (in `docs/requirements/`):**
- `system-landscape.md` — the integration deck's discovery artifact: current-state system
  inventory (Salesforce + the FRS/Vercel external system), data ownership/system-of-record,
  the constraints & pain points driving the integration, and the integration decision
  framework (timing/direction/pattern selection) applied to *this* case. This is what you'd
  hand a business/tech partner when scoping an integration.
- `functional-requirements.md` — Given/When/Then, stable IDs (FR-1…):
  - **Platform API:** `Logger.log()/error()` API consumable by any app; a generic
    `EventPublisher.publish()` API; a `CalloutService` API with built-in retry.
  - **Outbound integration:** on a domain event (e.g. todo completed) Salesforce calls the
    Vercel mock service via Named Credential; success/failure is logged + auditable.
  - **Inbound integration:** the Vercel service calls back into Salesforce (Platform Event
    publish via REST, or inbound Apex REST) and a record is updated **idempotently**
    (duplicate delivery causes no double-effect).
  - **Resilience:** timeouts, retry with backoff, and a poison-message/replay path.
- `non-functional-requirements.md` — measurable NFRs: integration security (Named
  Credential only, no hard-coded secrets/endpoints, least-priv inbound user); API stability
  (no breaking change without major bump); idempotency (proven by a duplicate-delivery
  test); governor-limit safety (callouts off the synchronous transaction; ≤100 callouts;
  no callout-after-DML errors); observability (every integration attempt produces a log
  record with correlation id); resilience (defined RTO for a failed integration replay);
  coverage ≥85%; zero Code Analyzer criticals.
- `integration-contract.md` — the **API contract** with the Vercel service: endpoints,
  request/response schemas, auth, error codes, idempotency-key semantics, retry
  expectations. This is the artifact both sides build against.
- `rtm.md` — Requirements Traceability Matrix skeleton (every FR/NFR → design → component
  → test).
- `risk-register.md` — integration-specific risks (third-party downtime, secret leakage,
  event-bus limits, replay storms) with mitigations.

**Dependencies:** Phase 1. **Risks:** scope creep into a full iPaaS — CCB hat holds the
line; the integration is a *thin proof*, not a product.

**Acceptance criteria:** every FR testable; every NFR measurable; the contract is concrete
enough that the Vercel service and the Apex side can be built independently against it;
RTM covers 100% of IDs.

## Phase 3 — Architecture and Diagrams

**Study tie-in:** system-design-* , security model; integration deck
`evaluate-authentication-and-authorization-needs` + `references.html` (decision framework,
outbound callouts & endpoint management, authentication/authorization & connected apps,
OAuth flows, security keys / auth hardening).
**JD tie-in:** "design… of platform services… enterprise patterns"; "Partner with InfoSec";
"Must have security model."

**Goal:** Design the integration and the trust boundary on paper first.

**Deliverables (in `docs/architecture/`, diagrams as Mermaid):**
- `integration-architecture.md` — context diagram (SF ↔ Vercel), the sync vs. async
  decision, where enterprise middleware *would* sit, and why each pattern was chosen.
- `sequence-diagrams.md` — outbound callout (happy + timeout + retry), inbound event/REST
  (happy + duplicate delivery → idempotent no-op), poison-message replay.
- `security-trust-boundary.md` — Named Credential auth model, secret storage + rotation
  approach, least-privilege integration user, inbound authentication, data-in-transit
  notes, the **InfoSec partnership artifact** (what you'd hand Security for sign-off).
  Grounded in the deck's `evaluate-authentication-and-authorization-needs` (which OAuth flow
  for which direction; Connected App vs. External Client App; auth-hardening choices).
- `package-dependency.md` — base package ↔ consumer (todo-app) dependency diagram; install
  ordering; how a consumer declares the dependency.
- `public-api-spec.md` — the documented Apex public surface (signatures, contracts,
  stability guarantees) — the "explicit APIs and abstractions" deliverable.
- ADRs: `ADR-002-integration-pattern.md` (callout vs. Platform Event vs. CDC for each
  direction), `ADR-003-retry-idempotency.md` (strategy + idempotency-key design),
  `ADR-004-error-logging-architecture.md` (Platform-Event-backed logging so logs persist
  even after a rollback), `ADR-005-auth-flow.md` (OAuth flow + Connected/External Client
  App choice per direction, grounded in the auth-needs topic + references).
- Fill RTM design column for every FR/NFR.

**Dependencies:** Phase 2. **Risks:** analysis paralysis — timebox; the diagrams are
talking points, not blueprints for a product.

**Acceptance criteria:** each integration direction has a happy + failure sequence diagram;
trust boundary + secret handling documented; package dependency diagrammed; public API
spec drafted; ADRs record the pattern choices with trade-offs.

## Phase 4 — Source Control, Orgs, Vercel Service, and CI

**Study tie-in:** source-driven development, deployment strategy.
**JD tie-in:** "develops/maintains automation for deployments"; GitLab CI; "supporting
multiple application teams."

**Goal:** Stand up the delivery platform for both sides, **consuming the todo-app's
reusable CI template** as the proof-of-reuse.

**Deliverables:**
- Salesforce DX project for the **base package** (`sfdx-project.json` with the package
  registered in Dev Hub; reuse the API-67 pin + `.forceignore` patterns from todo-app).
- New GitLab project (e.g. `sf-platform-enablement`); `main` protected, MR-only — mirror
  the todo-app repo settings.
- `.gitlab-ci.yml` that **`include:`s the todo-app's `ci-templates/`** (Phase 9 of that
  project) — this is the second-consumer validation; document any gaps the real adoption
  exposes (template bugs are *findings*, not annoyances).
- The **Vercel mock service**: a tiny Next.js/serverless app (REST endpoint for SF outbound,
  a webhook receiver, and an outbound caller into SF), with its own deploy. Keep it minimal;
  it is cargo. Its contract = `integration-contract.md`.
- CI variables: Named Credential secrets / Vercel API key stored masked+protected (reuse
  the base64 + protected-ref lessons from todo-app's progress NOTES).
- `docs/devops/pipeline-design.md` — stages/gates for this repo, incl. the integration-test
  job (HttpCalloutMock + event bus) and how the Vercel service is deployed/verified.

**Dependencies:** Phase 3; todo-app Phase 9 reusable template existing.
**Risks:** scratch-org budget shared with todo-app work (6 creates/day) — count before
pushing; Vercel auth in headless sessions (see todo-app sf-session-auth lesson, analogue).

**Acceptance criteria:** base package registered; pipeline green consuming the reusable
template; Vercel mock service deployed and reachable; a planted failing integration test
goes red then green (gates bite).

## Phase 5 — Walking Skeleton

**Study tie-in:** walking-skeleton / tracer-bullet.
**JD tie-in:** "delivering Salesforce solutions from design to production."

**Goal:** One thin slice through every layer, released as v0.1.0.

**Deliverables:**
- Base package v0.1.0: a minimal `Logger.log(String)` public API writing one
  `Platform_Log__e` Platform Event (or `Log__c`), with a consumer test.
- One real **outbound callout** to the Vercel `/health` endpoint via Named Credential,
  proven with an `HttpCalloutMock` unit test **and** a real call in a scratch org.
- Vercel service answering `/health` and logging the inbound hit.
- Package version 0.1.0.1 created by CI, installed in "prod"; tag `v0.1.0` + `CHANGELOG.md`;
  smoke-test checklist recorded; RTM rows for the skeleton FRs/NFRs → verified.

**Dependencies:** Phase 4. **Risks:** callout-from-test pitfalls — mock in unit tests,
real call only in the scratch-org smoke step.

**Acceptance criteria:** base package installed in prod; round-trip SF→Vercel proven live;
smoke test recorded; tag + changelog done.

## Phase 6 — Core Platform Components & Bidirectional Integration

**Study tie-in:** integration patterns, async Apex, secure coding.
**JD tie-in:** "Must have integration patterns"; "reusable components"; "logging…
patterns"; async/batch + governor limits.

**Goal:** Build the real reusable layer and the full round-trip, each as its own MR mapped
to an FR.

**Deliverables:**
- **Logger / error framework** — Platform-Event-backed so log records survive a rolled-back
  transaction; severity levels; correlation id; a consumer-facing API; the
  `@SuppressWarnings`/quarantine discipline from todo-app for any `without sharing`.
- **Generic `EventPublisher`** — a thin, testable wrapper over `EventBus.publish`.
- **Outbound `CalloutService`** — Named Credential + External Services; retry with backoff;
  callout executed in async context (Queueable) to respect callout-after-DML + 100-callout
  limits; bulk-safe.
- **Inbound path** — Vercel → SF via Platform Event publish (REST) or inbound Apex REST;
  **idempotent** apply keyed by an idempotency key (duplicate delivery = no double effect).
- **The round-trip** — todo completion (consumer event) → base package publishes event →
  callout to Vercel → Vercel webhook back → SF updates record + Logger records the whole
  correlation chain.
- **todo-app as consumer #1** — todo-app declares the base-package dependency and calls the
  Logger/EventPublisher API (a small MR in that repo or a documented integration branch).
- Every MR: positive, negative, `runAs`/permission, and **idempotency** tests; coverage
  ≥85%; RTM updated.

**Dependencies:** Phase 5. **Risks:** mega-MRs — one FR per MR; callout governor traps —
prove the async + bulk path with a 200-record test.

**Acceptance criteria:** all integration FRs implemented and traceable; duplicate-delivery
test proves idempotency; round-trip works end-to-end in a scratch org with the full
correlation chain visible in logs; todo-app successfully consumes the base API.

## Phase 7 — Test Strategy Expansion

**Study tie-in:** testing-methodologies (pyramid), test-data strategy.
**JD tie-in:** SFDX test automation, static analysis, e2e; secure, quality engineering.

**Goal:** Round out the **integration** test pyramid — the part the todo-app never had.

**Deliverables:**
- `HttpCalloutMock` / `HttpCalloutMockResponse` suites for every outbound path incl.
  timeout, 4xx, 5xx, malformed body.
- **Platform Event test harness** using `Test.getEventBus().deliver()` to assert
  subscriber behavior deterministically.
- **Contract tests** against the Vercel mock (the running service must satisfy
  `integration-contract.md`) — run in CI against the deployed mock.
- **Resilience tests** — retry exhaustion → poison path; duplicate delivery → idempotent.
- **Consumer-compatibility test** — a test proving the public API surface didn't break
  (the deprecation policy made executable).
- Playwright/e2e across the boundary for the headline round-trip journey.
- `docs/testing/test-strategy.md` (integration pyramid, what each level catches,
  mock-vs-real rule) and `docs/testing/test-data-strategy.md` (synthetic + correlation-id
  seeding); RTM test column filled.

**Dependencies:** Phase 6. **Risks:** e2e flakiness across a network boundary — timebox,
document the mock-vs-real trade-off; that judgment *is* the learning.

**Acceptance criteria:** RTM test column 100% filled; resilience + idempotency proven by
failing-then-passing tests; contract test green against the deployed Vercel mock;
consumer-compat test guards the public API.

## Phase 8 — Release Management and Operations

**Study tie-in:** release-management-strategy, operating-direct-changes-production.
**JD tie-in:** "Performs Salesforce release evaluations"; Tier 3 support; deployment
automation; "operationalization of reusable components."

**Goal:** Operate the platform like a platform — including the failure modes a *reusable,
integrated* layer introduces that a standalone app doesn't.

**Deliverables (in `docs/release/`):**
- `release-runbook.md` — **dependency-ordered** release: base package version validated in
  staging, then consumer install order; CCB approval; smoke; comms.
- `rollback-runbook.md` — rollback of a base package that has consumers (the harder case);
  schema-additive + API-additive policy so consumers survive a downgrade; **rehearsed once**.
- **Integration-failure runbook + live drill** (the "earns its keep" drill, analogue of the
  todo-app hotfix drill): simulate Vercel down / callout timeout / poison event — detect
  via the Logger surface, retry, manually replay, communicate; document RTO. *Expect the
  drill to expose a wrong assumption in the runbook — that finding is the deliverable.*
- **Breaking-change / deprecation drill** — ship base package v2 that evolves the public
  API via deprecate-then-remove; prove the todo-app consumer keeps working across the
  upgrade; document the consumer-notification cycle.
- `secrets-rotation-runbook.md` + **rotation drill** — rotate the Named Credential / Vercel
  API key with zero downtime; prove callouts keep working through the rotation.
- `salesforce-release-readiness.md` — seasonal-release impact assessment focused on
  **integration + API** surface (e.g. secure-by-default Apex, Named Credential changes).
- `post-release-review-template.md` + completed retro for `v1.0.0`.
- Release `v1.0.0` — full integration + platform API set, tagged, changelog, RTM frozen.

**Dependencies:** Phases 6–7. **Risks:** runbooks written but never executed — the three
drills (integration-failure, deprecation, secrets-rotation) are **mandatory** acceptance
criteria, same rule as the todo-app.

**Acceptance criteria:** `v1.0.0` installed in prod with consumer; rollback rehearsed;
integration-failure drill completed end-to-end with replay; deprecation drill proves a
non-breaking consumer upgrade; secrets rotated with zero downtime; retro written.

## Phase 9 — Platform Deepening: Observability, Reuse, and Hardening

**Study tie-in:** operating-managing-common-release-artifacts, deployment strategy.
**JD tie-in:** the core of the role — "patterns for logging, monitoring, alerting, backup,
encryption"; "increasing adoption, operational efficiency"; "supporting multiple
application teams."

**Goal:** Turn the components into an operable, observed, *adopted* platform.

**Deliverables:**
- **Observability surface** — a small LWC dashboard / report over the log Platform Events:
  integration success rate, latency, recent failures; the JD's "monitoring." Plus
  **alerting** on integration failure (e.g. a flow/email/Platform Event on N failures) —
  the JD's "alerting."
- **Integration SLOs + DORA-style metrics** — `docs/devops/platform-metrics.md`: callout
  success rate, p95 latency, mean-time-to-replay, deployment frequency/lead time/CFR from
  this project's real history.
- **Second consumer (proof of reuse)** — a throwaway stub app/package that consumes the
  base Logger + CalloutService API with zero code changes to the base, proving the
  abstraction is reusable across teams (the JD's literal "multiple application teams").
- **Backup & encryption patterns** — `docs/architecture/backup-and-encryption.md`: the
  Shield Platform Encryption design (free-tier: classic encrypted fields + documented
  Shield design), data-backup approach for the log/audit data, key-management notes — the
  JD's "backup, encryption" platform patterns.
- **Onboarding doc** — `docs/devops/consumer-onboarding.md`: zero-to-consuming-the-platform
  for a new app team; time yourself following it.

**Dependencies:** Phase 8 (needs real history + a working platform).
**Risks:** scratch-org/Vercel limits constrain experiments — batch them, document the
constraint as a real platform consideration.

**Acceptance criteria:** monitoring surface shows real integration data; alerting fires on
induced failure; second consumer adopts the base API with no base changes; backup +
encryption design documented; onboarding doc walked end-to-end.

---

## Out of Scope / Deferred

- **Real middleware (MuleSoft/Boomi/iPaaS)** — documented where it would sit; not built.
- **Data Cloud** (JD "preferred") — honest gap; study-only, no free playground assumed.
- **Paid Shield Platform Encryption, real enterprise SSO federation** — design-only.
- **Load/stress testing of the integration, event-bus scale tuning** — discussed, not run.
- **Real multi-team SAFe ceremonies** — simulated via consumer-contract governance only.

## Relationship to `projects/todo-app/`

| | todo-app | platform-enablement (this) |
|---|---|---|
| Role played | Application team | **Platform team serving app teams** |
| The "product" | The CI/CD pipeline | **The reusable components + integration** |
| Primary JD lines | DevOps & CI/CD (~80%) | **Integration patterns + platform enablers** (the "Must have" gaps) |
| Reuses | — | todo-app orgs, CI template, glab/auth + scratch-budget lessons |
| Validates | — | todo-app's "second team adopts the CI template" criterion |
| Consumer | itself | todo-app (consumer #1) + a stub (consumer #2) |

## Immediate Next Steps

1. Phase 1: write the governance docs in `docs/governance/` — reuse todo-app's where they
   fit; the new artifact is `api-governance.md` (public-API + deprecation policy).
2. Confirm the integration FR list in Phase 2 shows what you want to *demo in interviews*
   (the bidirectional round-trip + idempotency + the failure drill are the talking points).
3. Decide the base-package name and the Vercel service name; register the base package in
   the existing Dev Hub (counts against the daily package-version build budget, separate
   from scratch creates — see todo-app NOTES).
