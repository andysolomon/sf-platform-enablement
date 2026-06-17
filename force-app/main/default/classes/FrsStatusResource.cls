/**
 * FrsStatusResource — inbound Remote Call-In endpoint (FR-8), POST /services/apexrest/frs/v1/status.
 *
 * Walking-skeleton form: authenticates via the platform (Connected App + integration user,
 * ADR-005), logs the inbound hit with the echoed correlation id, and returns 200 {applied}.
 * Full idempotent apply (unique-key dedupe, FR-9/NFR-3) + record update land in Phase 6.
 */
@RestResource(urlMapping='/frs/v1/status')
global with sharing class FrsStatusResource {
    global class StatusResult {
        global String status;
        global String correlationId;
        global StatusResult(String status, String correlationId) {
            this.status = status;
            this.correlationId = correlationId;
        }
    }

    @HttpPost
    global static StatusResult handleStatus() {
        RestRequest req = RestContext.request;
        String correlationId = req != null && req.headers != null
            ? req.headers.get('X-Correlation-Id')
            : null;

        Logger.log(
            Logger.Severity.INFO,
            'inbound FRS status received',
            correlationId,
            'integration/inbound'
        );

        if (RestContext.response != null) {
            RestContext.response.statusCode = 200;
        }
        return new StatusResult('applied', correlationId);
    }
}
