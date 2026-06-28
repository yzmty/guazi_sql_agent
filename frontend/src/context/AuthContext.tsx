import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { getMe, login as apiLogin, logout as apiLogout, type UserInfo } from '../api/auth';
import { clearBridgeCredentialsStash, tryAutoConfigureLocalBridge } from '../api/localBridge';
import { getToken, getViewAs, setViewAs, setToken } from '../api/client';

interface AuthContextValue {
  user: UserInfo | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  refresh: () => Promise<void>;
  viewAs: string | null;
  setViewAsEmail: (email: string | null) => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<UserInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [viewAs, setViewAsState] = useState<string | null>(getViewAs());

  const refresh = useCallback(async () => {
    const token = getToken();
    if (!token) {
      setUser(null);
      return;
    }
    const me = await getMe();
    setUser(me);
  }, []);

  useEffect(() => {
    refresh()
      .catch(() => {
        setToken(null);
        setUser(null);
      })
      .finally(() => setLoading(false));

    const onLogout = () => {
      setUser(null);
    };
    window.addEventListener('auth:logout', onLogout);
    return () => window.removeEventListener('auth:logout', onLogout);
  }, [refresh]);

  const login = useCallback(
    async (email: string, password: string) => {
      await apiLogin(email, password);
      void tryAutoConfigureLocalBridge(email, password);
      await refresh();
    },
    [refresh],
  );

  const logout = useCallback(async () => {
    clearBridgeCredentialsStash();
    await apiLogout();
    setViewAs(null);
    setViewAsState(null);
    setUser(null);
  }, []);

  const setViewAsEmail = useCallback(
    async (email: string | null) => {
      setViewAs(email);
      setViewAsState(email);
      await refresh();
    },
    [refresh],
  );

  const value = useMemo(
    () => ({ user, loading, login, logout, refresh, viewAs, setViewAsEmail }),
    [user, loading, login, logout, refresh, viewAs, setViewAsEmail],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
