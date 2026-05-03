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
</style>
</head>
<body>
<div class="app" id="app">
  <header>
    <div class="title-row">
      <div class="title">AutoMsg</div>
      <div style="display: flex; gap: 6px;">
        <span class="status-pill"><span class="dot" id="dot-ollama"></span> Ollama</span>
        <span class="status-pill"><span class="dot" id="dot-msgs"></span> Msgs</span>
        <span class="status-pill"><span class="dot" id="dot-monitor"></span> Monitor</span>
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
    renderList();
  } catch (e) { toast('Failed to load contacts'); }
}

function renderHeader() {
  const s = state.status;
  document.getElementById('dot-ollama').className = 'dot ' + (s.ollama ? 'on' : 'off');
  document.getElementById('dot-msgs').className = 'dot ' + (s.messages ? 'on' : 'off');
  document.getElementById('dot-monitor').className = 'dot ' + (s.monitor ? 'on' : 'off');
  document.getElementById('status-line').textContent =
    `${s.enabledCount || 0} of ${s.contactCount || 0} contacts enabled` + (s.diskAccess === false ? ' · Full Disk Access required' : '');
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
    ? filtered.map(c => `
      <div class="contact ${c.enabled ? 'enabled' : ''}" data-id="${escapeHTML(c.id)}">
        <div class="avatar">${initials(c.name)}</div>
        <div class="name">
          <div class="n">${escapeHTML(c.name)} ${c.hasHistory ? '<span class="history-mark">💬</span>' : ''}</div>
          <div class="sub">${escapeHTML((c.handles || [])[0] || '')}${c.handles && c.handles.length > 1 ? ' +' + (c.handles.length - 1) : ''}</div>
        </div>
        <div class="status-dot"></div>
      </div>
    `).join('')
    : '<div class="empty">No contacts match</div>';

  list.querySelectorAll('.contact').forEach(el => {
    el.addEventListener('click', () => openDetail(el.dataset.id));
  });
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
  const handlesOpts = (d.handles || []).map(h =>
    `<option value="${escapeHTML(h)}" ${h === d.preferredHandle ? 'selected' : ''}>${escapeHTML(h)}</option>`
  ).join('');
  const draft = d.draft || '';
  body.innerHTML = `
    <div class="handle-row">
      <label>Send to:</label>
      <select id="handle-select">${handlesOpts}</select>
      <button class="secondary" id="toggle-btn" style="margin-left:auto">${d.enabled ? 'Disable' : 'Enable'}</button>
    </div>
    <div class="draft-card">
      <h3>AI Draft</h3>
      <textarea id="draft-input" placeholder="Tap Regenerate to compose...">${escapeHTML(draft)}</textarea>
      <div class="draft-actions">
        <button class="primary" id="send-btn">Send</button>
        <button class="secondary" id="regen-btn">Regenerate</button>
      </div>
    </div>
    <div class="thread">
      <h3>Recent Messages</h3>
      ${(d.messages || []).map(m => `
        <div class="bubble-row ${m.isFromMe ? 'me' : 'them'}">
          <span class="bubble ${m.isFromMe ? 'me' : 'them'}">${escapeHTML(m.text)}</span>
        </div>
      `).join('')}
    </div>
  `;

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
