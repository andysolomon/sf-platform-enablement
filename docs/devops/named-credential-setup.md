# Named Credential Setup — FRS_Service (execution step)

> Why this is a runbook, not committed metadata: the External Credential holds a **secret**
> (the OAuth client secret) and the Named Credential points at the **live Vercel URL** — neither
> belongs in version-controlled metadata (NFR-1). So the credential is configured per-org at
> execution time. Apex already references it as `callout:FRS_Service/...` (ADR-005, FR-4).

## Inputs (from Phase 4.4)

- **Base URL:** the deployed mock, e.g. `https://frs-mock-service-rezdny3pa-andrewsolomonedus-projects.vercel.app`
  (use the stable production alias once Vercel Deployment Protection is OFF).
- **Token URL:** `<base>/oauth/token`
- **client_id / client_secret:** the `FRS_CLIENT_ID` / `FRS_CLIENT_SECRET` set in the Vercel
  project env (saved locally in `frs-mock-service/.env.local`).

## Steps (per scratch org / "prod"), Setup UI

1. **External Credential** `FRS_Service_Cred`
   - Authentication Protocol: **OAuth 2.0**
   - Grant Type: **Client Credentials**
   - Token Endpoint URL: `<base>/oauth/token`
   - Scope: `notifications:write`
   - Add a **Principal** (Named Principal) and enter the `client_id` / `client_secret`.
2. **Named Credential** `FRS_Service`
   - URL: `<base>`
   - Linked to External Credential `FRS_Service_Cred`
   - Generate Authorization Header: on; Allow callouts to this endpoint.
3. **Permission set** — grant the running user (and `FRS_Integration`) access to the External
   Credential principal (External Credential Principal Access), so the callout can use it.

## Verify (5.2 — the real scratch-org callout)

```bash
# in the scratch org after deploy + credential setup:
sf apex run --target-org <scratch> <<'APEX'
HttpResponse r = CalloutService.ping();
System.debug('FRS /health status: ' + r.getStatusCode() + ' body: ' + r.getBody());
APEX
```

Expect `200` and `{"status":"ok","service":"frs-mock-service"}` — confirming the round-trip
SF → Named Credential → OAuth token → Vercel mock works end to end.

## Notes

- Until the credential exists, `CalloutServiceTest` still passes (it uses `HttpCalloutMock`);
  only the live `5.2` scratch-org call needs the real credential.
- The inbound direction (FRS → SF, `FrsStatusResource`) needs the **Connected App + JWT cert**
  (ADR-005) — that's its own setup, exercised when the round-trip is wired in Phase 6.
