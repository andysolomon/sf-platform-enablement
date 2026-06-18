/**
 * CalloutService — governed outbound callouts (FR-4, FR-5, FR-11).
 *
 * Public surface (public-api-spec.md §3): consumers describe *what* to send via a Request and
 * call sendAsync(); they never see the Queueable, Finalizer, retry, or dead-letter internals,
 * and never put an endpoint or secret in their code (routing is via the FRS_Service Named
 * Credential — NFR-1). Bulk is governor-safe: requests are chunked so no single transaction
 * exceeds the 100-callout limit (FR-11), and each chunk runs async so the caller's transaction
 * is never blocked (NFR-4).
 *
 * The retain/retry/dead-letter behavior is specified in ADR-003 and enforced by RetryPolicy +
 * CalloutQueueable.
 */
global with sharing class CalloutService {
    // Health-check probe retained from the walking skeleton (FR-4).
    @TestVisible
    private static final String HEALTH_PATH = 'callout:FRS_Service/v1/health';

    // One transaction may make at most 100 callouts; chunk bulk work below that ceiling (FR-11).
    @TestVisible
    private static final Integer CHUNK_SIZE = 100;

    private static final Integer CALLOUT_TIMEOUT_MS = 10000;

    /** What a consumer wants delivered to FRS. No endpoint/secret — just a credential path. */
    global class Request {
        global String namedCredentialPath; // e.g. 'FRS_Service/v1/notifications'
        global String method; // 'POST' etc.
        global String body; // JSON
        global String idempotencyKey; // stable per logical message — survives retries (ADR-003)
        global String correlationId; // threads the round-trip for tracing (FR-10)
    }

    /** The outcome of a single attempt (public-api-spec.md §3). */
    global class Result {
        global Boolean success;
        global Integer statusCode;
        global Boolean deadLettered;
    }

    /** Internal unit of work: a Request plus its 1-based attempt counter (not consumer-visible). */
    public class WorkItem {
        public Request request;
        public Integer attempt;
        public WorkItem(Request request, Integer attempt) {
            this.request = request;
            this.attempt = attempt;
        }
    }

    // --- Public API ---------------------------------------------------------------------------

    /** Enqueue an async, retrying, governed callout for a single message (NFR-4). */
    global static void sendAsync(Request request) {
        sendAsync(new List<Request>{ request });
    }

    /** Bulk-safe entry: fan out into governor-safe chunks, each its own async job (FR-11). */
    global static void sendAsync(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        for (List<Request> batch : chunk(requests, CHUNK_SIZE)) {
            List<WorkItem> items = new List<WorkItem>();
            for (Request r : batch) {
                items.add(new WorkItem(r, 1));
            }
            System.enqueueJob(new CalloutQueueable(items));
        }
    }

    // --- Internals used by CalloutQueueable / CalloutFinalizer --------------------------------

    /**
     * Build the HTTP request for a work item — routed entirely through the Named Credential.
     * `public` (not `global`): CalloutQueueable needs it at runtime, but it is not consumer API.
     */
    public static HttpRequest buildHttpRequest(Request r) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + r.namedCredentialPath);
        req.setMethod(r.method == null ? 'POST' : r.method);
        req.setTimeout(CALLOUT_TIMEOUT_MS);
        if (String.isNotBlank(r.idempotencyKey)) {
            req.setHeader('Idempotency-Key', r.idempotencyKey); // FRS dedupes our retries (ADR-003)
        }
        if (String.isNotBlank(r.correlationId)) {
            req.setHeader('X-Correlation-Id', r.correlationId);
        }
        if (r.body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(r.body);
        }
        return req;
    }

    /** Persist an exhausted/terminal call for operator visibility + replay (FR-7). */
    public static void deadLetter(WorkItem wi, Integer statusCode, String errorBody) {
        Integration_DeadLetter__c dl = new Integration_DeadLetter__c(
            Correlation_Id__c = wi.request.correlationId,
            Idempotency_Key__c = wi.request.idempotencyKey,
            Named_Credential_Path__c = wi.request.namedCredentialPath,
            Http_Method__c = wi.request.method,
            Payload__c = wi.request.body,
            Last_Error__c = errorBody,
            Last_Status_Code__c = statusCode,
            Attempt_Count__c = wi.attempt,
            Status__c = 'NEW'
        );
        insert dl;
        Result res = new Result();
        res.success = false;
        res.statusCode = statusCode;
        res.deadLettered = true;
        Logger.error(
            'CalloutService: dead-lettered after ' +
                wi.attempt +
                ' attempt(s) — status=' +
                res.statusCode +
                ' deadLettered=' +
                res.deadLettered +
                ' [' +
                wi.request.correlationId +
                ']',
            wi.request.correlationId
        );
    }

    /** Split a list into governor-safe chunks (FR-11). */
    public static List<List<Request>> chunk(List<Request> items, Integer size) {
        List<List<Request>> chunks = new List<List<Request>>();
        List<Request> current = new List<Request>();
        for (Request r : items) {
            current.add(r);
            if (current.size() == size) {
                chunks.add(current);
                current = new List<Request>();
            }
        }
        if (!current.isEmpty()) {
            chunks.add(current);
        }
        return chunks;
    }

    // --- Walking-skeleton probe (FR-4) --------------------------------------------------------

    global static HttpResponse ping() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(HEALTH_PATH);
        req.setMethod('GET');
        req.setTimeout(CALLOUT_TIMEOUT_MS);
        HttpResponse res = new Http().send(req);
        Logger.log(
            Logger.Severity.INFO,
            'FRS /health -> ' + res.getStatusCode(),
            null,
            'integration/outbound'
        );
        return res;
    }
}
