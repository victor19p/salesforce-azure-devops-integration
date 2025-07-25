# Phase 1: Manual Integration
*Interactive Work Item Creation and Linking*

## 🎯 Purpose
This phase provides **on-demand integration** capabilities, allowing users to manually create and link Azure DevOps Work Items from Salesforce Cases through interactive Lightning Web Component forms.

## � Key Components

### Core Classes
- **`WorkOrderService.cls`** - Main service orchestrator and entry point for LWC
- **`AzureDevOpsIntegration.cls`** - Azure API communication layer  
- **`WorkItemRepository.cls`** - Data access layer for Salesforce objects
- **`AzureMetadataService.cls`** - Configuration management via Custom Metadata
- **`WorkItemFormRequest.cls`** - Data Transfer Object for form validation

## � Functionality

### 1. Create Work Items (Salesforce → Azure)
```
User fills LWC form → Server validation → Queueable job → Azure API call → 
Salesforce record creation → Case association
```

### 2. Link Existing Work Items (Azure → Salesforce)  
```
User provides Azure Work Item ID → Fetch from Azure → Create SF record → 
Update Azure with Case ID → Create association
```

## 🏗️ Architecture Patterns
- **Service Layer Pattern**: Clean separation of concerns
- **Repository Pattern**: Encapsulated data access
- **DTO Pattern**: Type-safe data transfer
- **Queueable Pattern**: Asynchronous API processing
- **Metadata-Driven**: Dynamic field mappings

## 📊 Use Cases
- **Customer Support**: Create bugs/features from support cases
- **Project Management**: Link existing development work to customer requests
- **Traceability**: Maintain bidirectional visibility between systems

## ⚙️ Setup Requirements
1. Deploy all classes to Salesforce org
2. Configure Named Credential `Azure_DevOps_Integration` for Azure authentication
3. Create Custom Metadata records for field mappings
4. Deploy custom objects `Work_Item_Azure__c` and `Case_Work_Item__c`
5. Configure appropriate user permissions

---
*This phase establishes the foundation for Azure-Salesforce integration with user-driven workflows.*
