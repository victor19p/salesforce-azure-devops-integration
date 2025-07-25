/**
 * @description Batch Apex class to query Work_Item_Azure__c records and enqueue Queueable jobs
 * for asynchronous callouts to Azure. Implements Database.AllowsCallouts
 * because the Queueable it enqueues also performs callouts.
 * 
 * Example usage: Database.executeBatch(new AzureWorkItemSyncBatch(), 200);
 * 
 * @author Portfolio Demo - Sanitized Version
 * @note This is a sanitized version removing client-specific references
 */
public class AzureWorkItemSyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.stateful{
    
    /**
     * @description The start method queries all Work_Item_Azure__c records to be processed.
     * @param bc The Database.BatchableContext.
     * @return A Database.QueryLocator for Work_Item_Azure__c records.
     */
    public Database.QueryLocator start(Database.BatchableContext bc){
        System.debug(LoggingLevel.INFO,'Starting execution of AzureWorkItemSyncBatch');

        return Database.getQueryLocator('SELECT Id, AzureId__c FROM Work_Item_Azure__c WHERE AzureId__c != null');
    }

    /**
     * @description The execute method processes a chunk of records from the start method.
     * It enqueues a new Queueable job for these records.
     * @param bc The Database.BatchableContext.
     * @param scope A list of Work_Item_Azure__c records to process in this chunk.
     */
    public void execute(Database.BatchableContext bc, List<Work_Item_Azure__c> scope){
        System.debug('Processing batch of ' + scope.size() + ' Work_Item_Azure__c records.');
        System.debug(LoggingLevel.INFO,'Scope size: ' + scope.size());
    
        List<String> azureIdsForThisChunk = new List<String>();
        for(Work_Item_Azure__c item : scope){
            if(item.AzureId__c != null){
                azureIdsForThisChunk.add(item.AzureId__c);
                System.debug('Adding work item with Azure ID ' + item.AzureId__c);
            }
        }

        if(!azureIdsForThisChunk.isEmpty()){
            System.debug(LoggingLevel.INFO, 'Enqueuing Queueable job for sync');
            System.enqueueJob(new AzureWorkItemCalloutQueueable(azureIdsForThisChunk));
            System.debug('Enqueued new AzureWorkItemCalloutQueueable for ' + azureIdsForThisChunk.size() + ' IDs.');
        } else {
            System.debug(LoggingLevel.INFO,'No valid Azure IDs found in this batch scope to enqueue.');
        }
    }

    /**
     * @description The finish method is called once all batches are processed.
     * @param bc The Database.BatchableContext.
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('AzureWorkItemSyncBatch finished.');
        // Custom Log or notifications can be implemented here
        // Example: Send notification email, create log records, etc.
    }
}
