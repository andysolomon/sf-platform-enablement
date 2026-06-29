# Smoke Test — v0.1.0 (walking skeleton)

- **Date:** 2026-06-17
- **Package:** `frs-platform` 0.1.0.2 — `04tgK000000DsNZQA0`
- **Target:** `prodtest` org (00Dg500000BzwFGEAZ) — the "prod" install target
- **Pipeline:** 2609367709 (main, web-triggered) — all jobs green; manual `prod-install` approved (Release-Manager hat)
- **Tag:** `v0.1.0` (commit 1b5ec90)

## API / post-install checks

| # | Check | Method | Result |
|---|---|---|---|
| 1 | Package installed in prod | `sf package installed list -o prodtest` | ✅ frs-platform 0.1.0.2 (04tgK000000DsNZQA0) present |
| 2 | `Logger` executes in prod | anon apex `Logger.info('v0.1.0 prod smoke','SMOKE-v0.1.0')` | ✅ Compiled + Executed successfully |
| 3 | Log round-trip persists (FR-1, FR-2, NFR-7) | `SELECT … FROM Log__c WHERE Correlation_Id__c='SMOKE-v0.1.0'` | ✅ 1 row: INFO / "v0.1.0 prod smoke" — proves `Logger → LogEvent__e (publish-immediate) → subscriber → Log__c` works in prod |

## RTM rows verified by this release

- **FR-1** (log via Logger) — verified (CI tests + prod smoke #2/#3)
- **FR-2 / NFR-7** (logs survive rollback via immediate publish) — verified (CI `survivesRollback` test; prod persistence #3)
- **FR-4** (governed callout) — `built` (HttpCalloutMock test green); live `/health` call deferred to Phase 6 (needs Named Credential setup + Vercel protection off)
- **FR-8** (inbound resource skeleton) — `built` (CI test green); live inbound call deferred to Phase 6

## Not exercised at v0.1.0 (by design)

- Live SF→FRS `/health` callout (needs `FRS_Service` Named Credential — `named-credential-setup.md`, and Vercel Deployment Protection OFF).
- Live FRS→SF inbound (needs Connected App + JWT cert).
- Real round-trip e2e (placeholder e2e in CI; real journey in Phase 7).

## Sign-off

Automated API smoke ✅ (above). UI sign-off: n/a — `frs-platform` is a headless base package (no UI at v0.1.0).
