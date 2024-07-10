---
layout: default
parent: Troubleshooting
title: Common errors
description: 'Details and solutions for common issues you may experience.'
permalink: /resources/troubleshooting/troubleshooting-errocode
---

<span class="fs-9 d-block mb-4">Error codes</span>
List of most common error messages.
{: .fs-6 .fw-300 }
---

# 📇 Table of Contents
- [📇 Table of Contents](#-table-of-contents)
  - [The \<name\> resource provider is not registered in subscription \<guid\>](#the-name-resource-provider-is-not-registered-in-subscription-guid)
  - [x\_PricingSubcategory shows the commitment discount ID](#x_pricingsubcategory-shows-the-commitment-discount-id)
  - [Power BI: Reports are empty (no data)](#power-bi-reports-are-empty-no-data)
    - [FinOps hubs: Ingestion container is empty](#finops-hubs-ingestion-container-is-empty)
    - [FinOps hubs: Files available in the ingestion container](#finops-hubs-files-available-in-the-ingestion-container)
  - [Power BI: Exception of type 'Microsoft.Mashup.Engine.Interface.ResourceAccessForbiddenException' was thrown](#power-bi-exception-of-type-microsoftmashupengineinterfaceresourceaccessforbiddenexception-was-thrown)
  - [Power BI: The remote name could not be resolved: '\<storage-account\>.dfs.core.windows.net'](#power-bi-the-remote-name-could-not-be-resolved-storage-accountdfscorewindowsnet)
  - [Power BI: We cannot convert the value null to type Logical](#power-bi-we-cannot-convert-the-value-null-to-type-logical)
  - [FinOps hubs: RoleAssignmentUpdateNotPermitted](#finops-hubs-roleassignmentupdatenotpermitted)
  - [FinOps hubs: We cannot convert the value null to type Table](#finops-hubs-we-cannot-convert-the-value-null-to-type-table)
  - [FinOps hubs: Deployment failed with RoleAssignmentUpdateNotPermitted error](#finops-hubs-deployment-failed-with-roleassignmentupdatenotpermitted-error)
  - [Data Factory:  Operation on target Convert CSV failed: ErrorCode=MappingColumnNameNotFoundInSourceFile,'Type=Microsoft.DataTransfer.Common.Shared.HybridDeliveryException,Message=Column 'AvailabilityZone' specified in column mapping cannot be found](#data-factory--operation-on-target-convert-csv-failed-errorcodemappingcolumnnamenotfoundinsourcefiletypemicrosoftdatatransfercommonsharedhybriddeliveryexceptionmessagecolumn-availabilityzone-specified-in-column-mapping-cannot-be-found)




## The \<name> resource provider is not registered in subscription \<guid>

Open the subscription in the Azure portal, then select **Settings** > **Resource providers**, select the resource provider row (e.g., Microsoft.EventGrid), then select the **Register** command at the top of the page. Registration may take a few minutes.

---

## x_PricingSubcategory shows the commitment discount ID

Cost Management exports before Feb 28, 2024 had a bug where `x_PricingSubcategory` was being set incorrectly for committed usage. You should expect to see values like `Committed Spend` and `Committed Usage`. Instead, you may see values like:

- `Committed /providers/Microsoft.BillingBenefits/savingsPlanOrders/###/savingsPlans/###`
- `Committed /providers/Microsoft.Capacity/reservationOrders/###/reservations/###`

If you see these values, please re-export the cost data for that month. If you need to export data for an older month that is not available, please contact support to request the data be exported for you to resolve the data quality issue from the previous export runs.

---

## Power BI: Reports are empty (no data)

If you don't see any data in your Power BI or other reports or tools, try the following based on your data source:

1. If using the Cost Management connector in Power BI, check the `Billing Account ID` and `Number of Months` parameters to ensure they're set correctly. Keep in mind old billing accounts may not have data in recent months.
2. If using FinOps hubs, check the storage account to ensure data is populated in the **ingestion** container. You should see either a **providers** or **subscriptions** folder. Use the sections below to troubleshoot further.

### FinOps hubs: Ingestion container is empty

If the **ingestion** container is empty, open the Data Factory instance in Data Factory Studio and select **Manage** > **Author** > **Triggers** and verify the **msexports_FileAdded** trigger is started. If not, start it.

If the trigger fails to start with a "resource provider is not registered" error, open the subscription in the Azure portal, then select **Settings** > **Resource providers**, select the **Microsoft.EventGrid** row, then select the **Register** command at the top of the page. Registration may take a few minutes.

After registration completes, start the **msexports_FileAdded** trigger again.

After the trigger is started, re-run all connected Cost Management exports. Data should be fully ingested within 10-20 minutes, depending on the size of the account.

If the issue persists, check if Cost Management exports are configured with file partitioning enabled. If you find it disabled, turn it on and re-run the exports.

Confirm the **ingestion** container is populated and refresh your reports or other connected tools.

### FinOps hubs: Files available in the ingestion container

If the **ingestion** container is not empty, confirm whether you have **parquet** or **csv.gz** files by drilling into the folders.

Once you know, verify the **FileType** parameter is set to `.parquet` or `.gz` in the Power BI report. See [Connect to your data](../_reporting/power-bi/README.md#-connect-to-your-data) for details.

If you're using another tool, ensure it supports the file type you're using.

---

## Power BI: Exception of type 'Microsoft.Mashup.Engine.Interface.ResourceAccessForbiddenException' was thrown

Indicates that the account loading data in Power BI does not have the [Storage Blob Data Reader role](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-reader). Grant this role to the account loading data in Power BI.

---

## Power BI: The remote name could not be resolved: '\<storage-account>.dfs.core.windows.net'

Indicates that the storage account name is incorrect. If using FinOps hubs, verify the **StorageUrl** parameter from the deployment. See [Connect to your data](../_reporting/power-bi/README.md#-connect-to-your-data) for details.

---

## Power BI: We cannot convert the value null to type Logical

Indicates that the **Billing Account ID** parameter is empty. If using FinOps hubs, set the value to the desired billing account ID. If you do not have access to the billing account or do not want to include commitment purchases and refunds, set the value to `0` and open the **CostDetails** query in the advanced editor and change the `2` to a `1`. This will inform the report to not load actual/billed cost data from the Cost Management connector. See [Connect to your data](../_reporting/power-bi/README.md#-connect-to-your-data) for details.

Applicable versions: **0.1 - 0.1.1** (fixed in **0.2**)

---

## FinOps hubs: RoleAssignmentUpdateNotPermitted

Full error message:

> _Tenant ID, application ID, principal ID, and scope are not allowed to be updated._

This error happens when you try to update an Azure role assignment with a new identity. This can happen in FinOps hubs if you delete a managed identity and re-deploy because the managed identity will be created with the same name but a new principal ID. ARM cannot use the principal ID to generate a unique role assignment ID, so the deployment tries to reuse the old role assignment ID, which can't be updated and results in the error. To prevent this in the future, do not delete the managed identities that are created as part of the deployment. But since you're here, there are two options:

1. Delete the resource group and re-deploy.
   - If you go this route, also make sure the Key Vault instance was also fully deleted by going to [Key vaults](https://portal.azure.com/#browse/Microsoft.KeyVault%2Fvaults) > **Manage deleted vaults** and purge the deleted vault, if it was soft-deleted.
2. Manually delete the role assignment in the Azure portal.
   - Go to check role assignments for the resource group, ADF instance, and storage account and remove any unidentified accounts that have a direct assignment on those scopes.

---

## FinOps hubs: We cannot convert the value null to type Table

This error typically indicates that data was not ingested into the **ingestion** container.

If you just upgraded to FinOps hubs 0.2, this may be due to the Power BI report being old (from 0.1.x) or because you are not using FOCUS exports. See the [Upgrade guide](../_reporting/hubs/upgrade.md) for details.

See [Reports are empty (no data)](#power-bi-reports-are-empty-no-data) for additional troubleshooting steps.

---

## FinOps hubs: Deployment failed with RoleAssignmentUpdateNotPermitted error

If you've deleted FinOps Hubs and are attempting to redeploy it with the same values, including the Managed Identity name, you might encounter the following known issue:

```json
"code": "RoleAssignmentUpdateNotPermitted",
"message": "Tenant ID, application ID, principal ID, and scope are not allowed to be updated."
```

To fix that issue you will have to remove the stale identity:

- Navigate to the storage account and select **Access control (IAM)** in the menu.
- Select the **Role assignments** tab.
- Find any role assignments with an "unknown" identity and delete them.

---

## Data Factory:  Operation on target Convert CSV failed: ErrorCode=MappingColumnNameNotFoundInSourceFile,'Type=Microsoft.DataTransfer.Common.Shared.HybridDeliveryException,Message=Column 'AvailabilityZone' specified in column mapping cannot be found

If the ingestion pipeline is not running and it is showing this error message:

```json
Operation on target Convert CSV failed: ErrorCode=MappingColumnNameNotFoundInSourceFile,'Type=Microsoft.DataTransfer.Common.Shared.HybridDeliveryException,Message=Column 'AvailabilityZone' specified in column mapping cannot be found in 'part_0_0001.csv' source file.,Source=Microsoft.DataTransfer.ClientLibrary,'
```
**Solution:** This error means that the Cost Export is not set to FOCUS 1.0 (Preview). Review the export settings and ensure it is configured to FOCUS 1.0 (Preview), then run the pipeline again.
---
