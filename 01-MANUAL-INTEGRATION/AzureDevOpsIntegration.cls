/**
 * @description Integration layer to interact with the Azure DevOps API.
 * Manages HTTP request construction, sending and response processing.
 * Uses AzureMetadataService to obtain dynamic configurations.
 * Uses Named Credentials for authentication and base URL.
 * 
 * @author Portfolio Demo - Sanitized Version
 * @note This is a sanitized version removing client-specific references
 */
public without sharing class AzureDevOpsIntegration {

    private static final String NAMED_CREDENTIAL_CALLOUT = 'callout:Azure_DevOps_Integration';
    private static final String AZURE_API_VERSION_WIQL = '7.1'; 
    private static final String AZURE_API_VERSION_WORKITEMS = '7.2-preview.3'; 
    private static final String AZURE_API_VERSION_PICKLISTS = '7.1-preview.1'; 
    private static final String AZURE_PROJECT = 'SampleProject'; // Sanitized: was client-specific project name

    /**
     * @description Creates a Work Item in Azure DevOps.
     * Dynamically builds the JSON Patch using AzureIntegration__mdt metadata.
     * @param workItemData DTO with Work Item data from the LWC.
     * @return Map<String, Object> with Azure response (will contain the Azure Work Item ID).
     */
    public static Map<String, Object> createWorkItem(WorkItemFormRequest workItemData) {
        validateWorkItemType(workItemData.typeOf);
        
        HttpRequest req = buildCreateWorkItemRequest(workItemData);
        List<Map<String, Object>> jsonPatch = buildJsonPatch(workItemData);
        
        req.setBody(JSON.serialize(jsonPatch));
        System.debug(LoggingLevel.INFO, 'Azure Create Work Item Request Body: ' + req.getBody());

        return executeWorkItemRequest(req);
    }

    /**
     * @description Validates that the Work Item type is not empty.
     * @param workItemType Work Item type to validate.
     */
    private static void validateWorkItemType(String workItemType) {
        if (String.isBlank(workItemType)) {
            throw new AuraHandledException('Work Item type is required to create in Azure.');
        }
    }

    /**
     * @description Builds the HTTP request to create a Work Item.
     * @param workItemData DTO with Work Item data.
     * @return HttpRequest configured to create the Work Item.
     */
    private static HttpRequest buildCreateWorkItemRequest(WorkItemFormRequest workItemData) {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json-patch+json');
        
        String endpoint = NAMED_CREDENTIAL_CALLOUT + '/' + AZURE_PROJECT + '/_apis/wit/workitems/$' + workItemData.typeOf + '?api-version=' + AZURE_API_VERSION_WORKITEMS;
        req.setEndpoint(endpoint);
        
        return req;
    }

    /**
     * @description Builds the JSON Patch for Work Item creation.
     * Uses metadata-driven approach for flexible field mapping.
     * @param workItemData DTO with Work Item data.
     * @return List<Map<String, Object>> with JSON Patch operations.
     */
    private static List<Map<String, Object>> buildJsonPatch(WorkItemFormRequest workItemData) {
        List<Map<String, Object>> jsonPatch = new List<Map<String, Object>>();
        Map<String, AzureIntegration__mdt> mappings = AzureMetadataService.getActiveFieldMappings();

        for (String mdtLabel : mappings.keySet()) {
            AzureIntegration__mdt mdt = mappings.get(mdtLabel);
            
            if (String.isNotBlank(mdt.Azure_Path__c)) {
                Object fieldValue = getWorkItemFieldValue(workItemData, mdtLabel);
                
                if (isValidValue(fieldValue)) {
                    Map<String, Object> operation = new Map<String, Object>();
                    operation.put('op', 'add');
                    operation.put('path', mdt.Azure_Path__c);
                    operation.put('value', fieldValue);
                    jsonPatch.add(operation);
                    
                    System.debug(LoggingLevel.INFO, 'Added field to JSON Patch - Path: ' + mdt.Azure_Path__c + ', Value: ' + fieldValue);
                }
            }
        }
        
        return jsonPatch;
    }

    /**
     * @description Executes the HTTP request to create the Work Item.
     * @param req Configured HttpRequest.
     * @return Map<String, Object> with Azure response.
     */
    private static Map<String, Object> executeWorkItemRequest(HttpRequest req) {
        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            System.debug(LoggingLevel.INFO, 'Azure Create Work Item Response: ' + responseBody);
            return responseBody;
        } else {
            System.debug(LoggingLevel.ERROR, 'Azure Create Work Item Error: ' + res.getStatusCode() + ' - ' + res.getStatus() + ' - ' + res.getBody());
            throw new AuraHandledException('Error creating Work Item in Azure DevOps: ' + res.getStatusCode() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Gets the value of a specific Work Item field.
     * @param workItemData DTO with Work Item data.
     * @param mdtLabel Metadata label.
     * @return Object with the field value or null if not found.
     */
    private static Object getWorkItemFieldValue(WorkItemFormRequest workItemData, String mdtLabel) {
        switch on mdtLabel {
            when 'Title' { return workItemData.title; }
            when 'Description' { return workItemData.description; }
            when 'FoundBy' { return workItemData.foundBy; }
            when 'RegressionQA' { return workItemData.regressionQA; }
            when 'Severity' { return workItemData.severity; }
            when 'SystemInfo' { return workItemData.salesforceId; }
            when else { return null; }
        }
    }

    /**
     * @description Validates if a value is valid to include in the JSON Patch.
     * @param value Value to validate.
     * @return Boolean true if the value is valid, false otherwise.
     */
    private static Boolean isValidValue(Object value) {
        return value != null && (!(value instanceof String) || String.isNotBlank((String)value));
    }

    /**
     * @description Gets picklist values (Global List) from Azure DevOps.
     * Gets the picklist ID from AzurePicklistId__mdt.
     * @param picklistLabel The Label of the AzurePicklistId__mdt record (e.g. 'Found By', 'Regression QA').
     * @return List<String> with picklist values.
     */
    public static List<String> getPicklistValues(String picklistLabel) {
        List<String> values = new List<String>();

        AzurePicklistId__mdt picklistIdMdt = AzureMetadataService.getPicklistIdByLabel(picklistLabel);

        if (picklistIdMdt == null || String.isBlank(picklistIdMdt.azureId__c)) {
            System.debug(LoggingLevel.WARN, 'Metadata for picklist "' + picklistLabel + '" not found or azureId__c empty in AzurePicklistId__mdt.');
            return values;
        }

        String globalListAzureId = picklistIdMdt.azureId__c;

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');

        String endpoint = NAMED_CREDENTIAL_CALLOUT + '/_apis/work/processes/lists/' + globalListAzureId + '?api-version=' + AZURE_API_VERSION_PICKLISTS;
        req.setEndpoint(endpoint);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            System.debug(LoggingLevel.INFO, 'Azure Get Picklist Values Response: ' + responseBody);
            values = extractPicklistValues(responseBody);
        } else {
            System.debug(LoggingLevel.ERROR, 'Azure Get Picklist Values Error for "' + picklistLabel + '": ' + res.getStatusCode() + ' - ' + res.getStatus() + ' - ' + res.getBody());
            throw new AuraHandledException('Error getting picklist values from Azure: ' + res.getStatusCode() + ' - ' + res.getBody());
        }
        return values;
    }

    /**
     * @description Extracts picklist values from the Azure DevOps response.
     * @param responseBody Deserialized response from Azure DevOps.
     * @return List<String> with extracted picklist values.
     */
    private static List<String> extractPicklistValues(Map<String, Object> responseBody) {
        List<String> values = new List<String>();
        
        if (!responseBody.containsKey('items') || !(responseBody.get('items') instanceof List<Object>)) {
            return values;
        }
        
        List<Object> items = (List<Object>) responseBody.get('items');
        for (Object itemObj : items) {
            String value = extractItemValue(itemObj);
            if (String.isNotBlank(value)) {
                values.add(value);
            }
        }
        
        return values;
    }

    /**
     * @description Extracts the value of an individual picklist item.
     * @param itemObj Item object from Azure response.
     * @return String with extracted value or null if cannot be extracted.
     */
    private static String extractItemValue(Object itemObj) {
        if (itemObj instanceof Map<String, Object>) {
            Map<String, Object> itemMap = (Map<String, Object>) itemObj;
            return itemMap.containsKey('item') ? String.valueOf(itemMap.get('item')) : null;
        } else {
            return String.valueOf(itemObj);
        }
    }

    /**
     * @description Gets Work Item details from Azure DevOps by Azure ID.
     * @param azureWorkItemId The Azure Work Item ID to fetch.
     * @return Map<String, Object> with Work Item details.
     */
    public static Map<String, Object> getWorkItemDetailsByAzureId(String azureWorkItemId) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL_CALLOUT + '/' + AZURE_PROJECT + '/_apis/wit/workitems/'+ azureWorkItemId +'?api-version=' + AZURE_API_VERSION_WIQL);
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');

            Http http = new Http();
            HttpResponse res = http.send(req);

            if(res.getStatusCode() != 200){
                System.debug(LoggingLevel.ERROR, 'Error fetching Work Item: ' + res.getStatusCode() + ' - ' + res.getBody());
                throw new AuraHandledException('Error fetching Work Item from Azure: ' + res.getStatusCode());
            }

            String jsonResponse = res.getBody();
            if (String.isBlank(jsonResponse)) {
                throw new AuraHandledException('Empty response from Azure DevOps API');
            }

            Map<String, Object> resultado = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
            System.debug('Work Item details fetched successfully: ' + resultado);

            return resultado;

        } catch (Exception e) {
            System.debug('Error in getWorkItemDetailsByAzureId: ' + e.getMessage());
            throw new AuraHandledException('Error in Work Item details query: ' + e.getMessage());
        }
    }

    /**
     * @description Updates an existing Work Item in Azure DevOps.
     * This method updates the 'SystemInfo' field (Case ID) in Azure.
     * @param azureWorkItemId The Azure ID of the Work Item to update.
     * @param caseId The Salesforce Case ID to associate.
     * @param fields Current Work Item fields from Azure.
     * @return Map<String, Object> with Azure response.
     */
    public static Map<String, Object> updateWorkItemAzureCaseId(String azureWorkItemId, String caseId, Map<String, Object> fields) {
        List<Map<String, Object>> operations = new List<Map<String, Object>>();

        AzureIntegration__mdt salesforceIdMdt = AzureMetadataService.getMappingByLabel('SystemInfo');
        if (salesforceIdMdt == null || String.isBlank(salesforceIdMdt.Azure_Path__c)) {
            throw new AuraHandledException('Metadata for SystemInfo not found or Azure_Path__c empty.');
        }

        if (fields != null && fields.containsKey('Microsoft.VSTS.TCM.SystemInfo')) {
            String systemInfo = (String) fields.get('Microsoft.VSTS.TCM.SystemInfo');
            System.debug(LoggingLevel.INFO, 'SystemInfo field exists: ' + systemInfo);
            System.debug(LoggingLevel.INFO, 'Updating SystemInfo with Case ID');
            
            Map<String, Object> operation = new Map<String, Object>();
            operation.put('op', 'replace');
            operation.put('path', salesforceIdMdt.Azure_Path__c);
            operation.put('value', 'Salesforce Case ID: ' + caseId);
            operations.add(operation);
        } else {
            System.debug(LoggingLevel.INFO, 'SystemInfo field does not exist, adding new field');
            
            Map<String, Object> operation = new Map<String, Object>();
            operation.put('op', 'add');
            operation.put('path', salesforceIdMdt.Azure_Path__c);
            operation.put('value', 'Salesforce Case ID: ' + caseId);
            operations.add(operation);
        }

        String jsonBody = JSON.serialize(operations);
        System.debug('Azure Update Work Item Request Body: ' + jsonBody);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL_CALLOUT + '/_apis/wit/workitems/' + azureWorkItemId + '?api-version=' + AZURE_API_VERSION_WIQL);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json-patch+json');
        req.setBody(jsonBody);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            System.debug(LoggingLevel.INFO, 'Work Item updated successfully in Azure');
            return responseBody;
        } else {
            System.debug(LoggingLevel.ERROR, 'Error updating Work Item: ' + res.getStatusCode() + ' - ' + res.getBody());
            throw new AuraHandledException('Error updating Work Item in Azure: ' + res.getStatusCode() + ' - ' + res.getBody());
        }
    }
}
