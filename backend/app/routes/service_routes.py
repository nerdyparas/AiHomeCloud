"""
Service management routes — list and toggle NAS services.
"""

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import get_current_user
from ..models import ServiceInfo, ToggleServiceRequest
from .. import store

router = APIRouter(prefix="/api/services", tags=["services"])


@router.get("", response_model=list[ServiceInfo])
async def list_services(user: dict = Depends(get_current_user)):
    """List all configurable NAS services."""
    return [ServiceInfo(**svc) for svc in store.get_services()]


@router.post("/{service_id}/toggle", status_code=status.HTTP_204_NO_CONTENT)
async def toggle(
    service_id: str,
    body: ToggleServiceRequest,
    user: dict = Depends(get_current_user),
):
    """Enable or disable a NAS service."""
    if not store.toggle_service(service_id, body.enabled):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Service not found")
