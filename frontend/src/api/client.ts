/** Shared axios client with auth token and view-as support. */

import axios from 'axios';

const TOKEN_KEY = 'guazi_sql_token';
const VIEW_AS_KEY = 'guazi_sql_view_as';

export const apiClient = axios.create({
  baseURL: '/api',
  timeout: 120000,
});

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

export function getViewAs(): string | null {
  return localStorage.getItem(VIEW_AS_KEY);
}

export function setViewAs(email: string | null) {
  if (email) localStorage.setItem(VIEW_AS_KEY, email);
  else localStorage.removeItem(VIEW_AS_KEY);
}

apiClient.interceptors.request.use((config) => {
  const token = getToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  const viewAs = getViewAs();
  if (viewAs) {
    config.params = { ...config.params, view_as: viewAs };
  }
  return config;
});

apiClient.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      setToken(null);
      window.dispatchEvent(new Event('auth:logout'));
    }
    return Promise.reject(err);
  },
);
