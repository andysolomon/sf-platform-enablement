/**
 * EventPublisher — generic, testable wrapper over EventBus.publish (FR-3).
 *
 * Consumers publish domain/platform events through this instead of calling EventBus directly,
 * so publish failures are consistently surfaced (returned to the caller) AND logged (Logger),
 * never silently swallowed. Thin by design; the value is the uniform failure handling + a
 * single mockable seam for consumer tests.
 */
global with sharing class EventPublisher {
    global static Database.SaveResult publish(SObject event) {
        return publish(new List<SObject>{ event })[0];
    }

    global static List<Database.SaveResult> publish(List<SObject> events) {
        List<Database.SaveResult> results = EventBus.publish(events);
        logFailures(results);
        return results;
    }

    // Extracted so the failure-surfacing branch is unit-testable: EventBus.publish returns a
    // success SaveResult for well-formed events, so failures are simulated via a deserialized
    // SaveResult in the test (see EventPublisherTest).
    @TestVisible
    private static void logFailures(List<Database.SaveResult> results) {
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    Logger.error(
                        'EventPublisher: publish failed — ' + err.getStatusCode() + ': ' + err.getMessage(),
                        null
                    );
                }
            }
        }
    }
}
