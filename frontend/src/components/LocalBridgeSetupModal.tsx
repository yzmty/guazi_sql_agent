import { Form, Input, Modal, message } from 'antd';
import { useState } from 'react';
import {
  fetchLocalBridgeStatus,
  saveLocalBridgeCredentials,
} from '../api/localBridge';

interface LocalBridgeSetupModalProps {
  open: boolean;
  onClose: () => void;
  onConfigured: () => void;
  defaultUser?: string;
}

export default function LocalBridgeSetupModal({
  open,
  onClose,
  onConfigured,
  defaultUser,
}: LocalBridgeSetupModalProps) {
  const [loading, setLoading] = useState(false);
  const [form] = Form.useForm<{ user: string; password: string }>();

  const handleOk = async () => {
    const values = await form.validateFields();
    setLoading(true);
    try {
      await saveLocalBridgeCredentials(values.user.trim(), values.password);
      await fetchLocalBridgeStatus(false);
      message.success('本地 Doris 账号已保存');
      onConfigured();
      onClose();
    } catch (e: unknown) {
      message.error(e instanceof Error ? e.message : '配置失败');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal
      title="配置本地 Doris 账号"
      open={open}
      onCancel={onClose}
      onOk={handleOk}
      confirmLoading={loading}
      destroyOnClose
      okText="验证并保存"
    >
      <p style={{ marginBottom: 16, color: 'rgba(0,0,0,0.65)' }}>
        本地执行助手会通过您电脑上的 VPN 连接 Doris。账号密码仅保存在本机{' '}
        <code>~/.config/guazi-sql-agent/</code>，不会上传到云端。
      </p>
      <Form
        form={form}
        layout="vertical"
        initialValues={{ user: defaultUser || '' }}
      >
        <Form.Item
          name="user"
          label="Doris 用户名"
          rules={[{ required: true, message: '请输入 Doris 用户名' }]}
        >
          <Input placeholder="通常为邮箱，如 name@guazi.com" autoComplete="username" />
        </Form.Item>
        <Form.Item
          name="password"
          label="Doris 密码"
          rules={[{ required: true, message: '请输入 Doris 密码' }]}
        >
          <Input.Password placeholder="Doris 登录密码" autoComplete="current-password" />
        </Form.Item>
      </Form>
    </Modal>
  );
}
