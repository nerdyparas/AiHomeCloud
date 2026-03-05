# CI/CD & Quality Guardrails — CubieCloud

> **Version:** 1.0 | **Date:** 2026-03-06

---

## Strategy

Two layers of quality enforcement:

1. **Local pre-commit hooks** — Fast checks before every commit (seconds)
2. **GitHub Actions CI** — Full validation on every push/PR (minutes)

---

## Layer 1: Pre-commit Hooks

### Installation

```bash
pip install pre-commit
pre-commit install
```

### `.pre-commit-config.yaml`

```yaml
repos:
  # Python linting + formatting
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.9.7
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
        files: ^backend/
      - id: ruff-format
        files: ^backend/

  # Python type checking
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.15.0
    hooks:
      - id: mypy
        files: ^backend/app/
        additional_dependencies:
          - pydantic>=2.0
          - fastapi>=0.115
        args: [--ignore-missing-imports]

  # YAML validation
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-yaml
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-merge-conflict
      - id: check-added-large-files
        args: [--maxkb=500]

  # Secrets detection
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.5.0
    hooks:
      - id: detect-secrets
        args: [--baseline, .secrets.baseline]
```

### Ruff Configuration

Add to `backend/pyproject.toml`:

```toml
[tool.ruff]
target-version = "py313"
line-length = 100
src = ["backend/app", "backend/tests"]

[tool.ruff.lint]
select = [
    "E",    # pycodestyle errors
    "W",    # pycodestyle warnings
    "F",    # pyflakes
    "I",    # isort
    "B",    # flake8-bugbear
    "S",    # flake8-bandit (security)
    "UP",   # pyupgrade
    "SIM",  # flake8-simplify
]
ignore = [
    "S101",  # assert in tests is fine
    "S603",  # subprocess calls are sandboxed via subprocess_runner
    "S607",  # partial executable path (we control the env)
]

[tool.ruff.lint.per-file-ignores]
"backend/tests/**" = ["S101", "S106"]  # allow assert and hardcoded passwords in tests

[tool.ruff.format]
quote-style = "double"
```

### Mypy Configuration

Add to `backend/pyproject.toml`:

```toml
[tool.mypy]
python_version = "3.13"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = false  # gradual adoption
check_untyped_defs = true

[[tool.mypy.overrides]]
module = "jose.*"
ignore_missing_imports = true
```

---

## Layer 2: GitHub Actions

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  # ─── Backend Tests ──────────────────────────────
  backend:
    name: Backend (Python ${{ matrix.python-version }})
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.13"]
    defaults:
      run:
        working-directory: backend

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: pip
          cache-dependency-path: backend/requirements.txt

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Lint with ruff
        run: |
          pip install ruff
          ruff check app/ tests/
          ruff format --check app/ tests/

      - name: Type check with mypy
        run: |
          pip install mypy
          mypy app/ --ignore-missing-imports

      - name: Run tests
        run: python -m pytest tests/ -v --tb=short -x

      - name: Security scan
        run: |
          pip install bandit
          bandit -r app/ -ll -ii

  # ─── Flutter Checks ─────────────────────────────
  flutter:
    name: Flutter Analysis & Tests
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
          channel: stable
          cache: true

      - name: Get dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze --fatal-infos=false --fatal-warnings

      - name: Run tests
        run: flutter test

  # ─── Architecture Checks ────────────────────────
  architecture:
    name: Architecture Rules
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: No new root-level directories
        run: |
          ALLOWED="android backend build docs kb lib test .git .github .dart_tool .idea"
          for dir in */; do
            dir_name="${dir%/}"
            if ! echo "$ALLOWED" | grep -qw "$dir_name"; then
              echo "ERROR: Unauthorized root directory: $dir_name"
              echo "Add to allowed list or move to appropriate location"
              exit 1
            fi
          done
          echo "OK: No unauthorized root directories"

      - name: Check file size limits
        run: |
          FAIL=0
          while IFS= read -r file; do
            lines=$(wc -l < "$file")
            if [ "$lines" -gt 600 ]; then
              echo "FAIL: $file has $lines lines (max 600)"
              FAIL=1
            elif [ "$lines" -gt 400 ]; then
              echo "WARN: $file has $lines lines (target <400)"
            fi
          done < <(find lib/ -name "*.dart" -type f)
          while IFS= read -r file; do
            lines=$(wc -l < "$file")
            if [ "$lines" -gt 600 ]; then
              echo "FAIL: $file has $lines lines (max 600)"
              FAIL=1
            elif [ "$lines" -gt 400 ]; then
              echo "WARN: $file has $lines lines (target <400)"
            fi
          done < <(find backend/app/ -name "*.py" -type f)
          exit $FAIL

      - name: AI_RULES.md exists
        run: test -f AI_RULES.md || (echo "ERROR: AI_RULES.md missing from repo root" && exit 1)
```

### `.github/workflows/deploy.yml` (future)

```yaml
name: Deploy to Cubie

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy-backend:
    name: Deploy Backend
    runs-on: ubuntu-latest
    # Only deploy from tagged releases
    if: startsWith(github.ref, 'refs/tags/v')

    steps:
      - uses: actions/checkout@v4

      - name: Package backend
        run: tar -czf backend.tar.gz backend/

      - name: Deploy to Cubie
        # Uses SSH key stored as repository secret
        env:
          CUBIE_HOST: ${{ secrets.CUBIE_HOST }}
          CUBIE_SSH_KEY: ${{ secrets.CUBIE_SSH_KEY }}
        run: |
          echo "Deployment step — configure with actual Cubie SSH access"
          # scp backend.tar.gz cubie@$CUBIE_HOST:/tmp/
          # ssh cubie@$CUBIE_HOST 'cd /opt/cubie && ./deploy.sh'

  deploy-apk:
    name: Build APK
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/v')

    steps:
      - uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
          channel: stable

      - name: Build APK
        run: flutter build apk --release

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: cubie-cloud-${{ github.ref_name }}.apk
          path: build/app/outputs/flutter-apk/app-release.apk
```

---

## Quality Gates Summary

| Check | Tool | Local (pre-commit) | CI (GitHub Actions) | Blocks Merge |
|-------|------|:------------------:|:-------------------:|:------------:|
| Python lint | ruff | Yes | Yes | Yes |
| Python format | ruff format | Yes | Yes | Yes |
| Python types | mypy | Yes | Yes | No (gradual) |
| Python tests | pytest | No | Yes | Yes |
| Python security | bandit | No | Yes | Yes |
| Secrets | detect-secrets | Yes | No | Yes |
| Dart analysis | flutter analyze | No | Yes | Yes |
| Dart tests | flutter test | No | Yes | Yes |
| Architecture rules | shell scripts | No | Yes | Yes |
| File size | wc -l | No | Yes | Warn only |
| YAML validity | check-yaml | Yes | No | Yes |
| Merge conflicts | check-merge-conflict | Yes | No | Yes |

---

## Badge Status (add to README.md)

```markdown
![CI](https://github.com/nerdyparas/AiHomeCloud/actions/workflows/ci.yml/badge.svg)
```

---

## Getting Started

```bash
# One-time setup
pip install pre-commit
pre-commit install

# Run all hooks manually
pre-commit run --all-files

# Skip hooks for emergency commits (use sparingly)
git commit --no-verify -m "emergency fix"
```
