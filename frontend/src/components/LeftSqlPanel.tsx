/** Left SQL list sidebar: collapsible + paginated (5 per page). */

import { MenuFoldOutlined, MenuUnfoldOutlined } from '@ant-design/icons';
import { Button, Empty, Pagination, Spin, Tooltip } from 'antd';
import { useEffect, useState } from 'react';
import type { SqlFileListItem } from '../types/sqlFile';
import SqlListPanel from './SqlListPanel';

const PAGE_SIZE = 5;

interface LeftSqlPanelProps {
  items: SqlFileListItem[];
  total: number;
  loading: boolean;
  selectedId: number | null;
  collapsed: boolean;
  onToggleCollapse: () => void;
  onSelect: (item: SqlFileListItem) => void;
  hasSearched: boolean;
  title?: string;
}

export default function LeftSqlPanel({
  items,
  total,
  loading,
  selectedId,
  collapsed,
  onToggleCollapse,
  onSelect,
  hasSearched,
  title,
}: LeftSqlPanelProps) {
  const [page, setPage] = useState(1);
  const pageCount = Math.max(1, Math.ceil(items.length / PAGE_SIZE));
  const pageItems = items.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  useEffect(() => {
    setPage(1);
  }, [items]);

  useEffect(() => {
    if (page > pageCount) {
      setPage(pageCount);
    }
  }, [page, pageCount]);

  if (collapsed) {
    return (
      <div className="panel-left panel-left-collapsed">
        <Tooltip title="展开 SQL 列表" placement="right">
          <Button
            type="text"
            icon={<MenuUnfoldOutlined />}
            onClick={onToggleCollapse}
            className="panel-collapse-btn"
          />
        </Tooltip>
        <div className="panel-collapsed-label">SQL</div>
        {selectedId && (
          <Tooltip title="当前已选中一条 SQL" placement="right">
            <div className="panel-collapsed-dot" />
          </Tooltip>
        )}
      </div>
    );
  }

  return (
    <div className="panel-left">
      <div className="panel-header-bar panel-header-bar-flex">
        <span>
          {title ? `${title} · ` : ''}共 {total} 条 · 本页 {pageItems.length} 条
        </span>
        <Tooltip title="折叠列表">
          <Button
            type="text"
            size="small"
            icon={<MenuFoldOutlined />}
            onClick={onToggleCollapse}
          />
        </Tooltip>
      </div>

      <div className="list-scroll list-scroll-paged">
        {loading ? (
          <div className="empty-state-compact">
            <Spin tip="加载中..." />
          </div>
        ) : items.length === 0 ? (
          <div className="empty-state-compact">
            <Empty
              image={Empty.PRESENTED_IMAGE_SIMPLE}
              description={
                hasSearched
                  ? '无匹配结果'
                  : '请先同步 SQL'
              }
            />
          </div>
        ) : (
          <SqlListPanel
            items={pageItems}
            loading={false}
            selectedId={selectedId}
            onSelect={onSelect}
            hasSearched={hasSearched}
          />
        )}
      </div>

      {items.length > PAGE_SIZE && (
        <div className="list-pagination">
          <Pagination
            simple
            size="small"
            current={page}
            pageSize={PAGE_SIZE}
            total={items.length}
            onChange={setPage}
            showSizeChanger={false}
          />
        </div>
      )}
    </div>
  );
}
