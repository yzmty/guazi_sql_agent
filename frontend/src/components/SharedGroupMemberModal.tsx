/** Member approval UI for shared group owner (super admin). */

import { CheckOutlined, DeleteOutlined, TeamOutlined } from '@ant-design/icons';
import { Button, List, Modal, Space, Tag, Typography, message } from 'antd';
import { useCallback, useEffect, useState } from 'react';
import {
  approveSharedMember,
  listSharedGroupMembers,
  removeSharedMember,
  type SharedGroupMember,
} from '../api/sharedGroup';

const { Text } = Typography;

interface SharedGroupMemberModalProps {
  open: boolean;
  onClose: () => void;
}

export default function SharedGroupMemberModal({ open, onClose }: SharedGroupMemberModalProps) {
  const [members, setMembers] = useState<SharedGroupMember[]>([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const rows = await listSharedGroupMembers();
      setMembers(rows);
    } catch (e: unknown) {
      const msg =
        (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
        '加载成员失败';
      message.error(msg);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (open) void load();
  }, [open, load]);

  const handleApprove = async (email: string) => {
    try {
      await approveSharedMember(email);
      message.success(`已批准 ${email}`);
      await load();
    } catch (e: unknown) {
      message.error(
        (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
          '批准失败',
      );
    }
  };

  const handleRemove = async (email: string) => {
    try {
      await removeSharedMember(email);
      message.success(`已移除 ${email}`);
      await load();
    } catch (e: unknown) {
      message.error(
        (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
          '移除失败',
      );
    }
  };

  return (
    <Modal
      title={
        <Space>
          <TeamOutlined />
          共享群成员管理
        </Space>
      }
      open={open}
      onCancel={onClose}
      footer={null}
      width={640}
    >
      <List
        loading={loading}
        dataSource={members}
        locale={{ emptyText: '暂无成员' }}
        renderItem={(m) => (
          <List.Item
            actions={[
              m.status === 'pending' ? (
                <Button
                  key="approve"
                  type="link"
                  icon={<CheckOutlined />}
                  onClick={() => handleApprove(m.email)}
                >
                  批准
                </Button>
              ) : null,
              m.role !== 'owner' ? (
                <Button
                  key="remove"
                  type="link"
                  danger
                  icon={<DeleteOutlined />}
                  onClick={() => handleRemove(m.email)}
                >
                  移除
                </Button>
              ) : null,
            ].filter(Boolean)}
          >
            <List.Item.Meta
              title={
                <Space>
                  <Text>{m.email}</Text>
                  {m.role === 'owner' && <Tag color="gold">群主</Tag>}
                  {m.status === 'pending' && <Tag color="orange">待审批</Tag>}
                  {m.status === 'approved' && <Tag color="green">已加入</Tag>}
                </Space>
              }
              description={`角色: ${m.role}`}
            />
          </List.Item>
        )}
      />
    </Modal>
  );
}
