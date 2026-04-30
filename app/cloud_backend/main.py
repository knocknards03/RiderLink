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
        # ── Community tables ──────────────────────────────────────────────
        db.execute("""
            CREATE TABLE IF NOT EXISTS groups (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                name         TEXT    NOT NULL,
                description  TEXT,
                banner_color TEXT    DEFAULT '#E91E63',
                creator_id   INTEGER NOT NULL,
                created_at   INTEGER NOT NULL,
                FOREIGN KEY (creator_id) REFERENCES users(id)
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS group_members (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id  INTEGER NOT NULL,
                user_id   INTEGER NOT NULL,
                role      TEXT    DEFAULT 'member',
                joined_at INTEGER NOT NULL,
                UNIQUE(group_id, user_id),
                FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id)  REFERENCES users(id)  ON DELETE CASCADE
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS rides (
                id             INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id       INTEGER NOT NULL,
                creator_id     INTEGER NOT NULL,
                title          TEXT    NOT NULL,
                description    TEXT,
                start_location TEXT,
                end_location   TEXT,
                start_lat      REAL,
                start_lng      REAL,
                end_lat        REAL,
                end_lng        REAL,
                scheduled_at   INTEGER NOT NULL,
                status         TEXT    DEFAULT 'upcoming',
                created_at     INTEGER NOT NULL,
                FOREIGN KEY (group_id)   REFERENCES groups(id) ON DELETE CASCADE,
                FOREIGN KEY (creator_id) REFERENCES users(id)
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS ride_participants (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                ride_id   INTEGER NOT NULL,
                user_id   INTEGER NOT NULL,
                joined_at INTEGER NOT NULL,
                UNIQUE(ride_id, user_id),
                FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS feed_posts (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id    INTEGER NOT NULL,
                group_id   INTEGER,
                post_type  TEXT    DEFAULT 'update',
                content    TEXT    NOT NULL,
                created_at INTEGER NOT NULL,
                FOREIGN KEY (user_id)  REFERENCES users(id)  ON DELETE CASCADE,
                FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE SET NULL
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


# ── Community endpoints ───────────────────────────────────────────────────────

class GroupCreate(BaseModel):
    name: str
    description: Optional[str] = None
    banner_color: Optional[str] = "#E91E63"

class GroupOut(BaseModel):
    id: int
    name: str
    description: Optional[str]
    banner_color: Optional[str]
    creator_id: int
    created_at: int
    member_count: int
    is_member: bool

class RideCreate(BaseModel):
    group_id: int
    title: str
    description: Optional[str] = None
    start_location: Optional[str] = None
    end_location: Optional[str] = None
    start_lat: Optional[float] = None
    start_lng: Optional[float] = None
    end_lat: Optional[float] = None
    end_lng: Optional[float] = None
    scheduled_at: int  # Unix timestamp ms

class RideOut(BaseModel):
    id: int
    group_id: int
    creator_id: int
    title: str
    description: Optional[str]
    start_location: Optional[str]
    end_location: Optional[str]
    start_lat: Optional[float]
    start_lng: Optional[float]
    end_lat: Optional[float]
    end_lng: Optional[float]
    scheduled_at: int
    status: str
    created_at: int
    participant_count: int
    is_joined: bool
    creator_name: Optional[str]

class FeedPostCreate(BaseModel):
    group_id: Optional[int] = None
    post_type: Optional[str] = "update"
    content: str

class FeedPostOut(BaseModel):
    id: int
    user_id: int
    group_id: Optional[int]
    post_type: str
    content: str
    created_at: int
    author_name: str
    author_initials: str

def _initials(name: str) -> str:
    parts = name.strip().split()
    if not parts:
        return "?"
    if len(parts) == 1:
        return parts[0][0].upper()
    return (parts[0][0] + parts[1][0]).upper()


# ── Groups ────────────────────────────────────────────────────────────────────

@app.post("/groups", response_model=GroupOut, status_code=201)
def create_group(req: GroupCreate, payload: dict = Depends(require_auth)):
    user_id = int(payload["sub"])
    now_ts  = int(datetime.now(timezone.utc).timestamp())
    with get_db() as db:
        cur = db.execute(
            "INSERT INTO groups (name, description, banner_color, creator_id, created_at) VALUES (?,?,?,?,?)",
            (req.name, req.description, req.banner_color, user_id, now_ts),
        )
        group_id = cur.lastrowid
        # Creator auto-joins as admin
        db.execute(
            "INSERT INTO group_members (group_id, user_id, role, joined_at) VALUES (?,?,?,?)",
            (group_id, user_id, "admin", now_ts),
        )
    return GroupOut(id=group_id, name=req.name, description=req.description,
                    banner_color=req.banner_color, creator_id=user_id,
                    created_at=now_ts, member_count=1, is_member=True)


@app.get("/groups", response_model=list)
def list_my_groups(payload: dict = Depends(require_auth)):
    user_id = int(payload["sub"])
    with get_db() as db:
        rows = db.execute("""
            SELECT g.id, g.name, g.description, g.banner_color, g.creator_id, g.created_at,
                   (SELECT COUNT(*) FROM group_members WHERE group_id = g.id) AS member_count,
                   1 AS is_member
            FROM groups g
            JOIN group_members gm ON gm.group_id = g.id AND gm.user_id = ?
            ORDER BY g.created_at DESC
        """, (user_id,)).fetchall()
    return [dict(r) for r in rows]


@app.get("/groups/discover", response_model=list)
def discover_groups(payload: dict = Depends(require_auth)):
    """Return groups the user has NOT joined yet."""
    user_id = int(payload["sub"])
    with get_db() as db:
        rows = db.execute("""
            SELECT g.id, g.name, g.description, g.banner_color, g.creator_id, g.created_at,
                   (SELECT COUNT(*) FROM group_members WHERE group_id = g.id) AS member_count,
                   0 AS is_member
            FROM groups g
            WHERE g.id NOT IN (
                SELECT group_id FROM group_members WHERE user_id = ?
            )
            ORDER BY member_count DESC
            LIMIT 30
        """, (user_id,)).fetchall()
    return [dict(r) for r in rows]


@app.post("/groups/{group_id}/join", status_code=200)
def join_group(group_id: int, payload: dict = Depends(require_auth)):
    user_id = int(payload["sub"])
    now_ts  = int(datetime.now(timezone.utc).timestamp())
    with get_db() as db:
        grp = db.execute("SELECT id FROM groups WHERE id=?", (group_id,)).fetchone()
        if not grp:
            raise HTTPException(404, "Group not found")
        db.execute(
            "INSERT OR IGNORE INTO group_members (group_id, user_id, role, joined_at) VALUES (?,?,?,?)",
            (group_id, user_id, "member", now_ts),
        )
        # Post a feed entry
        db.execute(
            "INSERT INTO feed_posts (user_id, group_id, post_type, content, created_at) VALUES (?,?,?,?,?)",
            (user_id, group_id, "joined", "joined the group", now_ts),
        )
    return {"status": "joined"}


@app.delete("/groups/{group_id}/leave", status_code=200)
def leave_group(group_id: int, payload: dict = Depends(require_auth)):
    user_id = int(payload["sub"])
    with get_db() as db:
        db.execute(
            "DELETE FROM group_members WHERE group_id=? AND user_id=?",
            (group_id, user_id),
        )
    return {"status": "left"}


@app.get("/groups/{group_id}/members", response_model=list)
def group_members(group_id: int, payload: dict = Depends(require_auth)):
    with get_db() as db:
        rows = db.execute("""
            SELECT u.id, u.name, u.blood_group, gm.role, gm.joined_at
            FROM group_members gm
            JOIN users u ON u.id = gm.user_id
            WHERE gm.group_id = ?
            ORDER BY gm.role DESC, gm.joined_at ASC
        """, (group_id,)).fetchall()
    return [dict(r) for r in rows]


# ── Rides ─────────────────────────────────────────────────────────────────────

@app.post("/rides", response_model=RideOut, status_code=201)
def create_ride(req: RideCreate, payload: dict = Depends(require_auth)):
    user_id = int(payload["sub"])
    now_ts  = int(datetime.now(timezone.utc).timestamp())
    with get_db() as db:
        # Must be a member of the group
        mem = db.execute(
            "SELECT 1 FROM group_members WHERE group_id=? AND user_id=?",
            (req.group_id, user_id),
        ).fetchone()
        if not mem:
            raise HTTPException(403, "You must be a group member to create a ride")
        cur = db.execute("""
            INSERT INTO rides
              (group_id, creator_id, title, description, start_location, end_location,
               start_lat, start_lng, end_lat, end_lng, scheduled_at, status, created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (req.group_id, user_id, req.title, req.description,
              req.start_location, req.end_location,
              req.start_lat, req.start_lng, req.end_lat, req.end_lng,
              req.scheduled_at, "upcoming", now_ts))
        ride_id = cur.lastrowid
        # Creator auto-joins
        db.execute(
            "INSERT INTO ride_participants (ride_id, user_id, joined_at) VALUES (?,?,?)",
            (ride_id, user_id, now_ts),
        )
        # Feed post
        db.execute(
            "INSERT INTO feed_posts (user_id, group_id, post_type, content, created_at) VALUES (?,?,?,?,?)",
            (user_id, req.group_id, "ride_created", f"created a new ride: {req.title}", now_ts),
        )
        creator_row = db.execute("SELECT name FROM users WHERE id=?", (user_id,)).fetchone()
    return RideOut(id=ride_id, group_id=req.group_id, creator_id=user_id,
                   title=req.title, description=req.description,
                   start_location=req.start_location, end_location=req.end_location,
                   start_lat=req.start_lat, start_lng=req.start_lng,
                   end_lat=req.end_lat, end_lng=req.end_lng,
                   scheduled_at=req.scheduled_at, status="upcoming",
                   created_at=now_ts, participant_count=1, is_joined=True,
                   creator_name=creator_row["name"] if creator_row else None)


@app.get("/groups/{group_id}/rides", response_model=list)
def group_rides(group_id: int, payload: dict = Depends(require_auth)):
    user_id = int(payload["sub"])
    with get_db() as db:
        rows = db.execute("""
            SELECT r.*,
                   (SELECT COUNT(*) FROM ride_participants WHERE ride_id = r.id) AS participant_count,
                   (SELECT COUNT(*) FROM ride_participants WHERE ride_id = r.id AND user_id = ?) AS is_joined,
                   u.name AS creator_name
            FROM rides r
            JOIN users u ON u.id = r.creator_id
            WHERE r.group_id = ?
            ORDER BY r.scheduled_at ASC
        """, (user_id, group_id)).fetchall()
    return [dict(r) for r in rows]


@app.post("/rides/{ride_id}/join", status_code=200)
def join_ride(ride_id: int, payload: dict = Depends(require_auth)):
    user_id = int(payload["sub"])
    now_ts  = int(datetime.now(timezone.utc).timestamp())
    with get_db() as db:
        ride = db.execute("SELECT group_id, title FROM rides WHERE id=?", (ride_id,)).fetchone()
        if not ride:
            raise HTTPException(404, "Ride not found")
        db.execute(
            "INSERT OR IGNORE INTO ride_participants (ride_id, user_id, joined_at) VALUES (?,?,?)",
            (ride_id, user_id, now_ts),
        )
        db.execute(
            "INSERT INTO feed_posts (user_id, group_id, post_type, content, created_at) VALUES (?,?,?,?,?)",
            (user_id, ride["group_id"], "ride_joined", f"is joining the ride: {ride['title']}", now_ts),
        )
    return {"status": "joined"}


@app.delete("/rides/{ride_id}/leave", status_code=200)
def leave_ride(ride_id: int, payload: dict = Depends(require_auth)):
    user_id = int(payload["sub"])
    with get_db() as db:
        db.execute(
            "DELETE FROM ride_participants WHERE ride_id=? AND user_id=?",
            (ride_id, user_id),
        )
    return {"status": "left"}


# ── Feed ──────────────────────────────────────────────────────────────────────

@app.get("/feed", response_model=list)
def get_feed(payload: dict = Depends(require_auth), limit: int = 30, offset: int = 0):
    """Global feed of all groups the user belongs to."""
    user_id = int(payload["sub"])
    with get_db() as db:
        rows = db.execute("""
            SELECT fp.id, fp.user_id, fp.group_id, fp.post_type, fp.content, fp.created_at,
                   u.name AS author_name
            FROM feed_posts fp
            JOIN users u ON u.id = fp.user_id
            WHERE fp.group_id IN (
                SELECT group_id FROM group_members WHERE user_id = ?
            ) OR fp.group_id IS NULL
            ORDER BY fp.created_at DESC
            LIMIT ? OFFSET ?
        """, (user_id, limit, offset)).fetchall()
    result = []
    for r in rows:
        d = dict(r)
        d["author_initials"] = _initials(d["author_name"])
        result.append(d)
    return result


@app.post("/feed", response_model=FeedPostOut, status_code=201)
def create_post(req: FeedPostCreate, payload: dict = Depends(require_auth)):
    user_id = int(payload["sub"])
    now_ts  = int(datetime.now(timezone.utc).timestamp())
    with get_db() as db:
        cur = db.execute(
            "INSERT INTO feed_posts (user_id, group_id, post_type, content, created_at) VALUES (?,?,?,?,?)",
            (user_id, req.group_id, req.post_type, req.content, now_ts),
        )
        post_id = cur.lastrowid
        author  = db.execute("SELECT name FROM users WHERE id=?", (user_id,)).fetchone()
    name = author["name"] if author else "Rider"
    return FeedPostOut(id=post_id, user_id=user_id, group_id=req.group_id,
                       post_type=req.post_type, content=req.content,
                       created_at=now_ts, author_name=name,
                       author_initials=_initials(name))


# ── Simulation / WiFi-bridge endpoints (no ESP32 needed) ─────────────────────
# Two phones exchange location, messages, SOS, hazards through the backend.
# Each phone polls /sim/pull every 3 seconds to get events from other riders.

import threading
_sim_lock = threading.Lock()
_sim_events: list = []          # shared in-memory event bus (resets on restart)
_SIM_MAX_AGE_S = 30             # discard events older than 30 seconds

class SimEvent(BaseModel):
    user_id: int
    event_type: str             # location | message | sos | hazard
    payload: dict
    ts: Optional[int] = None    # filled server-side

@app.post("/sim/push", status_code=200)
def sim_push(event: SimEvent, payload_auth: dict = Depends(require_auth)):
    """Phone pushes an event (location update, message, SOS, hazard)."""
    now_ts = int(datetime.now(timezone.utc).timestamp())
    with _sim_lock:
        _sim_events.append({
            "user_id":    event.user_id,
            "event_type": event.event_type,
            "payload":    event.payload,
            "ts":         now_ts,
        })
        # Prune old events to keep memory bounded
        cutoff = now_ts - _SIM_MAX_AGE_S
        _sim_events[:] = [e for e in _sim_events if e["ts"] >= cutoff]
    return {"status": "ok", "ts": now_ts}

@app.get("/sim/pull", response_model=list)
def sim_pull(since: int = 0, payload_auth: dict = Depends(require_auth)):
    """Phone pulls all events from OTHER riders since a given timestamp."""
    caller_id = int(payload_auth["sub"])
    with _sim_lock:
        return [
            e for e in _sim_events
            if e["ts"] > since and e["user_id"] != caller_id
        ]




if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
