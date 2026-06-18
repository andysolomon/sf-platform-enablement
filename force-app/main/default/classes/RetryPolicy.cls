/**
 * RetryPolicy — the pure decision core for outbound resilience (FR-6, FR-7; ADR-003).
 *
 * Deliberately side-effect-free so the retry/dead-letter rules are unit-testable in isolation,
 * separate from the async callout machinery that's hard to exercise in a test (no Queueable
 * chaining in test context). CalloutQueueable consults this to choose SUCCESS / RETRY /
 * DEAD_LETTER after each attempt.
 *
 * Limits are config-not-code: max attempts comes from Integration_Setting__mdt (Default), with
 * a safe constant fallback — tuning resilience is a metadata change, never a public-API change.
 */
global with sharing class RetryPolicy {
    @TestVisible
    private static final Integer DEFAULT_MAX_ATTEMPTS = 3;

    // enqueueJob delay is capped at 10 minutes by the platform (ADR-003); never exceed it.
    @TestVisible
    private static final Integer MAX_DELAY_MINUTES = 10;

    // Test seam: lets a test force the configured ceiling without depending on deployed CMDT.
    @TestVisible
    private static Integer maxAttemptsOverride;

    global enum Decision {
        SUCCESS,
        RETRY,
        DEAD_LETTER
    }

    /**
     * Transient/retryable per the contract status table (ADR-003 §3.3):
     * timeout (sentinel 0), 429 throttling, and any 5xx. Auth/bad-request 4xx are terminal.
     */
    global static Boolean isRetryable(Integer statusCode) {
        if (statusCode == null) {
            return false;
        }
        if (statusCode == 0) {
            return true; // CalloutException / timeout sentinel
        }
        if (statusCode == 429) {
            return true; // throttled — honor Retry-After at the call site
        }
        return statusCode >= 500 && statusCode <= 599;
    }

    /** Bounded attempt ceiling — Integration_Setting__mdt.Default, else the constant fallback. */
    global static Integer maxAttempts() {
        if (maxAttemptsOverride != null) {
            return maxAttemptsOverride;
        }
        List<Integration_Setting__mdt> cfg = [
            SELECT Max_Attempts__c
            FROM Integration_Setting__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (!cfg.isEmpty() && cfg[0].Max_Attempts__c != null) {
            return (Integer) cfg[0].Max_Attempts__c;
        }
        return DEFAULT_MAX_ATTEMPTS;
    }

    /**
     * Exponential backoff (minutes) for the UPCOMING attempt (1-based): the first attempt has
     * no wait; retries grow 1 → 2 → 4 … capped at the platform's 10-minute enqueue ceiling.
     */
    global static Integer backoffMinutes(Integer upcomingAttempt) {
        if (upcomingAttempt == null || upcomingAttempt <= 1) {
            return 0;
        }
        Integer minutes = (Integer) Math.pow(2, upcomingAttempt - 2);
        return Math.min(minutes, MAX_DELAY_MINUTES);
    }

    /**
     * The core verdict after an attempt that just completed.
     * @param statusCode      HTTP status (0 = timeout/CalloutException; null = unknown failure)
     * @param completedAttempt the 1-based attempt number that just ran
     */
    global static Decision decide(Integer statusCode, Integer completedAttempt) {
        if (statusCode != null && statusCode >= 200 && statusCode < 300) {
            return Decision.SUCCESS;
        }
        if (isRetryable(statusCode) && completedAttempt < maxAttempts()) {
            return Decision.RETRY;
        }
        return Decision.DEAD_LETTER;
    }
}
