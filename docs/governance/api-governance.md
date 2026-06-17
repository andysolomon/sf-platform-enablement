# API Governance

> **Exercises:** building-quality-code (interfaces as contracts),
> operating-managing-common-release-artifacts (versioned artifacts), releasing-packaging-strategy.
> **JD lines:** "Deliver explicit APIs and abstractions that offer flexibility for
> application developers"; "operationalization of reusable components"; "platform patterns
> and technical best-practices… to increase adoption."
> **Constrains:** NFR-8 (public-API stability). **Referenced by:** charter.md (Consumer App
> Lead hat), change-management.md (breaking-API class), definition-of-done.md.

This is the document that makes this project a *platform* and not just another app: because
the package has **consumers** (todo-app, then a second team), its public API is a contract.
The todo-app had no analogue — this is net-new governance.

## 1. What counts as the public API

The public surface is **the only thing consumers may depend on**, and **the only thing
governed by the stability rules below.** Everything else is internal and may change freely.

| Surface | Public? | Marker |
|---|---|---|
| Apex classes/methods intended for consumers (`Logger`, `EventPublisher`, `CalloutService`) | **Yes** | `global` **or** `public` + listed in `public-api-spec.md` |
| Inbound integration endpoint (`/services/apexrest/frs/v1/*`) | **Yes** | versioned URL path (`/v1`), specified in `integration-contract.md` |
| Outbound wire contract (notification payload) | **Yes** | `integration-contract.md` `/v1` |
| Platform Event schemas consumers subscribe to | **Yes** | listed in `public-api-spec.md` |
| Custom objects/fields, helper/internal classes, trigger handlers, implementation details | **No** | not in `public-api-spec.md`; may change without a major bump |

**Rule:** if it isn't in `public-api-spec.md` (Apex/event surface) or `integration-contract.md`
(wire surface), it is **internal**. Consumers depending on internal members do so at their own
risk; that risk is documented in consumer onboarding.

## 2. Versioning the public API (semver of a contract)

The package version (`sfdx-project.json`) and the wire contract (`/vN`) both follow semver,
applied to the **public API**, not to internal churn:

| Change to the public API | Version impact |
|---|---|
| New optional member / new method / new optional field / new enum value consumers can ignore | **Minor** |
| Internal-only change, refactor behind the surface, bug fix that preserves the contract | **Patch** |
| Removed/renamed member, changed signature/return type, new *required* field, changed auth, behavior change that breaks a documented contract | **Major** (+ deprecation cycle first — §3) |

A consumer (todo-app) must be able to upgrade across any **minor/patch** with **zero code
changes** (NFR-8) — proven by the consumer-compatibility test (Phase 7) and the deprecation
drill (Phase 8).

## 3. Deprecation policy

Breaking changes are never shipped abruptly. The cycle:

1. **Deprecate** — mark the member (`@deprecated` annotation + doc note in
   `public-api-spec.md`) and add a replacement. Both old and new work.
2. **Warn** — the deprecated member logs a deprecation warning (via `Logger`) when called,
   and a `deprecation-log.md` entry records: what, since which version, replacement, planned
   removal version, and which consumers still use it.
3. **Notify** — the Consumer App Lead hat acknowledges the deprecation; consumers migrate.
4. **Remove** — only on a **major** version, and only after the deprecated member has shipped
   working for **≥ 1 minor version** and all known consumers have migrated.

Minimum support window: a deprecated public member is supported for at least one minor
release before removal. Removing faster requires a CCB exception with a documented reason.

## 4. Change workflow for a public-API change

A public-API change is a distinct change class (see `change-management.md`) and requires,
before merge:
- an **ADR** (or update) recording the change and why,
- **Architect** sign-off (design) **and Consumer App Lead** sign-off (impact + migration path),
- `public-api-spec.md` / `integration-contract.md` updated **in the same MR**,
- the consumer-compatibility test updated, and
- a `deprecation-log.md` entry if anything is deprecated.

## 5. Wire-contract governance (the integration surface)

The SF↔FRS contract (`integration-contract.md`) is versioned independently by URL path:
- Additive within `/v1` (new optional fields, new enum values) — no new version.
- Breaking → `/v2`, with `/v1` kept per the deprecation window until consumers migrate.
- The contract test (Phase 7) runs against the deployed mock and **fails on drift** in
  either direction — the executable enforcement of this policy.

## 6. Why this matters (interview framing)

"An app team owns its own blast radius; a **platform** team owns everyone else's. So the
discipline that's optional for an app — semver of the *public* surface, a deprecation window,
consumer sign-off, an executable compatibility test — becomes mandatory. That's the
difference between shipping a feature and operationalizing a reusable component."
