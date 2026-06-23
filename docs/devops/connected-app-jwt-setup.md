# Connected App + JWT Bearer Setup — inbound FRS → SF (execution step)

> Why this is a runbook, not committed metadata: like the outbound Named Credential
> (`named-credential-setup.md`), the inbound auth holds org-specific material — a digital
> certificate and the SF-generated consumer key — and authorizes a least-privilege integration
> user. Per NFR-1 / ADR-005 this is configured per-org at execution time. `FrsStatusResource`
> already exists and is authorized by the `FRS_Integration` permission set; this runbook is the
> last mile that lets the **FRS mock present `Authorization: Bearer <jwt>`** and be accepted.

Mechanism (contract §2, landscape §6 auth matrix): **OAuth 2.0 JWT Bearer**. The FRS side holds
a **private key**; Salesforce's Connected App holds the matching **certificate (public key)** and
maps the token to a dedicated integration user. Auth failures (`401`/`403`) are non-retryable and
raise the Phase 9 alert condition.

## Inputs

- A self-signed cert/key pair (the FRS side keeps the private key; SF gets the cert).
- A dedicated **integration user** (least-privilege; `FRS_Integration` permission set only).
- The mock's JWT signer config (set in the Vercel project env, see `frs-mock-service`).

## Step 0 — generate the key pair (local, one-time)

```bash
# Private key (stays with the FRS mock — set as a Vercel env secret, never committed)
openssl genrsa -out frs_jwt_private.key 2048
# Self-signed cert (the PUBLIC half — uploaded to the SF Connected App)
openssl req -new -x509 -key frs_jwt_private.key -out frs_jwt.crt -days 365 \
  -subj "/CN=frs-mock-service/O=arcnology"
```

Load `frs_jwt_private.key` into the mock as `FRS_JWT_PRIVATE_KEY` (Vercel env); the mock's
`/v1/simulate-callback` signs a JWT with it (`lib/auth.ts`). Keep the private key out of git.

## Step 1 — dedicated integration user (least-privilege)

1. Create a user (e.g. `frs-integration@<org>`), minimal profile (Minimum Access / API-only).
2. Assign the **`FRS_Integration`** permission set (grants `FrsStatusResource` + `LogEvent__e`
   create + `Integration_Message__c` create/read — nothing else, per charter SoD).

## Step 2 — Connected App (Setup UI → App Manager → New Connected App)

- **Name:** `FRS Inbound`
- **Enable OAuth Settings:** on
- **Callback URL:** `https://login.salesforce.com/services/oauth2/callback` (placeholder; unused for JWT)
- **Use digital signatures:** on → upload **`frs_jwt.crt`**
- **OAuth Scopes:** `Manage user data via APIs (api)`, `Perform requests at any time (refresh_token, offline_access)`
- Save → note the **Consumer Key** (this is the JWT `iss`).
- **Manage → Policies:** Permitted Users = *Admin approved users are pre-authorized*; then
  assign the **integration user** (via a permission set or profile) so JWT issuance is allowed.

> Committable alternative (if you later choose code over click-ops): a `ConnectedApp`
> `.connectedApp-meta.xml` can carry the cert (public) + OAuth config. It is intentionally kept
> out of `force-app/` here to honor the per-org-config decision and keep the package build clean.
> Template lives at the end of this doc.

## Step 3 — the mock obtains a token and calls inbound

The FRS mock builds a JWT (`iss`=Consumer Key, `sub`=integration user, `aud`=login URL,
`exp`<=5min), signs with the private key, exchanges it at
`POST https://login.salesforce.com/services/oauth2/token`
(`grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=<jwt>`), then calls
`POST <instance>/services/apexrest/frs/v1/status` with `Authorization: Bearer <access_token>`.

## Verify (the inbound half of the round-trip)

```bash
# After setup, from the mock (or curl) send a status callback:
curl -sS -X POST "<instance>/services/apexrest/frs/v1/status" \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: <corr>" \
  -d '{"correlationId":"<corr>","idempotencyKey":"frs-status-1","eventType":"status.updated","payload":{"salesforceRecordId":"<id>","status":"Acknowledged"}}'
# Expect 200 {"status":"applied",...}; resend the SAME idempotencyKey → 200 {"status":"duplicate",...}
```

Then confirm in the org: one `Integration_Message__c` for the key, and `Log__c` rows
(`Category__c = integration/inbound`) for the applied + deduplicated deliveries (FR-8/FR-9/NFR-6).

## Notes

- Until the Connected App exists, `FrsStatusResourceTest` still passes (it sets `RestContext`
  directly); only the live Bearer call needs this setup.
- `401`/`403` are non-retryable on both sides (contract §4.3) and feed the Phase 9 alert.

---

## Appendix — committable ConnectedApp template (optional, not in force-app/)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ConnectedApp xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>FRS Inbound</label>
    <contactEmail>integration@arcnology.dev</contactEmail>
    <oauthConfig>
        <callbackUrl>https://login.salesforce.com/services/oauth2/callback</callbackUrl>
        <certificate>-----BEGIN CERTIFICATE-----
&lt;paste frs_jwt.crt contents&gt;
-----END CERTIFICATE-----</certificate>
        <isAdminApproved>true</isAdminApproved>
        <scopes>Api</scopes>
        <scopes>RefreshToken</scopes>
    </oauthConfig>
</ConnectedApp>
```
