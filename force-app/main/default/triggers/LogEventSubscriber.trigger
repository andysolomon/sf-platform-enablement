/**
 * Subscriber for LogEvent__e — persists each immediate-publish log event to a queryable Log__c
 * (ADR-004). Trigger body stays thin; logic lives in LogEventHandler (DoD).
 */
trigger LogEventSubscriber on LogEvent__e (after insert) {
    LogEventHandler.handle(Trigger.new);
}
