import { Spin } from 'antd';
import { AuthProvider, useAuth } from './context/AuthContext';
import LoginPage from './pages/LoginPage';
import WorkbenchPage from './pages/WorkbenchPage';

function AppRoutes() {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div className="login-page">
        <Spin size="large" tip="加载中..." />
      </div>
    );
  }

  if (!user) {
    return <LoginPage />;
  }

  return <WorkbenchPage />;
}

export default function App() {
  return (
    <AuthProvider>
      <AppRoutes />
    </AuthProvider>
  );
}
