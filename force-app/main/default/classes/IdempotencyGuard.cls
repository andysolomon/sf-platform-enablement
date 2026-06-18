/**
 * IdempotencyGuard — exactly-once inbound application keyed by Idempotency-Key (FR-9, NFR-3).
 *
 * Strategy (ADR-003): reserve the key by INSERTING an Integration_Message__c whose Idempotency_Key__c
 * is a Unique External Id. The platform's unique constraint is what guarantees correctness — even
 * under *concurrent* duplicate delivery, where a query-then-insert check races (both callers read
 * "not present" and both apply). A second insert with the same key fails with DUPLICATE_VALUE, which
 * we translate into a DUPLICATE outcome (a no-op for the caller).
 *
 * The reservation runs in the same transaction as any record mutation the caller performs, so a
 * downstream failure rolls back the reservation too — the message can then be safely re-applied.
 */
public with sharing class IdempotencyGuard {
    public enum Outcome {
        APPLIED,
        DUPLICATE
    }

    /** A parsed inbound message — just the fields the guard persists. */
    public class Message {
        public String idempotencyKey;
        public String correlationId;
        public String eventType;
        public String salesforceRecordId;
        public String status;
    }

    /**
     * Reserve the key. APPLIED = first time we've seen it (caller should perform the effect);
     * DUPLICATE = already applied (caller must do nothing).
     */
    public static Outcome reserve(Message m) {
        try {
            insert new Integration_Message__c(
                Idempotency_Key__c = m.idempotencyKey,
                Correlation_Id__c = m.correlationId,
                Event_Type__c = m.eventType,
                Salesforce_Record_Id__c = m.salesforceRecordId,
                Applied_Status__c = m.status,
                Applied_At__c = System.now()
            );
            return Outcome.APPLIED;
        } catch (DmlException e) {
            if (isDuplicateKey(e)) {
                return Outcome.DUPLICATE;
            }
            throw e;
        }
    }

    @TestVisible
    private static Boolean isDuplicateKey(DmlException e) {
        for (Integer i = 0; i < e.getNumDml(); i++) {
            if (e.getDmlType(i) == System.StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        // Defensive: a unique External Id collision can also surface as a generic duplicate message.
        return e.getMessage() != null && e.getMessage().contains('DUPLICATE_VALUE');
    }
}
