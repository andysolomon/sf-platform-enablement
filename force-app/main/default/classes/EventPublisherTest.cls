/**
 * EventPublisher tests (FR-3). Exercises the generic wrapper via the existing LogEvent__e,
 * asserting delivery (subscriber writes Log__c) and bulk behavior.
 */
@isTest
private class EventPublisherTest {
    @isTest
    static void publish_single_delivers() {
        Test.startTest();
        Database.SaveResult sr = EventPublisher.publish(
            new LogEvent__e(Message__c = 'ep', Severity__c = 'INFO', Correlation_Id__c = 'EP-1')
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert(sr.isSuccess(), 'publish succeeded');
        System.assertEquals(1, [SELECT COUNT() FROM Log__c WHERE Correlation_Id__c = 'EP-1']);
    }

    @isTest
    static void publish_bulk_delivers() {
        List<SObject> evts = new List<SObject>();
        for (Integer i = 0; i < 5; i++) {
            evts.add(new LogEvent__e(Message__c = 'b' + i, Severity__c = 'INFO', Correlation_Id__c = 'EP-BULK'));
        }
        Test.startTest();
        List<Database.SaveResult> rs = EventPublisher.publish(evts);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(5, rs.size(), 'one result per event');
        for (Database.SaveResult sr : rs) {
            System.assert(sr.isSuccess(), 'each publish succeeded');
        }
        System.assertEquals(5, [SELECT COUNT() FROM Log__c WHERE Correlation_Id__c = 'EP-BULK']);
    }

    @isTest
    static void logFailures_logsEachError() {
        // EventBus.publish returns success for well-formed events, so simulate a failed
        // SaveResult (no public constructor) by deserializing JSON — the standard pattern —
        // to cover the failure-surfacing branch (FR-3).
        Database.SaveResult failed = (Database.SaveResult) JSON.deserialize(
            '{"success":false,"id":null,"errors":[{"message":"boom","statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION","fields":[]}]}',
            Database.SaveResult.class
        );

        Test.startTest();
        EventPublisher.logFailures(new List<Database.SaveResult>{ failed });
        Test.getEventBus().deliver();
        Test.stopTest();

        // Message__c is a LongTextArea (not filterable in SOQL), and this method's test data
        // is isolated, so counting ERROR logs is sufficient + correct here.
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Log__c WHERE Severity__c = 'ERROR'],
            'publish failure is logged (FR-3)'
        );
    }
}
