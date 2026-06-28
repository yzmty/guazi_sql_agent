import { apiClient, setToken } from './client';

export interface LoginResponse {
  token: string;
  email: string;
  is_super_admin: boolean;
}

export interface UserInfo {
  email: string;
  is_super_admin: boolean;
  view_as_email: string | null;
  owner_email: string;
}

export async function login(
  email: string,
  password: string,
  localBridgeProof?: string,
): Promise<LoginResponse> {
  const trimmed = email.trim();
  const { data } = await apiClient.post<LoginResponse>('/auth/login', {
    email: trimmed,
    password: localBridgeProof ? 'bridge-verified' : password,
    local_bridge_proof: localBridgeProof,
  });
  setToken(data.token);
  return data;
}

export async function loginWithBridgeProof(
  email: string,
  proof: string,
): Promise<LoginResponse> {
  return login(email, '', proof);
}

export async function logout(): Promise<void> {
  try {
    await apiClient.post('/auth/logout');
  } finally {
    setToken(null);
  }
}

export async function getMe(): Promise<UserInfo> {
  const { data } = await apiClient.get<UserInfo>('/auth/me');
  return data;
}

export async function listUsers(): Promise<string[]> {
  const { data } = await apiClient.get<{ users: string[] }>('/auth/users');
  return data.users;
}
