/**
 * FrsStatusResource — inbound Remote Call-In endpoint (FR-8/FR-9), POST
 * /services/apexrest/frs/v1/status. Authenticated via the platform (Connected App + least-priv
 * integration user, ADR-005) and authorized by the FRS_Integration permission set.
 *
 * Flow (contract §4): parse → validate (400 on missing required fields / malformed JSON) →
 * dedupe via IdempotencyGuard (unique-key reserve) → respond `applied` / `duplicate`. The
 * correlation id is echoed across the round-trip (FR-10) and every step is logged (NFR-6).
 *
 * Scope note: at the platform layer the durable Integration_Message__c IS the applied effect.
 * Mutating a *consumer's* business record (e.g. a todo-app Todo) is the consumer's concern and
 * is wired when todo-app adopts the package (6-C / 6.6).
 */
@RestResource(urlMapping='/frs/v1/status')
global with sharing class FrsStatusResource {
    global class StatusResult {
        global String status; // applied | duplicate | error
        global String recordId;
        global String correlationId;
        global StatusResult(String status, String recordId, String correlationId) {
            this.status = status;
            this.recordId = recordId;
            this.correlationId = correlationId;
        }
    }

    // Internal parse wrappers mirroring contract §4.1.
    public class Payload {
        public String externalRef;
        public String salesforceRecordId;
        public String status;
        public String detail;
    }
    public class StatusRequest {
        public String correlationId;
        public String idempotencyKey;
        public String eventType;
        public String occurredAt;
        public Payload payload;
    }

    @HttpPost
    global static StatusResult handleStatus() {
        RestRequest req = RestContext.request;
        String headerCorr = (req != null && req.headers != null)
            ? req.headers.get('X-Correlation-Id')
            : null;

        StatusRequest body;
        try {
            String raw = (req != null && req.requestBody != null) ? req.requestBody.toString() : null;
            if (String.isBlank(raw)) {
                return reject(400, 'empty request body', headerCorr, null);
            }
            body = (StatusRequest) JSON.deserialize(raw, StatusRequest.class);
        } catch (Exception e) {
            return reject(400, 'malformed JSON', headerCorr, null);
        }

        // Body correlation id wins (it's the authoritative echo); fall back to the header.
        String correlationId = (body != null && body.correlationId != null)
            ? body.correlationId
            : headerCorr;
        String recordId = (body != null && body.payload != null) ? body.payload.salesforceRecordId : null;

        // FR-8: reject incomplete messages before any side effect.
        if (body == null || String.isBlank(body.idempotencyKey) || String.isBlank(recordId)) {
            return reject(
                400,
                'missing required field(s): idempotencyKey and payload.salesforceRecordId',
                correlationId,
                recordId
            );
        }

        IdempotencyGuard.Message m = new IdempotencyGuard.Message();
        m.idempotencyKey = body.idempotencyKey;
        m.correlationId = correlationId;
        m.eventType = body.eventType;
        m.salesforceRecordId = recordId;
        m.status = (body.payload != null) ? body.payload.status : null;

        IdempotencyGuard.Outcome outcome = IdempotencyGuard.reserve(m);

        if (outcome == IdempotencyGuard.Outcome.DUPLICATE) {
            // FR-9 / NFR-3: same key already applied — no second effect, logged as deduplicated.
            Logger.log(
                Logger.Severity.INFO,
                'inbound FRS status DEDUPLICATED (key=' + body.idempotencyKey + ')',
                correlationId,
                'integration/inbound'
            );
            setStatus(200);
            return new StatusResult('duplicate', recordId, correlationId);
        }

        Logger.log(
            Logger.Severity.INFO,
            'inbound FRS status applied (key=' + body.idempotencyKey + ')',
            correlationId,
            'integration/inbound'
        );
        setStatus(200);
        return new StatusResult('applied', recordId, correlationId);
    }

    private static StatusResult reject(Integer code, String reason, String correlationId, String recordId) {
        Logger.log(
            Logger.Severity.WARN,
            'inbound FRS status rejected (' + code + '): ' + reason,
            correlationId,
            'integration/inbound'
        );
        setStatus(code);
        return new StatusResult('error', recordId, correlationId);
    }

    private static void setStatus(Integer code) {
        if (RestContext.response != null) {
            RestContext.response.statusCode = code;
        }
    }
}
