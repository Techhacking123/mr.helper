// Supabase config — uses the Cloudflare Worker proxy
const SUPABASE_URL = 'https://supabase-deep.phoenixsoftwaresolutions172.workers.dev';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ2cnBzcWRyYndmdmxsZWx5cWhmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUxNTgxOTksImV4cCI6MjA4MDczNDE5OX0.ON2ioqbNJegKOWeGu_eqsgjNxQ6IdHCDuFRqjUfBYHk';
// Service role key for unblock operations (bypasses RLS)
const SUPABASE_SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ2cnBzcWRyYndmdmxsZWx5cWhmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NTE1ODE5OSwiZXhwIjoyMDgwNzM0MTk5fQ.GyckF5tq300NJmV-invzTOLo-eBlv2U9AOoiMJtkMXc';

let providerId = null;

// Get provider ID from URL query param
function getProviderId() {
  const params = new URLSearchParams(window.location.search);
  return params.get('id');
}

// Supabase REST helper
async function supabaseRpc(fnName, params, useServiceRole = false) {
  const key = useServiceRole ? SUPABASE_SERVICE_KEY : SUPABASE_ANON_KEY;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fnName}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': key,
      'Authorization': `Bearer ${key}`,
    },
    body: JSON.stringify(params),
  });
  if (!res.ok) throw new Error(`RPC failed: ${res.statusText}`);
  return res.json();
}

// Fetch provider profile from users table
async function fetchProfile(id) {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/users?id=eq.${id}&select=full_name,avatar_url,red_stars,is_blocked,services(name)`,
    {
      headers: {
        'apikey': SUPABASE_SERVICE_KEY,
        'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
      },
    }
  );
  if (!res.ok) throw new Error('Failed to fetch profile');
  const data = await res.json();
  if (!data.length) throw new Error('Provider not found');
  return data[0];
}

// Render profile card
function renderProfile(profile) {
  const name = profile.full_name || 'Provider';
  const avatarUrl = profile.avatar_url;
  const service = profile.services?.name || 'Service Provider';
  const isBlocked = profile.is_blocked === true || (profile.red_stars || 0) >= 3;

  document.getElementById('provider-name').textContent = name;
  document.getElementById('service-name').textContent = service;

  const avatarEl = document.getElementById('avatar');
  const initialEl = document.getElementById('avatar-initial');
  if (avatarUrl) {
    initialEl.style.display = 'none';
    const img = document.createElement('img');
    img.src = avatarUrl;
    img.alt = name;
    img.onerror = () => { img.remove(); initialEl.style.display = ''; };
    avatarEl.appendChild(img);
  } else {
    initialEl.textContent = name.charAt(0).toUpperCase();
  }

  const dot = document.getElementById('status-dot');
  const badge = document.getElementById('account-status');
  const statusText = document.getElementById('status-text');
  if (isBlocked) {
    dot.className = 'status-dot blocked';
    badge.className = 'account-badge blocked';
    statusText.textContent = 'BLOCKED';
    document.querySelector('.badge-icon').textContent = '🚫';
  } else {
    dot.className = 'status-dot active';
    badge.className = 'account-badge active-acc';
    statusText.textContent = 'ACTIVE';
    document.querySelector('.badge-icon').textContent = '✅';
  }
}

// Render red stars
function renderStars(data) {
  const count = data.red_stars || 0;

  for (let i = 1; i <= 3; i++) {
    const el = document.getElementById(`star-${i}`);
    if (i <= count) el.classList.add('filled');
    else el.classList.remove('filled');
  }

  const msgEl = document.getElementById('star-message');
  const msgText = document.getElementById('star-msg-text');
  if (count >= 3) {
    msgEl.className = 'star-message danger';
    msgText.textContent = 'Your account is blocked. You cannot receive new orders.';
  } else if (count === 2) {
    msgEl.className = 'star-message warning';
    msgText.textContent = 'Warning! One more red star and your account will be blocked.';
  } else if (count === 1) {
    msgEl.className = 'star-message warning';
    msgText.textContent = 'You have 1 red star. Complete services on time.';
  } else {
    msgEl.className = 'star-message good';
    msgText.textContent = 'No penalties. Keep up the good work!';
  }

  // Show/hide unblock section
  const unblockSection = document.getElementById('unblock-section');
  if (count >= 3) unblockSection.classList.remove('hidden');
  else unblockSection.classList.add('hidden');
}

// Render history
function renderHistory(data) {
  const history = data.history || [];
  const listEl = document.getElementById('history-list');
  document.getElementById('history-count').textContent = history.length;

  if (!history.length) {
    listEl.innerHTML = '<div class="empty-state"><span>✅</span><p>No penalties recorded</p></div>';
    return;
  }

  listEl.innerHTML = history.map((item, idx) => {
    const orderId = item.order_id ? item.order_id.substring(0, 8).toUpperCase() : 'N/A';
    const reason = item.reason || 'Service not completed within deadline';
    const date = item.created_at
      ? new Date(item.created_at).toLocaleDateString('en-IN', {
          day: '2-digit', month: 'short', year: 'numeric',
          hour: '2-digit', minute: '2-digit',
        })
      : 'Unknown';

    return `
      <div class="history-item">
        <div class="history-star">⭐</div>
        <div class="history-details">
          <div class="history-reason">${reason}</div>
          <div class="history-meta">
            <span>📄 Order: ${orderId}</span>
            <span>🕐 ${date}</span>
          </div>
        </div>
        <span class="history-badge">⭐ ${idx + 1}</span>
      </div>
    `;
  }).join('');
}

// Handle unblock
async function handleUnblock() {
  if (!providerId) return;

  const ok = confirm(
    'Are you sure you want to unblock your account?\n\n' +
    'All red stars will be reset to 0 and you can receive orders again.\n' +
    'Please complete services on time to avoid future penalties.'
  );
  if (!ok) return;

  const btn = document.getElementById('unblock-btn');
  btn.disabled = true;
  btn.innerHTML = '<div class="spinner" style="width:20px;height:20px;border-width:2px;"></div> Processing...';

  try {
    const result = await supabaseRpc('unblock_provider', { p_provider_id: providerId }, true);

    if (result.success) {
      // Show success toast
      const toast = document.getElementById('success-msg');
      toast.classList.remove('hidden');
      setTimeout(() => toast.classList.add('hidden'), 4000);

      // Reload data
      await loadData();
    } else {
      throw new Error(result.message || 'Failed to unblock');
    }
  } catch (e) {
    alert('Error: ' + e.message);
    btn.disabled = false;
    btn.innerHTML = '<span class="btn-icon">🔓</span> Unblock My Account';
  }
}

// Load all data
async function loadData() {
  try {
    const [profile, redStarData] = await Promise.all([
      fetchProfile(providerId),
      supabaseRpc('get_provider_red_stars', { p_provider_id: providerId }, true),
    ]);

    renderProfile(profile);
    renderStars(redStarData);
    renderHistory(redStarData);

    document.getElementById('loading').classList.add('hidden');
    document.getElementById('main-content').classList.remove('hidden');

    // Reset unblock button
    const btn = document.getElementById('unblock-btn');
    btn.disabled = false;
    btn.innerHTML = '<span class="btn-icon">🔓</span> Unblock My Account';
  } catch (e) {
    console.error(e);
    document.getElementById('loading').classList.add('hidden');
    document.getElementById('error-message').textContent = e.message;
    document.getElementById('error-screen').classList.remove('hidden');
  }
}

// Init
document.addEventListener('DOMContentLoaded', () => {
  providerId = getProviderId();
  if (!providerId) {
    document.getElementById('loading').classList.add('hidden');
    document.getElementById('error-message').textContent = 'No provider ID provided. Please open this link from the MR Helper app.';
    document.getElementById('error-screen').classList.remove('hidden');
    return;
  }
  loadData();
});
