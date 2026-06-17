/**
 * Logger + LogEventHandler tests (FR-1, FR-2, NFR-7).
 * Uses Test.getEventBus().deliver() to run the LogEvent__e subscriber deterministically.
 */
@isTest
private class LoggerTest {
    @isTest
    static void log_writesDurableRecord() {
        Test.startTest();
        Logger.error('boom', 'CORR-1');
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log__c> logs = [
            SELECT Message__c, Severity__c, Correlation_Id__c
            FROM Log__c
            WHERE Correlation_Id__c = 'CORR-1'
        ];
        System.assertEquals(1, logs.size(), 'exactly one log persisted (FR-1)');
        System.assertEquals('ERROR', logs[0].Severity__c, 'severity recorded');
        System.assertEquals('boom', logs[0].Message__c, 'message recorded');
    }

    @isTest
    static void survivesRollback() {
        // ADR-004/NFR-7: immediate-publish events are emitted regardless of the publishing
        // transaction's rollback. Verify the log persists after a rollback.
        Savepoint sp = Database.setSavepoint();
        Logger.warn('pre-rollback', 'CORR-2');
        Database.rollback(sp);

        Test.getEventBus().deliver();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Log__c WHERE Correlation_Id__c = 'CORR-2'],
            'log survives publisher rollback (NFR-7)'
        );
    }

    @isTest
    static void severityHelpersAndCategory() {
        Test.startTest();
        Logger.info('i', 'CORR-3');
        Logger.warn('w', 'CORR-3');
        Logger.log(Logger.Severity.DEBUG, 'd', 'CORR-3', 'integration/test');
        Logger.error(new CalloutException('x'), 'CORR-3');
        Logger.log(null, 'defaulted-level', 'CORR-3'); // null level -> INFO
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert(
            [SELECT COUNT() FROM Log__c WHERE Correlation_Id__c = 'CORR-3'] >= 5,
            'all severity helpers persisted'
        );
    }
}
