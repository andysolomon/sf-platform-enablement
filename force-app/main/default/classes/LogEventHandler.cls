/**
 * Subscriber-side persistence for LogEvent__e (ADR-004): runs in the LogEvent__e subscriber trigger's
 * own transaction (Automated Process user), so its DML is independent of the publisher's
 * transaction — which is what lets logs survive a publisher rollback.
 *
 * @SuppressWarnings PMD.ApexCRUDViolation — this is the trusted platform log-persistence path
 * writing Log__c on behalf of the framework (system context, not user-initiated). The
 * suppression is the greppable quarantine marker (todo-app convention).
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class LogEventHandler {
    public static void handle(List<LogEvent__e> events) {
        List<Log__c> rows = new List<Log__c>();
        for (LogEvent__e e : events) {
            rows.add(
                new Log__c(
                    Message__c = e.Message__c,
                    Severity__c = e.Severity__c,
                    Correlation_Id__c = e.Correlation_Id__c,
                    Category__c = e.Category__c
                )
            );
        }
        if (!rows.isEmpty()) {
            insert rows;
        }
    }
}
