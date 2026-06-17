/**
 * CalloutService — governed outbound callouts (FR-4).
 *
 * Walking-skeleton form: a synchronous `ping()` to the FRS /health endpoint via the
 * FRS_Service Named Credential (no endpoint/secret in code — NFR-1). The full async,
 * retrying, dead-lettering `sendAsync(Request)` from public-api-spec.md §3 lands in Phase 6.
 */
global with sharing class CalloutService {
    @TestVisible
    private static final String HEALTH_PATH = 'callout:FRS_Service/v1/health';

    global static HttpResponse ping() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(HEALTH_PATH);
        req.setMethod('GET');
        req.setTimeout(10000);
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
