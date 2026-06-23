/**
 * FrsStatusResource tests (FR-8/FR-9) — inbound Remote Call-In: applies, dedupes a replay,
 * applies distinct keys independently, rejects incomplete/malformed payloads, echoes correlation.
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

    private static String bodyJson(String corr, String key, String recordId) {
        return JSON.serialize(new Map<String, Object>{
            'correlationId' => corr,
            'idempotencyKey' => key,
            'eventType' => 'status.updated',
            'occurredAt' => '2026-06-18T00:00:00Z',
            'payload' => new Map<String, Object>{
                'externalRef' => 'rcpt_1',
                'salesforceRecordId' => recordId,
                'status' => 'Acknowledged',
                'detail' => 'Processed by FRS'
            }
        });
    }

    @isTest
    static void firstMessage_isApplied() {
        setupRequest('CORR-1', bodyJson('CORR-1', 'K-1', 'a01gK00000XyZ12QAF'));
        Test.startTest();
        FrsStatusResource.StatusResult r = FrsStatusResource.handleStatus();
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals('applied', r.status);
        System.assertEquals('a01gK00000XyZ12QAF', r.recordId, 'record id echoed (contract §4.2)');
        System.assertEquals('CORR-1', r.correlationId, 'correlation echoed (FR-10)');
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM Integration_Message__c WHERE Idempotency_Key__c = 'K-1']);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Log__c WHERE Correlation_Id__c = 'CORR-1' AND Category__c = 'integration/inbound'],
            'inbound applied logged (NFR-6)'
        );
    }

    @isTest
    static void replaySameKey_isDuplicateNoOp() {
        setupRequest('CORR-2', bodyJson('CORR-2', 'K-DUP', 'a01gK00000XyZ12QAF'));
        FrsStatusResource.handleStatus(); // first apply

        setupRequest('CORR-2', bodyJson('CORR-2', 'K-DUP', 'a01gK00000XyZ12QAF'));
        Test.startTest();
        FrsStatusResource.StatusResult r = FrsStatusResource.handleStatus(); // replay
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals('duplicate', r.status, 'replay deduped (FR-9)');
        System.assertEquals(200, RestContext.response.statusCode, '200 duplicate, not an error');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Integration_Message__c WHERE Idempotency_Key__c = 'K-DUP'],
            'no second effect'
        );
    }

    @isTest
    static void distinctKeys_appliedIndependently() {
        setupRequest('C', bodyJson('C', 'K-A', 'a01gK00000XyZ12QAF'));
        FrsStatusResource.handleStatus();
        setupRequest('C', bodyJson('C', 'K-B', 'a01gK00000XyZ12QAF'));
        Test.startTest();
        FrsStatusResource.handleStatus();
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM Integration_Message__c], 'both keys applied');
    }

    @isTest
    static void missingRequiredField_is400() {
        // No payload.salesforceRecordId.
        String b = JSON.serialize(new Map<String, Object>{
            'correlationId' => 'C-400',
            'idempotencyKey' => 'K-400',
            'payload' => new Map<String, Object>{ 'status' => 'Acknowledged' }
        });
        setupRequest('C-400', b);
        Test.startTest();
        FrsStatusResource.StatusResult r = FrsStatusResource.handleStatus();
        Test.stopTest();
        System.assertEquals('error', r.status);
        System.assertEquals(400, RestContext.response.statusCode, 'validation error (contract §4.3)');
        System.assertEquals(0, [SELECT COUNT() FROM Integration_Message__c], 'no record on rejection');
    }

    @isTest
    static void malformedJson_is400() {
        setupRequest('C-MAL', '{ this is not json ');
        Test.startTest();
        FrsStatusResource.StatusResult r = FrsStatusResource.handleStatus();
        Test.stopTest();
        System.assertEquals('error', r.status);
        System.assertEquals(400, RestContext.response.statusCode);
    }

    @isTest
    static void emptyBody_is400() {
        setupRequest('C-EMPTY', '');
        Test.startTest();
        FrsStatusResource.StatusResult r = FrsStatusResource.handleStatus();
        Test.stopTest();
        System.assertEquals(400, RestContext.response.statusCode);
    }

    @isTest
    static void correlationFromHeader_whenBodyOmitsIt() {
        // Body has null correlationId -> falls back to the X-Correlation-Id header.
        String b = bodyJson(null, 'K-HDR', 'a01gK00000XyZ12QAF');
        setupRequest('CORR-HEADER', b);
        Test.startTest();
        FrsStatusResource.StatusResult r = FrsStatusResource.handleStatus();
        Test.stopTest();
        System.assertEquals('CORR-HEADER', r.correlationId, 'header correlation used as fallback');
    }
}
