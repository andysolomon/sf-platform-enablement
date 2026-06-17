# Definition of Done

> **Exercises:** building-quality-code (quality pillars, PR discipline),
> testing-execution-and-coverage. **JD line:** "Ensure code quality through static analysis,
> unit testing and test automation."

A story/MR is **done** only when every line below is true. Gates are not waivable (see
charter — change the gate via ADR instead). Extends the todo-app DoD with the **public-API**
and **integration** items this project needs.

## Code

- [ ] Implements exactly one classified change (one FR story per Minor MR)
- [ ] Apex: bulkified (no SOQL/DML/**callout** in loops); `with sharing` unless an ADR says
      otherwise; FLS/CRUD checked on user-facing paths; **callouts in async context (no
      callout-after-DML)**
- [ ] Trigger/subscriber logic lives in a handler, never in the trigger/subscriber body
- [ ] **No endpoint URL or secret in source** — outbound via Named Credential, inbound auth
      via Connected App (NFR-1)
- [ ] No commented-out code, no debug statements left behind

## Tests

- [ ] Written test-first where practical; user-focused (behavior, not implementation)
- [ ] Positive, negative, and (where access matters) `runAs` permission cases
- [ ] **Outbound paths covered with `HttpCalloutMock` incl. timeout/4xx/5xx/malformed**
- [ ] **Inbound idempotency proven (duplicate-delivery → no-op)** where applicable (NFR-3)
- [ ] All test data via a test data factory; no `SeeAllData=true`
- [ ] Bulk paths tested at 200+ records with `Limits` assertions (NFR-4)
- [ ] Org coverage ≥ 85% after merge; every class touched has coverage

## Quality gates (enforced by pipeline, verified by reviewer)

- [ ] Salesforce Code Analyzer: zero new criticals/highs
- [ ] **Contract test green against the deployed Vercel mock** (when the change touches the
      wire contract)
- [ ] Full pipeline green on the MR (running via the consumed todo-app CI template)

## Documentation & traceability

- [ ] RTM row(s) updated: requirement → component → test
- [ ] Diagrams/ADRs updated if integration pattern, schema, security model, or pipeline changed
- [ ] **`public-api-spec.md` updated if the public API surface changed; `integration-contract.md`
      updated if the wire contract changed** (api-governance §4)
- [ ] **Consumer-impact assessed; if a public member is deprecated, `deprecation-log.md` entry added**
- [ ] CHANGELOG entry if consumer-visible

## Review

- [ ] Reviewed against `code-review-checklist.md` by the reviewer hat, honoring the
      cooling-off rule (not same session as authored)
- [ ] **Public-API change: Consumer App Lead hat sign-off. Security/auth change: InfoSec hat
      sign-off** (charter decision-authority table)
- [ ] Review comments resolved with re-review, not self-dismissed
