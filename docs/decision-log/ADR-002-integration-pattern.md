# ADR-002: Integration Pattern Selection

- **Status:** Accepted
- **Date:** 2026-06-17
- **Deciders:** Architect hat (CCB consulted)

> **Exercises:** integration deck `inventory-systems-and-integration-patterns`,
> `references.html` (canonical pattern catalog + layer approach),
> `identify-performance-needs-and-integration-solutions`.
> **JD lines:** "Must have integration patterns"; async Apex + governor limits.
> **Constrains:** FR-5, FR-8, FR-11; NFR-4. **RTM design coverage:** FR-5, FR-8, S1/S2.

## Context

`system-landscape.md` classified three live scenarios; each must be mapped to a canonical
pattern (the six from `references.html`: RPI Request/Reply, RPI Fire-and-Forget, Batch Data
Synchronization, Remote Call-In, UI Update Based on Data Changes, Data Virtualization). The
deck's rule: choose by **type, timing, direction, volume, transactionality, failure handling,
and who initiates**. The platform constraints (NFR-4): no callout after uncommitted DML, ≤100
callouts/transaction, 120s, and the user transaction must never block on an external system.

## Decision

| Scenario | Pattern | Mechanism |
|---|---|---|
| **S1** SF → FRS notify | **RPI — Fire-and-Forget** | Consumer calls `EventPublisher.publish(domain event)` → platform subscriber (Apex trigger on the Platform Event) **enqueues a Queueable** (`Database.AllowsCallouts`) → callout via `CalloutService`. |
| **S2** FRS → SF status | **Remote Call-In** | Inbound **custom Apex REST** resource (`@RestResource` at `/frs/v1/status`) applies the update idempotently and returns `applied`/`duplicate` synchronously. |
| **S3** logging/observability | **UI Update Based on Data Changes** | Platform-Event-backed log stream feeds the Phase 9 monitoring surface (see ADR-004). |

**Excluded, on purpose** (naming the rejected patterns is the deck's discipline):
- **RPI Request/Reply (synchronous):** would block the user transaction and hit
  callout-after-DML — violates NFR-4. Rejected for S1.
- **Data Virtualization (Salesforce Connect / OData):** no requirement to surface live
  external data in the SF UI; adds an adapter for no benefit. Rejected.
- **Batch Data Synchronization:** kept as the **documented fallback** (landscape S4) if event
  delivery proves lossy; not built now (event-first).

### Why a Platform Event as the S1 trigger (not a direct call)

| Option for S1 trigger | For | Against |
|---|---|---|
| Consumer calls `CalloutService` directly (inline) | Simplest | Callout-after-DML risk; couples the consumer to callout timing; not bulk-safe by default |
| Consumer calls `CalloutService` which enqueues a Queueable | Async, decoupled from user txn | Consumer still depends on the callout service shape; less evented |
| **Consumer publishes a domain Platform Event; platform subscribes + enqueues Queueable (chosen)** | Full producer/consumer decoupling (the platform owns *how* notification happens); same event bus reused for logging; naturally bulk-safe; matches FR-5 wording ("when an app raises a domain event") | One more hop; PE delivery semantics to understand (handled in ADR-003/004) |

### Why inbound custom Apex REST (not "publish a Platform Event via REST")

| Inbound option | For | Against |
|---|---|---|
| FRS publishes a Platform Event via the REST API | Fully async; no custom Apex endpoint | Idempotency + the synchronous `applied`/`duplicate` response (contract §4.2) are awkward; harder to authorize narrowly; FRS needs PE create permission |
| **Custom Apex REST resource (chosen)** | Full control of idempotent apply + synchronous response per contract; least-privilege integration user scoped to exactly this resource; clean auth via Connected App | We own the endpoint code + its tests |

## Consequences

- S1 path: **domain PE → trigger → Queueable → callout** is the bulk-safe, governor-safe
  spine (NFR-4); the 200-record test (FR-11) asserts callout/DML limits on it.
- The Platform Event bus is used for **two** purposes (domain events for S1, log events for
  S3) — one mechanism, learned once.
- Inbound is a custom REST surface → it is part of the **public/wire contract**
  (`integration-contract.md` §4) and governed by `api-governance.md`.
- Retry, backoff, dead-letter, and idempotency are deferred to **ADR-003**; log durability to
  **ADR-004**; auth to **ADR-005** — this ADR fixes only the pattern choice.
