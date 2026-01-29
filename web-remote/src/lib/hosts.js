const HOSTS_KEY = 'shared_remote_hosts';
const ACTIVE_HOST_KEY = 'shared_remote_active_host';

export function loadHosts() {
  try {
    const raw = localStorage.getItem(HOSTS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed;
  } catch {
    return [];
  }
}

export function loadActiveHostId() {
  return localStorage.getItem(ACTIVE_HOST_KEY) || '';
}

export function persistHosts(hosts, activeHostId) {
  localStorage.setItem(HOSTS_KEY, JSON.stringify(hosts));
  if (activeHostId) {
    localStorage.setItem(ACTIVE_HOST_KEY, activeHostId);
  } else {
    localStorage.removeItem(ACTIVE_HOST_KEY);
  }
}

export function createHost({ displayName, baseUrl }) {
  return {
    id: String(Date.now()),
    displayName,
    baseUrl,
    lastConnectedAt: null,
    lastError: null,
    isOnline: false,
  };
}

function isLocalIpv4(host) {
  const match = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!match) return false;
  const parts = match.slice(1).map((part) => Number(part));
  if (parts.some((part) => Number.isNaN(part) || part < 0 || part > 255)) {
    return false;
  }
  const [first, second] = parts;
  if (first === 10 || first === 127) return true;
  if (first === 192 && second === 168) return true;
  if (first === 172 && second >= 16 && second <= 31) return true;
  return false;
}

function isLocalHost(host) {
  if (!host) return false;
  if (host === 'localhost' || host === '127.0.0.1') return true;
  if (host.endsWith('.local')) return true;
  if (host.includes(':')) {
    const lower = host.toLowerCase();
    return lower.startsWith('fc') || lower.startsWith('fd') || lower.startsWith('fe80');
  }
  return isLocalIpv4(host);
}

export function normalizeBaseUrl(input) {
  let normalized = input.trim();
  if (!normalized) return '';
  if (!normalized.includes('://')) {
    normalized = `http://${normalized}`;
  }
  try {
    const url = new URL(normalized);
    if (!url.port && url.protocol === 'http:' && isLocalHost(url.hostname)) {
      url.port = '1180';
    }
    normalized = url.toString();
  } catch {
    return normalized.replace(/\/+$/, '');
  }
  normalized = normalized.replace(/\/+$/, '');
  return normalized;
}

export function ensureActiveHost(hosts, activeHostId) {
  if (hosts.length === 0) return '';
  const existing = hosts.find((host) => host.id === activeHostId);
  return existing ? activeHostId : hosts[0].id;
}
