/**
 * CalloutFinalizer — failure safety net for CalloutQueueable (ADR-003, FR-7).
 *
 * Finalizers run even when the parent Queueable throws an unhandled exception (a governor limit,
 * an uncaught error), which is exactly the case CalloutQueueable's own try/catch can't reach. On
 * such a failure we dead-letter the carried work rather than risk a retry loop on a structural
 * problem — nothing is silently lost. On a clean run this is a no-op.
 *
 * Internal — never part of the consumer-facing API surface (api-governance ⚫).
 */
// `public` (not `global`): internal infrastructure carrying the internal WorkItem type.
public with sharing class CalloutFinalizer implements System.Finalizer {
    private List<CalloutService.WorkItem> items;

    public CalloutFinalizer(List<CalloutService.WorkItem> items) {
        this.items = items;
    }

    public void execute(FinalizerContext ctx) {
        Boolean unhandled = ctx != null && ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION;
        handle(unhandled, ctx == null ? null : ctx.getException());
    }

    // Extracted so the dead-letter decision is unit-testable without a FinalizerContext
    // (which has no public constructor).
    @TestVisible
    private void handle(Boolean unhandled, Exception ex) {
        if (!unhandled) {
            return;
        }
        String err = (ex == null) ? 'Queueable failed with an unhandled exception' : ex.getMessage();
        for (CalloutService.WorkItem wi : items) {
            CalloutService.deadLetter(wi, null, 'UNHANDLED: ' + err);
        }
    }
}
