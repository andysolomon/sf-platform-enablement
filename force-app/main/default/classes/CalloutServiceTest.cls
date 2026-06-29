/**
 * CalloutService tests (FR-4) — HttpCalloutMock, no real callout (per DoD).
 */
@isTest
private class CalloutServiceTest {
    private class HealthMock implements HttpCalloutMock {
        private Integer code;
        HealthMock(Integer code) {
            this.code = code;
        }
        public HttpResponse respond(HttpRequest req) {
            System.assertEquals(
                CalloutService.HEALTH_PATH,
                req.getEndpoint(),
                'routes through the FRS_Service Named Credential (no hard-coded URL)'
            );
            System.assertEquals('GET', req.getMethod());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody('{"status":"ok","service":"frs-mock-service"}');
            return res;
        }
    }

    @isTest
    static void ping_success() {
        Test.setMock(HttpCalloutMock.class, new HealthMock(200));
        Test.startTest();
        HttpResponse res = CalloutService.ping();
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode(), '200 from /health');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Log__c WHERE Category__c = 'integration/outbound'],
            'outbound attempt logged (NFR-6)'
        );
    }

    @isTest
    static void ping_serverError() {
        Test.setMock(HttpCalloutMock.class, new HealthMock(500));
        Test.startTest();
        HttpResponse res = CalloutService.ping();
        Test.stopTest();
        System.assertEquals(500, res.getStatusCode(), 'surfaces 5xx (retry handling = Phase 6)');
    }
}
