# NSA.Crawler Bicep Templates

Infrastructure as Code templates for deploying NSA.Crawler to Azure Container Apps.

## Files

| File | Description |
|------|-------------|
| `main.bicep` | Main Bicep template - adds NSA jobs to existing Eureka infrastructure |
| `main.json` | Compiled ARM template for "Deploy to Azure" button |
| `parameters.example.json` | Example parameters file for manual deployment |

## Prerequisites

This deployment **requires** existing Eureka.Crawler infrastructure:
- Container Apps Environment
- User-Assigned Managed Identity (with Key Vault and ACR access)
- Key Vault (with SharePoint secrets)
- Azure Container Registry
- Cosmos DB account

## Manual Deployment

```bash
# Login to Azure
az login

# Set subscription (if needed)
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Deploy to existing Eureka resource group
az deployment group create \
  --resource-group rg-eureka-crawler \
  --template-file main.bicep \
  --parameters \
    keyVaultName="kv-eureka-xxxx" \
    acrName="acreurekaxxxx" \
    cosmosAccountName="cosmos-eureka-xxxx"
```

## Updating the Template

After modifying `main.bicep`, recompile to JSON:

```bash
az bicep build --file main.bicep --outfile main.json
```

## Resources Created

| Resource | Name | Description |
|----------|------|-------------|
| Cosmos DB Database | `nsa` | MongoDB database for NSA decisions |
| Container Apps Job | `nsa-backfill` | Manual trigger, 24h timeout |
| Container Apps Job | `nsa-delta` | CRON 5:10 UTC daily, 1h timeout |

## Configuration Differences from Eureka

| Setting | Eureka | NSA |
|---------|--------|-----|
| `Cosmos__Database` | `eureka` | `nsa` |
| `SharePoint__BaseFolder` | `Eureka_docs` | `NSA_docs` |
| CRON schedule | `10 4 * * *` | `10 5 * * *` |
| CPU | 0.5 | 1.0 |
| Memory | 1Gi | 2Gi |

NSA requires more resources due to LibreOffice RTF→DOCX conversion.
