/** Left panel: list cards with key metadata visible. */

import type { ReactNode } from 'react';
import { Card, Empty, Spin, Tag, Typography } from 'antd';
import type { SqlFileListItem } from '../types/sqlFile';

const { Text, Paragraph } = Typography;

interface SqlListPanelProps {
  items: SqlFileListItem[];
  loading: boolean;
  selectedId: number | null;
  onSelect: (item: SqlFileListItem) => void;
  hasSearched: boolean;
}

function MetaRow({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="sql-card-meta-row">
      <Text type="secondary" className="sql-card-meta-label">
        {label}
      </Text>
      <div className="sql-card-meta-value">{children}</div>
    </div>
  );
}

function TagRow({ items, max = 4, color }: { items: string[]; max?: number; color?: string }) {
  if (!items.length) {
    return <Text type="secondary" style={{ fontSize: 11 }}>-</Text>;
  }
  const shown = items.slice(0, max);
  const rest = items.length - shown.length;
  return (
    <>
      {shown.map((item) => (
        <Tag key={item} color={color} className="sql-card-tag">
          {item}
        </Tag>
      ))}
      {rest > 0 && <Tag className="sql-card-tag">+{rest}</Tag>}
    </>
  );
}

export default function SqlListPanel({
  items,
  loading,
  selectedId,
  onSelect,
  hasSearched,
}: SqlListPanelProps) {
  if (loading) {
    return (
      <div className="empty-state-compact">
        <Spin tip="加载中..." />
      </div>
    );
  }

  if (items.length === 0) {
    return (
      <div className="empty-state-compact">
        <Empty
          image={Empty.PRESENTED_IMAGE_SIMPLE}
          description={hasSearched ? '未找到匹配的 SQL' : '暂无 SQL 数据'}
        />
      </div>
    );
  }

  return (
    <>
      {items.map((item) => (
        <Card
          key={item.id}
          size="small"
          hoverable
          onClick={() => onSelect(item)}
          className={`sql-list-card ${selectedId === item.id ? 'sql-list-card-selected' : ''}`}
        >
          <Text strong ellipsis className="sql-card-title">
            {item.file_name}
          </Text>

          <MetaRow label="业务">
            <Paragraph ellipsis={{ rows: 2 }} className="sql-card-text">
              {item.business || '-'}
            </Paragraph>
          </MetaRow>

          <MetaRow label="场景">
            <Paragraph ellipsis={{ rows: 2 }} className="sql-card-text">
              {item.scene || '-'}
            </Paragraph>
          </MetaRow>

          <MetaRow label="指标">
            <TagRow items={item.metrics || []} max={5} color="geekblue" />
          </MetaRow>

          <MetaRow label="维度">
            <TagRow items={item.dimensions || []} max={5} color="cyan" />
          </MetaRow>
        </Card>
      ))}
    </>
  );
}
