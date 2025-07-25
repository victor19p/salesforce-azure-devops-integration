/**
 * @description DTO (Data Transfer Object) for encapsulating Work Item form data for creation/update.
 * The properties of this class must match the properties that the LWC sends in its JSON.
 * 
 * @author Portfolio Demo - Sanitized Version
 * @note This is a sanitized version removing client-specific references
 */
public class WorkItemFormRequest {

    @AuraEnabled
    public String typeOf; 

    @AuraEnabled
    public String title;

    @AuraEnabled
    public String foundBy; 

    @AuraEnabled
    public String regressionQA; 

    @AuraEnabled
    public String severity; 

    @AuraEnabled
    public String salesforceId; 

    @AuraEnabled
    public String description; 

    /**
     * @description Validates if the form request has the minimum required data.
     * @return Boolean true if valid, false otherwise.
     */
    public Boolean isValid() {
        return !String.isBlank(this.typeOf) && !String.isBlank(this.title);
    }
}
