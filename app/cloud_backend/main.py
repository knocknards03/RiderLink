"""
RiderLink Cloud Backend
-----------------------
Provides:
  POST /auth/register  — create a new rider account
  POST /auth/login     — authenticate and receive a JWT
  GET  /auth/me        — return profile for the bearer token
  POST /auth/logout    — server-side token revocation (blocklist)
  POST /sync           — sync telemetry (existing)
  POST /predict        — crash ML hook (existing)

Auth uses:
  • bcrypt  — password hashing (never store plaintext)
  • PyJWT   — HS256 signed tokens, 7-day expiry
  • SQLite  — lightweight persistent store (swap for Postgres/Cloud SQL in prod)
"""

import os
import sqlite3
import logging
import secrets
from datetime import datetime, timedelta, timezone
from contextlib import contextmanager
from typing import Optional

import bcrypt
import jwt
from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, field_validator

# ── Config ────────────────────────────────────────────────────────────────────
SECRET_KEY = os.environ.get("JWT_SECRET", secrets.token_hex(32))
ALGORITHM  = "HS256"
TOKEN_TTL_DAYS = 7
DB_PATH    = os.environ.get("DB_PATH", "riderlink_users.db")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="RiderLink Cloud Backend", version="2.0.0")
bearer_scheme = HTTPBearer()

# ── Database ──────────────────────────────────────────────────────────────────

def _get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn

@contextmanager
def get_db():
    conn = _get_conn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def init_db():
    """Create tables on first run."""
    with get_db() as db:
        db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                name          TEXT    NOT NULL,
                email         TEXT    NOT NULL UNIQUE,
                phone         TEXT,
                blood_group   TEXT,
                emergency_contact TEXT,
                password_hash TEXT    NOT NULL,
                created_at    INTEGER NOT NULL,
                last_login    INTEGER
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS token_blocklist (
                jti        TEXT PRIMARY KEY,
                revoked_at INTEGER NOT NULL
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS login_sessions (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id    INTEGER NOT NULL,
                jti        TEXT    NOT NULL UNIQUE,
                issued_at  INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                user_agent TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
    logger.info("Database initialised at %s", DB_PATH)

init_db()

# ── Pydantic models ───────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str
    phone: Optional[str] = None
    blood_group: Optional[str] = None
    emergency_contact: Optional[str] = None

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        return v

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

class UserProfile(BaseModel):
    id: int
    name: str
    email: str
    phone: Optional[str]
    blood_group: Optional[str]
    emergency_contact: Optional[str]
    created_at: int
    last_login: Optional[int]

class AuthResponse(BaseModel):
    token: str
    token_type: str = "Bearer"
    expires_in: int          # seconds
    user: UserProfile

class SyncData(BaseModel):
    user_id: str
    telemetry: dict
    groups: list

class CrashData(BaseModel):
    accelerometer: dict
    gyroscope: dict

# ── JWT helpers ───────────────────────────────────────────────────────────────

def _create_token(user_id: int, email: str) -> tuple:
    """Returns (encoded_token, jti, expires_at)."""
    jti = secrets.token_hex(16)
    now = datetime.now(timezone.utc)
    exp = now + timedelta(days=TOKEN_TTL_DAYS)
    payload = {
        "sub": str(user_id),
        "email": email,
        "jti": jti,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
    }
    token = jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)
    return token, jti, exp

def _decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

def _is_revoked(jti: str) -> bool:
    with get_db() as db:
        row = db.execute(
            "SELECT 1 FROM token_blocklist WHERE jti = ?", (jti,)
        ).fetchone()
    return row is not None

# ── Auth dependency ───────────────────────────────────────────────────────────

def require_auth(
    creds: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> dict:
    payload = _decode_token(creds.credentials)
    if _is_revoked(payload["jti"]):
        raise HTTPException(status_code=401, detail="Token has been revoked")
    return payload

# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/")
def health():
    return {"status": "healthy", "service": "RiderLink Backend API", "version": "2.0.0"}


@app.post("/auth/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(req: RegisterRequest):
    """Register a new rider account and return a JWT immediately."""
    # Hash password with bcrypt (cost factor 12)
    pw_hash = bcrypt.hashpw(req.password.encode(), bcrypt.gensalt(rounds=12)).decode()
    now_ts = int(datetime.now(timezone.utc).timestamp())

    with get_db() as db:
        # Check duplicate email
        existing = db.execute(
            "SELECT id FROM users WHERE email = ?", (req.email,)
        ).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail="Email already registered")

        cursor = db.execute(
            """INSERT INTO users
               (name, email, phone, blood_group, emergency_contact, password_hash, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (req.name, req.email, req.phone, req.blood_group,
             req.emergency_contact, pw_hash, now_ts),
        )
        user_id = cursor.lastrowid

        token, jti, exp = _create_token(user_id, req.email)

        db.execute(
            """INSERT INTO login_sessions (user_id, jti, issued_at, expires_at)
               VALUES (?, ?, ?, ?)""",
            (user_id, jti, now_ts, int(exp.timestamp())),
        )

        # Update last_login
        db.execute(
            "UPDATE users SET last_login = ? WHERE id = ?", (now_ts, user_id)
        )

    logger.info("New rider registered: %s (id=%s)", req.email, user_id)
    return AuthResponse(
        token=token,
        expires_in=TOKEN_TTL_DAYS * 86400,
        user=UserProfile(
            id=user_id,
            name=req.name,
            email=req.email,
            phone=req.phone,
            blood_group=req.blood_group,
            emergency_contact=req.emergency_contact,
            created_at=now_ts,
            last_login=now_ts,
        ),
    )


@app.post("/auth/login", response_model=AuthResponse)
def login(req: LoginRequest):
    """Authenticate with email + password, receive a JWT."""
    with get_db() as db:
        row = db.execute(
            """SELECT id, name, email, phone, blood_group, emergency_contact,
                      password_hash, created_at, last_login
               FROM users WHERE email = ?""",
            (req.email,),
        ).fetchone()

    if not row:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not bcrypt.checkpw(req.password.encode(), row["password_hash"].encode()):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    now_ts = int(datetime.now(timezone.utc).timestamp())
    token, jti, exp = _create_token(row["id"], row["email"])

    with get_db() as db:
        db.execute(
            """INSERT INTO login_sessions (user_id, jti, issued_at, expires_at)
               VALUES (?, ?, ?, ?)""",
            (row["id"], jti, now_ts, int(exp.timestamp())),
        )
        db.execute(
            "UPDATE users SET last_login = ? WHERE id = ?", (now_ts, row["id"])
        )

    logger.info("Rider logged in: %s", req.email)
    return AuthResponse(
        token=token,
        expires_in=TOKEN_TTL_DAYS * 86400,
        user=UserProfile(
            id=row["id"],
            name=row["name"],
            email=row["email"],
            phone=row["phone"],
            blood_group=row["blood_group"],
            emergency_contact=row["emergency_contact"],
            created_at=row["created_at"],
            last_login=now_ts,
        ),
    )


@app.get("/auth/me", response_model=UserProfile)
def get_me(payload: dict = Depends(require_auth)):
    """Return the profile of the currently authenticated rider."""
    user_id = int(payload["sub"])
    with get_db() as db:
        row = db.execute(
            """SELECT id, name, email, phone, blood_group, emergency_contact,
                      created_at, last_login
               FROM users WHERE id = ?""",
            (user_id,),
        ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="User not found")
    return UserProfile(**dict(row))


@app.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(payload: dict = Depends(require_auth)):
    """Revoke the current JWT so it cannot be reused."""
    jti = payload["jti"]
    now_ts = int(datetime.now(timezone.utc).timestamp())
    with get_db() as db:
        db.execute(
            "INSERT OR IGNORE INTO token_blocklist (jti, revoked_at) VALUES (?, ?)",
            (jti, now_ts),
        )
    logger.info("Token revoked: jti=%s", jti)


# ── Existing endpoints (unchanged) ───────────────────────────────────────────

@app.post("/sync")
def sync_app_data(data: SyncData, payload: dict = Depends(require_auth)):
    logger.info("Syncing data for user: %s", data.user_id)
    return {"status": "success", "message": "Data synced successfully"}


@app.post("/predict")
def predict_crash(data: CrashData, payload: dict = Depends(require_auth)):
    logger.info("Evaluating crash telemetry...")
    return {"status": "success", "crash_detected": False, "confidence": 0.95}


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
