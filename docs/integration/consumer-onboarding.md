# Consumer Onboarding — adopting the `frs-platform` package (6.6)

> This is the proof of the project thesis: **the reusable layer is the product; the integration
> is the proof.** A consuming app team (here, **todo-app**) declares a dependency on
> `frs-platform`, then calls its public API (`Logger`, `EventPublisher`, `CalloutService`) instead
> of hand-rolling logging, eventing, or callouts. The platform owns resilience, idempotency,
> secrets, and observability; the consumer owns its business event. This is the **base ← consumer**
> model from `package-dependency.md` (ADR-001) made concrete.

Status: **ready to apply** — the steps below are validated as code/config but require the
published `frs-platform` package version installed in the consumer's org, so they execute when
6-C goes live. Nothing here is deployed yet.

## What the consumer may call (public API surface — public-api-spec.md)

| API | Use |
|---|---|
| `Logger.info/warn/error/log(...)` | structured, rollback-surviving logs with a correlation id (FR-1/2) |
| `EventPublisher.publish(...)` | publish a domain event the platform may act on (FR-3) |
| `CalloutService.sendAsync(Request)` | async, retrying, idempotent, governor-safe outbound notify (FR-5/6/7/11) |

Consumers **never** touch `LogEvent__e`, `CalloutQueueable`, retry/dead-letter internals, or
endpoints/secrets (api-governance ⚫). Those are the platform's.

## Step 1 — declare the dependency (todo-app `sfdx-project.json`)

```jsonc
{
  "packageDirectories": [
    {
      "path": "force-app",
      "default": true,
      "package": "todo-app",
      "versionNumber": "1.0.0.NEXT",
      "dependencies": [
        { "package": "frs-platform@0.1.0-2" }   // base layer
      ]
    }
  ],
  "packageAliases": {
    "todo-app": "0HogK0000002sM5SAI",
    "frs-platform": "0HogK00000038c9SAA",
    "frs-platform@0.1.0-2": "04tgK000000DsNZQA0"  // released subscriber pkg version
  }
}
```

> When 6-A/6-B ship as `frs-platform 0.2.0`, bump this to `frs-platform@0.2.0-1` so the consumer
> gets `CalloutService.sendAsync` + the inbound handler. (Re-validate the version alias from the
> platform's `sfdx-project.json` after the package build.)

## Step 2 — install into the consumer org (dev/scratch/prod)

```bash
sf package install --package frs-platform@0.2.0-1 --target-org <org> --wait 20 --no-prompt
```

Scratch dev resolves dependencies automatically on `sf project deploy`/package build once the
alias is declared.

## Step 3 — grant the running context the External Credential principal

The consumer's transaction makes the outbound callout via `callout:FRS_Service`. Assign the
running user **External Credential Principal Access** for `FRS_Service_Cred` (see
`named-credential-setup.md` step 3). Global Apex (`Logger`, `CalloutService`) needs no class
access — it's `global`.

## Step 4 — call the platform from the business event

todo-app already funnels DML through `TodoTriggerHandler` (one-trigger-per-object). Add an
after-update hook that notifies FRS when a todo flips to **Done** — fire-and-forget, async, so the
user's save is never blocked (S1, FR-5).

```apex
// In TodoTriggerHandler (consumer code) — runs in the after-update path.
private void notifyFrsOnCompletion(List<Todo__c> news, Map<Id, Todo__c> oldMap) {
    List<CalloutService.Request> requests = new List<CalloutService.Request>();
    for (Todo__c t : news) {
        Todo__c prior = oldMap.get(t.Id);
        Boolean justCompleted = t.Status__c == 'Done' && (prior == null || prior.Status__c != 'Done');
        if (!justCompleted) {
            continue;
        }
        String correlationId = newCorrelationId();              // fresh per business event (FR-10)
        CalloutService.Request req = new CalloutService.Request();
        req.namedCredentialPath = 'FRS_Service/v1/notifications';
        req.method = 'POST';
        req.correlationId = correlationId;
        req.idempotencyKey = 'todo-' + t.Id + '-completed';     // STABLE per logical message (ADR-003)
        req.body = JSON.serialize(new Map<String, Object>{
            'correlationId' => correlationId,
            'idempotencyKey' => req.idempotencyKey,
            'eventType' => 'todo.completed',
            'occurredAt' => System.now().formatGmt("yyyy-MM-dd'T'HH:mm:ss'Z'"),
            'source' => 'todo-app',
            'payload' => new Map<String, Object>{
                'salesforceRecordId' => t.Id,
                'status' => 'Completed'
            }
        });
        requests.add(req);
        Logger.info('todo completed -> notifying FRS [' + correlationId + ']', correlationId);
    }
    if (!requests.isEmpty()) {
        CalloutService.sendAsync(requests);   // bulk-safe, async, retrying, idempotent (platform owns it)
    }
}

// Correlation id: any unique trace token. Apex has no native UUID; a random hex is fine.
private String newCorrelationId() {
    return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
}
```

### Why this is the platform win (interview narrative)
- The consumer wrote ~25 lines of **business intent** and got retry/backoff, dead-letter +
  replay, idempotent delivery, 200-record bulk safety, secret-free callouts, and correlated
  observability **for free** — all owned, versioned, and tested by the platform team.
- The **same** correlation id appears in the consumer's log, the outbound call, the FRS record,
  and the inbound callback — one `WHERE Correlation_Id__c = :id` query reconstructs the round-trip
  (FR-10).
- Bulkified by construction: `sendAsync(List<Request>)` chunks to stay governor-safe even when a
  batch flips 200 todos to Done at once (FR-11) — the consumer can't get this wrong.

## Step 5 — verify

Complete a todo → expect an async `CalloutQueueable` run, a `200/202` from the FRS mock, and
(after FRS calls back) an `Integration_Message__c` + correlated `Log__c` rows for the full chain.
The live verification checklist is `docs/release/round-trip-test-plan-v0.2.0.md`.
