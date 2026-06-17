# Risk Register

> **Exercises:** planning-environment-risks (six risk categories + mitigations); integration
> deck `analyze-system-landscape-constraints-and-pain-points`,
> `identify-integration-security-authentication-authorization-requirements`.
> **JD line:** "Critical Thinking (applies objective analysis and reasoning)"; the Fed/FRS
> context generally: risk-managed, secure integration delivery.

Categories follow the study material, plus an **Integration** category for this project's
domain. Likelihood/Impact: L/M/H. Owner is a hat. Review cadence: at each release's
post-release review; new risks get CCB entries.

| # | Category | Risk | L | I | Mitigation | Owner |
|---|---|---|---|---|---|---|
| R-1 | Project mgmt | Gold-plating into a full iPaaS instead of a thin integration proof | M | M | Integration is a *thin proof* (plan scope boundary); CCB gates new FRs; the middleware seam is documented, not built (landscape §7) | CCB |
| R-2 | Integration | 3rd-party FRS (Vercel mock) downtime/timeout stalls the round-trip | H | M | Async fire-and-forget so user txn never blocks (FR-5/NFR-4); bounded retry+backoff (FR-6/NFR-5); dead-letter + replay (FR-7); integration-failure drill (Phase 8) | Platform Eng |
| R-3 | Integration | Retry amplification / replay storm overwhelms FRS | M | H | Bounded retries + exponential backoff; honor `Retry-After` on 429 (contract §3.3); dead-letter instead of infinite retry (NFR-5) | Platform Eng |
| R-4 | Development | Missing idempotency → duplicate delivery causes double effect | M | H | Idempotency-key design, receiver-side dedupe (FR-9/NFR-3, contract §4.2); duplicate-delivery test mandatory | Developer |
| R-5 | Development | Callout-after-DML / 100-callout limit breached at bulk volume | M | H | Callouts in async (Queueable) off the event, batched; mandatory 200-record `Limits` test (FR-11/NFR-4); review checklist (no callout in loop) | Developer |
| R-6 | Data security | Secret leakage — Named Cred secret, Vercel API key, or inbound JWT cert in repo/CI logs | M | H | Named/External Credentials + masked GitLab CI vars (todo-app base64 lesson); never in source/logs (NFR-1/NFR-2); secrets-rotation drill (Phase 8) | Release Mgr |
| R-7 | Data security | Inbound endpoint abused (unauthenticated / over-privileged) | L | H | Connected App + least-privilege integration user (NFR-1); reject+log unauthenticated calls; integration-user `runAs` test proves it can't exceed scope | Architect |
| R-8 | Data security | PII / over-sharing creeps into the cross-boundary payload | M | M | Field-dictionary allowlist; reject `400` on unknown fields (contract §5/NFR-2); classification check at contract review | Architect |
| R-9 | Governance | A breaking change to the public API silently breaks consumers (todo-app) | M | H | API-governance public-surface rules + deprecation policy (NFR-8); consumer-compatibility test; deprecation drill (Phase 8) | Architect |
| R-10 | Integration | Contract drift between the Apex side and the Vercel mock | M | M | Both assert against `integration-contract.md`; contract test against the *deployed* mock fails on drift (Phase 7); `/v1` additive-only rule | Developer |
| R-11 | Development | Log Platform Event publish fails silently → blind spots in observability | L | M | Publish failure surfaced to caller + fallback path (FR-3); `Logger` durability test; monitoring surface shows gaps (Phase 9) | Developer |
| R-12 | Testing | Callout tests give false green — mock diverges from real FRS behavior | M | M | Unit tests use `HttpCalloutMock`; **plus** contract tests run against the deployed Vercel mock (Phase 7); resilience cases (timeout/5xx/malformed) covered | Developer |
| R-13 | Project mgmt | Free-tier limits (scratch caps shared w/ todo-app, Dev Edition API caps, Vercel/event-bus limits) stall work | M | M | Batch experiments; count scratch budget before pushing; document caps as real platform constraints (landscape §4) | Release Mgr |
| R-14 | Governance | Solo project drifts from its own process (hats collapse, gates skipped) | H | M | ccb-log/release-log as forcing functions; retro at each release asks "which gate did I shortcut?"; reuse todo-app discipline | CCB |
| R-15 | Operations | Rollback of the base package breaks an installed consumer (todo-app) | L | H | Additive-only schema + public-API rule within a major (NFR-11); dependency-ordered install; rollback rehearsal with consumer installed (Phase 8) | Release Mgr |

## Notes

- R-2, R-3, R-4, R-10 are the integration-specific risks the todo-app never faced — they are
  the reason Phase 8 carries an **integration-failure drill** and Phase 7 carries
  **contract + resilience tests**.
- Highest-attention risks (I=H): R-4, R-5, R-6, R-7, R-9, R-15 — each maps to a mandatory
  test or drill, not just a doc.
