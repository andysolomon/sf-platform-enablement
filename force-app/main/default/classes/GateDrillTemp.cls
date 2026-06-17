/**
 * TEMPORARY — Phase 4.7 gate drill. Contains a deliberate SOQL-injection violation to prove
 * the CI scan gate (Code Analyzer, severity-threshold 2) fails the pipeline. Removed in the
 * next commit once RED is confirmed.
 */
public with sharing class GateDrillTemp {
    public static List<SObject> unsafe(String name) {
        return Database.query('SELECT Id FROM Account WHERE Name = \'' + name + '\'');
    }
}
