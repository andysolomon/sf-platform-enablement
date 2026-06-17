# Sequence Diagrams

> **Exercises:** building-quality-code (async patterns), integration deck (pattern timing/
> failure handling). **JD lines:** "Apex classes, triggers, asynchronous processing"; "Must
> have integration patterns"; resilient integration.
> **Implements:** ADR-002 (pattern), ADR-003 (retry/idempotency), ADR-004 (logging),
> ADR-005 (auth). **RTM design coverage:** FR-5, FR-6, FR-7, FR-8, FR-9, FR-10, FR-11;
> NFR-3, NFR-4, NFR-5, NFR-6, NFR-7.

Logging is omitted from §1–§5 for readability and shown explicitly in §6; assume every
participant calls `Logger` with the shared correlation id at each step.

## 1. Outbound S1 — happy path (RPI Fire-and-Forget, FR-5)

```mermaid
sequenceDiagram
    actor U as User
    participant APP as Consumer app (todo-app)
    participant EP as EventPublisher (public API)
    participant BUS as Domain Platform Event
    participant SUB as PE subscriber trigger
    participant Q as CalloutQueueable (AllowsCallouts)
    participant CS as CalloutService (Named Cred)
    participant FRS as FRS /v1/notifications

    U->>APP: completes a todo
    APP->>EP: publish(todo.completed, correlationId C)
    EP->>BUS: EventBus.publish
    APP-->>U: save commits (does NOT wait on FRS)
    Note over APP,BUS: user transaction ends here — NFR-4 (no block, no callout-after-DML)
    BUS->>SUB: deliver (async)
    SUB->>Q: System.enqueueJob (one enqueue / transaction)
    Q->>CS: send(notification, idempotencyKey K1, corr C)
    CS->>FRS: POST (OAuth Client-Creds via External Cred)
    FRS-->>CS: 202 Accepted
    Note over CS: success logged with corr C (FR-5)
```

## 2. Outbound S1 — transient failure → retry with backoff (FR-6, NFR-5)

```mermaid
sequenceDiagram
    participant Q as CalloutQueueable (attempt n)
    participant CS as CalloutService
    participant FRS as FRS /v1/notifications
    participant FIN as Queueable Finalizer

    Q->>CS: send(... same idempotencyKey K1)
    CS->>FRS: POST
    FRS-->>CS: 500 / timeout / 429
    CS-->>Q: retryable (per contract §3.3)
    Q->>FIN: finalizer evaluates outcome
    alt attempts remain
        FIN->>Q: re-enqueue with delay (1→2→4 min, honor Retry-After)
        Note over FIN,Q: same K1 → FRS dedupes if a prior try actually landed (409=success)
    else exhausted
        FIN->>FIN: route to dead-letter (see §3)
    end
```

Non-retryable codes (`400`/`401`/`403`) skip retry entirely and go straight to dead-letter +
alert (auth failures are an InfoSec signal, ADR-005/NFR-1).

## 3. Outbound S1 — exhaustion → dead-letter → operator replay (FR-7, NFR-5)

```mermaid
sequenceDiagram
    participant FIN as Finalizer (retries exhausted)
    participant DL as Integration_DeadLetter__c
    participant OPS as Operator
    participant RS as ReplayService
    participant Q as CalloutQueueable
    participant FRS as FRS

    FIN->>DL: insert (corr C, key K1, payload ref, last error, attempts)
    Note over DL: raises Phase 9 alert condition
    OPS->>RS: replay(deadLetterId) — after cause fixed
    RS->>Q: re-enqueue with SAME key K1, corr C
    Q->>FRS: POST
    FRS-->>Q: 202 (or 409 = already had it → success)
    RS->>DL: clear entry
    Note over RS,DL: timed against 30-min RTO (NFR-5) in the Phase 8 drill
```

## 4. Inbound S2 — happy path (Remote Call-In, idempotent apply, FR-8)

```mermaid
sequenceDiagram
    participant FRS as FRS outbound caller
    participant CA as Connected App (JWT Bearer)
    participant R as FrsStatusResource (@RestResource, integration user)
    participant IM as Integration_Message__c (unique key)
    participant REC as Target record

    FRS->>CA: JWT assertion (signed w/ private key)
    CA-->>FRS: access token (least-priv integration user)
    FRS->>R: POST /frs/v1/status (key K2, corr C echoed)
    R->>IM: upsert by unique External Id = K2
    IM-->>R: inserted (first time)
    R->>REC: apply status update
    R-->>FRS: 200 {status: applied, corr C}
```

## 5. Inbound S2 — duplicate delivery → idempotent no-op (FR-9, NFR-3)

```mermaid
sequenceDiagram
    participant FRS as FRS (re-delivers same message)
    participant R as FrsStatusResource
    participant IM as Integration_Message__c (unique key)
    participant REC as Target record

    FRS->>R: POST /frs/v1/status (SAME key K2)
    R->>IM: upsert by unique External Id = K2
    IM-->>R: DUPLICATE_VALUE (unique constraint hit)
    R--xREC: NO second update
    R-->>FRS: 200 {status: duplicate, corr C}
    Note over R,IM: platform-enforced uniqueness → race-safe under concurrent re-delivery (ADR-003)
```

## 6. Logging — survives rollback (FR-2, NFR-7, ADR-004)

```mermaid
sequenceDiagram
    participant TX as Any transaction
    participant LG as Logger (public API)
    participant LE as Log__e (Publish Immediately)
    participant LS as Log__e subscriber
    participant LC as Log__c (queryable)

    TX->>LG: error("...", corr C)
    LG->>LE: EventBus.publish (immediate — not tied to commit)
    TX--xTX: transaction throws → ROLLBACK
    Note over TX,LE: the rollback does NOT unpublish the immediate event
    LE->>LS: deliver (separate transaction)
    LS->>LC: insert Log__c (corr C, severity, source, category)
    Note over LS,LC: log persists despite the rollback — NFR-7 satisfied
```

## 7. Full round-trip — one correlation id end to end (FR-10)

```mermaid
sequenceDiagram
    actor U as User
    participant APP as Consumer
    participant PLAT as Platform layer
    participant FRS as FRS (Vercel)
    participant LOG as Log__c

    U->>APP: complete todo
    APP->>PLAT: domain event (corr C)
    PLAT->>LOG: log: event received (C)
    PLAT->>FRS: outbound notify (C, key K1)
    PLAT->>LOG: log: outbound 202 (C)
    FRS->>PLAT: inbound status (C echoed, key K2)
    PLAT->>LOG: log: inbound applied (C)
    FRS->>PLAT: duplicate inbound (same K2)
    PLAT->>LOG: log: deduplicated (C)
    Note over LOG: query Log__c WHERE correlationId = C → full ordered chain (FR-10, NFR-6)
```

## Design rules encoded here

- **One `enqueueJob` per transaction** (§1), never per record → bulk-safe to 200 (FR-11/NFR-4);
  the 200-record `Limits` test proves it on this exact path.
- **Same idempotency key across retries/replay** (§2, §3) → the receiver dedupes; correlation
  id is separate and threads tracing (§7).
- **Unique-constraint upsert** for inbound dedupe (§5) → correct under concurrent duplicate
  delivery, not just sequential.
- **Immediate-publish logging** (§6) → the one mechanism that makes pre-failure logs durable.
