/**
 * @description Queueable Apex class to handle asynchronous callouts to Azure for bulk Work Item synchronization.
 * It processes a list of Azure IDs, fetches details from Azure using batch API, compares metadata,
 * and updates Salesforce records if changes are detected.
 * 
 * @author Portfolio Demo - Sanitized Version
 * @note This is a sanitized version removing client-specific references
 */
public class AzureWorkItemCalloutQueueable implements Queueable, Database.AllowsCallouts{
    private List<String> azureIdsToFetch;

    /**
     * @description Constructor for the Queueable class.
     * @param ids A list of Azure IDs that this instance of the Queueable will process.
     */
    public AzureWorkItemCalloutQueueable(List<String> ids) {
        this.azureIdsToFetch = ids;
    }

    /**
     * @description The main execution method for the Queueable job.
     * It performs the callout, processes the response, and updates Salesforce records.
     * @param qc The QueueableContext.
     */
    public void execute(QueueableContext qc){
        if(azureIdsToFetch == null || azureIdsToFetch.isEmpty()){
            return;
        }
        System.debug('Processing Azure IDs: ' + azureIdsToFetch);

        // Convert the list of String IDs to List of Integers for the JSON body
        List<Integer> idsAsIntegers = new List<Integer>();
        for (String idStr : azureIdsToFetch) {
            try {
                idsAsIntegers.add(Integer.valueOf(idStr));
            } catch (TypeException e) {
                System.debug(LoggingLevel.WARN, 'Could not convert Azure ID "' + idStr + '" to Integer. Skipping.');
            }
        }

        if (idsAsIntegers.isEmpty()) {
            System.debug('No valid integer Azure IDs to process after conversion. Exiting.');
            return;
        }

        Map<String, AzureIntegration__mdt> mappings = AzureMetadataService.getActiveFieldMappings();
        List<String> fieldsToFetch = new List<String>();

        fieldsToFetch.add('System.Id'); 
        fieldsToFetch.add('System.ChangedDate'); 

        // Build dynamic field list from metadata mappings
        for (String mdtLabel : mappings.keySet()) {
            AzureIntegration__mdt mdt = mappings.get(mdtLabel);
            String azurePath = mdt.Azure_Path__c;
            if (azurePath != null) {
                if (azurePath.startsWithIgnoreCase('/fields/')) {
                    azurePath = azurePath.substring('/fields/'.length());
                }
                if (!fieldsToFetch.contains(azurePath)) {
                    fieldsToFetch.add(azurePath);
                }
            }
        }

        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('ids', idsAsIntegers);
        requestBody.put('fields', fieldsToFetch);

        String jsonBody = JSON.serialize(requestBody);

        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:Azure_DevOps_Integration/SampleProject/_apis/wit/workitemsbatch?api-version=7.1');
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setBody(jsonBody);

            Http http = new Http();
            HttpResponse response = http.send(request);

            if (response.getStatusCode() == 200){
                List<Map<String, Object>> azureWorkItemDetailsList = new List<Map<String, Object>>();
                Map<String, Object> responseBodyMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());

                if (responseBodyMap.containsKey('value') && responseBodyMap.get('value') instanceof List<Object>) {
                    List<Object> rawWorkItems = (List<Object>) responseBodyMap.get('value');
                    for (Object item : rawWorkItems) {
                        if (item instanceof Map<String, Object>) {
                            azureWorkItemDetailsList.add((Map<String, Object>) item);
                        }
                    }
                } else {
                    System.debug(LoggingLevel.ERROR, 'Azure response for batch API did not contain expected "value" array: ' + response.getBody());
                    return; 
                }
                System.debug(LoggingLevel.INFO, 'Successfully retrieved ' + azureWorkItemDetailsList.size() + ' Azure Work Item details.');

                // Query Salesforce records efficiently by Azure ID
                Set<String> azureIdsSet = new Set<String>(azureIdsToFetch);
                Map<String, Work_Item_Azure__c> salesforceWorkItems = new Map<String, Work_Item_Azure__c>();

                // Build the SOQL query string dynamically to include all mapped SF fields
                List<String> sfFieldsToQuery = new List<String>();
                sfFieldsToQuery.add('Id');
                sfFieldsToQuery.add('AzureId__c');
                sfFieldsToQuery.add('LastModifiedDate'); 

                for (AzureIntegration__mdt mdt : mappings.values()) { 
                    if (mdt.Salesforce_Field__c != null) { 
                        String sfApiName = mdt.Salesforce_Field__c; 
                        if (!sfFieldsToQuery.contains(sfApiName)) { 
                            sfFieldsToQuery.add(sfApiName);
                        }
                    }
                }
                String soqlQuery = 'SELECT ' + String.join(sfFieldsToQuery, ',') + ' FROM Work_Item_Azure__c WHERE AzureId__c IN :azureIdsSet';

                for (Work_Item_Azure__c sfItem : Database.query(soqlQuery)) {
                    salesforceWorkItems.put(sfItem.AzureId__c, sfItem);
                }
                System.debug(LoggingLevel.INFO, 'Queried ' + salesforceWorkItems.size() + ' Salesforce Work_Item_Azure__c records.');

                List<Work_Item_Azure__c> workItemsToUpdate = new List<Work_Item_Azure__c>();

                // Process each Azure Work Item and compare with Salesforce
                for (Map<String, Object> azureDetail : azureWorkItemDetailsList) {
                    String azureIdStr = String.valueOf(azureDetail.get('id'));
                    System.debug(LoggingLevel.DEBUG, 'Processing Azure ID: ' + azureIdStr);
                    Work_Item_Azure__c sfWorkItem = salesforceWorkItems.get(azureIdStr);

                    if (sfWorkItem != null) {
                        Boolean needsUpdate = false;
                        Map<String, Object> azureFieldsMap = (Map<String, Object>) azureDetail.get('fields'); 

                        if (azureFieldsMap != null) {
                            String azureChangedDateStr = (String) azureFieldsMap.get('System.ChangedDate');
                            DateTime azureChangedDateTime = null;
                            if (azureChangedDateStr != null) {
                                try {
                                    azureChangedDateTime = (DateTime) JSON.deserialize('"' + azureChangedDateStr + '"', DateTime.class);
                                } catch (Exception e) {
                                    System.debug(LoggingLevel.ERROR, 'Failed to parse System.ChangedDate "' + azureChangedDateStr + '": ' + e.getMessage());
                                }
                            }

                            // Only update if Azure has newer changes
                            if (azureChangedDateTime != null && (sfWorkItem.LastModifiedDate == null || azureChangedDateTime > sfWorkItem.LastModifiedDate)) {
                                System.debug(LoggingLevel.INFO, 'Azure ID ' + azureIdStr + ' has newer changes. Comparing fields.');
                                
                                // Dynamic Field Comparison and Update
                                for (AzureIntegration__mdt mdt : mappings.values()) {
                                    String sfApiName = mdt.Salesforce_Field__c;
                                    String azureFieldPath = mdt.Azure_Path__c;
                                
                                    if (sfApiName == null) {
                                        System.debug(LoggingLevel.WARN, 'Salesforce_Field__c is null for metadata record: ' + mdt.DeveloperName + '. Skipping this mapping.');
                                        continue; 
                                    }
                                
                                    if (azureFieldPath != null) {
                                        if (azureFieldPath.startsWithIgnoreCase('/fields/')) {
                                            azureFieldPath = azureFieldPath.substring('/fields/'.length());
                                        }
                                
                                        Object azureValue = azureFieldsMap.get(azureFieldPath);
                                        System.debug(LoggingLevel.INFO, 'Processing field ' + sfApiName + '. Azure Path: ' + azureFieldPath + ', Azure Value: ' + azureValue);
                                
                                        // Handle blank strings as null
                                        if (azureValue instanceof String && String.isBlank((String)azureValue)) {
                                            azureValue = null;
                                        }
                                
                                        Object sfValue = sfWorkItem.get(sfApiName);
                                        System.debug(LoggingLevel.INFO, 'Salesforce Field: ' + sfApiName + ', Current SF Value: ' + sfValue);
                                
                                        // Perform value comparison
                                        Boolean valuesAreEffectivelySame = false;
                                
                                        if (sfValue == null && azureValue == null) {
                                            valuesAreEffectivelySame = true;
                                        } else if (sfValue != null && azureValue != null) {
                                            valuesAreEffectivelySame = sfValue.equals(azureValue);
                                        }
                                
                                        if (!valuesAreEffectivelySame) {
                                            sfWorkItem.put(sfApiName, azureValue); 
                                            needsUpdate = true;
                                            System.debug(LoggingLevel.INFO, 'Field ' + sfApiName + ' for Azure ID ' + azureIdStr + ' updated. SF: ' + sfValue + ' --> Azure: ' + azureValue);
                                        } else {
                                            System.debug(LoggingLevel.INFO, 'Field ' + sfApiName + ' for Azure ID ' + azureIdStr + ' values are same. No update needed.');
                                        }
                                    }
                                }
                                
                                if (needsUpdate) {
                                    workItemsToUpdate.add(sfWorkItem);
                                }

                            } else {
                                System.debug(LoggingLevel.INFO, 'Azure ID ' + azureIdStr + ' has not changed since last sync. Skipping comparison.');
                            }
                        } else {
                            System.debug(LoggingLevel.WARN, 'Azure Work Item ' + azureIdStr + ' did not contain a "fields" map in the response.');
                        }
                    } else {
                        System.debug(LoggingLevel.WARN, 'No matching Salesforce Work_Item_Azure__c found for Azure ID: ' + azureIdStr + '. Consider creating it or logging this discrepancy.');
                    }
                }
                
                // Perform DML Update
                if (!workItemsToUpdate.isEmpty()) {
                    update workItemsToUpdate;
                    System.debug('Successfully updated ' + workItemsToUpdate.size() + ' Work_Item_Azure__c records.');
                } else {
                    System.debug('No Work_Item_Azure__c records needed an update in this run.');
                }

            } else {
                System.debug(LoggingLevel.ERROR, 'Callout to Azure failed with status code: ' + response.getStatusCode() + ' Body: ' + response.getBody());
            }

        } catch (CalloutException e) {
            System.debug(LoggingLevel.ERROR, 'Callout error to Azure: ' + e.getMessage() + ' for Ids: ' + azureIdsToFetch);
            // Implement retry logic for network errors if needed
        }
    }
}
