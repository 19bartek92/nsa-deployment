# NSA.Crawler - Wdrożenie w Azure

**Rozszerzenie istniejącej infrastruktury Eureka** o joby NSA.Crawler - systemu pobierania orzeczeń z orzeczenia.nsa.gov.pl.

> **Uwaga:** To repozytorium zawiera **tylko pliki deployment**. Kod aplikacji jest utrzymywany osobno.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2F19bartek92%2Fnsa-deployment%2Fmain%2Fbicep%2Fmain.json)

---

## Wymagania wstępne

**WAŻNE:** Ten deployment wymaga wcześniejszego wdrożenia Eureka.Crawler!

NSA.Crawler wykorzystuje istniejącą infrastrukturę Eureka:
- ✅ Ten sam Azure Container Registry (ACR)
- ✅ Ten sam Azure Key Vault (te same sekrety SharePoint)
- ✅ Ten sam Azure Cosmos DB account (inna baza danych: `nsa`)
- ✅ Ten sam Container Apps Environment
- ✅ Ta sama User-Assigned Managed Identity (UAMI)

### Przed deployment

1. **Eureka deployment musi być ukończony** - [eureka-deployment](https://github.com/19bartek92/eureka-deployment)
2. **Zbierz outputy z Eureka deployment:**
   - Resource Group name (np. `rg-eureka-crawler`)
   - Environment name (np. `env-eureka-crawler`)
   - UAMI name (np. `uami-eureka-crawler`)
   - Key Vault name (np. `kv-eureka-abc123`)
   - ACR name (np. `acreurekaxxxx`)
   - Cosmos DB account name (np. `cosmos-eureka-xxxx`)

---

## Co zostanie wdrożone?

Kliknij przycisk "Deploy to Azure" powyżej aby utworzyć:

- ✅ **Cosmos DB Database** - baza `nsa` w istniejącym Cosmos account
- ✅ **2 Container Apps Jobs** (w istniejącym environment):
  - `nsa-backfill` - ręczne uruchamianie (pełna synchronizacja, 24h timeout)
  - `nsa-delta` - codzienne aktualizacje o 5:10 UTC (1h timeout)

**Co NIE jest tworzone** (używa istniejących zasobów Eureka):
- Resource Group
- Container Apps Environment
- User-Assigned Managed Identity
- Key Vault
- ACR

**Czas wdrożenia:** ~3-5 minut

---

## Parametry deployment

| Parametr | Opis | Przykład | Źródło |
|----------|------|----------|--------|
| **Resource Group** | Istniejąca RG z Eureka | `rg-eureka-crawler` | Eureka output |
| **Location** | Region Azure | `West Europe` | - |
| **Environment Name** | Istniejące Container Apps Environment | `env-eureka-crawler` | Eureka output |
| **UAMI Name** | Istniejące Managed Identity | `uami-eureka-crawler` | Eureka output |
| **Key Vault Name** | Istniejący Key Vault | `kv-eureka-abc123` | Eureka output |
| **ACR Name** | Istniejący Container Registry | `acreurekaxxxx` | Eureka output |
| **Cosmos Account Name** | Istniejący Cosmos DB account | `cosmos-eureka-xxxx` | Eureka output |
| **Image Name** | Nazwa obrazu Docker NSA | `nsa-crawler` | Default |
| **Image Tag** | Tag obrazu | `latest` | Default |

---

## Architektura

```
┌────────────────────────────────────────────────────────────────────┐
│              Azure Container Apps Environment                       │
│              (env-eureka-crawler - ISTNIEJĄCE)                     │
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │ Eureka Backfill │  │ Eureka Delta    │  │ NSA Backfill    │     │
│  │ (istniejący)    │  │ (istniejący)    │  │ (NOWY)          │     │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘     │
│           │                    │                    │               │
│  ┌────────┴────────────────────┴────────────────────┴────────┐     │
│  │                                                           │     │
│  │  ┌─────────────────┐                                      │     │
│  │  │ NSA Delta       │                                      │     │
│  │  │ (NOWY)          │                                      │     │
│  │  │ CRON: 5:10 UTC  │                                      │     │
│  │  └────────┬────────┘                                      │     │
│  │           │                                               │     │
│  │           └──────────────┬────────────────────────────────┘     │
│  │                          │                                      │
│  │                  ┌───────▼─────────┐                            │
│  │                  │ UAMI (Identity) │  ← ISTNIEJĄCE              │
│  │                  │ - Key Vault     │                            │
│  │                  │ - Cosmos DB     │                            │
│  │                  │ - ACR Pull      │                            │
│  │                  └───────┬─────────┘                            │
│  └──────────────────────────┼──────────────────────────────────────┘
└─────────────────────────────┼──────────────────────────────────────┘
                              │
           ┌──────────────────┼─────────────────┐
           │                  │                 │
     ┌─────▼─────┐    ┌───────▼───────┐        │
     │   ACR     │    │  Key Vault    │        │
     │ (ISTN.)   │    │  (ISTNIEJĄCY) │        │
     │           │    │  ┌──────────┐ │        │
     │  Images:  │    │  │cosmos    │ │        │
     │  eureka   │    │  │sp-*      │ │        │
     │  nsa ←NEW │    │  └──────────┘ │        │
     └───────────┘    └───────────────┘        │
                                               │
           ┌───────────────────────────────────┘
           │
     ┌─────▼─────┐     ┌────────┐     ┌──────────┐
     │Cosmos DB  │     │SharePnt│     │ NSA API  │
     │(ISTNIEJĄCY)│    │(Graph) │     │(Public)  │
     │           │     │        │     │          │
     │ eureka DB │     │Eureka_ │     │orzeczenia│
     │ nsa DB ←  │     │docs    │     │.nsa.gov  │
     │    NEW    │     │NSA_docs│     │.pl       │
     └───────────┘     │ ← NEW  │     └──────────┘
                       └────────┘
```

---

## SharePoint - separacja danych

NSA.Crawler używa **tego samego SharePoint Site i Drive** co Eureka, ale zapisuje pliki w **osobnym folderze**:

| Crawler | BaseFolder | Przykładowa ścieżka |
|---------|------------|---------------------|
| Eureka | `Eureka_docs` | `/Eureka_docs/202601/dokument.docx` |
| NSA | `NSA_docs` | `/NSA_docs/202601/I_OSK_123_21.docx` |

Ta separacja jest konfigurowana w aplikacji (nie w deployment), więc sekrety SharePoint są **identyczne** dla obu crawlerów.

---

## Po wdrożeniu

✅ **Deployment zakończony!**

> **UWAGA:** Joby zostały utworzone z **placeholder image**. Developer musi zaktualizować image po zpushowaniu do ACR.

**Outputy deployment:**

```
NSA Backfill Job: nsa-backfill
NSA Delta Job: nsa-delta
Full Image URL: acreureka.azurecr.io/nsa-crawler:latest
Update NSA Backfill: az containerapp job update -n nsa-backfill -g rg-eureka-crawler --image acreureka.azurecr.io/nsa-crawler:latest --registry-server acreureka.azurecr.io --registry-identity <uami-id>
Update NSA Delta: az containerapp job update -n nsa-delta -g rg-eureka-crawler --image acreureka.azurecr.io/nsa-crawler:latest --registry-server acreureka.azurecr.io --registry-identity <uami-id>
```

**Przekaż te wartości developerowi.**

---

## Koszty (przyrostowe)

NSA.Crawler dodaje minimalne koszty do istniejącej infrastruktury Eureka:

| Serwis | Koszt przyrostowy/miesiąc |
|--------|---------------------------|
| Container Apps Jobs (2 dodatkowe) | ~$5-10 |
| Cosmos DB (dodatkowa baza `nsa`) | ~$5-15* |
| **Total przyrost** | **~$10-25** |

*Zależnie od volumenu danych

**Pełna infrastruktura (Eureka + NSA):** ~$90-130/miesiąc

---

## Różnice między Eureka a NSA

| Aspekt | Eureka.Crawler | NSA.Crawler |
|--------|----------------|-------------|
| Źródło danych | eureka.mf.gov.pl | orzeczenia.nsa.gov.pl |
| Typ dokumentów | Interpretacje podatkowe | Orzeczenia sądowe |
| Format źródłowy | HTML/plain text | RTF |
| Konwersja | Bezpośrednia | RTF → DOCX (LibreOffice) |
| Cosmos Database | `eureka` | `nsa` |
| SharePoint folder | `Eureka_docs` | `NSA_docs` |
| Delta CRON | 4:10 UTC | 5:10 UTC |
| Timeout backfill | 24h | 24h |

---

## Licencja

**Copyright © 2025. Wszelkie prawa zastrzeżone.**

Ta konfiguracja deployment jest dostarczona "jak jest" wyłącznie do celów referencyjnych i wdrożeniowych.
Kod źródłowy aplikacji jest licencjonowany osobno i nie jest zawarty w tym repozytorium.

---

**Ostatnia aktualizacja:** 2025-01-29
**Kompatybilne z:** NSA.Crawler v1.x
**Wymaga:** Eureka.Crawler deployment
**Utrzymywane przez:** bartoszpalmi@hotmail.com
