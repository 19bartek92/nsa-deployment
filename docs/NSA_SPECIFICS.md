# NSA.Crawler - Specyfika wdrożenia

## Różnice wobec Eureka.Crawler

### 1. Źródło danych

| Aspekt | Eureka | NSA |
|--------|--------|-----|
| Portal | eureka.mf.gov.pl | orzeczenia.nsa.gov.pl |
| Typ dokumentów | Interpretacje podatkowe | Orzeczenia sądowe |
| API | REST API z paginacją | Scraping HTML + bezpośrednie linki |

### 2. Format dokumentów

**Eureka:**
- Treść dostępna jako HTML/plain text
- Bezpośrednia konwersja do DOCX

**NSA:**
- Dokumenty w formacie RTF
- Wymagana konwersja: RTF → DOCX via LibreOffice
- Kontener wymaga zainstalowanego LibreOffice (`libreoffice-writer`)

### 3. Struktura uzasadnień

NSA ma dwuetapowy proces publikacji:
1. Sentencja orzeczenia (dostępna od razu)
2. Uzasadnienie (publikowane później, średnio 2-4 tygodnie)

W związku z tym NSA.Crawler ma dodatkowy mechanizm `pending_justifications`:
- Śledzi orzeczenia bez uzasadnień
- Sprawdza codziennie czy uzasadnienie jest dostępne
- Aktualizuje dokument gdy uzasadnienie się pojawi

### 4. Wymagania zasobów

| Zasób | Eureka | NSA | Powód |
|-------|--------|-----|-------|
| CPU | 0.5 | 1.0 | Konwersja LibreOffice |
| Memory | 1Gi | 2Gi | Buforowanie RTF + konwersja |
| Timeout delta | 1h | 1h | - |
| Timeout backfill | 24h | 24h | - |

### 5. Rate limiting

NSA wymaga bardziej konserwatywnego rate limitingu:
- 10 requests/minute (vs 40 dla Eureka)
- 100 requests/hour (vs 300 dla Eureka)
- Min delay: 2000ms (vs natychmiastowe dla Eureka)

Portal NSA jest bardziej wrażliwy na obciążenie.

---

## Konfiguracja środowiskowa

### Zmienne środowiskowe (różnice)

```bash
# Cosmos DB - inna baza
Cosmos__Database=nsa
Cosmos__DecisionsCollection=decisions
Cosmos__PendingJustificationsCollection=pending_justifications
Cosmos__FailedDocumentsCollection=failed_documents

# SharePoint - inny folder bazowy
SharePoint__BaseFolder=NSA_docs

# Konwersja - wymagane dla LibreOffice
Conversion__LibreOfficePath=/usr/bin/soffice
Conversion__TimeoutSeconds=120
Conversion__TempDirectory=/tmp/nsa-conversion

# NSA specific
Nsa__BackfillStartDate=2024-01-01
Nsa__BackfillEndDate=2024-12-31
Nsa__DeltaWindowDays=14
Nsa__SixMonthRuleMonths=6
```

---

## Harmonogram zadań

| Job | CRON | Opis |
|-----|------|------|
| `eureka-delta` | `10 4 * * *` | Eureka o 4:10 UTC |
| `nsa-delta` | `10 5 * * *` | NSA o 5:10 UTC |

Rozdzielone o godzinę aby uniknąć jednoczesnego obciążenia infrastruktury.

---

## Dockerfile - dodatkowe zależności

NSA.Crawler wymaga LibreOffice w obrazie Docker:

```dockerfile
# Dodatkowe pakiety dla NSA.Crawler
RUN apt-get update && apt-get install -y --no-install-recommends \
    libreoffice-writer \
    && rm -rf /var/lib/apt/lists/*
```

---

## Monitoring

### Logi do śledzenia

```
# Sukces konwersji RTF→DOCX
"Successfully converted RTF to DOCX"

# Błąd konwersji
"LibreOffice conversion failed"

# Pending justifications
"Found {N} pending justifications to check"
"Justification now available for {sygnatura}"

# Failed documents retry
"Retry phase: Found {N} failed documents eligible for retry"
"Successfully retried DOCX upload for {sygnatura}"
```

### Metryki Cosmos DB

Monitoruj kolekcje:
- `decisions` - główne orzeczenia
- `pending_justifications` - orzeczenia czekające na uzasadnienie
- `failed_documents` - dokumenty wymagające retry
- `rate_limiter_state` - stan rate limitera

---

## Troubleshooting

### LibreOffice nie działa w kontenerze

```bash
# Test wewnątrz kontenera
docker exec -it <container> /bin/bash
/usr/bin/soffice --headless --convert-to docx --outdir /tmp test.rtf
```

### Timeout podczas konwersji

Zwiększ `Conversion__TimeoutSeconds` (default: 120s)

### Rate limiter blokuje requesty

Stan rate limitera jest persystowany w `rate_limiter_state`.
Reset:
```bash
# MongoDB
db.rate_limiter_state.deleteMany({})
```

### Orphaned documents (docx_uploaded=false)

Crawler automatycznie wykrywa i ponawia upload na starcie.
Sprawdź logi: `"Retry phase: Checking for orphaned and failed documents"`
