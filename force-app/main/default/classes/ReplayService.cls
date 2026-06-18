/**
 * ReplayService — operator replay of a dead-lettered call once the cause is fixed (FR-7).
 *
 * Re-enqueues the original message through CalloutService using the SAME idempotency key, so if
 * the FRS side already processed an earlier attempt the replay is safely deduped there (contract
 * §3.3: 409 = already applied = success). No data loss, no double-effect. The dead-letter record
 * is marked REPLAYED for the audit trail.
 */
global with sharing class ReplayService {
    global static void replay(Id deadLetterId) {
        Integration_DeadLetter__c dl = [
            SELECT
                Id,
                Correlation_Id__c,
                Idempotency_Key__c,
                Named_Credential_Path__c,
                Http_Method__c,
                Payload__c,
                Status__c
            FROM Integration_DeadLetter__c
            WHERE Id = :deadLetterId
            LIMIT 1
        ];

        CalloutService.Request req = new CalloutService.Request();
        req.namedCredentialPath = dl.Named_Credential_Path__c;
        req.method = dl.Http_Method__c;
        req.body = dl.Payload__c;
        req.idempotencyKey = dl.Idempotency_Key__c; // same key — FRS dedupes a re-applied message
        req.correlationId = dl.Correlation_Id__c;

        CalloutService.sendAsync(req);

        dl.Status__c = 'REPLAYED';
        update dl;
        Logger.info(
            'Replayed dead letter ' + dl.Id + ' [' + dl.Correlation_Id__c + ']',
            dl.Correlation_Id__c
        );
    }
}
