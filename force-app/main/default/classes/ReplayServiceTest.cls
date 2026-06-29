/**
 * ReplayServiceTest (FR-7) — replays a dead letter and confirms it is re-sent with the same
 * idempotency key and marked REPLAYED.
 */
@isTest
private class ReplayServiceTest {
    private class StatusMock implements HttpCalloutMock {
        private Integer code;
        StatusMock(Integer code) {
            this.code = code;
        }
        public HttpResponse respond(HttpRequest req) {
            // Replay must carry the original idempotency key (ADR-003).
            System.assertEquals('IDEM-DL-1', req.getHeader('Idempotency-Key'), 'same key on replay');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody('{"status":"applied"}');
            return res;
        }
    }

    @isTest
    static void replay_resendsAndMarksReplayed() {
        Integration_DeadLetter__c dl = new Integration_DeadLetter__c(
            Correlation_Id__c = 'CORR-DL-1',
            Idempotency_Key__c = 'IDEM-DL-1',
            Named_Credential_Path__c = 'FRS_Service/v1/notifications',
            Http_Method__c = 'POST',
            Payload__c = '{"todoId":"42"}',
            Last_Status_Code__c = 503,
            Attempt_Count__c = 3,
            Status__c = 'NEW'
        );
        insert dl;

        Test.setMock(HttpCalloutMock.class, new StatusMock(200));
        Test.startTest();
        ReplayService.replay(dl.Id);
        Test.stopTest(); // the re-enqueued callout runs here

        Integration_DeadLetter__c after = [
            SELECT Status__c
            FROM Integration_DeadLetter__c
            WHERE Id = :dl.Id
        ];
        System.assertEquals('REPLAYED', after.Status__c, 'dead letter marked REPLAYED');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Integration_DeadLetter__c WHERE Status__c = 'NEW'],
            'successful replay creates no new dead letter'
        );
    }
}
