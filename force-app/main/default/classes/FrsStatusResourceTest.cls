/**
 * FrsStatusResource tests (FR-8 walking-skeleton) — inbound Remote Call-In returns applied
 * and logs with the echoed correlation id. Idempotency cases (FR-9) arrive in Phase 6.
 */
@isTest
private class FrsStatusResourceTest {
    private static void setupRequest(String correlationId, String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/frs/v1/status';
        req.httpMethod = 'POST';
        if (correlationId != null) {
            req.headers.put('X-Correlation-Id', correlationId);
        }
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @isTest
    static void post_returnsAppliedAndLogs() {
        setupRequest('CORR-9', '{"idempotencyKey":"K9","payload":{"salesforceRecordId":"a01xx0000000001"}}');
        Test.startTest();
        FrsStatusResource.StatusResult result = FrsStatusResource.handleStatus();
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals('applied', result.status, 'inbound applied');
        System.assertEquals('CORR-9', result.correlationId, 'correlation id echoed (FR-10)');
        System.assertEquals(200, RestContext.response.statusCode, 'HTTP 200');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Log__c WHERE Correlation_Id__c = 'CORR-9' AND Category__c = 'integration/inbound'],
            'inbound hit logged (NFR-6)'
        );
    }

    @isTest
    static void post_withoutCorrelationId_stillApplies() {
        setupRequest(null, '{"idempotencyKey":"K10","payload":{"salesforceRecordId":"a01xx0000000002"}}');
        Test.startTest();
        FrsStatusResource.StatusResult result = FrsStatusResource.handleStatus();
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals('applied', result.status);
        System.assertEquals(null, result.correlationId);
    }
}
