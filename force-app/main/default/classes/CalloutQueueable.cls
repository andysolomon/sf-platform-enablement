/**
 * CalloutQueueable — the async engine behind CalloutService.sendAsync (FR-5/6/7).
 *
 * Runs one chunk of work items (≤100, so we stay under the per-transaction callout limit),
 * makes each callout, and consults RetryPolicy for the verdict:
 *   SUCCESS     → log and move on
 *   RETRY       → carry the item forward (attempt+1) and re-enqueue with backoff
 *   DEAD_LETTER → persist for operator visibility + replay (FR-7)
 *
 * A Finalizer is attached as a safety net: if the job dies with an unhandled exception (e.g. a
 * governor limit), the work is still captured rather than silently lost (ADR-003).
 *
 * Internal — never part of the consumer-facing API surface (api-governance ⚫).
 */
// `public` (not `global`): internal infrastructure — no consumer instantiates this, and a global
// signature can't carry the internal WorkItem type (api-governance ⚫).
public with sharing class CalloutQueueable implements Queueable, Database.AllowsCallouts {
    private List<CalloutService.WorkItem> items;

    // Test seam: chained re-enqueue is disallowed in test context, so tests assert on what
    // *would* be re-enqueued instead of on the chain itself.
    @TestVisible
    private static List<CalloutService.WorkItem> lastEnqueuedRetries;

    public CalloutQueueable(List<CalloutService.WorkItem> items) {
        this.items = items;
    }

    public void execute(QueueableContext ctx) {
        System.attachFinalizer(new CalloutFinalizer(items));

        List<CalloutService.WorkItem> retries = new List<CalloutService.WorkItem>();
        for (CalloutService.WorkItem wi : items) {
            Integer status;
            String errorBody;
            try {
                HttpResponse res = new Http().send(CalloutService.buildHttpRequest(wi.request));
                status = res.getStatusCode();
                errorBody = (status >= 200 && status < 300) ? null : res.getBody();
            } catch (CalloutException e) {
                status = 0; // timeout / connection-failure sentinel (RetryPolicy treats as transient)
                errorBody = e.getMessage();
            }

            switch on RetryPolicy.decide(status, wi.attempt) {
                when SUCCESS {
                    Logger.info(
                        'FRS notify ok [' + wi.request.correlationId + '] status=' + status,
                        wi.request.correlationId
                    );
                }
                when RETRY {
                    retries.add(new CalloutService.WorkItem(wi.request, wi.attempt + 1));
                }
                when else {
                    CalloutService.deadLetter(wi, status, errorBody);
                }
            }
        }

        lastEnqueuedRetries = retries;
        if (!retries.isEmpty() && !Test.isRunningTest()) {
            // Backoff is keyed off the (uniform) next attempt number for this chunk (ADR-003).
            System.enqueueJob(
                new CalloutQueueable(retries),
                RetryPolicy.backoffMinutes(retries[0].attempt)
            );
        }
    }
}
