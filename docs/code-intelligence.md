# Code Intelligence System — CubieCloud

> **Version:** 1.0 | **Date:** 2026-03-06 | **Status:** Design Document (not yet implemented)

---

## Purpose

As CubieCloud grows, AI-assisted development becomes more costly in tokens and less accurate without focused context. A **Code RAG (Retrieval-Augmented Generation)** system provides:

1. **Targeted context** — AI sees only relevant code, not the entire codebase
2. **Token efficiency** — Reduce per-query cost by 60-80%
3. **Semantic understanding** — Find code by meaning, not just text matching
4. **Architecture awareness** — AI understands module boundaries and dependencies

---

## Architecture Overview

```
┌──────────────────────────────────────────────────┐
│                Code Intelligence Pipeline         │
│                                                   │
│  ┌─────────┐    ┌───────────┐    ┌────────────┐  │
│  │ Source   │───▶│ Parser    │───▶│ Embeddings │  │
│  │ Files    │    │ (tree-    │    │ (MiniLM /  │  │
│  │ .dart    │    │  sitter)  │    │  CodeBERT) │  │
│  │ .py      │    └───────────┘    └────────────┘  │
│  └─────────┘          │                │          │
│                        │                │          │
│                        ▼                ▼          │
│               ┌───────────────┐  ┌────────────┐   │
│               │ Chunk Store   │  │ Vector DB  │   │
│               │ (JSON/SQLite) │  │ (ChromaDB) │   │
│               └───────────────┘  └────────────┘   │
│                        │                │          │
│                        └───────┬────────┘          │
│                                ▼                   │
│                       ┌──────────────┐             │
│                       │   Query API  │             │
│                       │  (FastAPI)   │             │
│                       └──────────────┘             │
└──────────────────────────────────────────────────┘
```

---

## Components

### 1. Parser — tree-sitter

**Why tree-sitter:** Language-agnostic AST parsing. Supports both Dart and Python.

**Chunking Strategy:**

| Chunk Type | Granularity | Metadata Captured |
|-----------|------------|-------------------|
| Function/Method | Per function | Name, params, return type, docstring, file path, line range |
| Class | Per class | Name, methods list, fields, inheritance, file path |
| Import block | Per file | All imports (dependency graph) |
| Top-level | Per constant/variable | Name, type, value |

**Chunk size target:** 50-200 lines per chunk. Classes with >200 lines split into method-level chunks.

```python
# Example chunk metadata
{
    "id": "lib/services/api_service.dart::ApiService::getFileList",
    "type": "method",
    "language": "dart",
    "file": "lib/services/api_service.dart",
    "line_start": 245,
    "line_end": 268,
    "class": "ApiService",
    "name": "getFileList",
    "params": ["String path", "int page", "int pageSize"],
    "return_type": "Future<FileListResponse>",
    "imports": ["dart:convert", "package:http/http.dart"],
    "content": "... raw source code ..."
}
```

### 2. Embedding Model

**Primary choice:** `all-MiniLM-L6-v2` (sentence-transformers)

| Property | Value |
|----------|-------|
| Dimensions | 384 |
| Model size | 80 MB |
| Speed | ~1000 chunks/sec on CPU |
| Quality | Excellent for code search |
| RAM usage | ~200 MB loaded |

**Alternative for code-specific:** `microsoft/codebert-base` (768-dim, 500 MB) — better semantic code understanding but heavier. Use only if MiniLM proves insufficient.

**Embedding strategy:**
- Embed chunk content + metadata (function signature, docstring) as single text
- Store raw content separately for retrieval
- Re-embed on file change (incremental, not full rebuild)

### 3. Vector Database — ChromaDB

**Why ChromaDB:** Lightweight, embedded, Python-native, no external server needed.

```python
import chromadb

client = chromadb.PersistentClient(path="/var/lib/cubie/code-intel")
collection = client.get_or_create_collection(
    name="cubie_code",
    metadata={"hnsw:space": "cosine"}
)
```

**Collections:**

| Collection | Content | Est. Vectors |
|-----------|---------|-------------|
| `dart_code` | All Flutter/Dart chunks | ~500-1000 |
| `python_code` | All backend Python chunks | ~200-400 |
| `docs` | Markdown docs, comments, ARB strings | ~100-200 |

**Storage Estimate:** ~5 MB for 1500 vectors at 384 dimensions.

### 4. Query API

```python
# POST /api/code-intel/search
{
    "query": "how does file upload handle large files?",
    "language": "dart",        # optional filter
    "top_k": 5,                # number of results
    "min_score": 0.3           # similarity threshold
}

# Response
{
    "results": [
        {
            "id": "lib/services/api_service.dart::ApiService::uploadFile",
            "score": 0.87,
            "file": "lib/services/api_service.dart",
            "line_start": 310,
            "line_end": 355,
            "content": "Future<void> uploadFile(...) { ... }"
        }
    ]
}
```

---

## Indexing Pipeline

### Full Index (run once or on demand)

```
1. Walk source tree (lib/**/*.dart, backend/app/**/*.py)
2. Parse each file with tree-sitter → AST
3. Extract chunks at function/class/module granularity
4. Generate embeddings: embed(signature + docstring + content)
5. Upsert into ChromaDB with metadata
6. Store chunk→file mapping in JSON for fast lookup
```

### Incremental Index (on file save / git hook)

```
1. Detect changed files (git diff --name-only)
2. Re-parse only changed files
3. Delete old chunks for those files from ChromaDB
4. Insert new chunks
5. Log update to indexing journal
```

**Trigger options:**
- **Post-commit hook:** `git diff --name-only HEAD~1 | python index_changed.py`
- **File watcher:** `watchdog` library monitoring `lib/` and `backend/app/`
- **Manual:** CLI command `python -m code_intel.index --full`

---

## Token Efficiency Analysis

### Without Code Intelligence (Current)

| Scenario | Context Needed | Est. Tokens |
|----------|---------------|-------------|
| "Add a new API endpoint" | Full api_service.dart + routes + models | ~8,000-12,000 |
| "Fix file upload bug" | Entire file_routes.py + api_service.dart | ~6,000-10,000 |
| "How does auth work?" | auth.py + auth_routes.py + providers.dart | ~5,000-8,000 |

### With Code Intelligence (Target)

| Scenario | Context Retrieved | Est. Tokens |
|----------|------------------|-------------|
| "Add a new API endpoint" | Top 5 relevant chunks (~50 lines each) | ~1,500-2,500 |
| "Fix file upload bug" | Upload function + _safe_resolve + error handler | ~1,000-1,500 |
| "How does auth work?" | JWT functions + middleware + relevant providers | ~1,200-2,000 |

**Expected reduction: 60-75%**

---

## Implementation Plan

### Phase 1: Foundation (prerequisites)

```bash
pip install tree-sitter tree-sitter-python tree-sitter-dart
pip install sentence-transformers chromadb
```

**New files:**
```
backend/
  code_intel/
    __init__.py
    parser.py          # tree-sitter parsing + chunking
    embeddings.py      # MiniLM embedding generation
    store.py           # ChromaDB operations
    indexer.py         # Full + incremental indexing pipeline
    api.py             # FastAPI router for search
    config.py          # Paths, model name, collection names
```

### Phase 2: Parser + Chunker

Build `parser.py` with tree-sitter to extract:
- Python: functions, classes, module-level variables
- Dart: classes, methods, top-level functions, mixins

### Phase 3: Embedding + Storage

Build `embeddings.py` + `store.py`:
- Load MiniLM model
- Embed chunks
- Store in ChromaDB

### Phase 4: Query API

Build `api.py`:
- Search endpoint
- Filter by language, file, module
- Return ranked results with source code

### Phase 5: Integration

- Git post-commit hook for incremental indexing
- Optional: VS Code extension or Copilot custom instructions
- CLI tool for manual queries

---

## Hardware Considerations (Cubie A7Z)

| Resource | Available | Code Intel Usage | Feasibility |
|---------|-----------|-----------------|-------------|
| RAM | 8 GB total | MiniLM: ~200 MB, ChromaDB: ~50 MB | OK |
| CPU | ARM Cortex-A55 | Embedding: slower but acceptable | OK for indexing |
| Storage | NVMe/USB | ~50 MB for DB + model | OK |

**Concern:** Initial full index may take 2-5 minutes on ARM. Incremental updates will be <5 seconds.

**Mitigation:** Run full index as background job via `job_store.py`. Serve queries from pre-built index.

---

## Integration with AI Development Workflow

### Copilot / LLM Context Injection

When an AI agent begins a task:

```
1. Agent receives user prompt: "Fix the file upload timeout"
2. Query code-intel: search("file upload timeout", top_k=5)
3. Inject results into context: "Relevant code:\n{chunks}"
4. Agent works with focused context instead of full files
```

### Custom Instructions Integration

Add to `.github/copilot-instructions.md`:
```markdown
## Code Intelligence
Before modifying code, query the code intelligence system:
- POST /api/code-intel/search with your task description
- Use returned chunks as primary context
- Only read full files if chunks are insufficient
```

---

## Future Enhancements

1. **Dependency graph** — Build import/call graph for impact analysis
2. **Change impact prediction** — "Changing this function affects these 12 callers"
3. **Auto-documentation** — Generate/update docstrings from code changes
4. **Semantic git blame** — "Who last changed the authentication logic?" (not just file lines)
5. **Cross-language linking** — Connect Flutter API calls to backend endpoints they invoke
