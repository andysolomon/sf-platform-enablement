/**
 * CalloutQueueableTest — the async outbound engine (FR-5/6/7/11).
 *
 * Note on testability (a real Salesforce constraint, not a shortcut): a Queueable cannot chain
 * another Queueable in test context, so the *re-enqueue* of a retry can't be exercised live.
 * The retry DECISION lives in RetryPolicy (unit-tested there) and is asserted here via the
 * @TestVisible `lastEnqueuedRetries` seam — what *would* be re-enqueued — while the terminal and
 * exhaustion paths (which don't chain) are exercised end-to-end with HttpCalloutMock.
 */
@isTest
private class CalloutQueueableTest {
    // ---- Mocks -------------------------------------------------------------------------------
    private class CodeMock implements HttpCalloutMock {
        private Integer code;
        CodeMock(Integer code) {
            this.code = code;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody(code >= 200 && code < 300 ? '{"ok":true}' : '{"error":"x"}');
            return res;
        }
    }

    private class TimeoutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Read timed out');
        }
    }

    private class FinalizerTestException extends Exception {
    }

    // ---- Helpers -----------------------------------------------------------------------------
    private static CalloutService.Request req(String corr, String idem) {
        CalloutService.Request r = new CalloutService.Request();
        r.namedCredentialPath = 'FRS_Service/v1/notifications';
        r.method = 'POST';
        r.body = '{"todoId":"1"}';
        r.correlationId = corr;
        r.idempotencyKey = idem;
        return r;
    }

    // ---- buildHttpRequest --------------------------------------------------------------------
    @isTest
    static void buildHttpRequest_routesThroughNamedCredentialWithHeaders() {
        HttpRequest h = CalloutService.buildHttpRequest(req('C1', 'I1'));
        System.assertEquals('callout:FRS_Service/v1/notifications', h.getEndpoint(), 'NFR-1: no URL');
        System.assertEquals('POST', h.getMethod());
        System.assertEquals('I1', h.getHeader('Idempotency-Key'));
        System.assertEquals('C1', h.getHeader('X-Correlation-Id'));
        System.assertEquals('application/json', h.getHeader('Content-Type'));

        // Null optional fields take the defaults / are simply omitted (no NPE).
        CalloutService.Request bare = new CalloutService.Request();
        bare.namedCredentialPath = 'FRS_Service/v1/health';
        HttpRequest h2 = CalloutService.buildHttpRequest(bare);
        System.assertEquals('POST', h2.getMethod(), 'defaults to POST when method null');
    }

    // ---- chunking (FR-11) --------------------------------------------------------------------
    @isTest
    static void chunk_splitsAtGovernorSafeBoundary() {
        List<CalloutService.Request> two_hundred = new List<CalloutService.Request>();
        for (Integer i = 0; i < 200; i++) {
            two_hundred.add(req('C' + i, 'I' + i));
        }
        List<List<CalloutService.Request>> chunks = CalloutService.chunk(two_hundred, 100);
        System.assertEquals(2, chunks.size(), '200 splits into two 100-callout-safe chunks');
        System.assertEquals(100, chunks[0].size());
        System.assertEquals(100, chunks[1].size());
    }

    // ---- success path (+ finalizer execute coverage) -----------------------------------------
    @isTest
    static void sendAsync_success_noRetryNoDeadLetter() {
        Test.setMock(HttpCalloutMock.class, new CodeMock(200));
        Test.startTest();
        CalloutService.sendAsync(req('C-OK', 'I-OK'));
        Test.stopTest(); // queueable + attached finalizer (SUCCESS result) run here

        System.assertEquals(0, [SELECT COUNT() FROM Integration_DeadLetter__c], 'no dead letter');
        System.assert(
            CalloutQueueable.lastEnqueuedRetries == null ||
            CalloutQueueable.lastEnqueuedRetries.isEmpty(),
            'success path schedules no retry'
        );
    }

    // ---- retry decision (transient, attempts remaining) --------------------------------------
    @isTest
    static void transientFailure_capturesNextRetry() {
        RetryPolicy.maxAttemptsOverride = 3;
        Test.setMock(HttpCalloutMock.class, new CodeMock(503));
        Test.startTest();
        CalloutService.sendAsync(req('C-503', 'I-503')); // attempt 1 of 3
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Integration_DeadLetter__c], 'not dead-lettered yet');
        System.assertEquals(1, CalloutQueueable.lastEnqueuedRetries.size(), 'one item queued for retry');
        System.assertEquals(2, CalloutQueueable.lastEnqueuedRetries[0].attempt, 'attempt incremented');
    }

    // ---- terminal 4xx (immediate dead-letter, no retry) --------------------------------------
    @isTest
    static void terminalFailure_deadLettersImmediately() {
        Test.setMock(HttpCalloutMock.class, new CodeMock(400));
        Test.startTest();
        CalloutService.sendAsync(req('C-400', 'I-400'));
        Test.stopTest();

        List<Integration_DeadLetter__c> dls = [
            SELECT Last_Status_Code__c, Attempt_Count__c, Status__c, Correlation_Id__c
            FROM Integration_DeadLetter__c
        ];
        System.assertEquals(1, dls.size(), 'terminal 4xx dead-lettered');
        System.assertEquals(400, dls[0].Last_Status_Code__c);
        System.assertEquals(1, dls[0].Attempt_Count__c, 'no retries on a terminal failure');
        System.assertEquals('NEW', dls[0].Status__c);
    }

    // ---- exhaustion (transient, no attempts left) --------------------------------------------
    @isTest
    static void exhaustedRetries_deadLetters() {
        RetryPolicy.maxAttemptsOverride = 2;
        Test.setMock(HttpCalloutMock.class, new CodeMock(503));
        // Inject the final attempt directly so the verdict is exhaustion, not another retry.
        CalloutService.WorkItem last = new CalloutService.WorkItem(req('C-EX', 'I-EX'), 2);
        Test.startTest();
        System.enqueueJob(new CalloutQueueable(new List<CalloutService.WorkItem>{ last }));
        Test.stopTest();

        List<Integration_DeadLetter__c> dls = [
            SELECT Last_Status_Code__c, Attempt_Count__c FROM Integration_DeadLetter__c
        ];
        System.assertEquals(1, dls.size(), 'exhausted retries dead-lettered (FR-7)');
        System.assertEquals(503, dls[0].Last_Status_Code__c);
        System.assertEquals(2, dls[0].Attempt_Count__c, 'records the exhausting attempt');
    }

    // ---- timeout/CalloutException path -------------------------------------------------------
    @isTest
    static void timeout_isTransient_thenDeadLettersOnExhaustion() {
        RetryPolicy.maxAttemptsOverride = 1; // single attempt → timeout exhausts immediately
        Test.setMock(HttpCalloutMock.class, new TimeoutMock());
        Test.startTest();
        CalloutService.sendAsync(req('C-TO', 'I-TO'));
        Test.stopTest();

        List<Integration_DeadLetter__c> dls = [
            SELECT Last_Status_Code__c, Last_Error__c FROM Integration_DeadLetter__c
        ];
        System.assertEquals(1, dls.size(), 'timeout exhausted -> dead-letter');
        System.assertEquals(0, dls[0].Last_Status_Code__c, 'timeout recorded as status 0');
    }

    // ---- bulk safety (FR-11) -----------------------------------------------------------------
    @isTest
    static void bulk_200_staysGovernorSafe() {
        List<CalloutService.Request> requests = new List<CalloutService.Request>();
        for (Integer i = 0; i < 200; i++) {
            requests.add(req('C' + i, 'I' + i));
        }
        Test.setMock(HttpCalloutMock.class, new CodeMock(200));
        Test.startTest();
        CalloutService.sendAsync(requests); // 2 chunks × 100 callouts, no limit breach
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Integration_DeadLetter__c], 'all delivered');
    }

    @isTest
    static void sendAsync_emptyAndNull_areNoOps() {
        Test.startTest();
        CalloutService.sendAsync((List<CalloutService.Request>) null);
        CalloutService.sendAsync(new List<CalloutService.Request>());
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Integration_DeadLetter__c], 'no work, no records');
    }

    // ---- finalizer safety net ----------------------------------------------------------------
    @isTest
    static void finalizer_unhandledFailure_deadLettersCarriedWork() {
        CalloutService.WorkItem wi = new CalloutService.WorkItem(req('C-FIN', 'I-FIN'), 2);
        CalloutFinalizer fin = new CalloutFinalizer(new List<CalloutService.WorkItem>{ wi });

        Test.startTest();
        fin.handle(true, new FinalizerTestException('job blew up'));
        Test.stopTest();

        List<Integration_DeadLetter__c> dls = [SELECT Last_Error__c FROM Integration_DeadLetter__c];
        System.assertEquals(1, dls.size(), 'unhandled job failure is dead-lettered (safety net)');
        System.assert(dls[0].Last_Error__c.startsWith('UNHANDLED:'), 'flagged as unhandled');
    }

    @isTest
    static void finalizer_cleanRun_isNoOp() {
        CalloutService.WorkItem wi = new CalloutService.WorkItem(req('C-OK2', 'I-OK2'), 1);
        CalloutFinalizer fin = new CalloutFinalizer(new List<CalloutService.WorkItem>{ wi });
        Test.startTest();
        fin.handle(false, null);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Integration_DeadLetter__c], 'no failure, no record');
    }
}
