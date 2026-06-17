# Project Charter

> **Exercises:** planning-governance (CoE, program charter, decision authority),
> application-lifecycle-management (ALM stages).
> **JD line:** "change-management controls, auditability, and release governance using
> SFDX+CI/CD"; "platform patterns and technical best-practices… to increase adoption."

## Purpose

Build a **reusable Salesforce platform layer** (logging/error framework, event publisher,
outbound callout framework) plus a **bidirectional integration** to an external system,
through a fully governed, auditable ALM cycle. The components are the deliverable; the
discipline is the proof. This project plays the **platform team** to the todo-app's
**application team** — so unlike the todo-app, its public API is a **contract with
consumers**, and that changes how governance works (see `api-governance.md`).

## What's the same as todo-app, and what's new

This charter reuses the todo-app's governance model verbatim where it fits (hats,
segregation of duties, ALM stages, gates-are-not-waivable). The **new** governance surface,
because this project has consumers, is:
- a **Consumer App Lead** hat (represents the teams that depend on the package),
- an **InfoSec partner** hat (the JD's "Partner with Information Security"),
- a **breaking-API change class** (see `change-management.md`), and
- **API governance** with a deprecation policy (`api-governance.md`).

## Roles ("hats")

One person plays all roles. Discipline comes from making each hat's action explicit and
sequential — never author and approve in the same act.

| Hat | Responsibility | Authority |
|---|---|---|
| **Platform Engineer** | Author MRs: components, integration, tests, docs. Self-review against the checklist before requesting review. | Cannot approve own MR or trigger a release. |
| **Architect** | Own ADRs, integration patterns, security/trust boundary, the public-API spec, NFR conformance. Reviews MRs touching the API surface, schema, auth, or pipeline. | Approves design changes; cannot waive the DoD. |
| **Release Manager** | Run the release runbook: validate, approve the manual release job, dependency-ordered install, smoke test, comms, changelog/tag. | Only hat allowed to trigger the `release` job. |
| **Consumer App Lead** *(new)* | Represents consuming teams (todo-app + future). Signs off on any **public-API change** and on the consumer-impact assessment. | Veto on breaking changes that lack a migration path; owns the deprecation-notice acknowledgement. |
| **InfoSec partner** *(new)* | Reviews the trust boundary, secret handling, auth model, and least-privilege integration access. | Approves the security configuration before an integration ships; can block on unmitigated security risk. |
| **CCB Approver** | Approve scope changes (new/changed FRs after Phase 2 baseline), classification disputes, hotfix authorization, production exceptions. | Final say on what enters the backlog and what ships. |

## Segregation-of-duties rules (solo simulation)

1. Every governed action is recorded *as a hat* — MR approvals, release approvals, API
   change sign-offs, InfoSec approvals, and CCB decisions each get a written entry naming
   the hat and the rationale.
2. **Cooling-off rule:** an MR may not be approved in the same working session it was
   authored. Step away, return, review with the checklist as the reviewer hat.
3. CCB decisions are recorded in `ccb-log.md` (created at first use): date, request,
   classification, decision, rationale.
4. The release job in GitLab is manual-approval; clicking it *is* the Release Manager hat
   acting, and requires the runbook checklist completed first.
5. **A public-API change additionally requires the Consumer App Lead hat's sign-off**, and
   **an integration/security change requires the InfoSec hat's sign-off**, before merge.

## Decision authority

| Decision | Owner | Recorded in |
|---|---|---|
| New/changed requirement | CCB | ccb-log.md + RTM |
| Architecture / integration-pattern / stack choice | Architect | ADR in docs/decision-log/ |
| **Public-API change (signature/contract)** | Architect (design) + Consumer App Lead (impact) | ADR + api-governance deprecation log + RTM |
| **Security / auth / trust-boundary config** | InfoSec partner | security-trust-boundary.md sign-off note |
| Merge to main | Reviewer hat (per checklist) | MR record |
| Production release / hotfix | Release Manager (CCB authorizes hotfixes) | Release runbook entry + tag |
| Waiving any gate | Nobody. Gates are not waivable; change the gate via ADR instead. | — |

## ALM stages (study material's six-stage cycle, applied here)

| Stage | Meaning in this project |
|---|---|
| Plan Release | Pick FR stories; classify changes (incl. API-impact); update RTM |
| Develop | Feature branch + scratch org per story; test-first; mock the integration peer |
| Test | CI gates: static analysis, Apex tests + coverage, HttpCalloutMock, contract + resilience tests |
| Build Release | CI creates the base unlocked package version from `main` |
| Test Release | Install candidate (dependency-ordered) in staging scratch org; contract test vs. deployed Vercel mock; UAT |
| Release | Manual-approval install to "prod"; smoke test; tag; changelog; consumer comms |

## Governance maturity intent

Study material's ladder: Non-Existent → Emerging → Practicing → Leading. This project
starts at **Practicing** by construction (documented, repeatable, auditable) and uses the
api-governance + consumer-contract discipline and Phase 9 (metrics, second consumer) to
demonstrate **Leading** behaviors — a platform that other teams can adopt.
