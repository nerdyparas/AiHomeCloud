"""
GET /api/storage/stats — dedicated endpoint for storage info.
"""

from shutil import disk_usage

from fastapi import APIRouter, Depends

from ..auth import get_current_user
from ..config import settings
from ..models import StorageStats

router = APIRouter(prefix="/api/storage", tags=["storage"])


@router.get("/stats", response_model=StorageStats)
async def storage_stats(user: dict = Depends(get_current_user)):
    """Return real disk usage from the NAS root partition."""
    try:
        usage = disk_usage(str(settings.nas_root))
        total_gb = round(usage.total / (1024 ** 3), 1)
        used_gb = round(usage.used / (1024 ** 3), 1)
    except Exception:
        total_gb = settings.total_storage_gb
        used_gb = 0.0

    return StorageStats(totalGB=total_gb, usedGB=used_gb)
