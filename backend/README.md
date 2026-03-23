# AiHomeCloud Backend

FastAPI backend for the AiHomeCloud home NAS.

## Quick Start

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m app.main
```

## Full Setup

See [../kb/setup-instructions.md](../kb/setup-instructions.md) for complete deployment instructions.

## Tests

```bash
cd backend
python -m pytest tests/ -q
```

## Docs

| Doc | Description |
|-----|-------------|
| [kb/setup-instructions.md](../kb/setup-instructions.md) | Full deployment guide (dev + production) |
| [kb/api-contracts.md](../kb/api-contracts.md) | API reference — all endpoints, methods, auth |
| [kb/architecture.md](../kb/architecture.md) | System architecture — routes, models, providers |
| [kb/backend-patterns.md](../kb/backend-patterns.md) | Backend coding patterns and conventions |
| [kb/hardware.md](../kb/hardware.md) | Supported SBCs and hardware reference |
- `POST /api/services/{id}/toggle` — Enable/disable service
