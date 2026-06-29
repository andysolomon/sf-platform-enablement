# Changelog

All notable changes to the `frs-platform` base package. Versions are unlocked-package
versions; the public API surface follows semver per `docs/governance/api-governance.md`.

## [0.2.0] - 2026-06-23 — Core components: bidirectional integration

Outbound resilience + inbound idempotency. Minor bump: additive public API surface
(`docs/governance/api-governance.md`). Validated on scratch (35/35 tests, 98% org-wide) and
the CI staging-install gate. The live round-trip + todo-app consumer wiring are prepped and
gated on the per-org credential setup (see `docs/release/round-trip-test-plan-v0.2.0.md`).

### Added

- **`CalloutService.sendAsync(Request | List<Request>)`** — async, governed outbound callouts
  via the `FRS_Service` Named Credential (no endpoint/secret), bulk-safe to 200 by chunking
  ≤100 callouts/txn (FR-5, FR-11, NFR-1, NFR-4).
- **Retry/backoff/dead-letter** — `RetryPolicy` (classify + exponential backoff, config via
  `Integration_Setting__mdt`), `CalloutQueueable` + `CalloutFinalizer`, `Integration_DeadLetter__c`,
  and operator `ReplayService` (replays with the same idempotency key) (FR-6, FR-7, NFR-5).
- **`EventPublisher.publish`** — generic `EventBus` wrapper that surfaces + logs publish
  failures (FR-3).
- **Inbound idempotency** — `FrsStatusResource` now parses/validates and applies idempotently;
  `IdempotencyGuard` + **`Integration_Message__c`** (unique External Id key) dedupe replays,
  correct even under concurrent duplicate delivery (FR-8, FR-9, NFR-3).
- **`FRS_Operations`** permission set — operator access to dead letters + replay, separate from
  the inbound `FRS_Integration` set per separation-of-duties.

### Changed

- `FrsStatusResource` response is now `{status, recordId, correlationId}` with `applied` /
  `duplicate` / `error` (400 on malformed/invalid) per integration-contract §4.

### CI / build

- Pin `SF_CI_IMAGE=node:20` (the shared template's floating `node:22` drifted and broke the
  CLI login — NFR-10 coupling remediation, consumer-side).

## [0.1.0] - 2026-06-17 — Walking skeleton

First release: the thinnest slice through every layer, proving the delivery pipeline and the
core mechanisms end to end.

### Added

- **`Logger`** public API (`log`/`error`/`warn`/`info` + `Severity`) publishing a
  **`LogEvent__e`** Platform Event with **Publish-Immediately** behavior so logs survive a
  transaction rollback (FR-1, FR-2, NFR-7).
- **`LogEvent__e` → `Log__c`** subscriber (`LogEventSubscriber` → `LogEventHandler`) persisting
  a queryable log record (correlation id, severity, message, category).
- **`CalloutService.ping()`** — governed outbound callout to the FRS `/health` endpoint via the
  `FRS_Service` Named Credential, no hard-coded URL/secret (FR-4, NFR-1).
- **`FrsStatusResource`** — inbound Remote Call-In endpoint (`POST /services/apexrest/frs/v1/status`)
  returning `applied` and logging the echoed correlation id (FR-8, walking-skeleton subset).
- **`FRS_Integration`** least-privilege permission set (inbound resource + log publish only, NFR-1).
- Tests: `LoggerTest` (incl. rollback-survival), `CalloutServiceTest` (HttpCalloutMock), and
  `FrsStatusResourceTest` — 7 tests, 96% org-wide coverage.

### Notes

- The live SF→FRS round-trip callout and the Named Credential setup are wired in Phase 6
  (the mock is deployed; `docs/devops/named-credential-setup.md` is the org-config runbook).
- Public API surface is a subset of `docs/architecture/public-api-spec.md`; it is not frozen
  until v1.0.0 (Phase 8) per the deprecation policy.
