"""
Tests for file_sorter.py — InboxWatcher auto-sort logic.
"""

import os
import time
from pathlib import Path

import pytest


# ─── _destination_folder ──────────────────────────────────────────────────────

def test_jpg_goes_to_photos(tmp_path: Path):
    from app.file_sorter import _destination_folder
    f = tmp_path / "holiday.jpg"
    f.write_bytes(b"\xff\xd8\xff" + b"\x00" * (900 * 1024))  # >800 KB → Photos
    assert _destination_folder(f) == "Photos"


def test_mp4_goes_to_videos(tmp_path: Path):
    from app.file_sorter import _destination_folder
    f = tmp_path / "clip.mp4"
    f.write_bytes(b"fakevideo")
    assert _destination_folder(f) == "Videos"


def test_pdf_goes_to_documents(tmp_path: Path):
    from app.file_sorter import _destination_folder
    f = tmp_path / "report.pdf"
    f.write_bytes(b"%PDF-1.4")
    assert _destination_folder(f) == "Documents"


def test_unknown_ext_goes_to_others(tmp_path: Path):
    from app.file_sorter import _destination_folder
    f = tmp_path / "data.xyz"
    f.write_bytes(b"data")
    assert _destination_folder(f) == "Others"


def test_small_jpg_goes_to_documents(tmp_path: Path):
    """JPG under 800 KB → document photo → Documents/"""
    from app.file_sorter import _destination_folder
    f = tmp_path / "photo.jpg"
    f.write_bytes(b"\xff\xd8\xff" + b"\x00" * 100)  # tiny file
    assert _destination_folder(f) == "Documents"


def test_keyword_in_filename_goes_to_documents(tmp_path: Path):
    """Large JPG with 'aadhaar' in name → Documents/"""
    from app.file_sorter import _destination_folder
    f = tmp_path / "aadhaar_scan.jpg"
    f.write_bytes(b"\xff\xd8\xff" + b"\x00" * (900 * 1024))  # >800 KB
    assert _destination_folder(f) == "Documents"


def test_case_insensitive_extension(tmp_path: Path):
    from app.file_sorter import _destination_folder
    f = tmp_path / "video.MP4"
    f.write_bytes(b"fakevideo")
    assert _destination_folder(f) == "Videos"


# ─── _unique_dest ─────────────────────────────────────────────────────────────

def test_unique_dest_no_collision(tmp_path: Path):
    from app.file_sorter import _unique_dest
    result = _unique_dest(tmp_path, "file.txt")
    assert result == tmp_path / "file.txt"


def test_unique_dest_with_collision(tmp_path: Path):
    from app.file_sorter import _unique_dest
    (tmp_path / "file.txt").write_bytes(b"exists")
    result = _unique_dest(tmp_path, "file.txt")
    assert result == tmp_path / "file_2.txt"


def test_unique_dest_multiple_collisions(tmp_path: Path):
    from app.file_sorter import _unique_dest
    (tmp_path / "file.txt").write_bytes(b"1")
    (tmp_path / "file_2.txt").write_bytes(b"2")
    result = _unique_dest(tmp_path, "file.txt")
    assert result == tmp_path / "file_3.txt"


# ─── _sort_file ───────────────────────────────────────────────────────────────

def test_sort_file_moves_to_correct_folder(tmp_path: Path):
    from app.file_sorter import _sort_file
    inbox = tmp_path / ".inbox"
    inbox.mkdir()
    f = inbox / "movie.mp4"
    f.write_bytes(b"video")
    os.utime(f, (time.time() - 10, time.time() - 10))  # make it old enough

    dest = _sort_file(f, tmp_path)
    assert dest is not None
    assert dest.parent.name == "Videos"
    assert dest.name == "movie.mp4"
    assert not f.exists()
    assert dest.exists()


def test_sort_file_too_young_returns_none(tmp_path: Path):
    from app.file_sorter import _sort_file
    inbox = tmp_path / ".inbox"
    inbox.mkdir()
    f = inbox / "fresh.jpg"
    f.write_bytes(b"\xff\xd8\xff" + b"\x00" * (900 * 1024))
    # mtime is 'now' by default — file is too young

    dest = _sort_file(f, tmp_path)
    assert dest is None  # skipped
    assert f.exists()    # file stays in inbox


def test_sort_file_duplicate_renamed(tmp_path: Path):
    from app.file_sorter import _sort_file
    inbox = tmp_path / ".inbox"
    inbox.mkdir()
    photos = tmp_path / "Photos"
    photos.mkdir()
    # Pre-existing file in destination
    (photos / "photo.jpg").write_bytes(b"existing")

    # Inbox file
    f = inbox / "photo.jpg"
    f.write_bytes(b"\xff\xd8\xff" + b"\x00" * (900 * 1024))
    os.utime(f, (time.time() - 10, time.time() - 10))

    dest = _sort_file(f, tmp_path)
    assert dest is not None
    assert dest.name == "photo_2.jpg"  # renamed to avoid collision
    assert (photos / "photo.jpg").exists()   # original preserved
    assert dest.exists()


def test_sort_file_failure_returns_none_does_not_raise(tmp_path: Path):
    """A missing file should not raise — returns None and logs warning."""
    from app.file_sorter import _sort_file
    ghost = tmp_path / ".inbox" / "ghost.mp4"
    # File does not exist: stat() will fail
    result = _sort_file(ghost, tmp_path)
    assert result is None


# ─── _run_sort_pass (async) ────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_run_sort_pass_sorts_old_files(tmp_path: Path):
    """_run_sort_pass moves old files and skips new ones."""
    from app.file_sorter import _run_sort_pass
    from app.config import settings

    # Override nas_root to tmp_path so all computed paths are isolated
    orig_nas_root = settings.__dict__["nas_root"]
    settings.__dict__["nas_root"] = tmp_path

    try:
        user_dir = settings.personal_path / "alice"
        inbox = user_dir / ".inbox"
        inbox.mkdir(parents=True)

        # Old file → should be sorted
        old_file = inbox / "doc.pdf"
        old_file.write_bytes(b"%PDF-1.4")
        os.utime(old_file, (time.time() - 10, time.time() - 10))

        # New file → should stay
        new_file = inbox / "fresh.mp4"
        new_file.write_bytes(b"video")

        await _run_sort_pass()

        assert not old_file.exists()
        docs_dir = user_dir / "Documents"
        assert (docs_dir / "doc.pdf").exists()
        assert new_file.exists()  # still in inbox

    finally:
        settings.__dict__["nas_root"] = orig_nas_root


# ─── InboxWatcher lifecycle ───────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_inbox_watcher_start_stop():
    """InboxWatcher can be started and stopped without error."""
    from app.file_sorter import InboxWatcher
    watcher = InboxWatcher(interval=9999)  # very long interval — won't actually run
    watcher.start()
    assert watcher._task is not None
    await watcher.stop()
    assert watcher._task is None


@pytest.mark.asyncio
async def test_inbox_watcher_stop_without_start():
    """Calling stop() on an unstarted watcher is a no-op."""
    from app.file_sorter import InboxWatcher
    watcher = InboxWatcher()
    await watcher.stop()  # should not raise


# ─── User creation pre-creates folders ────────────────────────────────────────

@pytest.mark.asyncio
async def test_add_user_creates_standard_folders(client):
    """Creating a user should pre-create Photos, Videos, Documents, Others, .inbox/"""
    from app import store
    from app.config import settings

    await client.post("/api/v1/users", json={"name": "testuser", "pin": "1234"})

    personal_dir = settings.personal_path / "testuser"
    for folder in ("Photos", "Videos", "Documents", "Others", ".inbox"):
        assert (personal_dir / folder).is_dir(), f"Missing folder: {folder}"
