import Foundation

enum RemoteUI {
    static func serve(token: String) -> HTTPResponse {
        return HTTPResponse.html(200, html.replacingOccurrences(of: "__TOKEN__", with: token))
    }

    private static let html = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>AutoMsg Remote</title>
<style>
:root {
  --bg: #0d0d10;
  --bg-2: #16171c;
  --bg-3: #1f2129;
  --border: #2a2c36;
  --text: #f0f0f5;
  --text-2: #9ca0ad;
  --accent: #4a8cff;
  --green: #34c759;
  --red: #ff453a;
  --orange: #ff9f0a;
}
* { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
  background: var(--bg);
  color: var(--text);
  font-size: 15px;
  -webkit-font-smoothing: antialiased;
}
.app { padding-top: env(safe-area-inset-top); padding-bottom: env(safe-area-inset-bottom); }
header {
  position: sticky; top: 0; z-index: 10;
  background: var(--bg-2);
  border-bottom: 1px solid var(--border);
  padding: 12px 16px;
}
.title-row { display: flex; align-items: center; justify-content: space-between; }
.title { font-size: 18px; font-weight: 700; }
.status-pill {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 11px; padding: 3px 8px; border-radius: 12px;
  background: var(--bg-3); color: var(--text-2);
}
.dot { width: 6px; height: 6px; border-radius: 50%; background: var(--text-2); }
.dot.on { background: var(--green); }
.dot.off { background: var(--red); }
.global-toggle {
  margin-top: 10px;
  display: flex; align-items: center; justify-content: space-between;
  padding: 10px 14px;
  background: var(--bg-3); border-radius: 10px;
}
.toggle {
  position: relative; width: 50px; height: 30px;
  background: #3a3a3c; border-radius: 15px;
  cursor: pointer; transition: background .2s;
}
.toggle.on { background: var(--green); }
.toggle::after {
  content: ""; position: absolute; top: 2px; left: 2px;
  width: 26px; height: 26px; border-radius: 50%; background: white;
  transition: transform .2s;
}
.toggle.on::after { transform: translateX(20px); }
.search {
  margin: 12px 16px;
  display: flex; align-items: center; gap: 8px;
  padding: 10px 12px;
  background: var(--bg-3); border-radius: 10px;
}
.search input {
  flex: 1; border: 0; outline: 0;
  background: transparent; color: var(--text); font-size: 15px;
}
.filters {
  display: flex; gap: 8px; padding: 0 16px 12px;
}
.chip {
  padding: 6px 12px; border-radius: 16px;
  background: var(--bg-3); color: var(--text-2);
  font-size: 12px; cursor: pointer; user-select: none;
}
.chip.active { background: var(--accent); color: white; }
.list { padding: 0 8px 80px; }
.contact {
  display: flex; align-items: center; gap: 12px;
  padding: 12px 14px; margin: 4px 0;
  background: var(--bg-2); border-radius: 12px;
  cursor: pointer;
}
.contact:active { background: var(--bg-3); }
.contact .avatar {
  width: 38px; height: 38px; border-radius: 50%;
  background: var(--bg-3); display: flex; align-items: center; justify-content: center;
  font-weight: 600; color: var(--text-2);
}
.contact .name { flex: 1; }
.contact .name .n { font-weight: 500; }
.contact .name .sub { font-size: 12px; color: var(--text-2); }
.contact .status-dot {
  width: 8px; height: 8px; border-radius: 50%;
  background: var(--bg-3);
}
.contact.enabled .status-dot { background: var(--green); }
.history-mark { font-size: 12px; opacity: 0.5; }
.mode-pill {
  display: inline-block;
  font-size: 10px;
  padding: 2px 6px;
  border-radius: 8px;
  margin-left: 4px;
  background: var(--bg-3);
  color: var(--text-2);
}
.mode-pill.auto { background: rgba(255,159,10,0.2); color: var(--orange); }
.mode-pill.smart { background: rgba(74,140,255,0.2); color: var(--accent); }
.mode-pill.focus { background: rgba(176,131,255,0.2); color: #b083ff; }
.mode-pill.draft { background: rgba(52,199,89,0.2); color: var(--green); }
.pending-badge {
  display: inline-block;
  font-size: 10px;
  padding: 2px 8px;
  border-radius: 10px;
  background: var(--orange);
  color: black;
  margin-left: 6px;
  font-weight: 600;
}
.mem-pill {
  font-size: 10px;
  padding: 2px 6px;
  border-radius: 8px;
  background: rgba(176,131,255,0.2);
  color: #b083ff;
  margin-left: 4px;
}
.mem-section {
  margin: 12px 0;
  padding: 12px;
  background: var(--bg-2);
  border-radius: 10px;
  border-left: 3px solid #b083ff;
}
.mem-section h4 { margin: 0 0 6px; font-size: 12px; color: #b083ff; }
.mem-section ul { margin: 4px 0; padding-left: 18px; }
.mem-section li { font-size: 13px; margin-bottom: 2px; color: var(--text-2); }
.mem-section .summary { font-size: 13px; margin-bottom: 8px; color: var(--text); }
.detail-overlay {
  position: fixed; inset: 0; background: var(--bg);
  z-index: 100; overflow-y: auto;
  padding-top: env(safe-area-inset-top); padding-bottom: env(safe-area-inset-bottom);
  display: none; flex-direction: column;
}
.detail-overlay.open { display: flex; }
.detail-header {
  position: sticky; top: 0; background: var(--bg-2);
  border-bottom: 1px solid var(--border);
  padding: 12px 16px;
  display: flex; align-items: center; gap: 12px;
}
.back-btn { padding: 8px 12px; border-radius: 8px; background: var(--bg-3); cursor: pointer; }
.detail-name { flex: 1; font-weight: 600; font-size: 17px; }
.detail-body { padding: 16px; }
.handle-row { display: flex; gap: 8px; align-items: center; margin-bottom: 12px; flex-wrap: wrap; }
.handle-row label { font-size: 12px; color: var(--text-2); }
select {
  background: var(--bg-3); color: var(--text); border: 1px solid var(--border);
  padding: 6px 10px; border-radius: 6px; font-size: 13px;
}
.draft-card {
  background: var(--bg-2); border-radius: 12px; padding: 14px;
  margin-bottom: 16px;
}
.draft-card h3 { margin: 0 0 10px; font-size: 13px; color: var(--accent); font-weight: 600; }
.draft-card textarea {
  width: 100%; min-height: 80px;
  background: var(--bg-3); color: var(--text);
  border: 1px solid var(--border); border-radius: 8px;
  padding: 10px; font-size: 15px; font-family: inherit; resize: vertical;
}
.draft-actions { display: flex; gap: 8px; margin-top: 10px; }
button.primary, button.secondary {
  border: 0; padding: 10px 18px; border-radius: 8px;
  font-size: 14px; font-weight: 600; cursor: pointer;
}
button.primary { background: var(--accent); color: white; flex: 1; }
button.secondary { background: var(--bg-3); color: var(--text); }
button:disabled { opacity: 0.4; }
.thread { margin-top: 8px; }
.thread h3 { font-size: 13px; color: var(--text-2); font-weight: 600; margin: 0 0 8px; }
.bubble {
  display: inline-block; max-width: 75%; padding: 8px 12px;
  border-radius: 16px; margin-bottom: 4px; font-size: 14px;
  word-wrap: break-word;
}
.bubble-row { display: flex; margin-bottom: 4px; }
.bubble-row.me { justify-content: flex-end; }
.bubble.me { background: var(--accent); color: white; }
.bubble.them { background: var(--bg-3); color: var(--text); }
.empty { text-align: center; color: var(--text-2); padding: 40px 16px; }
.banner { padding: 8px 14px; background: var(--orange); color: black; font-size: 13px; text-align: center; }
.banner.error { background: var(--red); color: white; }
.banner.success { background: var(--green); color: black; }
.toast {
  position: fixed; bottom: 30px; left: 50%; transform: translateX(-50%);
  background: var(--bg-3); color: var(--text); padding: 10px 18px;
  border-radius: 20px; font-size: 13px; z-index: 200;
  opacity: 0; transition: opacity .2s;
}
.toast.show { opacity: 1; }
.refresh { padding: 8px 12px; cursor: pointer; color: var(--text-2); }
.settings-overlay {
  position: fixed; inset: 0; background: var(--bg);
  z-index: 90; overflow-y: auto;
  padding-top: env(safe-area-inset-top); padding-bottom: env(safe-area-inset-bottom);
  display: none; flex-direction: column;
}
.settings-overlay.open { display: flex; }
.model-row {
  display: flex; align-items: center; gap: 10px;
  padding: 12px 14px;
  background: var(--bg-2); border-radius: 10px;
  margin-bottom: 6px;
  cursor: pointer;
}
.model-row.active { background: rgba(74,140,255,0.15); border: 1px solid var(--accent); }
.model-row .radio {
  width: 18px; height: 18px; border-radius: 50%;
  border: 2px solid var(--text-2); flex-shrink: 0;
}
.model-row.active .radio { border-color: var(--accent); background: var(--accent); box-shadow: inset 0 0 0 3px var(--bg-2); }
.model-row .info { flex: 1; }
.model-row .name { font-family: ui-monospace, "SF Mono", Monaco, monospace; font-size: 14px; }
.model-row .meta { font-size: 11px; color: var(--text-2); margin-top: 2px; }
.gear-btn {
  background: none; border: 0; color: var(--text-2);
  font-size: 18px; cursor: pointer; padding: 4px 8px;
}
</style>
</head>
<body>
<div class="app" id="app">
  <header>
    <div class="title-row">
      <div class="title">AutoMsg</div>
      <div style="display: flex; gap: 6px; align-items: center;">
        <span class="status-pill"><span class="dot" id="dot-ollama"></span> Ollama</span>
        <span class="status-pill"><span class="dot" id="dot-msgs"></span> Msgs</span>
        <span class="status-pill"><span class="dot" id="dot-monitor"></span> Monitor</span>
        <button class="gear-btn" id="settings-btn" title="Settings">⚙</button>
      </div>
    </div>
    <div class="global-toggle">
      <div>
        <div style="font-weight:600">Auto-Reply Active</div>
        <div style="font-size:12px;color:var(--text-2)" id="status-line">Loading…</div>
      </div>
      <div class="toggle" id="global-toggle"></div>
    </div>
  </header>

  <div class="search">
    <span>🔍</span>
    <input type="search" id="search" placeholder="Search contacts" autocapitalize="none" autocomplete="off">
  </div>
  <div class="filters">
    <span class="chip" id="chip-all">All</span>
    <span class="chip" id="chip-enabled">Enabled</span>
    <span class="chip" id="chip-history">With history</span>
    <span class="chip refresh" id="refresh-btn">↻</span>
  </div>

  <div class="list" id="contact-list"></div>

  <div class="settings-overlay" id="settings">
    <div class="detail-header">
      <div class="back-btn" id="settings-back">‹ Back</div>
      <div class="detail-name">Settings</div>
    </div>
    <div class="detail-body">
      <h3 style="font-size:13px;color:var(--text-2);margin:0 0 10px;font-weight:600">AI MODEL</h3>
      <div id="active-model" style="margin-bottom:12px;font-size:13px;color:var(--text-2)"></div>
      <div id="model-list"></div>
      <p style="font-size:12px;color:var(--text-2);margin-top:14px;line-height:1.4">
        Tip: 7B+ models give better style mimicry. Recommended: <code>qwen2.5:7b</code>.
        Model changes apply on the next AutoMsg launch.
      </p>
      <p style="font-size:12px;color:var(--text-2);line-height:1.4">
        New models? Run <code style="background:var(--bg-3);padding:2px 4px;border-radius:3px">ollama pull &lt;name&gt;</code> in Terminal on the Mac, then refresh.
      </p>
      <div style="display:flex;gap:8px;margin-top:8px;flex-wrap:wrap">
        <button class="secondary" id="refresh-models">Refresh list</button>
        <button class="primary" id="restart-app" style="flex:1">⟲ Restart AutoMsg on Mac</button>
      </div>
      <p style="font-size:11px;color:var(--text-2);margin-top:8px;line-height:1.4">
        Restart applies the active model (and any other pending changes). The remote will reconnect within a few seconds.
      </p>
    </div>
  </div>

  <div class="detail-overlay" id="detail">
    <div class="detail-header">
      <div class="back-btn" id="back-btn">‹ Back</div>
      <div class="detail-name" id="detail-name"></div>
    </div>
    <div class="detail-body" id="detail-body"></div>
  </div>

  <div class="toast" id="toast"></div>
</div>

<script>
const TOKEN = "__TOKEN__";
const api = (path, opts = {}) => fetch(path + (path.includes('?') ? '&' : '?') + 'token=' + TOKEN, opts).then(r => r.json());

const state = {
  contacts: [],
  status: {},
  filter: 'all',
  search: '',
  current: null,
};

function toast(msg, ms = 2000) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), ms);
}

async function loadStatus() {
  try {
    state.status = await api('/api/status');
    renderHeader();
  } catch (e) { console.error(e); }
}

async function loadContacts() {
  try {
    const data = await api('/api/contacts');
    state.contacts = data.contacts || [];
    state.pendingReplies = data.pendingReplies || 0;
    renderList();
    renderHeader();
  } catch (e) { toast('Failed to load contacts'); }
}

function renderHeader() {
  const s = state.status;
  document.getElementById('dot-ollama').className = 'dot ' + (s.ollama ? 'on' : 'off');
  document.getElementById('dot-msgs').className = 'dot ' + (s.messages ? 'on' : 'off');
  document.getElementById('dot-monitor').className = 'dot ' + (s.monitor ? 'on' : 'off');
  let statusText = `${s.enabledCount || 0} of ${s.contactCount || 0} contacts enabled`;
  if (state.pendingReplies > 0) statusText += ` · ${state.pendingReplies} reply pending`;
  if (s.diskAccess === false) statusText += ' · Full Disk Access required';
  document.getElementById('status-line').textContent = statusText;
  document.getElementById('global-toggle').classList.toggle('on', !!s.globalEnabled);
}

function renderList() {
  const list = document.getElementById('contact-list');
  const q = state.search.toLowerCase();
  let filtered = state.contacts.filter(c => {
    if (state.filter === 'enabled' && !c.enabled) return false;
    if (state.filter === 'history' && !c.hasHistory) return false;
    if (q) {
      return c.name.toLowerCase().includes(q) || (c.handles || []).some(h => h.toLowerCase().includes(q));
    }
    return true;
  });
  filtered.sort((a, b) => {
    if (a.hasHistory !== b.hasHistory) return a.hasHistory ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  list.innerHTML = filtered.length
    ? filtered.map(c => {
        const modeLabel = modeLabelText(c.smartMode);
        const modeClass = c.smartMode || '';
        return `
      <div class="contact ${c.enabled ? 'enabled' : ''}" data-id="${escapeHTML(c.id)}">
        <div class="avatar">${initials(c.name)}</div>
        <div class="name">
          <div class="n">${escapeHTML(c.name)} ${c.hasHistory ? '<span class="history-mark">💬</span>' : ''}${c.hasMemory ? '<span class="mem-pill">🧠</span>' : ''}</div>
          <div class="sub">${escapeHTML((c.handles || [])[0] || '')}${c.handles && c.handles.length > 1 ? ' +' + (c.handles.length - 1) : ''}${c.enabled ? `<span class="mode-pill ${modeClass}">${modeLabel}</span>` : ''}</div>
        </div>
        <div class="status-dot"></div>
      </div>
    `;
      }).join('')
    : '<div class="empty">No contacts match</div>';

  list.querySelectorAll('.contact').forEach(el => {
    el.addEventListener('click', () => openDetail(el.dataset.id));
  });
}

function renderMemory(mem) {
  if (!mem) return '';
  const hasContent = (mem.summary && mem.summary.length) ||
    (mem.facts && mem.facts.length) ||
    (mem.openLoops && mem.openLoops.length) ||
    (mem.preferences && mem.preferences.length);
  if (!hasContent) return '';
  return `
    <div class="mem-section">
      <h4>🧠 Long-term memory</h4>
      ${mem.summary ? `<div class="summary">${escapeHTML(mem.summary)}</div>` : ''}
      ${mem.facts && mem.facts.length ? `<strong style="font-size:11px;color:var(--text-2)">Facts</strong><ul>${mem.facts.map(f => `<li>${escapeHTML(f)}</li>`).join('')}</ul>` : ''}
      ${mem.openLoops && mem.openLoops.length ? `<strong style="font-size:11px;color:var(--text-2)">Open loops</strong><ul>${mem.openLoops.map(f => `<li>${escapeHTML(f)}</li>`).join('')}</ul>` : ''}
      ${mem.preferences && mem.preferences.length ? `<strong style="font-size:11px;color:var(--text-2)">Preferences</strong><ul>${mem.preferences.map(f => `<li>${escapeHTML(f)}</li>`).join('')}</ul>` : ''}
    </div>
  `;
}

function modeLabelText(m) {
  switch (m) {
    case 'alwaysAuto': return '⚡ Auto';
    case 'moderate': return '🤖 Smart';
    case 'focusOnly': return '🌙 Focus';
    case 'draftOnly': return '✏️ Draft';
    case 'off': return '🚫 Off';
    default: return '🤖 Smart';
  }
}

function initials(name) {
  const parts = name.trim().split(/\\s+/);
  if (parts.length === 1) return (parts[0][0] || '?').toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function escapeHTML(s) {
  return String(s || '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

async function openDetail(id) {
  state.current = id;
  document.getElementById('detail').classList.add('open');
  document.getElementById('detail-name').textContent = 'Loading…';
  document.getElementById('detail-body').innerHTML = '';
  try {
    const d = await api('/api/contacts/' + encodeURIComponent(id));
    renderDetail(d);
  } catch (e) {
    document.getElementById('detail-body').innerHTML = '<div class="empty">Failed to load</div>';
  }
}

function renderDetail(d) {
  document.getElementById('detail-name').textContent = d.name;
  const body = document.getElementById('detail-body');
  const activeHandle = d.activeHandle || d.preferredHandle || (d.handles || [])[0];
  const handlesOpts = (d.handles || []).map(h =>
    `<option value="${escapeHTML(h)}" ${h === activeHandle ? 'selected' : ''}>${escapeHTML(h)}</option>`
  ).join('');
  const isManual = !!d.preferredHandle;
  const showSwitchHint = isManual && d.autoHandle && d.autoHandle !== d.preferredHandle;
  const draft = d.draft || '';
  const memHTML = renderMemory(d.memory);
  body.innerHTML = `
    <div class="handle-row">
      <label>Send to:</label>
      <select id="handle-select">${handlesOpts}</select>
      ${isManual ? '<button class="secondary" id="reset-handle-btn" title="Stop overriding">↺ Auto</button>' : '<span style="font-size:11px;color:var(--text-2);background:var(--bg-3);padding:2px 6px;border-radius:4px">auto</span>'}
      <button class="secondary" id="toggle-btn" style="margin-left:auto">${d.enabled ? 'Disable' : 'Enable'}</button>
    </div>
    ${showSwitchHint ? `
    <div style="display:flex;align-items:center;gap:6px;padding:8px 10px;background:rgba(255,159,10,0.1);border-radius:6px;margin-bottom:10px">
      <span style="color:var(--orange)">ⓘ</span>
      <span style="font-size:12px;color:var(--text-2);flex:1">Most recent activity on <code>${escapeHTML(d.autoHandle)}</code></span>
      <button class="secondary" id="switch-handle-btn" style="padding:4px 10px;font-size:12px">Switch</button>
    </div>` : ''}
    ${d.enabled ? `
    <div class="handle-row">
      <label>Mode:</label>
      <select id="mode-select">
        <option value="alwaysAuto" ${d.smartMode === 'alwaysAuto' ? 'selected' : ''}>⚡ Always auto</option>
        <option value="moderate" ${(d.smartMode === 'moderate' || !d.smartMode) ? 'selected' : ''}>🤖 Smart (recommended)</option>
        <option value="focusOnly" ${d.smartMode === 'focusOnly' ? 'selected' : ''}>🌙 Focus only</option>
        <option value="draftOnly" ${d.smartMode === 'draftOnly' ? 'selected' : ''}>✏️ Draft only</option>
        <option value="off" ${d.smartMode === 'off' ? 'selected' : ''}>🚫 Off</option>
      </select>
    </div>` : ''}
    <div class="draft-card">
      <h3>AI Draft</h3>
      <textarea id="draft-input" placeholder="Tap Regenerate to compose...">${escapeHTML(draft)}</textarea>
      <div class="draft-actions">
        <button class="primary" id="send-btn">Send</button>
        <button class="secondary" id="regen-btn">Regenerate</button>
      </div>
    </div>
    ${memHTML}
    <div class="thread">
      <h3>Recent Messages</h3>
      ${(d.messages || []).map(m => `
        <div class="bubble-row ${m.isFromMe ? 'me' : 'them'}">
          <span class="bubble ${m.isFromMe ? 'me' : 'them'}">${escapeHTML(m.text)}</span>
        </div>
      `).join('')}
    </div>
  `;

  const handleSel = document.getElementById('handle-select');
  if (handleSel) {
    handleSel.addEventListener('change', async (e) => {
      const r = await fetch(`/api/contacts/${encodeURIComponent(d.id)}/handle?token=${TOKEN}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ handle: e.target.value })
      }).then(r => r.json());
      if (r.error) toast('Error: ' + r.error);
      else toast('Send target: ' + r.preferredHandle);
      openDetail(d.id);  // re-render to show Reset button
    });
  }

  const resetBtn = document.getElementById('reset-handle-btn');
  if (resetBtn) {
    resetBtn.addEventListener('click', async () => {
      await fetch(`/api/contacts/${encodeURIComponent(d.id)}/handle/reset?token=${TOKEN}`, { method: 'POST' });
      toast('Auto-pick restored');
      openDetail(d.id);
    });
  }

  const switchBtn = document.getElementById('switch-handle-btn');
  if (switchBtn && d.autoHandle) {
    switchBtn.addEventListener('click', async () => {
      await fetch(`/api/contacts/${encodeURIComponent(d.id)}/handle?token=${TOKEN}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ handle: d.autoHandle })
      });
      toast('Switched to most recent thread');
      openDetail(d.id);
    });
  }

  const modeSel = document.getElementById('mode-select');
  if (modeSel) {
    modeSel.addEventListener('change', async (e) => {
      const r = await fetch(`/api/contacts/${encodeURIComponent(d.id)}/mode?token=${TOKEN}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mode: e.target.value })
      }).then(r => r.json());
      if (r.error) toast('Error: ' + r.error);
      else toast('Mode: ' + modeLabelText(r.mode));
      loadContacts();
    });
  }

  document.getElementById('toggle-btn').addEventListener('click', async () => {
    const r = await fetch(`/api/contacts/${encodeURIComponent(d.id)}/toggle?token=${TOKEN}`, { method: 'POST' }).then(r => r.json());
    toast(r.enabled ? 'Enabled' : 'Disabled');
    await loadContacts();
    openDetail(d.id);
  });

  document.getElementById('send-btn').addEventListener('click', async () => {
    const text = document.getElementById('draft-input').value;
    if (!text.trim()) { toast('Empty draft'); return; }
    const btn = document.getElementById('send-btn');
    btn.disabled = true; btn.textContent = 'Sending…';
    const r = await fetch(`/api/contacts/${encodeURIComponent(d.id)}/send?token=${TOKEN}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text })
    }).then(r => r.json());
    btn.disabled = false; btn.textContent = 'Send';
    if (r.error) {
      toast('Error: ' + r.error, 4000);
    } else {
      toast('Sent ✓');
      setTimeout(() => openDetail(d.id), 800);
    }
  });

  document.getElementById('regen-btn').addEventListener('click', async () => {
    const btn = document.getElementById('regen-btn');
    btn.disabled = true; btn.textContent = 'Generating…';
    const r = await fetch(`/api/contacts/${encodeURIComponent(d.id)}/regenerate?token=${TOKEN}`, { method: 'POST' }).then(r => r.json());
    btn.disabled = false; btn.textContent = 'Regenerate';
    document.getElementById('draft-input').value = r.draft || '';
  });
}

document.getElementById('back-btn').addEventListener('click', () => {
  document.getElementById('detail').classList.remove('open');
  state.current = null;
});

document.getElementById('search').addEventListener('input', e => {
  state.search = e.target.value;
  renderList();
});

['all','enabled','history'].forEach(f => {
  const chip = document.getElementById('chip-' + f);
  chip.addEventListener('click', () => {
    state.filter = f;
    document.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
    chip.classList.add('active');
    renderList();
  });
});
document.getElementById('chip-all').classList.add('active');

document.getElementById('refresh-btn').addEventListener('click', () => { loadContacts(); loadStatus(); });

document.getElementById('settings-btn').addEventListener('click', openSettings);
document.getElementById('settings-back').addEventListener('click', () => {
  document.getElementById('settings').classList.remove('open');
});
document.getElementById('refresh-models').addEventListener('click', loadModels);
document.getElementById('restart-app').addEventListener('click', async () => {
  const btn = document.getElementById('restart-app');
  btn.disabled = true; btn.textContent = '⟲ Restarting…';
  try {
    await fetch('/api/restart?token=' + TOKEN, { method: 'POST' });
  } catch (e) { /* expected — server tore down its connection */ }
  toast('Restart triggered. Reconnecting…');
  // Poll status until the server comes back up, then refresh the page
  let attempts = 0;
  const reconnect = setInterval(async () => {
    attempts++;
    try {
      const r = await fetch('/api/status?token=' + TOKEN, { cache: 'no-store' });
      if (r.ok) {
        clearInterval(reconnect);
        toast('AutoMsg back online ✓');
        btn.disabled = false; btn.textContent = '⟲ Restart AutoMsg on Mac';
        loadStatus(); loadContacts(); loadModels();
      }
    } catch (e) { /* still down, keep polling */ }
    if (attempts > 60) {
      clearInterval(reconnect);
      btn.disabled = false; btn.textContent = '⟲ Restart AutoMsg on Mac';
      toast('Server didn\\'t come back. Check the Mac.', 4000);
    }
  }, 1000);
});

async function openSettings() {
  document.getElementById('settings').classList.add('open');
  loadModels();
}

async function loadModels() {
  document.getElementById('model-list').innerHTML = '<div class="empty">Loading…</div>';
  try {
    const data = await api('/api/models');
    if (data.error) {
      document.getElementById('model-list').innerHTML = `<div class="empty">${escapeHTML(data.error)}</div>`;
      return;
    }
    document.getElementById('active-model').innerHTML = `Active: <code style="background:var(--bg-3);padding:2px 6px;border-radius:4px;color:var(--green)">${escapeHTML(data.active)}</code>`;
    const list = document.getElementById('model-list');
    if (!data.models || !data.models.length) {
      list.innerHTML = '<div class="empty">No models installed</div>';
      return;
    }
    list.innerHTML = data.models.map(m => `
      <div class="model-row ${m.name === data.active ? 'active' : ''}" data-name="${escapeHTML(m.name)}">
        <div class="radio"></div>
        <div class="info">
          <div class="name">${escapeHTML(m.name)}</div>
          <div class="meta">${m.sizeGB.toFixed(1)} GB · ${escapeHTML(m.modified)}</div>
        </div>
      </div>
    `).join('');
    list.querySelectorAll('.model-row').forEach(row => {
      row.addEventListener('click', () => selectModel(row.dataset.name));
    });
  } catch (e) {
    document.getElementById('model-list').innerHTML = `<div class="empty">Failed: ${escapeHTML(e.message)}</div>`;
  }
}

async function selectModel(name) {
  const r = await fetch('/api/models/active?token=' + TOKEN, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name })
  }).then(r => r.json());
  if (r.error) toast('Error: ' + r.error);
  else {
    toast('Saved · restart AutoMsg on the Mac to apply');
    loadModels();
  }
}

document.getElementById('global-toggle').addEventListener('click', async () => {
  const r = await fetch('/api/global/toggle?token=' + TOKEN, { method: 'POST' }).then(r => r.json());
  state.status.globalEnabled = r.globalEnabled;
  renderHeader();
});

(async () => {
  await loadStatus();
  await loadContacts();
  setInterval(loadStatus, 5000);
})();
</script>
</body>
</html>
"""
}
