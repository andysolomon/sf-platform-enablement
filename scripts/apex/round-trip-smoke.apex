/**
 * round-trip-smoke.apex — executable post-setup smoke for 6-C (run via `sf apex run`).
 *
 * NOT a unit test (those are mocked, 35/35). This exercises the LIVE wires after the Named
 * Credential + Connected App/JWT + Vercel-protection-off setup is done. Run section by section
 * and inspect the debug log + the resulting Log__c / Integration_* records.
 *
 * Usage:
 *   sf apex run --target-org <org> --file scripts/apex/round-trip-smoke.apex
 */

// ---- Section 1: OUTBOUND notify (S1, FR-5) -------------------------------------------------
String corr = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
CalloutService.Request req = new CalloutService.Request();
req.namedCredentialPath = 'FRS_Service/v1/notifications';
req.method = 'POST';
req.correlationId = corr;
req.idempotencyKey = 'smoke-' + corr.substring(0, 8) + '-completed';
req.body = JSON.serialize(new Map<String, Object>{
    'correlationId' => corr,
    'idempotencyKey' => req.idempotencyKey,
    'eventType' => 'todo.completed',
    'occurredAt' => System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
    'source' => 'round-trip-smoke',
    'payload' => new Map<String, Object>{ 'salesforceRecordId' => UserInfo.getUserId(), 'status' => 'Completed' }
});
CalloutService.sendAsync(req);
System.debug('OUTBOUND enqueued. correlationId=' + corr + ' idempotencyKey=' + req.idempotencyKey);
System.debug('After it runs, check: SELECT Message__c FROM Log__c WHERE Correlation_Id__c = \'' + corr + '\'');

// ---- Section 2: INBOUND apply + idempotency (S2, FR-8/FR-9) --------------------------------
// Simulates what the FRS mock POSTs to /services/apexrest/frs/v1/status (here invoked directly).
String inboundKey = 'smoke-inbound-' + corr.substring(0, 8);
RestRequest rr = new RestRequest();
rr.requestURI = '/services/apexrest/frs/v1/status';
rr.httpMethod = 'POST';
rr.headers.put('X-Correlation-Id', corr);
rr.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
    'correlationId' => corr,
    'idempotencyKey' => inboundKey,
    'eventType' => 'status.updated',
    'payload' => new Map<String, Object>{ 'salesforceRecordId' => UserInfo.getUserId(), 'status' => 'Acknowledged' }
}));
RestContext.request = rr;
RestContext.response = new RestResponse();

FrsStatusResource.StatusResult first = FrsStatusResource.handleStatus();
System.debug('INBOUND #1 status=' + first.status + ' (expect applied)');

FrsStatusResource.StatusResult dup = FrsStatusResource.handleStatus(); // same key -> duplicate
System.debug('INBOUND #2 status=' + dup.status + ' (expect duplicate, FR-9)');

System.debug('Round-trip trace: SELECT Category__c, Message__c FROM Log__c WHERE Correlation_Id__c = \'' + corr + '\' ORDER BY CreatedDate');
System.debug('Dedup proof: SELECT COUNT() FROM Integration_Message__c WHERE Idempotency_Key__c = \'' + inboundKey + '\' (expect 1)');
