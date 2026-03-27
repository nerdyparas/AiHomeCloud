# Web Upload Portal — Design & Task Breakdown

> LAN-accessible web interface for drag-and-drop file uploads to AiHomeCloud storage.
> Created: 2026-03-27

---

## Problem

- Telegram bot file uploads are capped at 2 GB.
- The Flutter mobile app only runs on phones — no desktop/laptop support.
- Users on a Mac, PC, or Linux laptop on the same LAN have no way to easily transfer large files to AiHomeCloud storage.

## Goal

A lightweight, self-contained web page served by the existing FastAPI backend at `https://<device-ip>:8443/web` that allows any browser on the local network to:

1. Select a user profile (with emoji avatar) and authenticate via PIN
2. Drag-and-drop (or browse) files into 3 destination zones: **Personal**, **Family**, **Entertainment**
3. See real-time upload progress per file
4. Log out and return to user selection

No new backend upload logic — reuse the existing `POST /api/v1/files/upload` endpoint.

## Strategy

### Architecture

- **One new route file**: `backend/app/routes/web_upload_routes.py`
- **One route**: `GET /web` → serves a self-contained HTML page (HTML + CSS + JS inlined)
- **No frontend framework** — vanilla HTML5/CSS3/JS (ES6+)
- **No build tools** — no npm, no webpack, no separate process
- **Same pattern** as `telegram_upload_routes.py` — Python serves inline HTML string
- **Auth flow**: JS calls existing `GET /auth/users/names` → `POST /auth/login` → stores JWT in `sessionStorage`
- **Upload flow**: JS calls existing `POST /api/v1/files/upload` with JWT + `path` query param
- **Styling**: Dark theme matching Cubie aesthetic (reuse colours from telegram upload page)

### Page Flow

```
[User Picker]  →  (PIN if needed)  →  [Upload Dashboard]  →  (Logout)  →  [User Picker]
```

### User Picker View

- Fetches `GET /auth/users/names` (public, no auth)
- Shows user cards in a centered grid: emoji avatar + name
- Click a user → if `has_pin` is true, show PIN input modal; if false, login directly
- Calls `POST /auth/login` with `{ name, pin }` → stores `accessToken` in `sessionStorage`

### Upload Dashboard View

- Header: "Welcome, {name}" + Logout button (top-right)
- 3 large equal drop zones in a responsive grid (CSS Grid, `1fr 1fr 1fr` on wide, stacks on narrow)
- Each zone:
  - Title + icon: **Personal** (🗂️), **Family** (👨‍👩‍👧‍👦), **Entertainment** (🎬)
  - Large dashed-border area for drag-and-drop
  - "or click to browse" file picker fallback
  - Upload queue list showing: filename, progress bar (%), status (uploading/done/failed)
- Upload path mapping:
  - Personal → `path=/srv/nas/personal/{username}/`
  - Family → `path=/srv/nas/family/`
  - Entertainment → `path=/srv/nas/entertainment/`

### Upload Mechanics

- Uses `XMLHttpRequest` (not fetch) for `upload.onprogress` events
- Sends `Authorization: Bearer {token}` header
- Sends file as `multipart/form-data` with `file` field + `path` query param
- Multiple files can be dropped at once → queued and uploaded sequentially per zone
- Blocked extensions handled server-side (existing validation)
- Max file size enforced server-side (existing 5 GB limit)

### Security

- LAN-only access (same as all AiHomeCloud endpoints)
- HTTPS with self-signed cert (existing TLS infrastructure)
- JWT auth with existing token validation
- `sessionStorage` — tokens cleared on tab close
- All uploads go through existing `_safe_resolve()` path sandboxing
- No new attack surface — just a new HTML page calling existing APIs

---

## Tasks

Each task is a self-contained unit an LLM can complete in one session.

### Task 1 — Create route file skeleton

**File**: `backend/app/routes/web_upload_routes.py`

- Create a new FastAPI router with `GET /web` endpoint
- Return `HTMLResponse` with a placeholder `<h1>AiHomeCloud</h1>`
- Register the router in `backend/app/main.py`
- Verify it works: `curl -sk https://localhost:8443/web`

**Acceptance**: Hitting `/web` in a browser shows the placeholder HTML.

---

### Task 2 — Build User Picker UI

**In**: `web_upload_routes.py` (extend the HTML string)

Build the user selection screen:

- On page load, `fetch('/auth/users/names')` → render user cards
- Each card shows emoji (large, 48px+) and name
- CSS Grid layout, centered on page, gap between cards
- Dark theme: background `#121212`, cards `#1e1e1e`, text white, accent `#6C63FF`
- Cubie logo/title at top: "AiHomeCloud"
- Click a card:
  - If `has_pin === false` → call login immediately
  - If `has_pin === true` → show PIN input (4-digit, auto-submit on 4th digit)
- On successful login → store `accessToken` and `user.name` in `sessionStorage`
- On failed login → show error message, stay on picker
- Transition to upload dashboard view (JS show/hide, no page reload)

**Acceptance**: Can select a user, enter PIN, and see upload dashboard appear.

---

### Task 3 — Build Upload Dashboard layout

**In**: `web_upload_routes.py` (extend the HTML string)

Build the 3-zone upload dashboard:

- Header bar: "Welcome, {name}" (left) + "Logout" button (right)
- 3 equal zones using CSS Grid: `grid-template-columns: 1fr 1fr 1fr`
- Responsive: on screens < 900px → stack vertically (`1fr`)
- Each zone:
  - Title with emoji icon
  - Large drop area (min-height 300px) with dashed border
  - Text: "Drag files here or click to browse"
  - Hidden `<input type="file" multiple>` triggered on click
  - Visual feedback on dragover (border colour change, background tint)
- Zones fill available space (`min-height: calc(100vh - 80px)`)

**Acceptance**: 3 drop zones render, respond to drag hover, and trigger file picker on click.

---

### Task 4 — Wire up file uploads with progress

**In**: `web_upload_routes.py` (extend the JS)

Implement actual file upload:

- On file drop or file picker selection:
  - For each file, create an upload entry in the zone's queue list
  - Show: filename (truncated), progress bar (0%), status text
- Upload using `XMLHttpRequest`:
  - `POST /api/v1/files/upload?path={target_path}`
  - Header: `Authorization: Bearer {token}`
  - Body: `FormData` with `file` field
  - `xhr.upload.onprogress` → update progress bar width + percentage text
  - `xhr.onload` → mark as done (green checkmark) or failed (red, show error)
- Sequential upload per zone (avoid overwhelming the server)
- Multiple zones can upload in parallel (one file per zone at a time)
- Handle 401 response → redirect to user picker (token expired)
- Handle network errors → show retry option

**Acceptance**: Can drag a file, see progress bar fill, and file appears in correct NAS folder.

---

### Task 5 — Logout + polish + testing

**In**: `web_upload_routes.py`

- Logout button: clears `sessionStorage`, shows user picker view
- Add upload complete summary (X files uploaded, Y failed)
- Add favicon (inline SVG or emoji)
- Add `<title>AiHomeCloud</title>`
- Test edge cases:
  - No users exist yet → show "No users configured" message
  - Large file (>5 GB) → server rejects, UI shows error
  - Blocked extension (.exe) → server rejects, UI shows error
  - Drop multiple files → all queued and uploaded in order
  - Browser back button doesn't break the SPA
  - Works in Chrome, Firefox, Safari
- Add to `backend/app/main.py` router registration comment

**Acceptance**: Full flow works end-to-end. Logout returns to picker. Error states handled gracefully.

---

### Task 6 — Documentation updates

- Update `kb/api-contracts.md` — add `GET /web` endpoint
- Update `kb/architecture.md` — mention web upload portal
- Update `kb/changelog.md` — dated entry for web upload feature
- Update `.github/copilot-instructions.md` — add `web_upload_routes.py` to route table
- Update `kb/features.md` — add web upload to feature inventory

---

## Non-Goals (explicitly out of scope)

- File browsing/downloading (use mobile app for that)
- User creation/management (use mobile app)
- Storage management (use mobile app)
- File deletion or renaming (use mobile app)
- Separate frontend build process (must be self-contained HTML)
- Internet/WAN access (LAN-only)
- Mobile-optimized responsive design (mobile users have the app)

---

## Testing & Verification

### 1. Service health

```bash
# Confirm backend is running
systemctl is-active aihomecloud

# Confirm health endpoint responds
curl -sk https://localhost:8443/api/health
# expected: {"status":"ok"}
```

### 2. Web portal reachable

```bash
# Returns HTTP 200 and the full HTML page
curl -sk -o /dev/null -w "%{http_code}\n" https://localhost:8443/web
# expected: 200

# From another machine on the LAN (replace IP):
curl -sk -o /dev/null -w "%{http_code}\n" https://192.168.0.241:8443/web
# expected: 200
```

### 3. Browser walkthrough (manual)

Open `https://<device-ip>:8443/web` in Chrome, Firefox, or Safari.
Accept the self-signed certificate warning.

| Step | What to do | Expected result |
|------|-----------|-----------------|
| User picker loads | Page opens | AiHomeCloud logo + user cards shown |
| No-PIN login | Click a user that has no PIN | Jumps straight to upload dashboard |
| PIN login | Click a user with a PIN, type 4 digits | Auto-submits; dashboard appears |
| Wrong PIN | Enter incorrect PIN | Error message shown, dots reset, try again |
| All 3 zones visible | After login | Personal 🗂️ / Family 👨‍👩‍👧‍👦 / Entertainment 🎬 zones rendered |
| Drag hover | Drag a file over a zone without dropping | Drop area border turns purple, background tints |
| Click to browse | Click a drop area | Native file picker opens |
| Upload a small file | Drop a .txt or .jpg | Progress bar fills to 100%, shows ✓ Done |
| Upload large file (>100 MB) | Drop a video | Progress bar updates in real time |
| Multi-file drop | Drop 3+ files at once | All queued, upload sequentially, individual progress |
| Per-zone stats | After uploads finish | "X uploaded · Y failed" shown below queue |
| Blocked extension | Drop a .sh or .exe | Server rejects with 422, item shows red ✗ error |
| Retry | Click Retry on a failed item | Item re-queues and attempts upload again |
| Logout | Click Logout button | sessionStorage cleared, user picker shown |
| Browser back | Press browser back button | Stays on /web (does not navigate away) |
| Responsive | Resize window below 900px | 3 zones stack vertically |

### 4. Verify files landed on NAS

```bash
# After uploading to Personal zone (logged in as "paras"):
ls /srv/nas/personal/paras/

# After uploading to Family zone:
ls /srv/nas/family/

# After uploading to Entertainment zone:
ls /srv/nas/entertainment/
```

### 5. Verify upload via API directly

```bash
# Get a token first
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"name":"paras","pin":""}' | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])")

# Upload a test file to Personal
curl -sk -X POST "https://localhost:8443/api/v1/files/upload?path=/srv/nas/personal/paras/" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@/etc/hostname" | python3 -m json.tool
# expected: {"name":"hostname","path":"...","sizeBytes":...}
```

### 6. Session security check

```bash
# Request without token should fail
curl -sk -X POST "https://localhost:8443/api/v1/files/upload?path=/srv/nas/personal/paras/" \
  -F "file=@/etc/hostname"
# expected: HTTP 401 or 403
```

### 7. Service restart survivability

```bash
sudo systemctl restart aihomecloud
sleep 5
curl -sk -o /dev/null -w "%{http_code}\n" https://localhost:8443/web
# expected: 200
```
