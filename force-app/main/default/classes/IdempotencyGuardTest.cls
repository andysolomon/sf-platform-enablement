/**
 * IdempotencyGuardTest (FR-9 / NFR-3) — first apply reserves; a repeat of the same key is a
 * DUPLICATE no-op; distinct keys are independent.
 */
@isTest
private class IdempotencyGuardTest {
    private static IdempotencyGuard.Message msg(String key) {
        IdempotencyGuard.Message m = new IdempotencyGuard.Message();
        m.idempotencyKey = key;
        m.correlationId = 'CORR-' + key;
        m.eventType = 'status.updated';
        m.salesforceRecordId = 'a01gK00000XyZ12QAF';
        m.status = 'Acknowledged';
        return m;
    }

    @isTest
    static void firstApply_reservesKey() {
        Test.startTest();
        IdempotencyGuard.Outcome o = IdempotencyGuard.reserve(msg('K-1'));
        Test.stopTest();
        System.assertEquals(IdempotencyGuard.Outcome.APPLIED, o, 'first time is APPLIED');
        System.assertEquals(1, [SELECT COUNT() FROM Integration_Message__c WHERE Idempotency_Key__c = 'K-1']);
    }

    @isTest
    static void duplicateKey_isNoOp() {
        IdempotencyGuard.reserve(msg('K-DUP'));
        Test.startTest();
        IdempotencyGuard.Outcome o = IdempotencyGuard.reserve(msg('K-DUP'));
        Test.stopTest();
        System.assertEquals(IdempotencyGuard.Outcome.DUPLICATE, o, 'same key dedupes (FR-9)');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Integration_Message__c WHERE Idempotency_Key__c = 'K-DUP'],
            'no second record (no double effect)'
        );
    }

    @isTest
    static void distinctKeys_appliedIndependently() {
        Test.startTest();
        IdempotencyGuard.reserve(msg('K-A'));
        IdempotencyGuard.reserve(msg('K-B'));
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM Integration_Message__c], 'two keys, two records');
    }

    @isTest
    static void isDuplicateKey_ignoresUnrelatedDml() {
        // A non-duplicate DML failure must propagate, not be swallowed as a dedupe.
        Boolean threw = false;
        try {
            // Required field (Idempotency_Key__c) missing -> REQUIRED_FIELD_MISSING, not DUPLICATE.
            IdempotencyGuard.reserve(msg(null));
        } catch (DmlException e) {
            threw = true;
            System.assertEquals(false, IdempotencyGuard.isDuplicateKey(e), 'not a duplicate-key error');
        }
        System.assert(threw, 'a non-duplicate DML error propagates');
    }
}
