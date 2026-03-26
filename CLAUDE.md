# AiHomeCloud — Claude Code Instructions

## Repository
- Windows path: C:\Dropbox\AiHomeCloud
- Radxa path: ~/AiHomeCloud

## Radxa SBC
- SSH: ssh paras@192.168.0.241 (passwordless ✅)
- Venv: source ~/AiHomeCloud/backend/.venv/bin/activate
- Service: aihomecloud (systemd)
- Python: 3.12.3

## Commands

### Run backend tests (on Radxa):
ssh paras@192.168.0.241 "cd ~/AiHomeCloud && source backend/.venv/bin/activate && python -m pytest backend/tests/ -q --ignore=backend/tests/test_hardware_integration.py 2>&1 | tail -30"

### Run single test (on Radxa):
ssh paras@192.168.0.241 "cd ~/AiHomeCloud && source backend/.venv/bin/activate && python -m pytest backend/tests/TEST_FILE.py::TEST_NAME -v 2>&1"

### Health check:
ssh paras@192.168.0.241 "curl -sk https://localhost:8443/api/health"

### Restart service:
ssh paras@192.168.0.241 "sudo systemctl restart aihomecloud && sleep 4 && curl -sk https://localhost:8443/api/health"

### Deploy:
ssh paras@192.168.0.241 "cd ~/AiHomeCloud && git pull && sudo systemctl restart aihomecloud && sleep 4 && curl -sk https://localhost:8443/api/health"

### Flutter tests (local):
flutter analyze --no-fatal-infos 2>&1
flutter test 2>&1

## Test rules
- ALWAYS ignore test_hardware_integration.py — requires physical hardware
- Run affected test file after every fix to confirm it passes
- Never break a passing test while fixing a failing one

## Workflow
1. Fix code locally in C:\Dropbox\AiHomeCloud
2. Run tests on Radxa via SSH
3. If tests pass → git add, commit, push
4. Deploy to Radxa via git pull + service restart
5. Confirm health check returns {"status":"ok"}

## Audit
- Latest audit: docs/AUDIT_2026_03_24.md
- P0 bugs: FIXED (commit 8299a1f)
- P1 bugs: pending
