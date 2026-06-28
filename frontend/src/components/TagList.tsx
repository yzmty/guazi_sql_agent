/** Reusable tag/chip row for metadata fields. */

import { Tag, Typography } from 'antd';
import type { ReactNode } from 'react';

interface TagListProps {
  label: string;
  items: string[];
  color?: string;
  max?: number;
  emptyText?: string;
}

export default function TagList({
  label,
  items,
  color = 'blue',
  max,
  emptyText = '-',
}: TagListProps) {
  const displayItems = max ? items.slice(0, max) : items;
  const overflow = max && items.length > max ? items.length - max : 0;

  return (
    <div className="meta-section">
      <div className="meta-label">{label}</div>
      {items.length === 0 ? (
        <Typography.Text type="secondary">{emptyText}</Typography.Text>
      ) : (
        <>
          {displayItems.map((item) => (
            <Tag key={item} color={color} style={{ marginBottom: 4 }}>
              {item}
            </Tag>
          ))}
          {overflow > 0 && (
            <Tag style={{ marginBottom: 4 }}>+{overflow}</Tag>
          )}
        </>
      )}
    </div>
  );
}

interface MetaFieldProps {
  label: string;
  value?: ReactNode;
}

export function MetaField({ label, value }: MetaFieldProps) {
  return (
    <div className="meta-section">
      <div className="meta-label">{label}</div>
      <div className="meta-value">{value || '-'}</div>
    </div>
  );
}
