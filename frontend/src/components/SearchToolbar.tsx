/** Top toolbar: search, filters, upload, admin switch. */

import { LogoutOutlined, SearchOutlined, UploadOutlined } from '@ant-design/icons';
import { Button, Input, Select, Space, Typography } from 'antd';
import { useEffect, useState } from 'react';
import { listUsers } from '../api/auth';
import { useAuth } from '../context/AuthContext';
import type { FilterOptions, SearchFilters } from '../types/sqlFile';

const { Title, Text } = Typography;

interface SearchToolbarProps {
  filters: SearchFilters;
  filterOptions: FilterOptions;
  onFiltersChange: (patch: Partial<SearchFilters>) => void;
  onSearch: () => void;
  onUpload: () => void;
}

export default function SearchToolbar({
  filters,
  filterOptions,
  onFiltersChange,
  onSearch,
  onUpload,
}: SearchToolbarProps) {
  const { user, logout, viewAs, setViewAsEmail } = useAuth();
  const [users, setUsers] = useState<string[]>([]);

  useEffect(() => {
    if (user?.is_super_admin) {
      listUsers().then(setUsers).catch(() => setUsers([]));
    }
  }, [user?.is_super_admin]);

  return (
    <div className="app-header">
      <Space direction="vertical" style={{ width: '100%' }} size="middle">
        <Space align="center" style={{ width: '100%', justifyContent: 'space-between' }}>
          <Title level={4} style={{ margin: 0 }}>
            Guazi SQL Data Agent
          </Title>
          <Space>
            <Text type="secondary">{user?.email}</Text>
            {user?.is_super_admin && (
              <Select
                allowClear
                placeholder="查看用户 SQL"
                style={{ width: 220 }}
                value={viewAs || undefined}
                onChange={(v) => setViewAsEmail(v || null)}
                options={users.map((u) => ({ label: u, value: u }))}
                showSearch
              />
            )}
            <Button icon={<UploadOutlined />} type="primary" onClick={onUpload}>
              导入 SQL
            </Button>
            <Button icon={<LogoutOutlined />} onClick={() => logout()}>
              退出
            </Button>
          </Space>
        </Space>

        <Space wrap style={{ width: '100%' }}>
          <Input.Search
            placeholder="搜索关键词..."
            allowClear
            style={{ width: 360 }}
            value={filters.keyword || ''}
            onChange={(e) => onFiltersChange({ keyword: e.target.value })}
            onSearch={onSearch}
            enterButton={<SearchOutlined />}
          />

          <Select
            allowClear
            placeholder="业务"
            style={{ width: 180 }}
            value={filters.business || undefined}
            onChange={(v) => onFiltersChange({ business: v })}
            options={filterOptions.businesses.map((b) => ({ label: b, value: b }))}
            showSearch
            optionFilterProp="label"
          />

          <Select
            allowClear
            placeholder="标签"
            style={{ width: 140 }}
            value={filters.tag || undefined}
            onChange={(v) => onFiltersChange({ tag: v })}
            options={filterOptions.tags.map((t) => ({ label: t, value: t }))}
            showSearch
            optionFilterProp="label"
          />

          <Select
            allowClear
            placeholder="核心表"
            style={{ width: 220 }}
            value={filters.core_table || undefined}
            onChange={(v) => onFiltersChange({ core_table: v })}
            options={filterOptions.core_tables.map((t) => ({ label: t, value: t }))}
            showSearch
            optionFilterProp="label"
          />

          <Select
            allowClear
            placeholder="作者"
            style={{ width: 120 }}
            value={filters.author || undefined}
            onChange={(v) => onFiltersChange({ author: v })}
            options={filterOptions.authors.map((a) => ({ label: a, value: a }))}
            showSearch
            optionFilterProp="label"
          />

          <Button type="default" onClick={onSearch}>
            搜索
          </Button>
        </Space>
      </Space>
    </div>
  );
}
