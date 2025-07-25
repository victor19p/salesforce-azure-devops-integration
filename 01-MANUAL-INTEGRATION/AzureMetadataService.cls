/**
 * @description Service to access Custom Metadata Types configuration related to Azure DevOps.
 * Includes field mappings and picklist IDs.
 * 
 * @author Portfolio Demo - Sanitized Version
 * @note This is a sanitized version removing client-specific references
 */
public without sharing class AzureMetadataService {
    // Cache for AzureIntegration__mdt
    private static Map<String, AzureIntegration__mdt> activeFieldMappingsCache;
    // Cache for AzurePicklistId__mdt
    private static Map<String, AzurePicklistId__mdt> azurePicklistIdsCache;

    /**
     * @description Gets and caches all active field mappings from AzureIntegration__mdt.
     * @return Map<String, AzureIntegration__mdt> where the key is the record Label.
     */
    public static Map<String, AzureIntegration__mdt> getActiveFieldMappings() {
        if (activeFieldMappingsCache == null) {
            // Validate CRUD permissions
            if (!AzureIntegration__mdt.SObjectType.getDescribe().isAccessible()) {
                throw new AuraHandledException('You do not have permissions to read AzureIntegration__mdt records');
            }
            
            activeFieldMappingsCache = new Map<String, AzureIntegration__mdt>();
            for (AzureIntegration__mdt mdt : [
                SELECT Label, DeveloperName, Azure_Path__c, Salesforce_Field__c, Active__c 
                FROM AzureIntegration__mdt 
                WHERE Active__c = true
            ]) {
                activeFieldMappingsCache.put(mdt.Label, mdt);
            }
        }
        return activeFieldMappingsCache;
    }

    /**
     * @description Gets a specific mapping from AzureIntegration__mdt by its Label.
     * @param label The Label of the metadata record.
     * @return AzureIntegration__mdt if found, null otherwise.
     */
    public static AzureIntegration__mdt getMappingByLabel(String label) {
        return getActiveFieldMappings().get(label);
    }

    /**
     * @description Gets and caches all Azure picklist IDs from AzurePicklistId__mdt.
     * @return Map<String, AzurePicklistId__mdt> where the key is the record Label.
     */
    public static Map<String, AzurePicklistId__mdt> getAzurePicklistIds() {
        if (azurePicklistIdsCache == null) {
            // Validate CRUD permissions
            if (!AzurePicklistId__mdt.SObjectType.getDescribe().isAccessible()) {
                throw new AuraHandledException('You do not have permissions to read AzurePicklistId__mdt records');
            }
            
            azurePicklistIdsCache = new Map<String, AzurePicklistId__mdt>();
            for (AzurePicklistId__mdt mdt : [
                SELECT Label, DeveloperName, azureId__c 
                FROM AzurePicklistId__mdt
            ]) {
                azurePicklistIdsCache.put(mdt.Label, mdt);
            }
        }
        return azurePicklistIdsCache;
    }

    /**
     * @description Gets a specific picklist ID from AzurePicklistId__mdt by its Label.
     * @param label The Label of the picklist metadata record (e.g. 'Found By', 'Regression QA').
     * @return AzurePicklistId__mdt if found, null otherwise.
     */
    public static AzurePicklistId__mdt getPicklistIdByLabel(String label) {
        return getAzurePicklistIds().get(label);
    }
}
