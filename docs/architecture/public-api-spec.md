# Public API Specification

> **Exercises:** building-quality-code (interfaces as contracts); "Deliver explicit APIs and
> abstractions that offer flexibility for application developers" (JD).
> **JD lines:** "explicit APIs and abstractions"; "reusable components."
> **Governed by:** `api-governance.md`. **Constrains:** NFR-8. **Implements:** FR-1, FR-3, FR-4.
> **RTM design coverage:** FR-1, FR-3, FR-4, NFR-8.

This document **is** the public surface (api-governance §1): anything listed here is governed
by the stability + deprecation rules; anything not listed is internal and may change freely.
The Phase 7 **consumer-compatibility test pins itself to this spec** — so this file is
executable contract, not just docs.

## Stability legend

- 🟢 **Stable** — covered by NFR-8; no breaking change without a major bump + deprecation cycle.
- 🟡 **Beta** — may change in a minor with notice (none at v1.0.0).
- ⚫ **Internal** — listed for clarity; NOT public; do not depend on.

## 1. Apex — `Logger` 🟢 (FR-1, FR-2)

```apex
global inherited sharing class Logger {
    global enum Severity { DEBUG, INFO, WARN, ERROR }

    // Core entry points. correlationId threads the round-trip (FR-10); null → auto-generated.
    global static void log(Severity level, String message, String correlationId);
    global static void error(String message, String correlationId);
    global static void error(Exception ex, String correlationId);
    global static void warn(String message, String correlationId);
    global static void info(String message, String correlationId);

    // Optional structured context (category e.g. 'integration/outbound').
    global static void log(Severity level, String message, String correlationId, String category);
}
```

Guarantees: a logged record is **durable across rollback** (NFR-7 — publishes `LogEvent__e`
immediately). Consumers never reference `LogEvent__e` or `Log__c` directly (those are ⚫ internal —
the storage mechanism can change without a major bump).

## 2. Apex — `EventPublisher` 🟢 (FR-3)

```apex
global inherited sharing class EventPublisher {
    // Publish a domain event the platform may act on (e.g. trigger an outbound notify).
    global static void publish(PlatformEvent__e event);          // single
    global static void publish(List<PlatformEvent__e> events);   // bulk
}
```

Guarantees: testable without real delivery; a publish failure is surfaced to the caller and
logged (never silently swallowed).

## 3. Apex — `CalloutService` 🟢 (FR-4, FR-5, FR-6)

```apex
global inherited sharing class CalloutService {
    global class Request {
        global String namedCredentialPath;  // e.g. 'FRS_Service/v1/notifications'
        global String method;               // 'POST' etc.
        global String body;                 // JSON
        global String idempotencyKey;       // stable per logical message (ADR-003)
        global String correlationId;
    }
    global class Result {
        global Boolean success;
        global Integer statusCode;
        global Boolean deadLettered;
    }

    // Enqueues an async, retrying, governed callout (never inline — NFR-4).
    global static void sendAsync(Request request);
}
```

Guarantees: no endpoint/secret in consumer code (routes via Named Credential — NFR-1);
bounded retry + backoff + dead-letter handled internally (ADR-003); bulk-safe to 200 (FR-11).
Consumers do **not** see the Queueable, Finalizer, or retry internals (⚫ internal).

## 4. Platform Events 🟢

| Event | Direction | Public fields | Notes |
|---|---|---|---|
| `LogEvent__e` | internal publish via `Logger` | ⚫ not for direct consumer use | hidden behind `Logger` |
| domain event(s) consumers publish via `EventPublisher` | consumer → platform | name + documented fields | the S1 trigger surface |

The **shape** of any domain event consumers publish/subscribe to is public and versioned here
when added; `LogEvent__e`'s shape is internal.

## 5. Inbound REST contract 🟢 (FR-8, FR-9)

`POST /services/apexrest/frs/v1/status` — full request/response, auth, idempotency, and
status codes are specified in `integration-contract.md` §4 (the wire contract). That document
is the authoritative public spec for the inbound surface; it is versioned by URL path (`/v1`)
under the same governance.

## 6. Outbound wire contract 🟢

`POST callout:FRS_Service/v1/notifications` — specified in `integration-contract.md` §3.

## 7. Versioning & deprecation

Governed by `api-governance.md`:
- Additive (new method/overload/optional field) → **minor**; internal change → **patch**;
  removed/renamed/changed signature → **major**, only after the deprecation cycle.
- Deprecated members are marked `@deprecated` here with: since-version, replacement, planned
  removal, and a `deprecation-log.md` entry.
- The **consumer-compatibility test** (Phase 7) asserts every 🟢 signature in this file still
  exists and is callable — a removed/changed signature fails CI (executable NFR-8).

## 8. v1.0.0 surface summary (frozen target)

`Logger` (6 methods + Severity enum), `EventPublisher` (2), `CalloutService` (1 method + 2
inner types), the inbound `/frs/v1/status` resource, the outbound `/v1/notifications` contract.
Everything else in the base package is ⚫ internal.
