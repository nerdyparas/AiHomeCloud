"""
JWT authentication utilities.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from .config import settings

_bearer_scheme = HTTPBearer()


def create_token(subject: str, extra: Optional[dict] = None) -> str:
    """Create a signed JWT for the given subject (user id / device serial)."""
    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "iat": now,
        "exp": now + timedelta(hours=settings.jwt_expire_hours),
    }
    if extra:
        payload.update(extra)
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict:
    """Decode and verify a JWT. Raises HTTPException on failure."""
    try:
        return jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
) -> dict:
    """FastAPI dependency — extracts & validates the Bearer token."""
    return decode_token(credentials.credentials)


async def require_admin(user: dict = Depends(get_current_user)) -> dict:
    """FastAPI dependency — ensures the user has admin privileges.
    Works by looking up the user in the store by subject (serial/user_id).
    Device-type tokens (from pairing) are always treated as admin.
    """
    from . import store

    if user.get("type") == "device":
        return user  # Device tokens are admin-level

    user_id = user.get("sub", "")
    found = store.find_user(user_id)
    if found and not found.get("is_admin", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin privileges required",
        )
    return user
