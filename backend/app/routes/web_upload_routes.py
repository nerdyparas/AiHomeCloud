"""
AiHomeCloud Web Upload Portal — serves a self-contained HTML page at GET /web.

This is a LAN-accessible drag-and-drop file upload interface for desktop/laptop
users who cannot run the Flutter mobile app. It reuses existing API endpoints:
  - GET  /auth/users/names   → user picker
  - POST /auth/login         → PIN authentication
  - POST /api/v1/files/upload → file upload with progress

No new upload logic — this route only serves HTML/CSS/JS.
"""

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter()

_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AiHomeCloud</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🏠</text></svg>">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #121212;
      color: #ffffff;
      min-height: 100vh;
    }

    /* ── Views ─────────────────────────────────────────────────────────── */
    .view { display: none; }
    .view.active { display: flex; }

    /* ── User Picker ────────────────────────────────────────────────────── */
    #view-picker {
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 2rem;
      gap: 2rem;
    }

    .logo {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0.5rem;
    }
    .logo-icon { font-size: 3rem; line-height: 1; }
    .logo-title {
      font-size: 1.75rem;
      font-weight: 700;
      color: #6C63FF;
      letter-spacing: -0.5px;
    }
    .logo-subtitle {
      font-size: 0.9rem;
      color: #888;
    }

    .user-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
      gap: 1rem;
      width: 100%;
      max-width: 680px;
      justify-content: center;
    }

    .user-card {
      background: #1e1e1e;
      border: 1.5px solid #2a2a2a;
      border-radius: 16px;
      padding: 1.5rem 1rem;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0.6rem;
      cursor: pointer;
      transition: border-color 0.15s, transform 0.1s, background 0.15s;
      user-select: none;
    }
    .user-card:hover {
      border-color: #6C63FF;
      background: #252535;
      transform: translateY(-2px);
    }
    .user-card:active { transform: translateY(0); }
    .user-card .avatar { font-size: 3rem; line-height: 1; }
    .user-card .uname {
      font-size: 0.95rem;
      font-weight: 600;
      text-align: center;
      color: #eee;
      word-break: break-word;
    }

    .picker-error {
      color: #ff6b6b;
      font-size: 0.875rem;
      text-align: center;
      min-height: 1.2em;
    }

    /* ── PIN Modal ──────────────────────────────────────────────────────── */
    #pin-overlay {
      display: none;
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.7);
      backdrop-filter: blur(4px);
      z-index: 100;
      align-items: center;
      justify-content: center;
    }
    #pin-overlay.open { display: flex; }

    .pin-modal {
      background: #1e1e1e;
      border: 1.5px solid #2a2a2a;
      border-radius: 20px;
      padding: 2rem 2.5rem;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 1.25rem;
      width: 100%;
      max-width: 340px;
    }
    .pin-modal .avatar-lg { font-size: 4rem; line-height: 1; }
    .pin-modal h2 { font-size: 1.1rem; font-weight: 600; color: #eee; }

    .pin-dots {
      display: flex;
      gap: 1rem;
    }
    .pin-dot {
      width: 14px;
      height: 14px;
      border-radius: 50%;
      border: 2px solid #555;
      background: transparent;
      transition: background 0.1s, border-color 0.1s;
    }
    .pin-dot.filled { background: #6C63FF; border-color: #6C63FF; }

    .pin-keypad {
      display: grid;
      grid-template-columns: repeat(3, 64px);
      gap: 0.6rem;
    }
    .pin-key {
      height: 52px;
      border-radius: 12px;
      border: 1.5px solid #2a2a2a;
      background: #252525;
      color: #fff;
      font-size: 1.2rem;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.1s, border-color 0.1s;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .pin-key:hover { background: #333; border-color: #6C63FF; }
    .pin-key:active { background: #6C63FF; }
    .pin-key.del { font-size: 1rem; color: #aaa; }
    .pin-key.spacer { visibility: hidden; cursor: default; }

    .pin-error {
      color: #ff6b6b;
      font-size: 0.85rem;
      text-align: center;
      min-height: 1.2em;
    }
    .pin-cancel {
      background: none;
      border: none;
      color: #888;
      font-size: 0.875rem;
      cursor: pointer;
      text-decoration: underline;
    }
    .pin-cancel:hover { color: #ccc; }

    /* ── Upload Dashboard ───────────────────────────────────────────────── */
    #view-dashboard {
      flex-direction: column;
      min-height: 100vh;
    }

    .dash-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0 1.5rem;
      height: 64px;
      background: #1a1a1a;
      border-bottom: 1px solid #2a2a2a;
      flex-shrink: 0;
    }
    .dash-header .greeting {
      display: flex;
      align-items: center;
      gap: 0.6rem;
      font-weight: 600;
      font-size: 1rem;
      color: #eee;
    }
    .dash-header .greeting .logo-small { color: #6C63FF; font-size: 1.1rem; }
    .btn-logout {
      background: none;
      border: 1.5px solid #333;
      border-radius: 8px;
      color: #aaa;
      font-size: 0.875rem;
      padding: 0.4rem 0.9rem;
      cursor: pointer;
      transition: border-color 0.15s, color 0.15s;
    }
    .btn-logout:hover { border-color: #6C63FF; color: #fff; }

    .zones-grid {
      display: grid;
      grid-template-columns: 1fr 1fr 1fr;
      gap: 1rem;
      padding: 1rem;
      flex: 1;
      min-height: calc(100vh - 64px);
    }
    @media (max-width: 900px) {
      .zones-grid { grid-template-columns: 1fr; }
    }

    .zone {
      background: #1e1e1e;
      border-radius: 16px;
      display: flex;
      flex-direction: column;
      overflow: hidden;
      border: 1.5px solid #2a2a2a;
      transition: border-color 0.15s;
    }
    .zone-header {
      padding: 1rem 1.25rem 0.6rem;
      display: flex;
      align-items: center;
      gap: 0.5rem;
      flex-shrink: 0;
    }
    .zone-icon { font-size: 1.5rem; line-height: 1; }
    .zone-title { font-size: 1rem; font-weight: 700; color: #eee; }
    .zone-subtitle { font-size: 0.78rem; color: #666; margin-left: auto; }

    .zone-drop {
      margin: 0 1rem;
      border: 2px dashed #333;
      border-radius: 12px;
      min-height: 220px;
      flex: 1;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 0.5rem;
      cursor: pointer;
      transition: border-color 0.15s, background 0.15s;
      padding: 1.5rem;
    }
    .zone-drop:hover {
      border-color: #6C63FF;
      background: rgba(108,99,255,0.04);
    }
    .zone.dragover .zone-drop {
      border-color: #6C63FF;
      background: rgba(108,99,255,0.1);
    }
    .drop-icon { font-size: 2.5rem; opacity: 0.4; }
    .drop-hint { font-size: 0.875rem; color: #666; text-align: center; }
    .drop-hint span { color: #6C63FF; text-decoration: underline; }

    .zone-queue {
      padding: 0.5rem 1rem 0;
      display: flex;
      flex-direction: column;
      gap: 0.4rem;
      flex-shrink: 0;
    }

    /* ── Upload queue items ─────────────────────────────────────────────── */
    .upload-item {
      background: #252525;
      border-radius: 8px;
      padding: 0.45rem 0.65rem;
      display: flex;
      flex-direction: column;
      gap: 0.3rem;
    }
    .upload-row {
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }
    .upload-name {
      color: #ccc;
      font-size: 0.8rem;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      flex: 1;
      min-width: 0;
    }
    .upload-status {
      font-size: 0.75rem;
      white-space: nowrap;
      flex-shrink: 0;
    }
    .upload-status.pending   { color: #888; }
    .upload-status.uploading { color: #6C63FF; }
    .upload-status.done      { color: #4caf50; }
    .upload-status.failed    { color: #ff6b6b; }
    .upload-bar-wrap {
      height: 3px;
      background: #2a2a2a;
      border-radius: 2px;
      overflow: hidden;
    }
    .upload-bar {
      height: 100%;
      background: #6C63FF;
      border-radius: 2px;
      width: 0%;
      transition: width 0.15s linear;
    }
    .upload-bar.done   { background: #4caf50; }
    .upload-bar.failed { background: #ff6b6b; }
    .btn-retry {
      background: none;
      border: 1px solid #ff6b6b;
      border-radius: 4px;
      color: #ff6b6b;
      font-size: 0.7rem;
      padding: 0.15rem 0.4rem;
      cursor: pointer;
      flex-shrink: 0;
    }
    .btn-retry:hover { background: rgba(255,107,107,0.1); }
    .zone-stats {
      padding: 0.3rem 1rem 0.8rem;
      font-size: 0.75rem;
      color: #666;
      flex-shrink: 0;
      min-height: 1.6em;
    }
  </style>
</head>
<body>

<!-- ── User Picker View ─────────────────────────────────────────────── -->
<div id="view-picker" class="view active">
  <div class="logo">
    <div class="logo-icon">🏠</div>
    <div class="logo-title">AiHomeCloud</div>
    <div class="logo-subtitle">Choose your profile to continue</div>
  </div>

  <div id="user-grid" class="user-grid">
    <!-- populated by JS -->
  </div>

  <div id="picker-error" class="picker-error"></div>
</div>

<!-- ── PIN Modal ────────────────────────────────────────────────────── -->
<div id="pin-overlay">
  <div class="pin-modal">
    <div id="pin-avatar" class="avatar-lg">👤</div>
    <h2 id="pin-username">Enter PIN</h2>
    <div class="pin-dots">
      <div class="pin-dot" id="d0"></div>
      <div class="pin-dot" id="d1"></div>
      <div class="pin-dot" id="d2"></div>
      <div class="pin-dot" id="d3"></div>
    </div>
    <div class="pin-keypad" id="pin-keypad">
      <!-- keys injected by JS -->
    </div>
    <div id="pin-error" class="pin-error"></div>
    <button class="pin-cancel" id="pin-cancel">Cancel</button>
  </div>
</div>

<!-- ── Upload Dashboard View ──────────────────────────────────────── -->
<div id="view-dashboard" class="view">

  <header class="dash-header">
    <div class="greeting">
      <span class="logo-small">🏠</span>
      <span>AiHomeCloud &mdash; <span id="dash-username">…</span></span>
    </div>
    <button class="btn-logout" id="btn-logout">Logout</button>
  </header>

  <div class="zones-grid">

    <!-- Personal zone -->
    <div class="zone" id="zone-personal" data-zone="personal">
      <div class="zone-header">
        <span class="zone-icon">🗂️</span>
        <span class="zone-title">Personal</span>
        <span class="zone-subtitle">Your private files</span>
      </div>
      <div class="zone-drop" id="drop-personal">
        <div class="drop-icon">⬆️</div>
        <div class="drop-hint">Drag files here<br>or <span>click to browse</span></div>
      </div>
      <input type="file" id="file-personal" multiple style="display:none">
      <div class="zone-queue" id="queue-personal"></div>
      <div class="zone-stats" id="stats-personal"></div>
    </div>

    <!-- Family zone -->
    <div class="zone" id="zone-family" data-zone="family">
      <div class="zone-header">
        <span class="zone-icon">👨‍👩‍👧‍👦</span>
        <span class="zone-title">Family</span>
        <span class="zone-subtitle">Shared with everyone</span>
      </div>
      <div class="zone-drop" id="drop-family">
        <div class="drop-icon">⬆️</div>
        <div class="drop-hint">Drag files here<br>or <span>click to browse</span></div>
      </div>
      <input type="file" id="file-family" multiple style="display:none">
      <div class="zone-queue" id="queue-family"></div>
      <div class="zone-stats" id="stats-family"></div>
    </div>

    <!-- Entertainment zone -->
    <div class="zone" id="zone-entertainment" data-zone="entertainment">
      <div class="zone-header">
        <span class="zone-icon">🎬</span>
        <span class="zone-title">Entertainment</span>
        <span class="zone-subtitle">Movies, music &amp; more</span>
      </div>
      <div class="zone-drop" id="drop-entertainment">
        <div class="drop-icon">⬆️</div>
        <div class="drop-hint">Drag files here<br>or <span>click to browse</span></div>
      </div>
      <input type="file" id="file-entertainment" multiple style="display:none">
      <div class="zone-queue" id="queue-entertainment"></div>
      <div class="zone-stats" id="stats-entertainment"></div>
    </div>

  </div>
</div>

<script>
'use strict';

// ── State ────────────────────────────────────────────────────────────────
const state = {
  users: [],
  selectedUser: null,   // { name, icon_emoji, has_pin }
  pin: '',
  token: null,
  userName: null,
};
// Per-zone upload queues, busy flags and summary counters
const uploadQueues = { personal: [], family: [], entertainment: [] };
const uploadBusy   = { personal: false, family: false, entertainment: false };
const uploadStats  = {
  personal:      { done: 0, failed: 0 },
  family:        { done: 0, failed: 0 },
  entertainment: { done: 0, failed: 0 },
};
// ── View switching ───────────────────────────────────────────────────────
function showView(id) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  document.getElementById(id).classList.add('active');
}

// ── User Picker ──────────────────────────────────────────────────────────
async function loadUsers() {
  const grid = document.getElementById('user-grid');
  const err  = document.getElementById('picker-error');
  grid.innerHTML = '';
  err.textContent = '';

  let users;
  try {
    const res = await fetch('/api/v1/auth/users/names');
    if (!res.ok) throw new Error('Server error ' + res.status);
    const data = await res.json();
    users = data.users || [];
  } catch (e) {
    err.textContent = 'Could not load users: ' + e.message;
    return;
  }

  state.users = users;

  if (users.length === 0) {
    err.textContent = 'No users configured. Set up profiles in the mobile app first.';
    return;
  }

  users.forEach(u => {
    const card = document.createElement('div');
    card.className = 'user-card';
    card.innerHTML = `
      <div class="avatar">${escHtml(u.icon_emoji || '👤')}</div>
      <div class="uname">${escHtml(u.name)}</div>
    `;
    card.addEventListener('click', () => onUserSelect(u));
    grid.appendChild(card);
  });
}

function onUserSelect(user) {
  state.selectedUser = user;
  if (user.has_pin) {
    openPinModal(user);
  } else {
    doLogin(user.name, '');
  }
}

// ── Login ────────────────────────────────────────────────────────────────
async function doLogin(name, pin) {
  const pickerErr = document.getElementById('picker-error');
  const pinErr    = document.getElementById('pin-error');
  pickerErr.textContent = '';
  pinErr.textContent = '';

  let data;
  try {
    const res = await fetch('/api/v1/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, pin }),
    });
    data = await res.json();
    if (!res.ok) {
      const msg = data.detail || 'Login failed';
      if (state.selectedUser && state.selectedUser.has_pin) {
        pinErr.textContent = msg;
        resetPin();
      } else {
        pickerErr.textContent = msg;
      }
      return;
    }
  } catch (e) {
    const msg = 'Network error: ' + e.message;
    if (state.selectedUser && state.selectedUser.has_pin) {
      pinErr.textContent = msg;
      resetPin();
    } else {
      pickerErr.textContent = msg;
    }
    return;
  }

  // Store session
  sessionStorage.setItem('ahc_token', data.accessToken);
  sessionStorage.setItem('ahc_user',  data.user.name);
  state.token    = data.accessToken;
  state.userName = data.user.name;

  closePinModal();
  initDashboard();
  showView('view-dashboard');
}

// ── Dashboard ────────────────────────────────────────────────────────────
const ZONE_PATHS = {
  personal:      () => '/srv/nas/personal/' + encodeURIComponent(state.userName) + '/',
  family:        () => '/srv/nas/family/',
  entertainment: () => '/srv/nas/entertainment/',
};

function initDashboard() {
  resetUploadState();
  document.getElementById('dash-username').textContent = state.userName || '';
  ['personal', 'family', 'entertainment'].forEach(zone => setupZone(zone));
}

function setupZone(zoneId) {
  const zoneEl  = document.getElementById('zone-' + zoneId);
  const dropEl  = document.getElementById('drop-' + zoneId);
  const fileEl  = document.getElementById('file-' + zoneId);

  // Click on drop area → open file picker
  dropEl.addEventListener('click', () => fileEl.click());

  // File picker selection
  fileEl.addEventListener('change', () => {
    if (fileEl.files && fileEl.files.length) {
      onFilesSelected(zoneId, Array.from(fileEl.files));
      fileEl.value = '';  // reset so same file can be re-selected
    }
  });

  // Drag events
  dropEl.addEventListener('dragenter', e => { e.preventDefault(); zoneEl.classList.add('dragover'); });
  dropEl.addEventListener('dragover',  e => { e.preventDefault(); zoneEl.classList.add('dragover'); });
  dropEl.addEventListener('dragleave', e => {
    // Only remove if truly leaving the zone (not entering a child)
    if (!zoneEl.contains(e.relatedTarget)) zoneEl.classList.remove('dragover');
  });
  dropEl.addEventListener('drop', e => {
    e.preventDefault();
    zoneEl.classList.remove('dragover');
    const files = Array.from(e.dataTransfer.files);
    if (files.length) onFilesSelected(zoneId, files);
  });
}

// ── Upload engine ───────────────────────────────────────────────────────────────
function resetUploadState() {
  ['personal', 'family', 'entertainment'].forEach(z => {
    uploadQueues[z] = [];
    uploadBusy[z]   = false;
    uploadStats[z]  = { done: 0, failed: 0 };
  });
}

function onFilesSelected(zoneId, files) {
  files.forEach(f => {
    const itemEl = createQueueItem(f.name);
    document.getElementById('queue-' + zoneId).appendChild(itemEl);
    uploadQueues[zoneId].push({ file: f, itemEl });
  });
  processQueue(zoneId);
}

function createQueueItem(name) {
  const el = document.createElement('div');
  el.className = 'upload-item';
  const nameHtml = escHtml(truncateName(name, 36));
  const nameFull = escHtml(name);
  el.innerHTML =
    '<div class="upload-row">' +
      '<span class="upload-name" title="' + nameFull + '">' + nameHtml + '</span>' +
      '<span class="upload-status pending">Queued</span>' +
    '</div>' +
    '<div class="upload-bar-wrap"><div class="upload-bar"></div></div>';
  return el;
}

function truncateName(str, max) {
  if (str.length <= max) return str;
  const dot = str.lastIndexOf('.');
  if (dot > 0 && str.length - dot <= 8) {
    return str.slice(0, max - (str.length - dot) - 1) + '\u2026' + str.slice(dot);
  }
  return str.slice(0, max - 1) + '\u2026';
}

function processQueue(zoneId) {
  if (uploadBusy[zoneId] || uploadQueues[zoneId].length === 0) return;
  uploadBusy[zoneId] = true;
  const entry = uploadQueues[zoneId].shift();
  uploadFile(zoneId, entry).then(() => {
    uploadBusy[zoneId] = false;
    updateZoneStats(zoneId);
    processQueue(zoneId);
  });
}

function uploadFile(zoneId, entry) {
  return new Promise(resolve => {
    const { file, itemEl } = entry;
    const statusEl = itemEl.querySelector('.upload-status');
    const barEl    = itemEl.querySelector('.upload-bar');
    statusEl.className   = 'upload-status uploading';
    statusEl.textContent = '0%';

    const path = ZONE_PATHS[zoneId]();
    const url  = '/api/v1/files/upload?path=' + encodeURIComponent(path);
    const fd   = new FormData();
    fd.append('file', file);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', url);
    xhr.setRequestHeader('Authorization', 'Bearer ' + state.token);

    xhr.upload.onprogress = e => {
      if (e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100);
        barEl.style.width    = pct + '%';
        statusEl.textContent = pct + '%';
      }
    };

    xhr.onload = () => {
      if (xhr.status === 401) {
        statusEl.className   = 'upload-status failed';
        statusEl.textContent = 'Session expired';
        barEl.classList.add('failed');
        uploadStats[zoneId].failed++;
        setTimeout(() => document.getElementById('btn-logout').click(), 1500);
        resolve();
        return;
      }
      if (xhr.status >= 200 && xhr.status < 300) {
        barEl.style.width    = '100%';
        barEl.classList.add('done');
        statusEl.className   = 'upload-status done';
        statusEl.textContent = '\u2713 Done';
        uploadStats[zoneId].done++;
        resolve();
      } else {
        let errMsg = 'Failed (' + xhr.status + ')';
        try {
          const body = JSON.parse(xhr.responseText);
          errMsg = body.detail || errMsg;
        } catch(_) {}
        markFailed(zoneId, entry, itemEl, statusEl, barEl, errMsg, resolve);
      }
    };

    xhr.onerror = () =>
      markFailed(zoneId, entry, itemEl, statusEl, barEl, 'Network error', resolve);

    xhr.send(fd);
  });
}

function markFailed(zoneId, entry, itemEl, statusEl, barEl, msg, resolve) {
  barEl.classList.add('failed');
  statusEl.className   = 'upload-status failed';
  statusEl.textContent = '\u2717 ' + msg;
  uploadStats[zoneId].failed++;
  const row      = itemEl.querySelector('.upload-row');
  const retryBtn = document.createElement('button');
  retryBtn.className   = 'btn-retry';
  retryBtn.textContent = 'Retry';
  retryBtn.addEventListener('click', () => {
    retryBtn.remove();
    barEl.className      = 'upload-bar';
    barEl.style.width    = '0%';
    statusEl.className   = 'upload-status pending';
    statusEl.textContent = 'Queued';
    uploadStats[zoneId].failed = Math.max(0, uploadStats[zoneId].failed - 1);
    uploadQueues[zoneId].unshift(entry);
    updateZoneStats(zoneId);
    processQueue(zoneId);
  });
  row.appendChild(retryBtn);
  resolve();
}

function updateZoneStats(zoneId) {
  const el = document.getElementById('stats-' + zoneId);
  if (!el) return;
  const { done, failed } = uploadStats[zoneId];
  if (done + failed === 0) { el.textContent = ''; return; }
  const parts = [];
  if (done)   parts.push(done   + ' uploaded');
  if (failed) parts.push(failed + ' failed');
  el.textContent = parts.join(' \u00b7 ');
}

// ── PIN Modal ────────────────────────────────────────────────────────────
function openPinModal(user) {
  document.getElementById('pin-avatar').textContent   = user.icon_emoji || '👤';
  document.getElementById('pin-username').textContent = user.name;
  document.getElementById('pin-error').textContent    = '';
  resetPin();
  buildKeypad();
  document.getElementById('pin-overlay').classList.add('open');
}

function closePinModal() {
  document.getElementById('pin-overlay').classList.remove('open');
  resetPin();
}

function resetPin() {
  state.pin = '';
  updateDots();
}

function updateDots() {
  for (let i = 0; i < 4; i++) {
    document.getElementById('d' + i).classList.toggle('filled', i < state.pin.length);
  }
}

function buildKeypad() {
  const kp = document.getElementById('pin-keypad');
  kp.innerHTML = '';
  const keys = ['1','2','3','4','5','6','7','8','9','spacer','0','del'];
  keys.forEach(k => {
    const btn = document.createElement('button');
    btn.className = 'pin-key' + (k === 'del' ? ' del' : '') + (k === 'spacer' ? ' spacer' : '');
    btn.textContent = k === 'del' ? '⌫' : k === 'spacer' ? '' : k;
    btn.type = 'button';
    if (k !== 'spacer') {
      btn.addEventListener('click', () => onPinKey(k));
    }
    kp.appendChild(btn);
  });
}

function onPinKey(key) {
  if (key === 'del') {
    state.pin = state.pin.slice(0, -1);
    updateDots();
    return;
  }
  if (state.pin.length >= 4) return;
  state.pin += key;
  updateDots();
  if (state.pin.length === 4) {
    // Auto-submit
    doLogin(state.selectedUser.name, state.pin);
  }
}

// Close modal on overlay click
document.getElementById('pin-overlay').addEventListener('click', e => {
  if (e.target === e.currentTarget) closePinModal();
});
document.getElementById('pin-cancel').addEventListener('click', closePinModal);

// Keyboard support for PIN
document.addEventListener('keydown', e => {
  if (!document.getElementById('pin-overlay').classList.contains('open')) return;
  if (e.key >= '0' && e.key <= '9') { onPinKey(e.key); return; }
  if (e.key === 'Backspace') { onPinKey('del'); return; }
  if (e.key === 'Escape') { closePinModal(); return; }
});

// ── Utility ──────────────────────────────────────────────────────────────
function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Logout ───────────────────────────────────────────────────────────────
document.getElementById('btn-logout').addEventListener('click', () => {
  sessionStorage.removeItem('ahc_token');
  sessionStorage.removeItem('ahc_user');
  state.token    = null;
  state.userName = null;
  state.selectedUser = null;
  // Clear queues, progress and stats so stale entries don't appear on next login
  ['personal', 'family', 'entertainment'].forEach(z => {
    const q = document.getElementById('queue-' + z);
    if (q) q.innerHTML = '';
    const s = document.getElementById('stats-' + z);
    if (s) s.textContent = '';
  });
  resetUploadState();
  showView('view-picker');
  loadUsers();
});

// ── Boot ─────────────────────────────────────────────────────────────────
// Keep the SPA on /web so the browser back button does not navigate away.
history.replaceState({ ahc: true }, '', '/web');
window.addEventListener('popstate', () => history.pushState({ ahc: true }, '', '/web'));
loadUsers();
</script>
</body>
</html>"""


@router.get("/web", response_class=HTMLResponse, include_in_schema=False)
async def web_upload_portal():
    """Serve the self-contained web upload portal (LAN-only drag-and-drop interface)."""
    headers = {
        "Cache-Control": "no-store, no-cache, must-revalidate",
        "Pragma": "no-cache",
    }
    return HTMLResponse(content=_HTML, status_code=200, headers=headers)
