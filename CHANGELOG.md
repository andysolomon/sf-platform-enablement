# Changelog

All notable changes to the `frs-platform` base package. Versions are unlocked-package
versions; the public API surface follows semver per `docs/governance/api-governance.md`.

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
