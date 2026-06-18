# Requirements Traceability Matrix (RTM)

> **Exercises:** testing-methodologies (RTM as UAT/audit evidence),
> operating-managing-common-release-artifacts (component provenance).
> **JD line:** "auditability" — this document is the project's audit-evidence backbone.

Rules (same as todo-app):

- Every FR/NFR has a row. Rows are updated **in the same MR** that adds the design,
  component, or test (per `definition-of-done.md`).
- "Design" → file in `docs/architecture/` (or governance/decision-log / requirements where
  noted). "Component" → metadata/source path. "Test" → test class/method or suite file.
  `—` = intentionally pending; never blank.
- Status: `planned` → `designed` → `built` → `verified` (test green in CI) → `frozen`
  (v1.0.0 audit snapshot).

> **Status at Phase 3 close (2026-06-17):** Design column **filled** and most rows advanced to
> `designed`. The Phase 3 design set is complete — ADR-001…005, integration-architecture,
> sequence-diagrams, security-trust-boundary, package-dependency, public-api-spec. Three rows
> remain `planned` because their design lands later: **FR-12** (monitoring surface, Phase 9),
> **NFR-9 / NFR-10** (CI pipeline design, Phase 4). Components/tests stay forward-referenced;
> they advance to `built`/`verified` as MRs land in Phases 5–9.

> **Status at Phase 6 (2026-06-18):** MR 6-A (outbound) + 6-B (inbound) landed — FR-3/5/6/7/9/11
> and NFR-3/4/5 advanced to **`built`** (validated on scratch `ws-p6e`: 35/35 tests, 98% org-wide).
> `built` not `verified` because `verified` requires test-green **in CI** (the release pipeline
> hasn't run these yet). FR-1/2 + NFR-7 stay `verified` (prod smoke, v0.1.0). FR-10 (full
> round-trip) stays `designed` — its components exist but acceptance is the live 6-C round-trip,
> gated on Vercel-protection-off + Named Credential + Connected App/JWT (see
> `../release/round-trip-test-plan-v0.2.0.md`).

## Functional requirements

| ID | Summary | Design | Component(s) | Test(s) | Status |
|---|---|---|---|---|---|
| FR-1 | Log via Logger | ADR-004, public-api-spec.md §1 | `Logger`, `LogEvent__e` | `LoggerTest.log_writesDurableRecord` | verified |
| FR-2 | Logs survive rollback | ADR-004, sequence-diagrams.md §6 | `Logger` (immediate-mode publish) | `LoggerTest.survivesRollback` | verified |
| FR-3 | Publish via EventPublisher | public-api-spec.md §2 | `EventPublisher` | `EventPublisherTest.publish_* / logFailures_logsEachError` | built |
| FR-4 | Governed outbound callout | public-api-spec.md §3, security-trust-boundary.md, ADR-005, integration-contract.md §3 | `CalloutService`, `FRS_Service` Named Credential | `CalloutServiceTest` (HttpCalloutMock) | built |
| FR-5 | Notify FRS on business event | ADR-002, integration-architecture.md, sequence-diagrams.md §1, integration-contract.md §3 | `CalloutService.sendAsync`, `CalloutQueueable` (consumer wiring: consumer-onboarding.md `TodoTriggerHandler.notifyFrsOnCompletion`) | `CalloutQueueableTest.sendAsync_success_noRetryNoDeadLetter` | built |
| FR-6 | Retry transient outbound w/ backoff | ADR-003, sequence-diagrams.md §2, integration-contract.md §3.3 | `RetryPolicy` + `CalloutQueueable` + `CalloutFinalizer` | `RetryPolicyTest.decide_coversFullMatrix`, `CalloutQueueableTest.transientFailure_capturesNextRetry / exhaustedRetries_deadLetters` | built |
| FR-7 | Dead-letter + replay | ADR-003, sequence-diagrams.md §3 | `Integration_DeadLetter__c`, `ReplayService`, `CalloutFinalizer` | `ReplayServiceTest.replay_resendsAndMarksReplayed`, `CalloutQueueableTest.terminalFailure_deadLettersImmediately` | built |
| FR-8 | Accept inbound status callback | ADR-002, integration-contract.md §4, sequence-diagrams.md §4, security-trust-boundary.md | `FrsStatusResource` (Apex REST), Connected App + integration user | `FrsStatusResourceTest.firstMessage_isApplied / missingRequiredField_is400` | built |
| FR-9 | Apply inbound idempotently | ADR-003, sequence-diagrams.md §5, integration-contract.md §4.2 | `IdempotencyGuard`, `Integration_Message__c` (unique key) | `IdempotencyGuardTest.duplicateKey_isNoOp`, `FrsStatusResourceTest.replaySameKey_isDuplicateNoOp` | built |
| FR-10 | Trace round-trip by correlation id | integration-architecture.md §5, sequence-diagrams.md §7 | `correlationId` on all log events | round-trip-test-plan-v0.2.0.md §C (live, gated) | designed |
| FR-11 | Governor-safe under bulk | sequence-diagrams.md §1 (one enqueue/txn), ADR-002 | `CalloutService.chunk` + `CalloutQueueable` (≤100/txn, one job/chunk) | `CalloutQueueableTest.chunk_splitsAtGovernorSafeBoundary / bulk_200_staysGovernorSafe` | built |
| FR-12 | View integration health *(Phase 9)* | — (monitoring surface, Phase 9) | `lwc/integrationHealth`, reports | e2e + manual UAT | planned |

## Non-functional requirements

| ID | Summary | Design | Component(s) | Test(s) | Status |
|---|---|---|---|---|---|
| NFR-1 | Integration security & secrets | security-trust-boundary.md, ADR-005 | `FRS_Service` Named/External Credential, `FRS_Integration` perm set, Connected App | `FrsStatusResourceTest.unauthenticated_rejected`; integration-user `runAs` test; no-secret grep gate | designed |
| NFR-2 | Data minimization & classification | integration-contract.md §5, security-trust-boundary.md §5 | payload builders (allowlist) | `IntegrationContractTest.payload_matchesDictionary`; `LoggerTest.noSecretPersisted` | designed |
| NFR-3 | Idempotency | ADR-003, sequence-diagrams.md §5, integration-contract.md §4.2 | `IdempotencyGuard` (unique External Id) | `IdempotencyGuardTest.duplicateKey_isNoOp / distinctKeys_appliedIndependently` | built |
| NFR-4 | Governor-limit safety | sequence-diagrams.md §1, ADR-002 | `CalloutService.chunk` + `CalloutQueueable` (one enqueue/chunk) | `CalloutQueueableTest.bulk_200_staysGovernorSafe` | built |
| NFR-5 | Resilience & RTO | ADR-003, sequence-diagrams.md §2-§3 | `RetryPolicy`, `ReplayService`, `Integration_DeadLetter__c` | retry/replay tests (built) + Phase 8 integration-failure drill (timed RTO) | built |
| NFR-6 | Observability & SLO | ADR-004, integration-architecture.md §5, sequence-diagrams.md §7 | `Logger`, `lwc/integrationHealth` | `IntegrationRoundTripTest.correlationChain`; Phase 9 surface renders success%/p95 | designed |
| NFR-7 | Log durability (survives rollback) | ADR-004, sequence-diagrams.md §6 | `Logger` immediate-mode publish + `LogEvent__e` subscriber | `LoggerTest.survivesRollback` | verified |
| NFR-8 | Public-API stability / compat | api-governance.md, public-api-spec.md, package-dependency.md §2 | annotated public API surface | consumer-compatibility test (pinned to public-api-spec) + Phase 8 deprecation drill | designed |
| NFR-9 | Code quality | — (pipeline-design.md, Phase 4) | CI coverage + Code Analyzer gates | CI gates (≥85%, 0 crit/high) | planned |
| NFR-10 | Reproducibility & CI reuse | — (pipeline-design.md, Phase 4) | `.gitlab-ci.yml` `include:` of todo-app template, `scripts/org-setup.sh` | CI run consuming template + notes file; timed onboarding (Phase 9) | planned |
| NFR-11 | Recoverability w/ consumers | ADR-001, package-dependency.md §3 | dependency-ordered install (base ← todo-app) | timed rollback rehearsal w/ consumer installed (Phase 8) | designed |

## Coverage check

- **FR rows:** 12 (FR-1…FR-12). **NFR rows:** 11 (NFR-1…NFR-11). **Total: 23.**
- **At Phase 3 close:** 20 rows `designed`, 3 `planned` (FR-12, NFR-9, NFR-10 — by-design,
  land in Phases 4/9). Every row has a named design (or an explicit later-phase note),
  component, and test — no blanks.
- Every FR maps to ≥1 NFR (see `non-functional-requirements.md` NFR→FR table).
- This matrix is the audit spine; it is frozen as the v1.0.0 snapshot in Phase 8.
