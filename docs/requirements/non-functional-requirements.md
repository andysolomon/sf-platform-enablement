# Non-Functional Requirements

> **Exercises:** planning-environment-risks (risk-driven NFRs), building-quality-code,
> testing-execution-and-coverage; integration deck
> `identify-functional-and-non-functional-integration-requirements`,
> `identify-integration-security-authentication-authorization-requirements`,
> `identify-performance-needs-and-integration-solutions`,
> `classify-integration-data-confidential-secure-public`.
> **JD lines:** "Must have security model"; "Must have integration patterns"; "least-
> privilege, scalable access models"; "governor limits, performance optimization, secure
> coding"; "auditability"; "explicit APIs and abstractions"; static analysis / test
> automation.

Every NFR has a measurable target and a named verification method — if it can't fail a
check, it isn't a requirement. Each cites the FR(s) and discovery scenario it constrains.

## NFR-1 — Integration security & secret handling

**Target:** No endpoint URL, secret, token, or API key appears in Apex source, metadata, or
logs. All outbound calls use **Named Credential + External Credential** (`callout:Name/...`);
all inbound calls authenticate via a **Connected App** against a dedicated **least-privilege
integration user** that holds only the permissions to publish the inbound event / write the
target record (no broad object access, no admin). Unauthenticated inbound calls are rejected.
*(Constrains FR-4, FR-5, FR-8; scenarios S1/S2; deck: integration security/auth.)*
**Verified by:** `security-trust-boundary.md` review + access matrix (Phase 3); a grep/review
gate proving zero hard-coded endpoints/secrets; a `runAs`/permission test on the integration
user proving it cannot exceed its scope; an inbound test asserting an unauthenticated call is
rejected and logged; Code Analyzer security rules zero critical/high.

## NFR-2 — Data minimization & classification

**Target:** Cross-boundary payloads (S1 outbound, S2 inbound) carry only the fields the FRS
system needs plus a correlation id — no PII in scope; no field classified above **Internal**
crosses the boundary. Log records (Confidential) never contain secrets or full sensitive
payloads (payloads redacted/truncated). Every field that crosses is listed in the contract.
*(Constrains FR-5, FR-8, FR-1; deck: data classification.)*
**Verified by:** payload field list in `integration-contract.md` checked against the data-
classification table in `system-landscape.md` §5; a log-content test asserting no secret
pattern is persisted; code-review checklist item.

## NFR-3 — Idempotency

**Target:** A duplicated or replayed inbound message (same idempotency key) produces **zero**
double effect — no second record update, no duplicate side effect. Idempotency is keyed by a
message-supplied key persisted on first apply.
*(Constrains FR-9; scenario S2; pain point P4.)*
**Verified by:** a test delivering the same keyed message twice and asserting exactly one
applied effect + one "deduplicated" log; a distinct-key test asserting both apply.

## NFR-4 — Governor-limit safety (callouts & async)

**Target:** No outbound callout executes synchronously after uncommitted DML. At 200-record
bulk volume, the notify path stays within the **100-callout/transaction** limit and consumes
≤ 50% of SOQL/DML/CPU limits, measured with `Limits` methods inside
`Test.startTest()/stopTest()`. Callouts execute in async context (Queueable), batched.
*(Constrains FR-5, FR-11; scenario S1; deck: performance needs.)*
**Verified by:** mandatory 200-record test with explicit `Limits` assertions and no
callout-after-DML error; code-review checklist (no callout/SOQL/DML in loops).

## NFR-5 — Resilience & recovery of in-flight integrations

**Target:** Transient outbound failures (timeout, 5xx) retry up to a configured maximum
(default 3) with increasing backoff; non-retryable failures (most 4xx) do not retry. An
exhausted call lands in a dead-letter store with enough context to replay. **RTO:** an
operator can replay a dead-lettered integration within **30 minutes** of cause resolution,
with no data loss.
*(Constrains FR-6, FR-7; scenario S1 resilience.)*
**Verified by:** retry-exhaustion test (asserts attempt count → poison path); a replay test
re-sending and clearing the entry; a timed integration-failure drill (Phase 8) documenting
the RTO against this target.

## NFR-6 — Observability

**Target:** 100% of integration attempts (outbound, inbound, retries, dead-letters) emit a
durable log carrying a correlation id, severity, and outcome. A complete round-trip is
reconstructable from logs by correlation id alone. **SLO seeds:** outbound success rate ≥ 99%
over a rolling window; p95 outbound latency recorded; both surfaced in Phase 9.
*(Constrains FR-1, FR-10, FR-12; scenario S3; deck: performance/observability.)*
**Verified by:** a round-trip test asserting the ordered correlation chain exists across both
directions; the Phase 9 monitoring surface rendering success rate + p95 from real log data.

## NFR-7 — Log durability (survives rollback)

**Target:** A log written during a transaction persists even if that transaction rolls back —
guaranteed by immediate-mode Platform Event publish (not DML on a custom object inside the
same transaction).
*(Constrains FR-2; scenario S3; pain point P2.)*
**Verified by:** a test that logs then forces a rollback and asserts the log record still
exists; ADR-004 records the mechanism choice.

## NFR-8 — Public-API stability & backward compatibility

**Target:** The package's public API surface (annotated `global`/documented `public`) never
changes in a breaking way without a **major** version bump. Deprecations follow the policy
(`api-governance.md`): mark deprecated → keep working for ≥ 1 minor version → remove only on a
major. A consuming app (todo-app) upgrades across a minor version with **zero** code changes.
*(Constrains FR-1, FR-3, FR-4; JD: "explicit APIs and abstractions.")*
**Verified by:** a consumer-compatibility test pinned to the published API surface (fails if a
signature changes incompatibly); the Phase 8 deprecation drill proving a non-breaking
consumer upgrade; semver check at release.

## NFR-9 — Code quality

**Target:** Org-wide Apex coverage ≥ **85%** (floor, not target — platform gate is 75%); every
class and trigger covered; zero new Code Analyzer critical/high findings; any `without
sharing` carries a justified `@SuppressWarnings` quarantine marker (todo-app convention).
*(Constrains all FRs; JD: static analysis, secure coding, test automation.)*
**Verified by:** CI coverage gate; CI Code Analyzer gate; review checklist.

## NFR-10 — Reproducibility & automation (DevOps reuse)

**Target:** The repo's CI **consumes the todo-app's reusable CI template** (`include:`), with
any adaptation documented — proving the template is reusable by a second team (the JD's
"supporting multiple application teams"). A contributor goes from clean clone to a ready
scratch org via one documented command. Production install is the pipeline's release job
only — zero manual deploys after v0.1.0; cross-package install is dependency-ordered.
*(Constrains delivery; JD: deployment automation, reusable platform enablers.)*
**Verified by:** the CI config showing the `include:` of the todo-app template + a notes file
on gaps found; timed onboarding walkthrough (Phase 9); absence of manual-deploy entries in the
release log.

## NFR-11 — Recoverability of a package with consumers

**Target:** Rollback = reinstall the previous base-package version, completed in ≤ **30
minutes** (RTO) including smoke test, **without breaking installed consumers**. Schema and
**public-API** changes are additive-only within a major version so a downgrade never strands
consumer code or data.
*(Constrains release; scenario: base package has dependents; JD: Tier 3 / release ops.)*
**Verified by:** a timed rollback rehearsal of a base package that has the todo-app installed
as a dependent (Phase 8), documented against this RTO; change-management additive-only rule
enforced in review.

---

## NFR → FR / scenario coverage

| NFR | Constrains FRs | Scenario | Primary verification phase |
|---|---|---|---|
| NFR-1 security/secrets | 4, 5, 8 | S1, S2 | 3 (design), 5–7 (tests) |
| NFR-2 data minimization | 5, 8, 1 | S1, S2 | 2.3 contract, 7 |
| NFR-3 idempotency | 9 | S2 | 6–7 |
| NFR-4 governor safety | 5, 11 | S1 | 6–7 |
| NFR-5 resilience/RTO | 6, 7 | S1 | 7, 8 (drill) |
| NFR-6 observability/SLO | 1, 10, 12 | S3 | 7, 9 |
| NFR-7 log durability | 2 | S3 | 6 |
| NFR-8 API stability | 1, 3, 4 | API | 7, 8 (deprecation drill) |
| NFR-9 code quality | all | — | 4–7 (CI) |
| NFR-10 reproducibility/reuse | delivery | — | 4, 9 |
| NFR-11 recoverability w/ consumers | release | — | 8 (rollback rehearsal) |

Every FR is constrained by at least one measurable NFR; every NFR names a check that can
fail. The RTM (Phase 2.4) carries both FR and NFR rows through design → component → test.
