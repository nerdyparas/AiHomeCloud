"""
Ingest core tests — the unified file-write path shared by app upload,
Telegram, phone sync, and the web portal (app/ingest.py).
"""

import asyncio

import pytest

from app.ingest import (
    Destination,
    IngestMode,
    IngestSizeError,
    IngestStallError,
    Scope,
    ingest,
)


async def _chunks(*parts: bytes):
    for p in parts:
        yield p


async def _stalling_chunks(first: bytes):
    yield first
    await asyncio.sleep(10)  # far longer than the tiny stall_timeout_s used in tests
    yield b"never gets here"


@pytest.mark.asyncio
async def test_ingest_writes_and_sorts(client):
    """A photo with no explicit subpath lands under Photos/ (synchronous sort)."""
    dest = Destination(scope=Scope.FAMILY, mode=IngestMode.SORTED)
    result = await ingest(_chunks(b"hello world"), filename="pic.jpg", dest=dest)

    assert result.bytes_written == len(b"hello world")
    assert result.dedup_hit is False
    assert result.sorted_to == "Photos"
    assert result.path.name == "pic.jpg"
    assert result.path.parent.name == "Photos"
    assert result.path.exists()
    assert not result.path.with_name(result.path.name + ".uploading").exists()


@pytest.mark.asyncio
async def test_ingest_dedup_hit_on_second_identical_upload(client):
    """The same content uploaded twice into the same scope dedup-hits the second time."""
    dest = Destination(scope=Scope.FAMILY, mode=IngestMode.SORTED)

    first = await ingest(_chunks(b"same bytes"), filename="a.jpg", dest=dest)
    assert first.dedup_hit is False

    second = await ingest(_chunks(b"same bytes"), filename="b.jpg", dest=dest)
    assert second.dedup_hit is True
    assert second.sha256 == first.sha256
    # The second (duplicate) temp file must not be left behind.
    assert not (first.path.parent / "b.jpg").exists()
    assert not (first.path.parent / "b.jpg.uploading").exists()


@pytest.mark.asyncio
async def test_ingest_same_content_different_scope_not_deduped(client):
    """Dedup is per-(scope, hash) — the same file in two different scopes is not collapsed
    (a family copy existing does not suppress a personal copy of the same content)."""
    family_dest = Destination(scope=Scope.FAMILY, mode=IngestMode.SORTED)
    personal_dest = Destination(scope=Scope.PERSONAL, owner="alice", mode=IngestMode.SORTED)

    family_result = await ingest(_chunks(b"cross-scope bytes"), filename="x.jpg", dest=family_dest)
    personal_result = await ingest(_chunks(b"cross-scope bytes"), filename="x.jpg", dest=personal_dest)

    assert family_result.dedup_hit is False
    assert personal_result.dedup_hit is False
    assert family_result.path.exists()
    assert personal_result.path.exists()


@pytest.mark.asyncio
async def test_ingest_stall_timeout_cleans_up_temp(client):
    """A chunk source that goes silent longer than stall_timeout_s raises IngestStallError
    and leaves no partial .uploading file behind."""
    dest = Destination(scope=Scope.FAMILY, mode=IngestMode.SORTED)

    with pytest.raises(IngestStallError):
        await ingest(
            _stalling_chunks(b"first chunk"), filename="stalled.jpg", dest=dest,
            stall_timeout_s=1,
        )

    from app.config import settings
    leftovers = list((settings.family_path / "Photos").glob("stalled.jpg*")) if (settings.family_path / "Photos").exists() else []
    assert leftovers == []


@pytest.mark.asyncio
async def test_ingest_oversize_rejected_and_cleaned_up(client, monkeypatch):
    """A stream exceeding max_upload_bytes is rejected and its temp file removed."""
    from app.config import settings
    monkeypatch.setattr(settings, "max_upload_bytes", 5)

    dest = Destination(scope=Scope.FAMILY, mode=IngestMode.SORTED)
    with pytest.raises(IngestSizeError):
        await ingest(_chunks(b"way more than five bytes"), filename="big.jpg", dest=dest)

    leftovers = list((settings.family_path / "Photos").glob("big.jpg*")) if (settings.family_path / "Photos").exists() else []
    assert leftovers == []


@pytest.mark.asyncio
async def test_ingest_personal_scope_requires_owner_auth(client):
    """A non-admin, non-owner user is rejected from writing into another user's personal scope."""
    from app import store

    await store.add_user("alice", "1111")
    bob = await store.add_user("bob", "2222")
    bob_user_claims = {"sub": bob["id"], "type": "user"}

    dest = Destination(scope=Scope.PERSONAL, owner="alice", mode=IngestMode.SORTED)

    from fastapi import HTTPException
    with pytest.raises(HTTPException) as exc_info:
        await ingest(_chunks(b"private"), filename="secret.jpg", dest=dest, user=bob_user_claims)
    assert exc_info.value.status_code == 403


@pytest.mark.asyncio
async def test_ingest_mirror_mode_no_sort(client):
    """MIRROR mode with an explicit subpath writes verbatim, no extension-based sort."""
    dest = Destination(scope=Scope.FAMILY, subpath="Raw", mode=IngestMode.MIRROR)
    result = await ingest(_chunks(b"raw bytes"), filename="clip.mp4", dest=dest)

    assert result.sorted_to is None
    assert result.path.parent.name == "Raw"
    assert result.path.name == "clip.mp4"


@pytest.mark.asyncio
async def test_ingest_raw_dir_bypasses_scope_derivation(client, tmp_path):
    """A Destination built from an already-resolved arbitrary directory (raw_dir) writes
    exactly there — this is what explicit-path app uploads use, and must not silently
    redirect uploads to a scope-derived path."""
    from app.config import settings

    arbitrary_dir = settings.nas_root / "shared"
    dest = Destination(scope=Scope.FAMILY, raw_dir=arbitrary_dir, mode=IngestMode.MIRROR)
    result = await ingest(_chunks(b"arbitrary"), filename="note.txt", dest=dest)

    assert result.path.parent == arbitrary_dir
