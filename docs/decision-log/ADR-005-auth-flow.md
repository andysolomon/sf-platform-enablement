# ADR-005: Authentication & Authorization Flows

- **Status:** Accepted
- **Date:** 2026-06-17
- **Deciders:** Architect hat + InfoSec partner hat

> **Exercises:** integration deck `evaluate-authentication-and-authorization-needs`,
> `identify-integration-security-authentication-authorization-requirements`, `references.html`
> (OAuth flows, Connected Apps, Named Credentials, security keys).
> **JD lines:** "Must have security model"; "Partner with InfoSec"; "Creates Integrations…
> between Salesforce and 3rd party applications."
> **Constrains:** FR-4, FR-8; NFR-1. **RTM design coverage:** NFR-1, FR-4, FR-8.
> **Relates to:** Andy's `arc-sf-jwt-bearer` skill (RSA keypair + JWT bearer setup).

## Context

The deck's rule (`references.html`): *don't pick "OAuth" generically — pick the flow by
**actor, interactivity, and secret handling**.* Two directions, both **server-to-server with
no interactive user**, but with opposite trust postures: outbound *we* authenticate to FRS;
inbound *FRS* authenticates to us. NFR-1: no secret in source/logs; least-privilege inbound.

## Decision — Outbound (SF → FRS): Named Credential + External Credential

- **External Credential** of type **OAuth 2.0 — Client Credentials** holds the auth config;
  a **Named Credential** (`FRS_Service`) holds the endpoint. Apex calls
  `callout:FRS_Service/v1/notifications` — **no URL or secret in code** (NFR-1, FR-4), and the
  endpoint is **per-environment** (scratch/prod) so deployments are portable.
- Token lifetime/refresh handled by the platform; secrets live in the External Credential's
  protected store, never in metadata committed to git.
- **Documented fallback:** an External Credential of type **Custom** sending an API-key header
  — acceptable if standing up an OAuth token endpoint on the Vercel mock is overkill. Primary
  remains Client Credentials because demonstrating the OAuth flow is a JD talking point.

| Outbound option | For | Against |
|---|---|---|
| Endpoint + key hard-coded / Remote Site Setting | none worth it | secret in code/metadata, not portable, fails NFR-1 |
| Named Cred + **Custom (API key)** External Cred | simple; no token endpoint | weaker than OAuth; less to talk about |
| Named Cred + **OAuth Client Credentials** External Cred (chosen) | no user, server-to-server fit; centrally governed; portable; phishing-resistant vs. shared key | mock must expose a token endpoint |

## Decision — Inbound (FRS → SF): Connected App + JWT Bearer + integration user

- A **Connected App** is the control plane for FRS's access (scopes, IP/session policy, admin
  approval) — the JD's "manages the core security model."
- FRS authenticates with the **OAuth 2.0 JWT Bearer flow**: it signs a JWT with its **private
  key**; Salesforce verifies with the **certificate** uploaded to the Connected App. **No
  client secret or password is stored on the FRS side** — the strongest server-to-server
  posture (and the exact flow Andy's `arc-sf-jwt-bearer` skill provisions).
- The token is issued **as a dedicated least-privilege integration user** whose permission set
  grants **only** access to the inbound `FrsStatusResource` and the specific object/fields it
  updates — nothing else (NFR-1, risk R-7). Unauthenticated/over-scoped calls are rejected and
  logged.

| Inbound option | For | Against |
|---|---|---|
| Username-password OAuth | simple | stores a password + secret on FRS; weakest; discouraged |
| Client Credentials (runs as a named user) | no JWT setup | requires a stored client secret on FRS |
| **JWT Bearer (cert-based) (chosen)** | no stored secret on FRS; key-pair/cert trust; phishing-resistant; canonical SF server-to-server flow | cert lifecycle to manage (rotation drill, Phase 8) |

## Auth hardening (references.html — security keys)

- **MFA / phishing-resistant factors** required for any human admin of the Connected App.
- Least-privilege Connected App policy: minimum OAuth scopes, IP relaxation only as needed,
  short token lifetime, admin-approved-users-only.
- **Secret/cert rotation** is a Phase 8 drill (rotate the External Credential secret and the
  JWT signing cert with zero downtime) — proves the rotation runbook.

## Consequences

- **NFR-1 testable:** an inbound test asserts an unauthenticated call is rejected+logged; a
  `runAs(integrationUser)` test proves the integration user cannot exceed its scope; a
  grep/review gate proves no endpoint/secret in source.
- Outbound is **environment-portable** (Named Credential per org) — the same code runs against
  the scratch-org mock and the deployed Vercel mock with no change.
- Two distinct OAuth flows, each justified by actor/secret-handling — the deck's discipline
  made concrete, and a strong interview answer ("I don't say 'OAuth,' I say *which* flow and
  *why*").
- Cert + secret lifecycles introduce a rotation obligation → the Phase 8 secrets-rotation
  drill exists precisely to exercise it.
- Feeds `security-trust-boundary.md` (the InfoSec handoff artifact) and the Connected App /
  Named Credential / integration-user metadata built in Phases 4–6.
