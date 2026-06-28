import { LockOutlined, UserOutlined } from '@ant-design/icons';

import { Alert, Button, Card, Divider, Form, Input, Typography } from 'antd';

import { useEffect, useState } from 'react';

import { loginWithBridgeProof } from '../api/auth';

import { getLocalLoginUrl } from '../api/localBridge';

import { useAuth } from '../context/AuthContext';



const { Title, Paragraph, Text } = Typography;



export default function LoginPage() {

  const { login, refresh } = useAuth();

  const [loading, setLoading] = useState(false);

  const [error, setError] = useState<string | null>(null);

  const localLoginUrl = getLocalLoginUrl();



  useEffect(() => {

    const params = new URLSearchParams(window.location.search);

    const proof = params.get('bridge_proof');

    const email = params.get('bridge_email');

    if (!proof || !email) return;



    setLoading(true);

    setError(null);

    loginWithBridgeProof(email, proof)

      .then(async () => {

        window.history.replaceState({}, '', '/');

        await refresh();

      })

      .catch((e: unknown) => {

        const err = e as { response?: { data?: { detail?: string } } };

        setError(err.response?.data?.detail || '本地验证后登录失败，请重试');

      })

      .finally(() => setLoading(false));

  }, [refresh]);



  const onFinish = async (values: { email: string; password: string }) => {

    setLoading(true);

    setError(null);

    try {

      await login(values.email.trim(), values.password);

    } catch (e: unknown) {

      const err = e as {

        response?: { status?: number; data?: { detail?: string } };

        message?: string;

      };

      if (err.response?.status === 404) {

        setError('登录接口不存在，请确认后端已更新到 V3 并重新部署');

      } else {

        setError(

          err.response?.data?.detail ||

            (e instanceof Error ? e.message : null) ||

            '登录失败。Doris 账号请使用下方「本地助手登录」',

        );

      }

    } finally {

      setLoading(false);

    }

  };



  return (

    <div className="login-page">

      <Card className="login-card">

        <Title level={3} style={{ marginTop: 0 }}>

          Guazi SQL Data Agent

        </Title>

        <Paragraph type="secondary">

          Doris 账号请先连接 <Text strong>VPN</Text>，运行 <Text code>启动Doris助手.bat</Text>，

          再点击下方按钮在本地页面输入账号密码（秒开，不用弹窗）。

        </Paragraph>

        {error && <Alert type="error" message={error} showIcon style={{ marginBottom: 16 }} />}

        <Button type="primary" block size="large" href={localLoginUrl} loading={loading}>

          打开本地助手登录（推荐）

        </Button>

        <Divider plain>或 超级管理员直接登录</Divider>

        <Form layout="vertical" onFinish={onFinish}>

          <Form.Item

            name="email"

            label="账号"

            rules={[{ required: true, message: '请输入账号' }]}

          >

            <Input prefix={<UserOutlined />} placeholder="邮箱或 Doris 用户名" />

          </Form.Item>

          <Form.Item

            name="password"

            label="密码"

            rules={[{ required: true, message: '请输入密码' }]}

          >

            <Input.Password prefix={<LockOutlined />} placeholder="数据库密码" />

          </Form.Item>

          <Button htmlType="submit" block loading={loading}>

            超级管理员登录

          </Button>

        </Form>

      </Card>

    </div>

  );

}

