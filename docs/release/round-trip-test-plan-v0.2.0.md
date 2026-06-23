# Round-Trip Test Plan — v0.2.0 (6-C live verification, FR-10)

> Proves the full bidirectional chain once the live setup is in place. Unit tests already cover
> every branch with mocks (35/35, 98%); this plan exercises the **real** wires that mocks can't:
> Named Credential → OAuth → Vercel, and Vercel → JWT → inbound Apex REST. It is the 6.5
> acceptance for FR-10 (one correlation id across the whole round-trip).

## Preconditions (the live setup — see runbooks)

- [ ] Vercel **Deployment Protection OFF** on `frs-mock-service` (else 401 wall blocks callouts).
- [ ] **Named/External Credential** `FRS_Service` configured (`docs/devops/named-credential-setup.md`).
- [ ] **Connected App + JWT** configured + integration user assigned (`docs/devops/connected-app-jwt-setup.md`).
- [ ] `frs-platform` (>= 0.2.0 with 6-A/6-B) installed in the target org.
- [ ] Consumer wired per `docs/integration/consumer-onboarding.md` (or use the smoke script below).

## A. Outbound only (S1 — Fire-and-Forget)

1. `sf apex run` the smoke script `scripts/apex/round-trip-smoke.apex` (section 1) OR complete a Todo.
2. **Expect:** an async `CalloutQueueable`; FRS mock returns `202`; one `Log__c`
   (`Category__c = integration/outbound`, `Severity__c = INFO`) with the correlation id.
3. **Negative:** point the request at `/v1/notifications` while the mock is set to fail (env
   `FRS_FORCE_STATUS=503`) → after bounded retries an `Integration_DeadLetter__c` row appears
   (FR-7). Then `ReplayService.replay(dlId)` with the mock healthy → `Status__c = REPLAYED`,
   delivery succeeds, no new dead letter.

## B. Inbound only (S2 — Remote Call-In)

1. Drive the mock's `/v1/simulate-callback` (or curl per the JWT runbook) to POST
   `/services/apexrest/frs/v1/status`.
2. **Expect:** `200 {"status":"applied"}`, one `Integration_Message__c` for the key, one inbound
   `Log__c`.
3. **Idempotency:** resend the SAME `idempotencyKey` → `200 {"status":"duplicate"}`, still ONE
   `Integration_Message__c`, a "DEDUPLICATED" log (FR-9 / NFR-3).
4. **Validation:** POST without `payload.salesforceRecordId` → `400`, no record (contract §4.3).

## C. Full round-trip (FR-10 — the headline)

1. Complete a Todo in todo-app (Status Open → Done).
2. Chain: consumer `Logger.info` → outbound `CalloutService.sendAsync` → FRS `202` → FRS calls
   back inbound `/frs/v1/status` echoing the **same correlation id** → SF applies + logs.
3. **Acceptance:** `SELECT Id, Category__c, Message__c, CreatedDate FROM Log__c WHERE
   Correlation_Id__c = :corr ORDER BY CreatedDate` returns the ordered chain across BOTH
   directions; exactly one `Integration_Message__c` for the inbound key.
4. **Resilience replay:** glitch a duplicate inbound (same key) → `200 duplicate`, no second
   effect — the round-trip is exactly-once end to end.

## Exit criteria → tag v0.2.0

- [ ] A, B, C all green; correlation chain reconstructs from logs (FR-10).
- [ ] Dead-letter + replay demonstrated (FR-7); duplicate inbound is a no-op (FR-9).
- [ ] RTM rows FR-5/6/7/8/9/10/11 moved to **Verified**; CHANGELOG `[0.2.0]`; smoke archived here.
- [ ] No secret/endpoint in code or logs (NFR-1/2 spot-check on the new `Log__c` rows).
