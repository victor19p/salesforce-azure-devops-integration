/**
 * @description Main service class for managing the creation and status of Work Items
 * related to Cases in Salesforce and Azure DevOps.
 * This class serves as the entry point for LWC components.
 * 
 * @author Portfolio Demo - Sanitized Version
 * @note This is a sanitized version removing client-specific references
 */
public without sharing class WorkOrderService {
    
    /**
     * @description Entry point for the LWC to initiate the creation of a Work Item in Azure DevOps
     * and its subsequent registration in Salesforce, along with the association to the Case.
     * This method is called from the LWC and queues an asynchronous operation.
     * @param formRequestJson JSON string with the Work Item form data.
     * @param caseId The ID of the Salesforce Case to which the Work Item will be associated.
     */
    @AuraEnabled
    public static void createAndAssociateWorkItem(String formRequestJson, Id caseId) {
        WorkItemFormRequest formRequest = (WorkItemFormRequest)JSON.deserialize(formRequestJson, WorkItemFormRequest.class);
        System.debug(LoggingLevel.Info, 'Form Request: ' + formRequest);
        System.debug(LoggingLevel.Info, 'Case ID: ' + caseId);
        
        // Basic validation
        if (formRequest == null || !formRequest.isValid()) {
            throw new AuraHandledException('Form data is incomplete or invalid.');
        }
        if (caseId == null) {
            throw new AuraHandledException('Case ID is required to associate the Work Item.');
        }

        // Create an instance of the Queueable class and queue it.
        // Complex parameters (WorkItemFormRequest, Id) can be passed to the Queueable class.
        System.enqueueJob(new CreateAzureWorkItemQueueable(formRequest, caseId));
        System.debug(LoggingLevel.INFO, 'Work Item creation job queued for Case ID: ' + caseId);
        // Note: We cannot directly return the Work_Item_Azure__c.Id, since the operation is asynchronous.
        // The LWC should handle the response asynchronously (e.g., using a success/error message, or reloading the data).
    }
    
    /**
     * @description Gets specific Azure DevOps picklist values for an LWC.
     * @param picklistLabel The Label of the AzurePicklistId__mdt metadata.
     * @return List<String> with the picklist values.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getAzurePicklistOptions(String picklistLabel) {
        return AzureDevOpsIntegration.getPicklistValues(picklistLabel);
    }

    /**
     * @description Links an existing Azure Work Item to a Salesforce Case.
     * @param azureWorkItemId The Azure Work Item ID to link.
     * @param caseId The Salesforce Case ID to link to.
     */
    @AuraEnabled
    public static void linkWorkItemById(String azureWorkItemId, Id caseId ){
        System.enqueueJob(new LinkWorkItemAzureQueueable(azureWorkItemId, caseId));
        System.debug(LoggingLevel.INFO, 'Work Item linking job queued for Azure Work Item ID: ' + azureWorkItemId);
    }

    /**
     * @description Queueable class for creating Work Items in Azure DevOps asynchronously.
     * Handles the complete flow: Azure creation → Salesforce record → Case association.
     */
    public class CreateAzureWorkItemQueueable implements Queueable, Database.AllowsCallouts {
        
        private WorkItemFormRequest formRequest;
        private Id salesforceCaseId;

        public CreateAzureWorkItemQueueable(WorkItemFormRequest req, Id caseId) {
            this.formRequest = req;
            this.salesforceCaseId = caseId;
        }

        public void execute(QueueableContext context) {
            System.debug(LoggingLevel.INFO, 'Starting execution of CreateAzureWorkItemQueueable for Case ID: ' + salesforceCaseId);
            try {
                // 1. Create Work Item in Azure DevOps
                Map<String, Object> azureResponse = AzureDevOpsIntegration.createWorkItem(formRequest);

                String azureWorkItemId = null;
                if (azureResponse != null && azureResponse.containsKey('id')) {
                    azureWorkItemId = String.valueOf(azureResponse.get('id'));
                    System.debug(LoggingLevel.INFO, 'Work Item created in Azure with ID: ' + azureWorkItemId);
                } else {
                    throw new AuraHandledException('Could not get the Work Item ID from the Azure DevOps response.');
                }

                // 2. Create the Work_Item_Azure__c record in Salesforce
                Id salesforceWorkItemId = WorkItemRepository.createWorkItemRecord(formRequest, azureWorkItemId);
                System.debug(LoggingLevel.INFO, 'Work_Item_Azure__c created in Salesforce with ID: ' + salesforceWorkItemId);

                // 3. Create the Case_Work_Item__c relationship in Salesforce
                WorkItemRepository.createCaseWorkItemRelationship(salesforceCaseId, salesforceWorkItemId);
                System.debug(LoggingLevel.INFO, 'Case_Work_Item__c relationship created between Case ' + salesforceCaseId + ' and Work Item ' + salesforceWorkItemId);

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Error in CreateAzureWorkItemQueueable for Case ID ' + salesforceCaseId + ': ' + e.getMessage() + ' at line ' + e.getLineNumber());
            }
        }
    }

    /**
     * @description Queueable class for linking existing Azure Work Items to Salesforce Cases.
     * Handles the flow: Azure lookup → Salesforce creation → Case association → Azure update.
     */
    public class LinkWorkItemAzureQueueable implements Queueable, Database.AllowsCallouts {
        private String azureWorkItemId;
        private Id salesforceCaseId;

        public LinkWorkItemAzureQueueable(String workItemId, Id caseId) {
            this.azureWorkItemId = workItemId;
            this.salesforceCaseId = caseId;
        }

        public void execute(QueueableContext context) {
            System.debug(LoggingLevel.INFO, 'Starting execution of LinkWorkItemAzureQueueable for Case ID: ' + salesforceCaseId);
            System.debug(LoggingLevel.INFO, 'Azure Work Item ID: ' + azureWorkItemId);

            try {
                // 1. Get Azure Work Item details by ID
                Map<String, Object> azureResponse = AzureDevOpsIntegration.getWorkItemDetailsByAzureId(azureWorkItemId);
                
                // 2. Validate response and process linking
                if (azureResponse != null && azureResponse.containsKey('fields')) {
                    Map<String, Object> fields = (Map<String, Object>) azureResponse.get('fields');
                    
                    // Update Azure Work Item with Salesforce Case ID
                    AzureDevOpsIntegration.updateWorkItemAzureCaseId(azureWorkItemId, salesforceCaseId, fields);

                    // Check if Work Item already exists in Salesforce
                    Work_Item_Azure__c workItemSf = WorkItemRepository.getSalesforceWorkItemById(azureWorkItemId);
                    
                    Id salesforceWorkItemId;
                    if (workItemSf.Id != null) {
                        // Work Item already exists, use existing ID
                        salesforceWorkItemId = workItemSf.Id;
                        System.debug(LoggingLevel.INFO, 'Using existing Work Item in Salesforce: ' + salesforceWorkItemId);
                    } else {
                        // Create new Work Item from Azure data
                        salesforceWorkItemId = WorkItemRepository.createWorkItemFromAzure(fields, azureWorkItemId);
                        System.debug(LoggingLevel.INFO, 'Created new Work Item in Salesforce: ' + salesforceWorkItemId);
                    }
                    
                    // Create the Case-Work Item relationship
                    WorkItemRepository.createCaseWorkItemRelationship(salesforceCaseId, salesforceWorkItemId);
                    System.debug(LoggingLevel.INFO, 'Case-Work Item relationship created successfully');
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Error in LinkWorkItemAzureQueueable for Case ID ' + salesforceCaseId + ': ' + e.getMessage() + ' at line ' + e.getLineNumber());
            }
        }
    }
}
