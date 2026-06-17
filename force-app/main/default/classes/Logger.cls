/**
 * Logger — the platform's reusable logging API (FR-1, FR-2).
 *
 * Publishes a LogEvent__e Platform Event with Publish-Immediately behavior so a log written
 * during a transaction survives that transaction rolling back (ADR-004 / NFR-7). Consumers
 * call this API and never touch LogEvent__e / Log__c directly (api-governance public-surface rule).
 *
 * Walking-skeleton subset of public-api-spec.md §1; remaining overloads land in Phase 6.
 */
global inherited sharing class Logger {
    global enum Severity {
        DEBUG,
        INFO,
        WARN,
        ERROR
    }

    global static void log(Severity level, String message, String correlationId) {
        log(level, message, correlationId, null);
    }

    global static void log(Severity level, String message, String correlationId, String category) {
        EventBus.publish(
            new LogEvent__e(
                Severity__c = (level == null ? Severity.INFO : level).name(),
                Message__c = message,
                Correlation_Id__c = correlationId,
                Category__c = category
            )
        );
    }

    global static void error(String message, String correlationId) {
        log(Severity.ERROR, message, correlationId);
    }

    global static void error(Exception ex, String correlationId) {
        String msg = (ex == null)
            ? 'null exception'
            : ex.getMessage() + '\n' + ex.getStackTraceString();
        log(Severity.ERROR, msg, correlationId);
    }

    global static void warn(String message, String correlationId) {
        log(Severity.WARN, message, correlationId);
    }

    global static void info(String message, String correlationId) {
        log(Severity.INFO, message, correlationId);
    }
}
