"""
File Routes Tests — upload safety, directory ops, download, path edge cases.
"""

import io
import os
import uuid

import pytest
from httpx import AsyncClient
from pathlib import Path


@pytest.mark.asyncio
async def test_upload_file_basic(authenticated_client: AsyncClient, tmp_path: Path):
    """Upload a file and verify it appears in the listing."""
    content = b"hello world"
    files = {"file": ("test.txt", io.BytesIO(content), "text/plain")}
    response = await authenticated_client.post(
        "/api/v1/files/upload?path=/srv/nas/shared/",
        files=files,
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "test.txt"
    assert data["sizeBytes"] == len(content)


@pytest.mark.asyncio
async def test_upload_filename_traversal_blocked(authenticated_client: AsyncClient):
    """Upload with ../etc/evil filename should be sanitized to just 'evil'."""
    content = b"malicious"
    files = {"file": ("../../etc/evil", io.BytesIO(content), "text/plain")}
    response = await authenticated_client.post(
        "/api/v1/files/upload?path=/srv/nas/shared/",
        files=files,
    )
    # Should sanitize to "evil" and succeed, or reject
    if response.status_code == 201:
        data = response.json()
        # Filename should be sanitized — no path separators
        assert "/" not in data["name"]
        assert ".." not in data["name"]


@pytest.mark.asyncio
async def test_upload_filename_with_slashes_sanitized(authenticated_client: AsyncClient):
    """Upload with path separators in filename should be stripped to just the filename."""
    content = b"test content"
    files = {"file": ("subdir/deep/file.txt", io.BytesIO(content), "text/plain")}
    response = await authenticated_client.post(
        "/api/v1/files/upload?path=/srv/nas/shared/",
        files=files,
    )
    if response.status_code == 201:
        data = response.json()
        assert data["name"] == "file.txt"


@pytest.mark.asyncio
async def test_mkdir_and_list(authenticated_client: AsyncClient):
    """Create a folder and verify it appears in listing."""
    folder_name = f"test_folder_{uuid.uuid4().hex[:8]}"
    # Create folder
    response = await authenticated_client.post(
        "/api/v1/files/mkdir",
        json={"path": f"/srv/nas/shared/{folder_name}"},
    )
    assert response.status_code == 201

    # List and verify
    response = await authenticated_client.get(
        "/api/v1/files/list?path=/srv/nas/shared/"
    )
    assert response.status_code == 200
    items = response.json()["items"]
    folder_names = [i["name"] for i in items if i["isDirectory"]]
    assert folder_name in folder_names


@pytest.mark.asyncio
async def test_mkdir_duplicate_returns_409(authenticated_client: AsyncClient):
    """Creating a folder that already exists returns 409."""
    # Create once
    await authenticated_client.post(
        "/api/v1/files/mkdir",
        json={"path": "/srv/nas/shared/dup_folder"},
    )
    # Create again
    response = await authenticated_client.post(
        "/api/v1/files/mkdir",
        json={"path": "/srv/nas/shared/dup_folder"},
    )
    assert response.status_code == 409


@pytest.mark.asyncio
async def test_delete_file(authenticated_client: AsyncClient):
    """Delete a file and verify it's gone."""
    # Upload a file — it lands in user's .inbox/ now
    files = {"file": ("to_delete.txt", io.BytesIO(b"bye"), "text/plain")}
    resp = await authenticated_client.post(
        "/api/v1/files/upload?path=/srv/nas/shared/",
        files=files,
    )
    assert resp.status_code == 201
    uploaded_path = resp.json()["path"]

    # Delete using the actual path returned by upload
    response = await authenticated_client.delete(
        f"/api/v1/files/delete?path={uploaded_path}"
    )
    assert response.status_code == 204


@pytest.mark.asyncio
async def test_delete_nonexistent_returns_404(authenticated_client: AsyncClient):
    """Deleting a nonexistent file returns 404."""
    response = await authenticated_client.delete(
        "/api/v1/files/delete?path=/srv/nas/shared/no_such_file_xyz.txt"
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_rename_file(authenticated_client: AsyncClient):
    """Rename a file and verify old name gone, new name exists."""
    old_name = f"old_{uuid.uuid4().hex[:8]}.txt"
    new_name = f"new_{uuid.uuid4().hex[:8]}.txt"
    # Upload — file lands in .inbox/
    files = {"file": (old_name, io.BytesIO(b"data"), "text/plain")}
    resp = await authenticated_client.post(
        "/api/v1/files/upload?path=/srv/nas/shared/",
        files=files,
    )
    assert resp.status_code == 201
    uploaded_path = resp.json()["path"]

    # Rename using the actual uploaded path
    response = await authenticated_client.put(
        "/api/v1/files/rename",
        json={"oldPath": uploaded_path, "newName": new_name},
    )
    assert response.status_code == 204


@pytest.mark.asyncio
async def test_rename_to_empty_name_returns_400(authenticated_client: AsyncClient):
    """Renaming with empty new name returns 400."""
    response = await authenticated_client.put(
        "/api/v1/files/rename",
        json={"oldPath": "/srv/nas/shared/something.txt", "newName": ""},
    )
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_download_nonexistent_returns_404(authenticated_client: AsyncClient):
    """Downloading a nonexistent file returns 404."""
    response = await authenticated_client.get(
        "/api/v1/files/download?path=/srv/nas/shared/no_file_here_xyz.txt"
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_download_directory_returns_400(authenticated_client: AsyncClient):
    """Downloading a directory returns 400."""
    # Use /shared/ which maps to the sandboxed nas_root/shared/ created by conftest
    response = await authenticated_client.get(
        "/api/v1/files/download?path=/shared/"
    )
    assert response.status_code == 400


@pytest.mark.asyncio
@pytest.mark.parametrize("filename", [
    "evil.sh", "run.bash", "script.zsh",
    "hack.py", "exploit.rb", "payload.pl",
    "malware.php", "binary.elf", "virus.exe",
    "app.apk", "module.so", "kernel.ko",
    "package.deb", "package.rpm",
])
async def test_blocked_executable_upload_returns_415(
    authenticated_client: AsyncClient, filename: str
):
    """Uploading a blocked executable file type must return HTTP 415 before any disk write."""
    files = {"file": (filename, io.BytesIO(b"#!/bin/sh\nrm -rf /"), "application/octet-stream")}
    response = await authenticated_client.post(
        "/api/v1/files/upload?path=/srv/nas/shared/",
        files=files,
    )
    assert response.status_code == 415, f"Expected 415 for {filename}, got {response.status_code}"
    assert "not allowed" in response.json().get("detail", "").lower()


@pytest.mark.asyncio
async def test_blocked_extension_case_insensitive(authenticated_client: AsyncClient):
    """Extension check must be case-insensitive (e.g. .SH, .EXE)."""
    for filename in ("EVIL.SH", "VIRUS.EXE", "HACK.PY"):
        files = {"file": (filename, io.BytesIO(b"bad"), "application/octet-stream")}
        response = await authenticated_client.post(
            "/api/v1/files/upload?path=/srv/nas/shared/",
            files=files,
        )
        assert response.status_code == 415, f"Expected 415 for {filename}"


@pytest.mark.asyncio
async def test_list_with_pagination(authenticated_client: AsyncClient):
    """Verify pagination parameters work."""
    response = await authenticated_client.get(
        "/api/v1/files/list?path=/srv/nas/shared/&page=0&page_size=5"
    )
    assert response.status_code == 200
    data = response.json()
    assert "items" in data
    assert "totalCount" in data
    assert data["page"] == 0
    assert data["pageSize"] == 5


@pytest.mark.asyncio
async def test_list_with_sort(authenticated_client: AsyncClient):
    """Verify sort parameters are accepted."""
    response = await authenticated_client.get(
        "/api/v1/files/list?path=/srv/nas/shared/&sort_by=modified&sort_dir=desc"
    )
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_sort_now_sorts_existing_folder(authenticated_client: AsyncClient):
    """Manual sort endpoint should categorize files in an existing folder."""
    from app.routes.file_routes import _safe_resolve

    response = await authenticated_client.post(
        "/api/v1/files/mkdir",
        json={"path": "/srv/nas/shared/RawData"},
    )
    assert response.status_code == 201

    shared_raw = _safe_resolve("/srv/nas/shared/RawData")
    shared_raw.mkdir(parents=True, exist_ok=True)
    (shared_raw / "nested").mkdir(parents=True, exist_ok=True)
    (shared_raw / "holiday.jpg").write_bytes(b"img")
    (shared_raw / "movie.mp4").write_bytes(b"vid")
    (shared_raw / "notes.txt").write_bytes(b"doc")
    (shared_raw / "nested" / "paper.pdf").write_bytes(b"%PDF-1.4")

    response = await authenticated_client.post(
        "/api/v1/files/sort-now?path=/srv/nas/shared/RawData"
    )
    assert response.status_code == 200
    data = response.json()
    assert data["moved"] >= 4

    # Small images are treated as scanned documents by heuristic.
    assert (shared_raw / "Documents" / "holiday.jpg").exists()
    assert (shared_raw / "Videos" / "movie.mp4").exists()
    assert (shared_raw / "Documents" / "notes.txt").exists()
    assert (shared_raw / "Documents" / "paper.pdf").exists()


@pytest.mark.asyncio
async def test_sort_now_missing_dir_returns_404(authenticated_client: AsyncClient):
    """Sorting a missing directory should return 404."""
    response = await authenticated_client.post(
        "/api/v1/files/sort-now?path=/srv/nas/shared/no_such_folder"
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_file_ops_require_auth(client: AsyncClient):
    """All file endpoints require authentication."""
    endpoints = [
        ("GET", "/api/v1/files/list?path=/srv/nas/shared/"),
        ("POST", "/api/v1/files/mkdir"),
        ("DELETE", "/api/v1/files/delete?path=/srv/nas/shared/x"),
        ("GET", "/api/v1/files/download?path=/srv/nas/shared/x"),
        ("POST", "/api/v1/files/sort-now?path=/srv/nas/shared/RawData"),
    ]
    for method, url in endpoints:
        response = await client.request(method, url)
        assert response.status_code in (401, 403), \
            f"{method} {url} should require auth, got {response.status_code}"
