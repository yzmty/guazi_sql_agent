import { DeleteOutlined, EditOutlined, SaveOutlined } from '@ant-design/icons';
import { Button, Empty, Input, Popconfirm, Space, Spin, Tag, Typography, message } from 'antd';
import { useEffect, useState } from 'react';
import { deleteSqlFile, updateSqlFile } from '../api/sqlFiles';
import type { SqlFileDetail } from '../types/sqlFile';
import SqlCodeBlock from './SqlCodeBlock';
import TagList, { MetaField } from './TagList';

const { Title } = Typography;
const { TextArea } = Input;

function indexStatusTag(status?: string | null) {
  if (!status || status === 'ready') return <Tag color="success">语义索引就绪</Tag>;
  if (status === 'pending') return <Tag color="processing">索引更新中</Tag>;
  if (status === 'failed') return <Tag color="error">索引失败</Tag>;
  return null;
}

interface SqlDetailPanelProps {
  detail: SqlFileDetail | null;
  loading: boolean;
  onExplain?: () => void;
  onRecommendSimilar?: () => void;
  onUpdated?: (detail: SqlFileDetail) => void;
  onDeleted?: () => void;
}

export default function SqlDetailPanel({
  detail,
  loading,
  onExplain,
  onRecommendSimilar,
  onUpdated,
  onDeleted,
}: SqlDetailPanelProps) {
  const [editing, setEditing] = useState(false);
  const [content, setContent] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (detail) {
      const full =
        detail.comment_block && detail.sql_content
          ? `${detail.comment_block}\n\n${detail.sql_content}`
          : detail.comment_block || detail.sql_content || '';
      setContent(full);
      setEditing(false);
    }
  }, [detail]);

  if (loading) {
    return (
      <div className="empty-state">
        <Spin tip="加载详情..." />
      </div>
    );
  }

  if (!detail) {
    return (
      <div className="empty-state">
        <Empty description="请从左侧选择一条 SQL，或导入新 SQL" />
      </div>
    );
  }

  const handleSave = async () => {
    setSaving(true);
    try {
      const updated = await updateSqlFile(detail.id, content, detail.file_name);
      message.success('保存成功');
      setEditing(false);
      onUpdated?.(updated);
    } catch (e: unknown) {
      const msg =
        (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
        '保存失败';
      message.error(msg);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    try {
      await deleteSqlFile(detail.id);
      message.success('已删除');
      onDeleted?.();
    } catch {
      message.error('删除失败');
    }
  };

  return (
    <div className="detail-content">
      <div className="sql-detail-header">
        <Title level={4} className="sql-detail-title">
          {detail.file_name} {indexStatusTag(detail.index_status)}
        </Title>
        <Space wrap className="sql-detail-actions">
          <Button
            size="small"
            icon={editing ? <SaveOutlined /> : <EditOutlined />}
            type={editing ? 'primary' : 'default'}
            loading={saving}
            onClick={() => (editing ? handleSave() : setEditing(true))}
          >
            {editing ? '保存' : '编辑'}
          </Button>
          {editing && (
            <Button size="small" onClick={() => setEditing(false)}>
              取消
            </Button>
          )}
          <Popconfirm title="确定删除此 SQL？" onConfirm={handleDelete}>
            <Button size="small" danger icon={<DeleteOutlined />}>
              删除
            </Button>
          </Popconfirm>
          <Button size="small" onClick={onExplain}>
            解释 SQL
          </Button>
          <Button size="small" onClick={onRecommendSimilar}>
            推荐相似
          </Button>
        </Space>
      </div>

      {!editing && (
        <>
          <TagList label="指标" items={detail.metrics} color="geekblue" />
          <TagList label="维度" items={detail.dimensions} color="cyan" />
          <MetaField label="业务" value={detail.business} />
          <MetaField label="场景" value={detail.scene} />
          <TagList label="标签" items={detail.tags} color="blue" />
          <TagList label="核心表" items={detail.core_tables} color="purple" />
          <TagList label="作者" items={detail.authors} color="green" />
          <MetaField label="描述" value={detail.description} />
        </>
      )}

      <div className="meta-section" style={{ marginTop: 20 }}>
        <div className="meta-label">{editing ? '编辑 SQL（含注释块）' : 'SQL 代码'}</div>
        {editing ? (
          <TextArea
            rows={22}
            value={content}
            onChange={(e) => setContent(e.target.value)}
            style={{ fontFamily: 'monospace', fontSize: 13 }}
          />
        ) : (
          <SqlCodeBlock code={detail.sql_content || ''} fileName={detail.file_name} />
        )}
      </div>
    </div>
  );
}
