# System Landscape & Integration Discovery

> **Phase 2.0a deliverable.** The Integration Architect deck puts *discovery before design*:
> evaluate the current landscape, inventory the systems and the patterns that connect them,
> surface constraints and pain points, classify the data, and only then choose patterns and
> auth. This document does that for the platform-enablement project — it is the artifact you
> would hand a business/technology partner when scoping the integration, and the source the
> Phase 2 functional/non-functional requirements draw from.
>
> **Grounded in** `study/architect-certification-guides/integration/` topics:
> `evaluate-current-system-landscape`, `inventory-systems-and-integration-patterns`,
> `analyze-system-landscape-constraints-and-pain-points`,
> `evaluate-system-and-process-constraints`,
> `classify-integration-data-confidential-secure-public`,
> `evaluate-authentication-and-authorization-needs`,
> `identify-business-growth-and-regulatory-factors-for-integration-solutions`,
> `identify-performance-needs-and-integration-solutions`, and `references.html`.
>
> **Free-tier honesty:** the "FRS external system" is *simulated* by a mock SaaS we build on
> Vercel (we control both ends and the failure modes — required for the Phase 8 drills). The
> landscape is documented as if for the real FRS estate; where the free tier diverges, it is
> called out. That reasoning is itself the JD-relevant artifact.

---

## 1. Purpose & driving question

A platform team exists to deliver *reusable enablers in support of business products*
(the JD's core sentence). Before building anything, discovery answers two questions:

1. **What is the current landscape**, and what pain in it justifies a platform integration
   layer — rather than each app team hand-rolling its own?
2. **Which integration patterns, data classifications, and auth primitives** does that
   landscape demand?

The answers below feed directly into the Phase 2 FRs/NFRs and the Phase 3 ADRs.

## 2. Current system landscape

*(deck: `evaluate-current-system-landscape`)*

| System | Role | System of record for | Tech / hosting | In scope |
|---|---|---|---|---|
| **Salesforce platform** (Dev Edition "prod" + Dev Hub) | The CRM platform the FRS app teams build on | Todo records, audit/log events, integration correlation data | Salesforce (API 67 / Summer '26) | Yes — the platform we enable |
| **`todo-app`** (`projects/todo-app/`) | First consuming **application team** | Its own `Todo__c` domain | Apex + LWC unlocked package | Yes — consumer #1 |
| **Stub consumer #2** (Phase 9) | Proof the enabler is reusable, not bespoke | n/a (throwaway) | Apex unlocked package | Yes — reuse proof |
| **"FRS External Service"** | A 3rd-party / heterogeneous SaaS the FRS estate must exchange data with | External case/notification status | **Simulated** by a Next.js mock on Vercel | Yes — the integration peer |
| Enterprise middleware (MuleSoft/iPaaS) | Where an enterprise would broker integrations | — | — | **No** — documented where it *would* sit (§7) |
| Data Cloud | JD "preferred" | — | — | No — honest gap |

**Topology (target):**

```
  app teams (todo-app, consumer #2)
        │  call the public API
        ▼
  ┌─────────────────────────────┐        outbound (async, fire-and-forget)
  │  PLATFORM ENABLEMENT LAYER   │  ───────────────────────────────────▶  ┌──────────────┐
  │  (base unlocked package)     │        Named Credential + OAuth         │ FRS External │
  │  Logger · EventPublisher ·   │                                         │  Service     │
  │  CalloutService              │  ◀───────────────────────────────────  │ (Vercel mock)│
  └─────────────────────────────┘        inbound (Remote Call-In)         └──────────────┘
                                          Connected App + OAuth, idempotent
```

## 3. Systems & integration-pattern inventory

*(deck: `inventory-systems-and-integration-patterns`; pattern catalog + layer approach from
`references.html`)*

Each integration scenario is classified the deck's way — **layer · direction · timing ·
volume · transactionality · failure handling · who initiates** — and mapped to one of the
six canonical patterns (Remote Process Invocation Request/Reply, RPI Fire-and-Forget, Batch
Data Synchronization, Remote Call-In, UI Update Based on Data Changes, Data Virtualization).

| # | Scenario | Layer | Direction | Timing | Initiator | Canonical pattern | Why this pattern |
|---|---|---|---|---|---|---|---|
| **S1** | Notify FRS when a business event occurs (e.g. todo completed) | Process | SF → FRS | Async | Salesforce | **RPI — Fire-and-Forget** | No business response needed; decouple to dodge callout-after-DML + governor limits; failure must not block the user transaction |
| **S2** | FRS reports status back into Salesforce | Data/Process | FRS → SF | Async (near-real-time) | External | **Remote Call-In** | External system initiates; must be idempotent against duplicate delivery; uses Platform Event publish (REST) or inbound Apex REST |
| **S3** | Reusable logging surface for app teams | Data → UI | Internal | Async | Salesforce | **UI Update Based on Data Changes** | Platform-Event-backed logs persist through rollback and drive a monitoring surface (Phase 9) |
| **S4** *(considered, deferred)* | Bulk reconciliation of FRS status nightly | Data | Bidirectional | Async batch | Scheduler | **Batch Data Synchronization** | Documented as the fallback if event delivery gaps appear; not built (event-first) |

**Layer-approach note:** S1/S2 live at the **business-process** layer (an event drives a
process across systems), not the UI layer — so they belong in Apex/async, not in a flow or
LWC. S3 is a **data→UI** concern. No **Data Virtualization** (no need to surface live
external data in SF UI) and no real-time **Request/Reply** (we deliberately decouple) — both
are named-and-excluded so the pattern selection is defensible.

## 4. Constraints & pain points

*(deck: `analyze-system-landscape-constraints-and-pain-points`,
`evaluate-system-and-process-constraints`)*

**Pain points driving the project (the "why integrate / why a platform layer"):**

- **P1 — Duplicated, ungoverned integration code.** Each app team hand-rolls callouts and
  logging → hard-coded endpoints/secrets, inconsistent error handling, no central auth
  governance. *A reusable enabler with Named Credentials fixes the security + portability
  problem at the platform level.* (This is the JD's literal rationale for the role.)
- **P2 — No durable observability.** When an integration fails mid-transaction, the failure
  is rolled back with the transaction and lost. *Platform-Event-backed logging survives
  rollback.*
- **P3 — Manual reconciliation with the external FRS system.** Status drifts between SF and
  FRS with no automated exchange. *S1 + S2 close the loop.*
- **P4 — Duplicate/replayed external calls cause double effects.** Without idempotency,
  Remote Call-In retries corrupt data. *Idempotency-key design (Phase 3 ADR-003).*

**Technical constraints (the free-tier + platform reality):**

| Constraint | Source | Design impact |
|---|---|---|
| Synchronous callout limits: ≤100 callouts/transaction, 120s total, **no callout after uncommitted DML** | Salesforce governor limits | S1 callout runs in async (Queueable) off the event, never inline after DML |
| Platform Event publish/delivery limits on Dev Edition | Edition limits | Keep event volume low; document where higher tiers/event bus sizing matter |
| Daily API request caps on Dev Edition | Edition limits | Contract tests batched; no chatty polling |
| **6 scratch-org creates/day, shared with todo-app**; package builds a separate 6/day | Free Dev Hub | Count before pushing; batch integration experiments |
| No real sandboxes; no paid Shield; no real SSO federation | No paid org | Sandboxes → scratch orgs; encryption/SSO are **design-only** (Phase 9) |
| No enterprise middleware | Free tier | Direct callout + events; document the middleware seam (§7) |

**Process constraints:** solo engineer wearing all hats (Platform Eng / Release Mgr /
Consumer Lead / InfoSec) → segregation-of-duties is *simulated* via the governance hats
(Phase 1); changes flow MR-only through CCB-hat approval.

## 5. Data classification

*(deck: `classify-integration-data-confidential-secure-public`; `references.html` data
classification)*

Classify the data *before* choosing transport, storage, encryption, retention, and logging
behavior.

| Data element | Classification | Crosses the boundary? | Handling |
|---|---|---|---|
| Todo business fields (title, status, due date) | **Internal** | Yes (S1 payload) | Minimal payload; only fields FRS needs |
| Correlation id / idempotency key | **Internal** | Yes (both directions) | Non-sensitive; enables tracing + dedupe |
| Integration log records (errors, payload fragments) | **Confidential** | No (stays in SF) | Avoid logging secrets/PII; redact payloads; retention + purge policy (reuse todo-app audit-purge pattern) |
| Named Credential secrets / OAuth tokens / API keys | **Restricted** | n/a | Never in code or logs; Named/External Credentials + CI vars; rotation drill (Phase 8) |
| PII | **None in scope** | — | Deliberately kept out of the demo payload; the *framework* (residency, consent, deletion, audit) is documented for the FRS regulatory context |

**Regulatory framing** *(deck:
`identify-business-growth-and-regulatory-factors-for-integration-solutions`):* the FRS is a
financial-services / federal context → even with synthetic data, the design names the
shared-responsibility boundary (Salesforce platform controls + customer-owned access model,
backup, monitoring, audit), least-privilege integration access, and full auditability of
every cross-boundary exchange. **Growth factor:** the enabler must scale from one app team
to many without per-team rework — the core success measure (proven by consumer #2).

## 6. Authentication & authorization needs

*(deck: `evaluate-authentication-and-authorization-needs`,
`identify-integration-security-authentication-authorization-requirements`; `references.html`
auth section)*

Per the deck's rule — *don't pick "OAuth" generically; pick the flow by actor,
interactivity, and secret handling*:

| Direction | Actor | Primitive | Flow | Rationale |
|---|---|---|---|---|
| **Outbound** (S1: SF → FRS) | Server-to-server, no user | **Named Credential + External Credential** | OAuth 2.0 **Client Credentials** (or API-key header) to the Vercel service | Keeps endpoint + secret out of Apex (`callout:Name/path`); environment-portable; centrally governed; no Remote Site Settings |
| **Inbound** (S2: FRS → SF) | Server-to-server, no user | **Connected App** + least-privilege **integration user** | OAuth 2.0 **JWT Bearer** (or Client Credentials) | Connected App is the control plane: scopes, IP/session policy, admin approval; integration user holds only the perms needed to publish the event/write the record |

**Auth hardening** *(references.html: Security Keys):* for the high-trust FRS posture,
document MFA / phishing-resistant factors for any human admin of the Connected App, and a
least-privilege Connected App policy (minimum scopes, IP ranges, short token lifetime). This
becomes **ADR-005-auth-flow** and the `security-trust-boundary.md` InfoSec handoff artifact
in Phase 3.

## 7. Where enterprise middleware would sit (documented, not built)

In the real FRS estate, S1/S2 would likely traverse an integration/middleware tier
(MuleSoft/iPaaS) providing routing, transformation, throttling, and a canonical data model.
This project goes **point-to-point** (direct Named Credential callout + Platform Events)
because (a) the free tier has no middleware and (b) the learning target is the *Salesforce*
integration primitives. The seam is documented so the design is honest: the
`CalloutService` abstraction is the insertion point where a middleware endpoint would later
replace the direct FRS endpoint with **zero consumer changes** — which is exactly the
"explicit abstraction for app developers" the JD asks for.

## 8. Performance needs

*(deck: `identify-performance-needs-and-integration-solutions`)*

- **Non-blocking:** S1 must never delay the user's save → async (event → Queueable callout).
- **Bulk-safe:** a 200-record bulk operation must not breach callout/SOQL/DML limits → proven
  by a 200-record test (Phase 6/7).
- **Resilient:** timeout + retry-with-backoff; a poison-message/replay path; idempotent S2.
- **Observable:** every attempt emits a log with a correlation id (S3) → success rate + p95
  latency become the Phase 9 SLOs.

Seed SLO targets (refined into NFRs in Phase 2.2): outbound success rate ≥ 99% over a
rolling window; mean-time-to-replay a failed integration within the documented RTO; zero
double-effects under duplicate delivery.

## 9. Discovery summary → "fast answer" applied

*(references.html fast-answer template, applied to this case)*

> *Classify the integration:* business-process layer; one async **fire-and-forget** outbound
> (SF→FRS) and one async **Remote Call-In** inbound (FRS→SF), low volume, SF-or-external
> initiated, failure must not block the user. *Classify the data:* internal business fields +
> internal correlation ids crossing the boundary; confidential logs staying in SF; restricted
> secrets; no PII in scope but the regulatory framework is named for the FRS context. *Choose
> patterns:* decouple via Platform Events + Queueable callouts (no inline Request/Reply), no
> Data Virtualization, batch sync held as fallback. *Choose auth:* Named/External Credentials
> for outbound, Connected App + least-privilege integration user for inbound, never secrets in
> code.

## 10. What this feeds

| Discovery output | Flows into |
|---|---|
| Scenarios S1–S3 + pattern selection | Phase 2.1 functional requirements (FR IDs) |
| Constraints, data classification, performance/SLO seeds | Phase 2.2 non-functional requirements |
| Auth matrix (§6) + middleware seam (§7) | Phase 3 `security-trust-boundary.md`, ADR-002 (pattern), ADR-005 (auth) |
| API contract implied by S1/S2 payloads | Phase 2.3 `integration-contract.md` (the SF↔Vercel contract) |
| Pain points P1–P4 | The project's justification + interview narrative |

---

*Open follow-up:* the source decks (`evaluate-current-system-landscape` et al.) are
image-only PDFs — no extractable text — so this discovery applies the **deck titles + the
`references.html` framework** rather than quoting slides. If specific slide content should be
reflected, review the embedded viewer and flag deltas.
