# ADR-004: Logging & Error-Handling Architecture

- **Status:** Accepted
- **Date:** 2026-06-17
- **Deciders:** Architect hat

> **Exercises:** building-quality-code (observability), integration deck performance/
> observability; "patterns for logging, monitoring, alerting" (JD platform-enabler list).
> **JD lines:** "Develop patterns for common platform needs (logging, monitoring, alerting…)";
> Tier 3 support; "reusable components."
> **Constrains:** FR-1, FR-2, FR-10; NFR-6, NFR-7. **RTM design coverage:** FR-1, FR-2, NFR-7.

## Context

The platform's logging framework is a **reusable enabler** consumed by app teams (FR-1) and
the backbone of observability (FR-10, NFR-6). The hard requirement (NFR-7, pain point P2):
**a log written during a transaction must survive that transaction rolling back** — otherwise
the most important logs (the ones written just before a failure) are lost.

The problem: ordinary DML to a custom `Log__c` object **rolls back with the transaction**. A
log written right before an unhandled exception would vanish exactly when it matters most.

## Decision

**Platform-Event-backed logging** (the Nebula-Logger pattern, simplified):

- `Logger.log()/error()/warn()` publishes a **`LogEvent__e` Platform Event** with **Publish
  Behavior = "Publish Immediately."** Immediate publish is **not** tied to the transaction's
  commit, so the event is delivered even if the publishing transaction later rolls back
  (satisfies NFR-7 / FR-2).
- A platform **subscriber trigger on `LogEvent__e`** persists each event to a queryable `Log__c`
  record (for the monitoring surface, FR-12, and audit). The subscriber runs in its own
  transaction, so its DML is independent of the original (rolled-back) one.
- Each log carries: `correlationId`, `severity`, `source`, `message`, `category`
  (e.g. integration/outbound, integration/inbound, retry, dead-letter), and a truncated/
  redacted payload reference (NFR-2 — never secrets).
- The public API (`Logger`) **hides the event entirely** — consumers never touch `LogEvent__e`
  (api-governance public-surface rule); the storage mechanism can change without a major bump.

### Options considered

| Option | Survives rollback? | For | Against |
|---|---|---|---|
| DML to `Log__c` directly | **No** | Simplest, immediately queryable | Loses the logs written before a failure — fails NFR-7 |
| `LogEvent__e` with default (after-commit) publish | **No** for a rolled-back txn | Decoupled | After-commit publish is suppressed when the transaction rolls back — fails NFR-7 |
| **`LogEvent__e` with Publish-Immediately + subscriber → `Log__c` (chosen)** | **Yes** | Survives rollback; decoupled; queryable via the subscriber; one bus reused for domain events (ADR-002) | Eventual (not synchronous) persistence; PE daily publish limits on DE (documented) |
| External logging service (e.g. callout per log) | Yes | Off-platform durability | A callout per log is absurd cost + governor pressure; ironic for a logging framework |

## Consequences

- **NFR-7 is met and testable:** a test that logs then forces a rollback asserts the `Log__c`
  record still exists (via `Test.getEventBus().deliver()` to run the subscriber) — Phase 6/7.
- **FR-10 round-trip tracing** falls out for free: every step (outbound, retry, inbound,
  dead-letter, dedupe) logs with the same `correlationId`; querying `Log__c` by it returns the
  ordered chain.
- The **same Platform Event bus** carries domain events (ADR-002 S1) and log events — one
  mechanism, consistent mental model.
- **Cost/limit:** immediate-publish events count against the org's daily PE publish allocation;
  on Developer Edition this is tight, so `DEBUG`-level logging is sampled/off by default and
  the limit is documented as a real platform constraint (Phase 9 metrics watch it).
- Persistence is **eventual** (subscriber runs async); a log isn't queryable in the same
  transaction it was written. Accepted — durability beats immediacy for this requirement.
