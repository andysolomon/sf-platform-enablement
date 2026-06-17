# Functional Requirements

> **Exercises:** application-lifecycle-management (Plan stage); testing-methodologies
> (requirements written to be traceable to tests); integration deck
> `identify-functional-and-non-functional-integration-requirements`,
> `inventory-systems-and-integration-patterns`.
> **JD lines:** "Must have integration patterns"; "explicit APIs and abstractions for
> application developers"; "reusable components in support of business products"; async Apex
> + governor limits (FR-11 exists to force async/bulk-safe design — the idempotency analogue
> to the todo-app's bulkification story in FR-9 there).

Baseline set at end of Phase 2. Changes after baseline require a CCB entry (see
`../governance/change-management.md`); a change to the **public API surface** additionally
triggers the API-governance + deprecation rules. Priority is WSJF-lite per ADR-001:
**order = value ÷ effort**, highest first within each release.

Each FR traces to a discovery scenario in `system-landscape.md` (S1–S4). **Actors** differ
from a normal app: a FR's actor may be a **consuming app developer** (calling the public
API), the **platform itself** (integration behavior), or the **external FRS system**
(Remote Call-In). The actor is named in each FR.

---

## A. Reusable platform API (the "explicit abstractions for app developers")

## FR-1 — Log an event through the platform Logger
*Actor: consuming app developer (Apex). Scenario: S3. (Value: H, Effort: L — walking-skeleton story)*

As a consuming developer, I record a structured log/error through a single public API call,
without knowing how logs are stored.

- **Given** consumer Apex calls `Logger.error('msg', correlationId)`, **when** the
  transaction commits, **then** a durable log record exists carrying the message, severity,
  correlation id, and originating context.
- **Given** I call the API, **then** I never reference the underlying object or Platform
  Event directly (the storage mechanism is encapsulated — verified by the public-API spec).

## FR-2 — Logs survive a rolled-back transaction
*Actor: platform. Scenario: S3 (pain point P2). (Value: H, Effort: M)*

As a platform, I ensure a log written during a transaction persists even if that
transaction later throws and rolls back.

- **Given** consumer Apex logs an error and then hits an unhandled exception that rolls back
  the DML, **when** the transaction ends, **then** the log record still exists (Platform-
  Event-backed publish, immediate-mode — see ADR-004).

## FR-3 — Publish a domain event through EventPublisher
*Actor: consuming app developer. Scenario: S1 (source side). (Value: H, Effort: L)*

As a consuming developer, I publish a domain event through a thin, testable wrapper rather
than calling `EventBus.publish` directly.

- **Given** consumer Apex calls `EventPublisher.publish(event)`, **then** the event is
  published and the call is unit-testable without real delivery (mockable wrapper).
- **Given** a publish failure, **then** the failure is surfaced to the caller and logged
  (FR-1), not silently swallowed.

## FR-4 — Make a governed outbound callout through CalloutService
*Actor: consuming app developer. Scenario: S1. (Value: H, Effort: M)*

As a consuming developer, I call an external endpoint through the platform's
`CalloutService` without handling endpoints, secrets, or auth myself.

- **Given** I call `CalloutService.send(request)`, **then** the call routes through a Named
  Credential (`callout:Name/path`) — no endpoint URL or secret appears in consumer code
  (NFR — secrets; verified by code review + the trust-boundary doc).
- **Given** the same call runs in a different org/environment, **then** it targets that
  environment's endpoint with no code change (environment portability).

## B. Outbound integration — SF → FRS (Remote Process Invocation, Fire-and-Forget)

## FR-5 — Notify the FRS system on a business event
*Actor: platform (triggered by a consumer domain event). Scenario: S1. (Value: H, Effort: M)*

As the platform, when an app raises a domain event (e.g. a todo is completed), I notify the
external FRS system asynchronously, without blocking the user's transaction.

- **Given** a consumer publishes a "completed" domain event, **when** it is delivered,
  **then** the platform performs an outbound callout to the FRS service carrying the minimal
  payload (NFR — data minimization) and a correlation id.
- **Given** the originating user transaction, **then** it commits without waiting for the
  callout (the callout runs in async context — no callout-after-DML, no added user latency).
- **Given** a successful callout, **then** a success log with the correlation id is written
  (FR-1).

## FR-6 — Retry a transient outbound failure with backoff
*Actor: platform. Scenario: S1 (resilience). (Value: M, Effort: M)*

As the platform, I retry a transient outbound failure (timeout, 5xx) a bounded number of
times with backoff before giving up.

- **Given** the FRS endpoint returns a timeout or 5xx, **when** the callout runs, **then**
  it is retried up to the configured maximum with increasing delay.
- **Given** retries succeed on attempt N, **then** the operation is logged as recovered with
  the attempt count.
- **Given** a permanent failure (4xx that is not retryable), **then** no retry occurs and it
  routes to the poison path (FR-7).

## FR-7 — Dead-letter and replay an exhausted outbound call
*Actor: platform / operator. Scenario: S1 (resilience, pain point). (Value: M, Effort: M)*

As an operator, when an outbound call exhausts its retries, I can see it and replay it once
the cause is fixed — without data loss.

- **Given** retries are exhausted, **then** the failed call is recorded as a poison/dead-
  letter entry with enough context to replay (payload ref + correlation id), and an alert
  condition is met (Phase 9).
- **Given** a dead-letter entry and a fixed endpoint, **when** an operator triggers replay,
  **then** the original notification is re-sent and, on success, the entry is cleared.

## C. Inbound integration — FRS → SF (Remote Call-In)

## FR-8 — Accept a status callback from the FRS system
*Actor: external FRS system. Scenario: S2. (Value: H, Effort: M)*

As the FRS system, I report status back into Salesforce, which updates the related record.

- **Given** the FRS service sends a status message (Platform Event publish via REST, or
  inbound Apex REST) authenticated per the auth matrix (§6 of landscape), **when** it is
  received, **then** the related record is updated and the exchange is logged with the
  correlation id.
- **Given** an unauthenticated or unauthorized inbound call, **then** it is rejected and the
  attempt is logged (NFR — security).

## FR-9 — Apply inbound messages idempotently
*Actor: platform. Scenario: S2 (pain point P4). (Value: H, Effort: M — this FR exists to force idempotent design)*

As the platform, I ensure a duplicated or replayed inbound message produces no double
effect.

- **Given** an inbound message with idempotency key K has already been applied, **when** a
  second message with the same key K arrives, **then** it is a no-op (no second record
  update, no duplicate side effect) and is logged as a deduplicated delivery.
- **Given** two distinct keys, **then** both are applied independently.

## D. Cross-cutting

## FR-10 — Trace a full round-trip by correlation id
*Actor: operator / consuming developer. Scenario: S1 + S2 + S3. (Value: M, Effort: L)*

As an operator, I follow one business event across the boundary using a single correlation
id.

- **Given** a completed round-trip (domain event → outbound → FRS → inbound callback →
  record update), **when** I query logs by the correlation id, **then** I see the ordered
  chain of every step across both directions.

## FR-11 — Stay governor-safe under bulk load
*Actor: platform. Scenario: S1 (NFR — governor safety). (Value: H, Effort: M — forces async/bulk design)*

As the platform, I notify the FRS system for a bulk operation without breaching callout or
DML governor limits.

- **Given** 200 todos are completed in a single transaction, **when** the notifications are
  processed, **then** all are sent without exceeding the 100-callout/transaction limit and
  with no callout-after-DML error (callouts batched across async context).
- **Given** the bulk path, **then** a single test asserts the callout/SOQL/DML counts stay
  within limits at 200 records.

## FR-12 — View integration health *(Phase 9; listed for traceability)*
*Actor: operator. Scenario: S3. (Value: M, Effort: M)*

As an operator, I see integration success rate, recent failures, and latency on a surface.

- **Given** integration activity has occurred, **when** I open the monitoring surface,
  **then** I see success/failure counts, recent dead-letter entries, and p95 latency from
  the log events. *(Built in Phase 9 — observability; FR recorded now so the RTM is complete.)*

---

## Scenario → FR coverage (traceability into `system-landscape.md`)

| Discovery scenario | FRs |
|---|---|
| S1 — Outbound notify (Fire-and-Forget) | FR-3, FR-4, FR-5, FR-6, FR-7, FR-11 |
| S2 — Inbound status (Remote Call-In) | FR-8, FR-9 |
| S3 — Reusable logging / observability | FR-1, FR-2, FR-12 |
| Cross-cutting (correlation, governor) | FR-10, FR-11 |
| Reusable public API surface | FR-1, FR-3, FR-4 |

## Walking-skeleton subset (Phase 5 — thinnest slice through every layer)

FR-1 (log one record), FR-4 (one Named-Credential callout to `/health`), and the inbound
receipt half of FR-8 — proven end-to-end and released as v0.1.0. Everything else lands in
Phase 6.

## Notes / deferred

- **FR-12** (monitoring surface) and the **alerting** condition in FR-7 are built in Phase 9.
- **Batch Data Synchronization** (landscape S4) has no FR — it is the documented fallback if
  event delivery proves lossy; promote to an FR via CCB only if that pain materializes.
- Forward references to NFRs (secrets, data minimization, security, governor safety,
  observability) are defined in `non-functional-requirements.md` (Phase 2.2).
