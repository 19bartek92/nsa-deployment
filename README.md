# NSA.Crawler - Wdrożenie w Azure

**Izolowane wdrożenie NSA.Crawler** z wykorzystaniem współdzielonej infrastruktury Eureka.

> **Uwaga:** To repozytorium zawiera **tylko pliki deployment**. Kod aplikacji jest utrzymywany osobno.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2F19bartek92%2Fnsa-deployment%2Fmain%2Fbicep%2Fmain.json)

---

## Architektura dwóch Resource Groups

```
┌─────────────────────────────────────────────────────────────────┐
│  rg-eureka-crawler (SHARED - już istnieje)                      │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Environment  │  │    UAMI      │  │  Key Vault   │          │
│  │ (Container   │  │ (Managed     │  │ (SharePoint  │          │
│  │  Apps)       │  │  Identity)   │  │  secrets)    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                            │
│  │     ACR      │  │  Cosmos DB   │                            │
│  │ (Container   │  │  Account     │                            │
│  │  Registry)   │  │  ├─ eureka   │                            │
│  │  ├─ eureka   │  │  └─ nsa ←NEW │                            │
│  │  └─ nsa ←NEW │  └──────────────┘                            │
│  └──────────────┘                                              │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                            │
│  │ eureka-      │  │ eureka-      │  ← Eureka jobs             │
│  │ backfill     │  │ delta        │    (już istnieją)          │
│  └──────────────┘  └──────────────┘                            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  rg-nsa-crawler (ISOLATED - ten deployment)                     │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                            │
│  │ nsa-         │  │ nsa-         │  ← NSA jobs                │
│  │ backfill     │  │ delta        │    (NOWE)                  │
│  └──────────────┘  └──────────────┘                            │
│                                                                 │
│  🔗 References shared infrastructure from rg-eureka-crawler    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Korzyści izolacji

| Aspekt | Opis |
|--------|------|
| **Bezpieczne testowanie** | Możesz usunąć `rg-nsa-crawler` bez wpływu na Eurekę |
| **Łatwy rollback** | `az group delete -n rg-nsa-crawler --yes` |
| **Jasne koszty** | Azure Cost Management per RG |
| **Niezależny lifecycle** | NSA może być wdrażane/usuwane niezależnie |
| **Minimalne ryzyko** | Błąd w NSA deployment nie uszkodzi Eureki |

---

## Wymagania wstępne

**WAŻNE:** Ten deployment wymaga wcześniejszego wdrożenia Eureka.Crawler!

### Przed deployment

1. **Eureka deployment musi być ukończony** - [eureka-deployment](https://github.com/19bartek92/eureka-deployment)
2. **Zbierz outputy z Eureka deployment:**

| Parametr | Gdzie znaleźć | Przykład |
|----------|---------------|----------|
| Shared Resource Group | Portal → Resource Groups | `rg-eureka-crawler` |
| Environment name | Portal → Container Apps Environments | `env-eureka-crawler` |
| UAMI name | Portal → Managed Identities | `uami-eureka-crawler` |
| Key Vault name | Portal → Key Vaults | `kv-eureka-abc123` |
| ACR name | Portal → Container Registries | `acreurekaxxxx` |
| Cosmos DB account | Portal → Azure Cosmos DB | `cosmos-eureka-xxxx` |

---

## Co zostanie wdrożone?

**W nowej RG (`rg-nsa-crawler`):**
- ✅ `nsa-backfill` - Container Apps Job (ręczne, 24h timeout)
- ✅ `nsa-delta` - Container Apps Job (CRON 5:10 UTC, 1h timeout)

**W shared RG (`rg-eureka-crawler`):**
- ✅ Cosmos DB database `nsa` (w istniejącym account)

**Czas wdrożenia:** ~3-5 minut

---

## Parametry deployment

| Parametr | Opis | Default |
|----------|------|---------|
| **Resource Group** | **NOWA** RG dla NSA | `rg-nsa-crawler` |
| **Location** | Region Azure | `West Europe` |
| **Shared Resource Group** | Istniejąca RG z Eureka | `rg-eureka-crawler` |
| **Environment Name** | Istniejące Environment | `env-eureka-crawler` |
| **UAMI Name** | Istniejące Managed Identity | `uami-eureka-crawler` |
| **Key Vault Name** | Istniejący Key Vault | _(wymagane)_ |
| **ACR Name** | Istniejący Container Registry | _(wymagane)_ |
| **Cosmos Account Name** | Istniejący Cosmos DB | _(wymagane)_ |

---

## Deployment krok po kroku

### 1. Utwórz nową Resource Group dla NSA

```bash
az group create --name rg-nsa-crawler --location westeurope
```

### 2. Deploy (przycisk lub CLI)

**Opcja A: Przycisk "Deploy to Azure"** (góra README)

**Opcja B: Azure CLI**
```bash
az deployment group create \
  --resource-group rg-nsa-crawler \
  --template-file bicep/main.bicep \
  --parameters \
    sharedResourceGroupName="rg-eureka-crawler" \
    keyVaultName="kv-eureka-XXXXX" \
    acrName="acreurekaXXXXX" \
    cosmosAccountName="cosmos-eureka-XXXXX"
```

### 3. Po deployment - przekaż developerowi outputy

```
NSA Backfill Job: nsa-backfill
NSA Delta Job: nsa-delta
NSA Resource Group: rg-nsa-crawler
Full Image URL: acreureka.azurecr.io/nsa-crawler:latest
```

---

## Operacje po wdrożeniu

### Aktualizacja image (developer)

```bash
# 1. Build i push
docker build -t acreureka.azurecr.io/nsa-crawler:v1.0.0 .
docker push acreureka.azurecr.io/nsa-crawler:v1.0.0

# 2. Update jobs
az containerapp job update -n nsa-backfill -g rg-nsa-crawler \
  --image acreureka.azurecr.io/nsa-crawler:v1.0.0

az containerapp job update -n nsa-delta -g rg-nsa-crawler \
  --image acreureka.azurecr.io/nsa-crawler:v1.0.0
```

### Usunięcie NSA (bezpieczne!)

```bash
# Usuwa TYLKO NSA joby, NIE dotyka Eureki
az group delete --name rg-nsa-crawler --yes

# Opcjonalnie: usuń też NSA database z Cosmos
az cosmosdb mongodb database delete \
  --account-name cosmos-eureka-XXXXX \
  --name nsa \
  --resource-group rg-eureka-crawler
```

### Rollback do poprzedniej wersji

```bash
az containerapp job update -n nsa-backfill -g rg-nsa-crawler \
  --image acreureka.azurecr.io/nsa-crawler:v0.9.0
```

---

## SharePoint - separacja danych

NSA używa **tego samego SharePoint** co Eureka, ale zapisuje w **osobnym folderze**:

| Crawler | BaseFolder | Przykładowa ścieżka |
|---------|------------|---------------------|
| Eureka | `Eureka_docs` | `/Eureka_docs/202601/dokument.docx` |
| NSA | `NSA_docs` | `/NSA_docs/202601/I_OSK_123_21.docx` |

---

## Koszty (przyrostowe)

| Serwis | Koszt/miesiąc |
|--------|---------------|
| Container Apps Jobs (NSA) | ~$5-10 |
| Cosmos DB (database `nsa`) | ~$5-15 |
| **Total przyrost** | **~$10-25** |

---

## Licencja

**Copyright © 2025. Wszelkie prawa zastrzeżone.**

---

**Ostatnia aktualizacja:** 2025-01-29
**Kompatybilne z:** NSA.Crawler v1.x
**Wymaga:** Eureka.Crawler deployment (rg-eureka-crawler)
**Utrzymywane przez:** bartoszpalmi@hotmail.com
