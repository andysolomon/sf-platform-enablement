/**
 * RetryPolicyTest — exhaustive coverage of the pure decision core (FR-6/FR-7).
 * No async, no callouts: this is exactly the logic we *can* nail down deterministically.
 */
@isTest
private class RetryPolicyTest {
    @isTest
    static void isRetryable_classifiesStatusCodes() {
        System.assertEquals(true, RetryPolicy.isRetryable(0), 'timeout sentinel is retryable');
        System.assertEquals(true, RetryPolicy.isRetryable(429), '429 throttling is retryable');
        System.assertEquals(true, RetryPolicy.isRetryable(500), '5xx is retryable');
        System.assertEquals(true, RetryPolicy.isRetryable(503), '5xx is retryable');
        System.assertEquals(false, RetryPolicy.isRetryable(200), '2xx is not a retry');
        System.assertEquals(false, RetryPolicy.isRetryable(400), '400 is terminal');
        System.assertEquals(false, RetryPolicy.isRetryable(401), '401 is terminal');
        System.assertEquals(false, RetryPolicy.isRetryable(403), '403 is terminal');
        System.assertEquals(false, RetryPolicy.isRetryable(null), 'null is not retryable');
    }

    @isTest
    static void backoffMinutes_growsExponentiallyAndCaps() {
        System.assertEquals(0, RetryPolicy.backoffMinutes(1), 'first attempt: no wait');
        System.assertEquals(0, RetryPolicy.backoffMinutes(0), 'guards non-positive');
        System.assertEquals(0, RetryPolicy.backoffMinutes(null), 'guards null');
        System.assertEquals(1, RetryPolicy.backoffMinutes(2), 'attempt 2: 1 min');
        System.assertEquals(2, RetryPolicy.backoffMinutes(3), 'attempt 3: 2 min');
        System.assertEquals(4, RetryPolicy.backoffMinutes(4), 'attempt 4: 4 min');
        System.assertEquals(10, RetryPolicy.backoffMinutes(20), 'capped at platform 10-min ceiling');
    }

    @isTest
    static void maxAttempts_readsConfigWithFallback() {
        // Override seam exercises the configured ceiling deterministically.
        RetryPolicy.maxAttemptsOverride = 5;
        System.assertEquals(5, RetryPolicy.maxAttempts(), 'honors configured override');

        // Clearing the override falls through to CMDT (Default record) or the constant fallback;
        // either way it must be a sane positive bound.
        RetryPolicy.maxAttemptsOverride = null;
        System.assert(RetryPolicy.maxAttempts() >= 1, 'config/fallback yields a positive ceiling');
    }

    @isTest
    static void decide_coversFullMatrix() {
        RetryPolicy.maxAttemptsOverride = 3;

        System.assertEquals(
            RetryPolicy.Decision.SUCCESS,
            RetryPolicy.decide(200, 1),
            '2xx -> success'
        );
        System.assertEquals(
            RetryPolicy.Decision.DEAD_LETTER,
            RetryPolicy.decide(400, 1),
            'terminal 4xx -> dead-letter immediately (no retry)'
        );
        System.assertEquals(
            RetryPolicy.Decision.RETRY,
            RetryPolicy.decide(503, 1),
            'transient 5xx with attempts left -> retry'
        );
        System.assertEquals(
            RetryPolicy.Decision.RETRY,
            RetryPolicy.decide(0, 2),
            'timeout with attempts left -> retry'
        );
        System.assertEquals(
            RetryPolicy.Decision.DEAD_LETTER,
            RetryPolicy.decide(503, 3),
            'transient but attempts exhausted -> dead-letter (FR-7)'
        );
    }
}
