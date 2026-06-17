# Change Management

> **Exercises:** releasing-release-management-strategy (release types + paths),
> operating-direct-changes-production, operating-integrating-direct-changes-alm.
> **JD lines:** "Experience with change management systems and processes";
> "change-management controls, auditability, and release governance using SFDX+CI/CD."

Reuses the todo-app change model and adds one class — **breaking API change** — because this
package has consumers (see `api-governance.md`).

## Change classes and release paths

Every change is classified before work starts. Classification disputes go to the CCB hat.

| Class | Examples | Approval | Release path | Cadence |
|---|---|---|---|---|
| **Immediate** | Doc fixes, comments, CI tweaks that don't touch gates | Reviewer hat | MR → main (full pipeline runs; no package release) | As needed |
| **Minor** | One FR story; new optional API member; new optional payload field; internal refactor | Reviewer hat | MR → pipeline → base package version → next planned release | Per release |
| **Major** | Schema change, auth/security-model change, pipeline gate change, multi-story batch | Architect (design) + CCB (scope) before work | Minor path + staging UAT + contract test vs. deployed mock before release | Planned release only |
| **Breaking API change** *(new)* | Removed/renamed public member, changed signature, new required field, changed wire auth, `/v2` of the contract | Architect + **Consumer App Lead** + CCB; **must follow the deprecation cycle** (api-governance §3) | Major path + deprecation window + consumer migration confirmed | Major version only |
| **Hotfix** | Production defect blocking use (incl. a failing live integration) | CCB authorizes; Release Manager fast-tracks | Branch from release tag → all pipeline gates (none skipped) → patch version → prod → back-merge to main | Urgent only |

Notes:
- "Fast-track" means *priority*, not *fewer gates*. Every class runs every gate.
- Schema **and public-API** changes must be **additive** within a major version (no field or
  public-member deletes/renames) so base-package rollback stays safe for installed consumers
  (NFR-11). Destructive changes are Major/Breaking class and require an ADR.
- A **security or integration-auth change** additionally requires the **InfoSec hat** sign-off
  (charter decision-authority table) before merge.

## Direct changes to production: forbidden

No setup edits, field tweaks, or "quick fixes" directly in the "prod" org — same reasons as
the study material: bypassed testing, environment drift, broken audit trail, compliance
exposure. **This is sharper here:** a manual prod change to a base package can desync it from
the installed consumer, breaking the dependency.

**If it happens anyway**, run the retroactive-integration cycle in order:
1. **Document** — what changed, which hat, when, why.
2. **Approve** — retroactive CCB entry; if it wouldn't have been approved, schedule reversal.
3. **Back-integrate** — reproduce in source (`sf project retrieve`), land via a normal MR so
   git matches prod again.
4. **Update downstream** — recreate long-lived scratch orgs and re-validate the **consumer**
   against the changed base.
5. **Validate** — full pipeline; confirm no drift remains.
6. **Monitor** — note in the next post-release review.

## Scope changes

The FR/NFR baseline was set at the end of Phase 2 (2026-06-17). After that, any new or
materially changed requirement is a CCB decision *before* implementation — logged with
rationale, RTM updated in the same MR that implements it.

## Communication

Each release gets a short comms note in the changelog (audience: consuming app teams).
Hotfixes additionally get an incident note: impact, cause, fix, prevention. **A
public-API change or deprecation gets a consumer-facing notice** (api-governance §3) so
dependent teams can plan migration.
