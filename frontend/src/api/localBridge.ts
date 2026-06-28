/** Local Doris bridge on the user's machine (VPN). Cloud UI delegates SQL execution here. */

import type { ExecuteResult } from './execute';

export const LOCAL_BRIDGE_URL =
  import.meta.env.VITE_LOCAL_BRIDGE_URL || 'http://127.0.0.1:8765';

export interface LocalBridgeStatus {
  available: boolean;
  configured: boolean;
  user: string | null;
}

export class LocalBridgeNotConfiguredError extends Error {
  constructor() {
    super('请先配置本地 Doris 账号');
    this.name = 'LocalBridgeNotConfiguredError';
  }
}

export class LocalBridgeUnavailableError extends Error {
  constructor() {
    super('请先启动本地 Doris 执行助手');
    this.name = 'LocalBridgeUnavailableError';
  }
}

const STATUS_CACHE_MS = 3000;
let statusCache: { at: number; status: LocalBridgeStatus } | null = null;

async function bridgeFetch<T>(
  path: string,
  init?: RequestInit,
): Promise<{ ok: true; data: T } | { ok: false; status: number; detail: string }> {
  const res = await fetch(`${LOCAL_BRIDGE_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...init?.headers,
    },
  });
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const body = await res.json();
      detail = body.detail || detail;
    } catch {
      /* ignore */
    }
    return { ok: false, status: res.status, detail };
  }
  const data = (await res.json()) as T;
  return { ok: true, data };
}

export async function fetchLocalBridgeStatus(
  useCache = true,
): Promise<LocalBridgeStatus> {
  if (useCache && statusCache && Date.now() - statusCache.at < STATUS_CACHE_MS) {
    return statusCache.status;
  }

  const unavailable: LocalBridgeStatus = {
    available: false,
    configured: false,
    user: null,
  };

  try {
    const health = await fetch(`${LOCAL_BRIDGE_URL}/health`, {
      signal: AbortSignal.timeout(2000),
    });
    if (!health.ok) {
      statusCache = { at: Date.now(), status: unavailable };
      return unavailable;
    }

    const statusRes = await fetch(`${LOCAL_BRIDGE_URL}/credentials/status`, {
      signal: AbortSignal.timeout(2000),
    });
    if (!statusRes.ok) {
      statusCache = { at: Date.now(), status: unavailable };
      return unavailable;
    }

    const body = (await statusRes.json()) as {
      configured?: boolean;
      user?: string | null;
    };
    const status: LocalBridgeStatus = {
      available: true,
      configured: Boolean(body.configured),
      user: body.user ?? null,
    };
    statusCache = { at: Date.now(), status };
    return status;
  } catch {
    statusCache = { at: Date.now(), status: unavailable };
    return unavailable;
  }
}

export function invalidateLocalBridgeCache() {
  statusCache = null;
}

/** Cloud site root — /login is not a valid SPA path on CloudBase (returns 404). */
export function getLocalLoginUrl(): string {
  const returnTo = `${window.location.origin}/`;
  return `${LOCAL_BRIDGE_URL}/login?return_url=${encodeURIComponent(returnTo)}`;
}

export async function saveLocalBridgeCredentials(
  user: string,
  password: string,
): Promise<void> {
  const res = await bridgeFetch<{ configured: boolean }>('/credentials', {
    method: 'POST',
    body: JSON.stringify({ user, password }),
  });
  invalidateLocalBridgeCache();
  if (!res.ok) {
    throw new Error(res.detail);
  }
}

export async function executeViaLocalBridge(payload: {
  sql: string;
  start_date: string;
  end_date: string;
  params?: Record<string, string>;
}): Promise<ExecuteResult> {
  const res = await bridgeFetch<ExecuteResult>('/execute', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    if (res.status === 401) {
      throw new LocalBridgeNotConfiguredError();
    }
    throw new Error(res.detail);
  }
  return res.data;
}

export function isDorisNetworkError(message: string): boolean {
  const lower = message.toLowerCase();
  return (
    lower.includes('无法解析 doris') ||
    lower.includes('name or service not known') ||
    lower.includes('连接 doris 超时') ||
    lower.includes('doris-adhoc')
  );
}

const BRIDGE_SYNC_KEY = 'guazi_sql_bridge_sync';

interface BridgeSyncPayload {
  email: string;
  password: string;
}

function stashBridgeCredentials(email: string, password: string) {
  const payload: BridgeSyncPayload = { email, password };
  sessionStorage.setItem(BRIDGE_SYNC_KEY, JSON.stringify(payload));
}

export function clearBridgeCredentialsStash() {
  sessionStorage.removeItem(BRIDGE_SYNC_KEY);
}

function readBridgeCredentialsStash(): BridgeSyncPayload | null {
  const raw = sessionStorage.getItem(BRIDGE_SYNC_KEY);
  if (!raw) return null;
  try {
    const data = JSON.parse(raw) as BridgeSyncPayload;
    if (data.email && data.password) return data;
  } catch {
    /* ignore */
  }
  return null;
}

/** After login: auto-save Doris creds to local bridge if it is running. */
export async function tryAutoConfigureLocalBridge(
  email: string,
  password: string,
): Promise<boolean> {
  stashBridgeCredentials(email, password);
  const status = await fetchLocalBridgeStatus(false);
  if (!status.available) {
    return false;
  }
  if (status.configured && status.user === email.trim()) {
    clearBridgeCredentialsStash();
    return true;
  }
  try {
    await saveLocalBridgeCredentials(email.trim(), password);
    clearBridgeCredentialsStash();
    return true;
  } catch {
    return false;
  }
}

/** If user logged in before starting the bridge, configure when bridge comes up. */
export async function tryAutoConfigureFromStash(): Promise<boolean> {
  const stash = readBridgeCredentialsStash();
  if (!stash) return false;
  const status = await fetchLocalBridgeStatus(false);
  if (!status.available || status.configured) {
    if (status.configured) clearBridgeCredentialsStash();
    return status.configured;
  }
  try {
    await saveLocalBridgeCredentials(stash.email.trim(), stash.password);
    clearBridgeCredentialsStash();
    return true;
  } catch {
    return false;
  }
}
