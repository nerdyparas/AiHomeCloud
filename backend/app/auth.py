"""
JWT authentication utilities.
"""

import asyncio
import functools
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import jwt
from jwt import InvalidTokenError
from passlib.context import CryptContext
import uuid

from . import store

from .config import settings

_bearer_scheme = HTTPBearer()
# rounds configurable via AHC_BCRYPT_ROUNDS (default 10 ≈ 0.1s on ARM).
# PINs are rate-limited (10 attempts / 15 min lockout), so lower rounds are safe.
def _make_pwd_context() -> CryptContext:
    from .config import settings
    return CryptContext(
        schemes=["bcrypt"], deprecated="auto",
        bcrypt__rounds=settings.bcrypt_rounds,
    )

pwd_context = _make_pwd_context()


async def hash_password(plain: str) -> str:
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(
        None,
        functools.partial(pwd_context.hash, plain),
    )


async def verify_password(plain: str, hashed: str) -> bool:
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(
        None,
        functools.partial(pwd_context.verify, plain, hashed),
    )


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


async def create_refresh_token(subject: str, expires_days: int = 30) -> tuple[str, str, int]:
    """Create a refresh JWT with a `jti` and persist a token record.

    Returns (token, jti, expires_at_ts).
    """
    now = datetime.now(timezone.utc)
    jti = uuid.uuid4().hex
    exp = now + timedelta(days=expires_days)
    payload = {
        "sub": subject,
        "iat": now,
        "exp": exp,
        "type": "refresh",
        "jti": jti,
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    # Persist token record (epoch seconds)
    record = {
        "jti": jti,
        "userId": subject,
        "issuedAt": int(now.timestamp()),
        "expiresAt": int(exp.timestamp()),
        "revoked": False,
    }
    await store.add_token(record)
    return token, jti, int(exp.timestamp())


def decode_refresh_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "refresh":
            raise InvalidTokenError("Not a refresh token")
        return payload
    except InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired refresh token")


def decode_token(token: str) -> dict:
    """Decode and verify a JWT. Raises HTTPException on failure."""
    try:
        return jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
    except InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
) -> dict:
    """FastAPI dependency — extracts & validates the Bearer token."""
    return decode_token(credentials.credentials)


_optional_bearer = HTTPBearer(auto_error=False)


async def get_current_user_optional(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_optional_bearer),
) -> Optional[dict]:
    """FastAPI dependency — returns decoded token or None if no auth header."""
    if credentials is None:
        return None
    return decode_token(credentials.credentials)


async def migrate_plaintext_pins() -> int:
    """Hash any plaintext PINs still in the user store. Returns count migrated."""
    users = await store.get_users()
    migrated = 0
    changed = False
    for user in users:
        pin = user.get("pin", "")
        if pin and not str(pin).startswith("$2"):
            user["pin"] = await hash_password(str(pin))
            migrated += 1
            changed = True
    if changed:
        await store.save_users(users)
    return migrated


async def require_admin(user: dict = Depends(get_current_user)) -> dict:
    """FastAPI dependency — ensures the user has admin privileges.
    Works by looking up the user in the store by subject (serial/user_id).
    Device-type tokens (from pairing) are always treated as admin.
    """
    from . import store

    if user.get("type") == "device":
        return user  # Device tokens are admin-level

    user_id = user.get("sub", "")
    found = await store.find_user(user_id)
    # Reject if user not found (deleted account with valid JWT) OR not admin
    if not found or not found.get("is_admin", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin privileges required",
        )
    return user


