# Enterprise Integration Platform — Smart Meter Data Pipeline

A three-service pipeline for ingesting, validating, and persisting smart meter telemetry:

```
curl / client  →  Java ingestion gateway  →  Python transformation API  →  PostgreSQL
                   (Spring Boot, :8081)       (FastAPI, :8082)              (:5432)
```

- **`01-java-ingestion-service`** — Spring Boot gateway that accepts bulk meter payloads, validates them, and forwards them downstream (with automatic retries).
- **`02-python-transformation-api`** — FastAPI service that authenticates the request, validates the schema, computes usage analytics, and persists the data.
- **PostgreSQL** — stores the transformed readings in the `smart_meter_intervals` table.

All three run as containers orchestrated by `docker-compose.yml` — no local Java, Maven, or Python installation is required to run and test the stack.

## Prerequisites

- **Docker Desktop** (with the Compose plugin, included by default in current versions)
- **Git**

### Windows-specific notes

If Docker Desktop reports "Virtualization support not detected":
1. Open Task Manager → Performance → CPU, and confirm virtualization is enabled. If it's disabled, it must be turned on in BIOS first.
2. If virtualization is enabled but Docker still won't start, run in an elevated PowerShell:
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All
   ```
3. Restart the computer.
4. If Docker then reports "Windows Subsystem for Linux is not installed", run in an elevated PowerShell:
   ```powershell
   wsl --install
   ```
5. Relaunch Docker Desktop and wait for the "Engine started" message.

## Quick Start

```bash
git clone https://github.com/nikmar0808/enterprise-integration-project.git
cd enterprise-integration-project
docker compose up --build -d
```

Check that all three containers are running:

```bash
docker compose ps
```

Verify each service is up:

```bash
curl http://localhost:8081/health
# {"status":"UP"}

curl http://localhost:8082/
# {"status":"operational","engine":"FastAPI", ...}
```

## Testing the Pipeline

### End-to-end: send a payload through the Java gateway

**Windows Command Prompt:**
```cmd
curl -X POST http://localhost:8081/api/v1/ingest/bulk -H "Content-Type: application/json" -d "{\"meter_id\": \"MTR-99-NORTH\", \"grid_zone\": \"ZONE-A\", \"readings\": [{\"timestamp\": \"2026-07-29T20:20:00Z\", \"kwh_value\": 42.75, \"voltage\": 228.6}]}"
```

**PowerShell:**
```powershell
curl.exe -X POST http://localhost:8081/api/v1/ingest/bulk -H "Content-Type: application/json" -d '{\"meter_id\": \"MTR-99-NORTH\", \"grid_zone\": \"ZONE-A\", \"readings\": [{\"timestamp\": \"2026-07-29T20:20:00Z\", \"kwh_value\": 42.75, \"voltage\": 228.6}]}'
```

**macOS / Linux:**
```bash
curl -X POST http://localhost:8081/api/v1/ingest/bulk \
  -H "Content-Type: application/json" \
  -d '{"meter_id": "MTR-99-NORTH", "grid_zone": "ZONE-A", "readings": [{"timestamp": "2026-07-29T20:20:00Z", "kwh_value": 42.75, "voltage": 228.6}]}'
```

Expected response — the request is validated in Java, forwarded to Python, transformed, and persisted, and the Python service's response is passed straight back through:

```json
{
  "message": "Payload schema validated and saved successfully to grid warehouse",
  "metadata": {
    "processed_asset": "MTR-99-NORTH",
    "regional_zone": "ZONE-A",
    "intervals_saved": 1
  },
  "analytics_summary": {
    "cumulative_kwh": 42.75,
    "average_load_per_interval": 42.75
  }
}
```

### Testing the Python service directly (interactive docs)

The Python service exposes interactive API documentation at **http://localhost:8082/docs**. This calls `/api/v1/transform` directly, bypassing the Java gateway — useful for exercising the validation and persistence layer in isolation. Requests here require the `X-EAI-Token` header (see Configuration below); the Swagger UI's "Authorize" button lets you set it once for all requests.

**A valid payload** (locate `POST /api/v1/transform`, click "Try it out", paste this into the request body, and click "Execute"):

```json
{
  "meter_id": "MTR-2026-99A",
  "grid_zone": "NORTH-UTILITY-GRID",
  "readings": [
    {
      "timestamp": "2026-07-28T09:00:00Z",
      "kwh_value": 12.45,
      "voltage": 230.5
    },
    {
      "timestamp": "2026-07-28T09:15:00Z",
      "kwh_value": 14.20,
      "voltage": 228.1
    }
  ]
}
```

This returns a `200` with `cumulative_kwh: 26.65` in the analytics summary.

**An invalid payload**, to see the validation layer reject bad data — this violates three constraints at once (`meter_id` under 5 characters, a negative `kwh_value`, and a `voltage` below the allowed minimum):

```json
{
  "meter_id": "M1",
  "grid_zone": "NORTH-UTILITY-GRID",
  "readings": [
    {
      "timestamp": "2026-07-28T09:00:00Z",
      "kwh_value": -5.5,
      "voltage": 80.0
    }
  ]
}
```

This returns a `422 Unprocessable Entity` with a field-by-field error report — no application code has to check for these cases explicitly; the schema layer rejects them before the route handler ever runs.

## Useful Docker Commands

```bash
docker compose logs <service-name>       # e.g. python-validator, java-gateway, postgres-db
docker compose restart <service-name>
docker compose stop <service-name>
docker compose up --build -d <service-name>   # rebuild and restart just one service

docker compose restart      # restart the whole stack
docker compose stop         # stop the whole stack (containers preserved)
docker compose down         # stop and remove containers (data volume is preserved separately)
```

## Configuration

The stack is fully configured via `docker-compose.yml` — no additional setup is required to run it as-is. Key environment variables per service:

| Service | Variable | Purpose |
|---|---|---|
| `postgres-db` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | Database credentials, applied on first boot only |
| `python-validator` | `API_SECURITY_TOKEN` | Shared secret checked against the `X-EAI-Token` header |
| `python-validator` | `DATABASE_URL` | Full Postgres connection string |
| `java-gateway` | `INTEGRATION_PYTHON_BASE-URL`, `INTEGRATION_PYTHON_AUTH-TOKEN` | Downstream Python service address and shared token |

**Before pushing this repository publicly**: `02-python-transformation-api/.env` and its `.gitignore` (which currently only excludes `.venv/`) mean the `.env` file's contents — including a placeholder security token — are not excluded from version control. Consider adding `.env` to `.gitignore` and rotating any token values that were ever committed, even placeholder-looking ones.

## Repository Structure

```
enterprise-integration-project/
├── docker-compose.yml
├── stream_telemetry.py
├── 01-java-ingestion-service/
│   ├── Dockerfile
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/utility/ingest/
│       │   ├── IngestionApplication.java
│       │   ├── IngestionController.java
│       │   ├── IntegrationClient.java
│       │   ├── MeterReading.java
│       │   └── SmartMeterPayload.java
│       └── resources/
│           └── application.properties
└── 02-python-transformation-api/
    ├── Dockerfile
    ├── requirements.txt
    ├── .env
    ├── app/
    │   ├── main.py
    │   ├── config.py
    │   ├── api/
    │   │   └── transform.py
    │   ├── database/
    │   │   ├── connection.py
    │   │   └── models.py
    │   └── schemas/
    │       └── meter.py
    ├── services/
    │   └── transformer.py       # standalone legacy-XML converter, not part of the live request path
    ├── test_data/
    │   └── telemetry.xml
    └── tests/
        └── test_integration.py
```

(Build artifacts such as `target/`, `__pycache__/`, and `.pytest_cache/` are omitted above — Maven and Python regenerate these automatically and they aren't part of the source layout.)

## Stopping the Stack

```bash
docker compose down
```

This stops and removes the containers. The Postgres data volume (`postgres_persistent_engine_data`) persists separately — add `-v` to `docker compose down -v` if a full data reset is intended.
