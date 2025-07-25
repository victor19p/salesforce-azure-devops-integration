/**
 * @description Repository layer (Data Access Object - DAO) for Work_Item_Azure__c and Case_Work_Item__c.
 * Encapsulates all data access logic for these objects.
 * Uses AzureMetadataService to dynamically map Work_Item_Azure__c fields.
 * 
 * @author Portfolio Demo - Sanitized Version
 * @note This is a sanitized version removing client-specific references
 */
public without sharing class WorkItemRepository {
    
    /**
     * @description Creates a new Work_Item_Azure__c record in Salesforce.
     * Fields are dynamically mapped using AzureIntegration__mdt metadata.
     * Does NOT manage the relationship with Case__c directly here.
     * @param formRequest DTO with form data (LWC).
     * @param azureId The ID of the Work Item created in Azure DevOps.
     * @return The ID of the Work_Item_Azure__c created in Salesforce.
     */
    public static Id createWorkItemRecord(WorkItemFormRequest formRequest, String azureId) {
        // Validate CRUD permissions
        if (!Work_Item_Azure__c.SObjectType.getDescribe().isCreateable()) {
            throw new AuraHandledException('You do not have permissions to create Work_Item_Azure__c records');
        }
        
        Work_Item_Azure__c workItem = new Work_Item_Azure__c();
        workItem.AzureId__c = azureId; 

        // Map form fields to Work_Item_Azure__c object
        mapFormFieldsToWorkItem(formRequest, workItem);

        try {
            System.debug(LoggingLevel.INFO, 'Creating Work_Item_Azure__c: ' + workItem);
            insert workItem;
            System.debug(LoggingLevel.INFO, 'Work_Item_Azure__c created successfully with ID: ' + workItem.Id);
            return workItem.Id;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'Error inserting Work_Item_Azure__c: ' + e.getMessage());
            throw new AuraHandledException('Error creating Work Item record in Salesforce: ' + e.getMessage());
        }
    }

    /**
     * @description Maps form fields to Work_Item_Azure__c object using metadata.
     * @param formRequest DTO with form data.
     * @param workItem Work_Item_Azure__c object to map.
     */
    private static void mapFormFieldsToWorkItem(WorkItemFormRequest formRequest, Work_Item_Azure__c workItem) {
        Map<String, AzureIntegration__mdt> mappings = AzureMetadataService.getActiveFieldMappings();
        System.debug(LoggingLevel.INFO, 'Mapping form request: ' + formRequest);
        
        for (String mdtLabel : mappings.keySet()) {
            AzureIntegration__mdt mdt = mappings.get(mdtLabel);
            if (String.isNotBlank(mdt.Salesforce_Field__c)) {
                Object valueToMap = getFormFieldValue(formRequest, mdtLabel);
                
                if (valueToMap != null && !(valueToMap instanceof String && String.isBlank((String)valueToMap))) {
                    workItem.put(mdt.Salesforce_Field__c, valueToMap);
                }
            }
        }
        
        // Map the Work Item type
        Object valueTypeOf = getFormFieldValue(formRequest, 'TypeOf');
        System.debug(LoggingLevel.INFO, 'Work Item type: ' + valueTypeOf);
        workItem.put('Type__c', valueTypeOf);
    }

    /**
     * @description Gets the form field value based on the metadata label.
     * @param formRequest DTO with form data.
     * @param mdtLabel Metadata label.
     * @return Field value or null if not found.
     */
    private static Object getFormFieldValue(WorkItemFormRequest formRequest, String mdtLabel) {
        switch on mdtLabel {
            when 'Title' { return formRequest.title; }
            when 'Description' { return formRequest.description; }
            when 'FoundBy' { return formRequest.foundBy; }
            when 'RegressionQA' { return formRequest.regressionQA; }
            when 'Severity' { return formRequest.severity; }
            when 'TypeOf' { return formRequest.typeOf; }
            when else { return null; }
        }
    }

    /**
     * @description Creates an association between a Case and a Work_Item_Azure__c through the Case_Work_Item__c object.
     * @param caseId The Salesforce Case ID.
     * @param workItemAzureId The Work_Item_Azure__c ID in Salesforce.
     */
    public static void createCaseWorkItemRelationship(Id caseId, Id workItemAzureId) {
        // Validate CRUD permissions
        if (!Case_Work_Item__c.SObjectType.getDescribe().isCreateable()) {
            throw new AuraHandledException('You do not have permissions to create Case_Work_Item__c records');
        }
        
        List<Case_Work_Item__c> existingRelations = [
            SELECT Id 
            FROM Case_Work_Item__c 
            WHERE Case__c = :caseId AND Work_Item_Azure__c = :workItemAzureId 
            LIMIT 1
        ];

        if (existingRelations.isEmpty()) {
            Case_Work_Item__c newRelation = new Case_Work_Item__c();
            newRelation.Case__c = caseId;
            newRelation.Work_Item_Azure__c = workItemAzureId;

            try {
                insert newRelation;
                System.debug(LoggingLevel.INFO, 'Case_Work_Item__c relationship created: ' + newRelation.Id);
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, 'Error creating Case_Work_Item__c relationship: ' + e.getMessage());
                throw new AuraHandledException('Error creating Case-Work Item relationship: ' + e.getMessage());
            }
        } else {
            System.debug(LoggingLevel.WARN, 'Case_Work_Item__c relationship already exists for Case ID: ' + caseId + ' and Work Item ID: ' + workItemAzureId);
        }
    }

    /**
     * @description Gets a Work_Item_Azure__c record by its Azure ID.
     * @param workItemAzureId The Azure ID of the Work Item.
     * @return The found Work_Item_Azure__c record, or empty record if not found.
     */
    public static Work_Item_Azure__c getSalesforceWorkItemById(String workItemAzureId){
        List<Work_Item_Azure__c> workItems = [
            SELECT Id, AzureId__c, Description__c, Found_By__c, Severity__c, Title__c, Regression_QA__c
            FROM Work_Item_Azure__c 
            WHERE AzureId__c = :workItemAzureId
            LIMIT 1
        ];
        
        Work_Item_Azure__c workItem;
        if (!workItems.isEmpty()) {
            workItem = workItems[0];
        } else {
            workItem = new Work_Item_Azure__c();
        }

        return workItem;
    }

    /**
     * @description Creates a Work_Item_Azure__c record from Azure DevOps data.
     * Used when linking an existing Azure Work Item to Salesforce.
     * @param azureFields Map of field values from Azure DevOps.
     * @param azureId The Azure Work Item ID.
     * @return The ID of the created Work_Item_Azure__c record.
     */
    public static Id createWorkItemFromAzure(Map<String, Object> azureFields, String azureId) {
        Map<String, AzureIntegration__mdt> mappings = AzureMetadataService.getActiveFieldMappings();
        Work_Item_Azure__c workItem = new Work_Item_Azure__c();
        workItem.AzureId__c = azureId; 

        for (String mdtLabel : mappings.keySet()) {
            AzureIntegration__mdt mdt = mappings.get(mdtLabel);
            if (String.isNotBlank(mdt.Azure_Path__c) && String.isNotBlank(mdt.Salesforce_Field__c)) {
                String azureKey = mdt.Azure_Path__c.replace('/fields/', '');
                if (azureFields.containsKey(azureKey)) {
                    Object value = azureFields.get(azureKey);
                    System.debug('Mapping Azure field - Key: ' + azureKey + ', Value: ' + value);
                    workItem.put(mdt.Salesforce_Field__c, value);
                }
            }
        }
        
        // Map Work Item type
        if(azureFields.containsKey('System.WorkItemType')){
            Object typeValue = azureFields.get('System.WorkItemType');
            System.debug('Work Item Type - Value: ' + typeValue);
            workItem.put('Type__c', typeValue);
        }

        try {
            insert workItem;
            System.debug(LoggingLevel.INFO, 'Work Item created from Azure data: ' + workItem);
            System.debug(LoggingLevel.INFO, 'Work Item ID: ' + workItem.Id);

            return workItem.Id;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'Error inserting Work_Item_Azure__c: ' + e.getMessage());
            throw new AuraHandledException('Error creating Work Item record in Salesforce: ' + e.getMessage());
        }
    } 
}
