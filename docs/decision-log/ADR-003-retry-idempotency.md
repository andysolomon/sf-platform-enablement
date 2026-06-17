# ADR-003: Retry, Backoff & Idempotency Strategy

- **Status:** Accepted
- **Date:** 2026-06-17
- **Deciders:** Architect hat

> **Exercises:** integration deck `identify-performance-needs-and-integration-solutions`,
> `references.html` (idempotency, fast-answer template); async Apex patterns.
> **JD lines:** "Must have integration patterns"; "performance optimization"; resilient,
> secure integration.
> **Constrains:** FR-6, FR-7, FR-9; NFR-3, NFR-5. **RTM design coverage:** FR-6, FR-7, FR-9.

## Context

S1 (outbound) must survive transient FRS failures; S2 (inbound) must not double-apply a
replayed message. Salesforce has **no native retry/backoff for callouts** and **no native
exactly-once delivery**, so both are designed explicitly. Constraints: Queueable depth/chain
limits, the inability to `System.enqueueJob` with arbitrary delay (delay is 0–10 minutes,
and limited on Developer Edition), and governor limits.

## Decision — Outbound retry & dead-letter (FR-6, FR-7, NFR-5)

- **Bounded retries:** max **3** attempts (configurable via custom metadata), classified by
  the contract's status table (§3.3): retry `429`/`5xx`/timeout; never `400`/`401`/`403`.
- **Backoff:** re-enqueue the callout Queueable with an increasing **`enqueueJob` delay**
  (e.g. 1 → 2 → 4 minutes, capped at the platform's 10-min max), honoring `Retry-After` on
  `429`. An **attempt counter** is carried on the work item.
- **Failure handling:** use a **Queueable Finalizer** to catch an unhandled failure of the
  callout job and decide retry-vs-dead-letter without losing the work (finalizers run even if
  the Queueable throws).
- **Dead-letter:** on exhaustion, write an `Integration_DeadLetter__c` record (correlation
  id, idempotency key, serialized payload ref, last error, attempt count) → satisfies FR-7
  and raises the Phase 9 alert condition.
- **Replay:** an operator action (`ReplayService`) re-enqueues from the dead-letter record
  using the **same idempotency key**, so a replay that the FRS already processed is safely
  deduped on their side (contract §3.3, `409` = success).

### Retry-mechanism options considered

| Option | For | Against |
|---|---|---|
| Synchronous in-Apex retry loop | Simple | Burns the 120s/transaction budget; no real backoff; blocks | 
| Scheduled Apex per retry | Arbitrary delay | Scheduler limits; heavyweight per message |
| **Queueable re-enqueue with delay + Finalizer (chosen)** | Async, real backoff via `enqueueJob` delay, finalizer guarantees failure handling, governor-friendly | Delay capped at 10 min (acceptable for this RTO); DE chain limits (documented) |

## Decision — Idempotency (FR-9, NFR-3)

- **Inbound** is keyed by the message's `Idempotency-Key`. On first apply, the handler
  **upserts** an `Integration_Message__c` record whose **External Id, Unique** field is the
  idempotency key, inside the same transaction as the record update. A duplicate key hits the
  **unique constraint** → handler returns `200 duplicate` with **no second effect** and logs
  a deduplicated delivery.
- **Outbound** carries a **stable idempotency key** per logical message (not per retry), so
  the FRS side dedupes our retries (contract §3.1/§3.3).
- **Correlation id** (distinct from the idempotency key) threads the whole round-trip for
  tracing (FR-10) and is stamped on every log event.

### Idempotency-store options considered

| Option | For | Against |
|---|---|---|
| Query-then-insert check | No new constraint | **Race condition** under concurrent delivery — two callers both see "not present" |
| Platform Cache | Fast | **Volatile** — eviction loses the dedupe guarantee; wrong for correctness |
| **Custom object with Unique External Id field (chosen)** | Platform-enforced uniqueness even under concurrency; durable; queryable for audit | One extra DML in the inbound transaction (acceptable) |

## Consequences

- Retry/idempotency are **testable**: retry-exhaustion → dead-letter test, replay test, and
  the duplicate-delivery → no-op test (NFR-3) — all in Phase 7; the timed replay drill proves
  the 30-min RTO (NFR-5) in Phase 8.
- The unique-key upsert makes inbound **correct under concurrent duplicate delivery**, not
  just sequential — the failure mode the todo-app never had to consider.
- Backoff delay is capped at the platform's 10-minute `enqueueJob` ceiling; for longer
  backoff the dead-letter + scheduled replay path is the documented escalation.
- Retry counts/limits live in **custom metadata** so tuning them is config, not a code change
  (and not a public-API change).
