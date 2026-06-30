import { DeleteOutlined } from '@ant-design/icons';
import { Button, Empty, Popconfirm, Space, Spin, Tag, Typography, message } from 'antd';
import { deleteSharedSql } from '../api/sharedGroup';
import type { SqlFileDetail } from '../types/sqlFile';
import SqlCodeBlock from './SqlCodeBlock';
import TagList, { MetaField } from './TagList';

const { Title, Text } = Typography;

export type SharedSqlDetail = SqlFileDetail & {
  storage_mode?: string;
  is_public?: boolean;
  uploaded_by?: string;
  scope?: string;
};

function indexStatusTag(status?: string | null) {
  if (!status || status === 'ready') return <Tag color="success">语义索引就绪</Tag>;
  if (status === 'pending') return <Tag color="processing">索引更新中</Tag>;
  if (status === 'failed') return <Tag color="error">索引失败</Tag>;
  return null;
}

interface SharedSqlDetailPanelProps {
  detail: SharedSqlDetail | null;
  loading: boolean;
  onExplain?: () => void;
  onRecommendSimilar?: () => void;
  onDeleted?: () => void;
}

export default function SharedSqlDetailPanel({
  detail,
  loading,
  onExplain,
  onRecommendSimilar,
  onDeleted,
}: SharedSqlDetailPanelProps) {
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
        <Empty description="请从左侧选择一条共享 SQL，或上传新 SQL" />
      </div>
    );
  }

  const handleDelete = async () => {
    try {
      await deleteSharedSql(detail.id);
      message.success('已删除');
      onDeleted?.();
    } catch (e: unknown) {
      message.error(
        (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
          '删除失败',
      );
    }
  };

  return (
    <div className="detail-content">
      <div className="sql-detail-header">
        <Title level={4} className="sql-detail-title">
          {detail.file_name}{' '}
          <Tag color="blue">共享群</Tag>
          {detail.storage_mode === 'encrypted' && <Tag color="purple">加密存储</Tag>}
          {detail.is_public === false && <Tag>非公开</Tag>}
          {indexStatusTag(detail.index_status)}
        </Title>
        <Space wrap className="sql-detail-actions">
          <Button size="small" onClick={onExplain}>
            AI 解释
          </Button>
          <Button size="small" onClick={onRecommendSimilar}>
            推荐相似
          </Button>
          <Popconfirm title="确定删除此共享 SQL？" onConfirm={handleDelete}>
            <Button size="small" danger icon={<DeleteOutlined />}>
              删除
            </Button>
          </Popconfirm>
        </Space>
        <Text type="secondary" style={{ display: 'block', marginTop: 8 }}>
          上传者: {detail.uploaded_by || '未知'}
        </Text>
      </div>

      <TagList label="指标" items={detail.metrics} color="geekblue" />
      <TagList label="维度" items={detail.dimensions} color="cyan" />
      <MetaField label="业务" value={detail.business} />
      <MetaField label="场景" value={detail.scene} />
      <TagList label="标签" items={detail.tags} color="blue" />
      <TagList label="核心表" items={detail.core_tables} color="purple" />
      <TagList label="作者" items={detail.authors} color="green" />
      <MetaField label="描述" value={detail.description} />

      <div className="meta-section" style={{ marginTop: 20 }}>
        <div className="meta-label">SQL 代码</div>
        <SqlCodeBlock code={detail.sql_content || ''} fileName={detail.file_name} />
      </div>
    </div>
  );
}
