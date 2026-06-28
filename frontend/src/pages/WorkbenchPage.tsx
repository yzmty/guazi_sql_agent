/** Main workbench: SQL library + Agent + Execute tabs. */

import { message, Tabs } from 'antd';
import { useCallback, useEffect, useState } from 'react';
import { getFilterOptions, getSqlFileDetail, searchSqlFiles } from '../api/sqlFiles';
import { useAuth } from '../context/AuthContext';
import AgentPanel from '../components/agent/AgentPanel';
import ExecutePanel from '../components/ExecutePanel';
import LeftSqlPanel from '../components/LeftSqlPanel';
import SearchToolbar from '../components/SearchToolbar';
import SqlDetailPanel from '../components/SqlDetailPanel';
import SqlUploadModal from '../components/SqlUploadModal';
import type { AgentMode } from '../types/agent';
import type {
  FilterOptions,
  SearchFilters,
  SqlFileDetail,
  SqlFileListItem,
} from '../types/sqlFile';

const DEFAULT_FILTERS: SearchFilters = {
  keyword: '',
  page: 1,
  page_size: 100,
};

export default function WorkbenchPage() {
  const { user, viewAs } = useAuth();
  const [filters, setFilters] = useState<SearchFilters>(DEFAULT_FILTERS);
  const [filterOptions, setFilterOptions] = useState<FilterOptions>({
    businesses: [],
    authors: [],
    tags: [],
    core_tables: [],
  });
  const [list, setList] = useState<SqlFileListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<SqlFileDetail | null>(null);
  const [listLoading, setListLoading] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [agentAction, setAgentAction] = useState<{ mode: AgentMode; ts: number } | null>(
    null,
  );
  const [listCollapsed, setListCollapsed] = useState(false);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [centerTab, setCenterTab] = useState('detail');

  const loadFilterOptions = useCallback(async () => {
    try {
      const options = await getFilterOptions();
      setFilterOptions(options);
    } catch {
      // optional
    }
  }, []);

  const loadDetail = useCallback(async (id: number) => {
    setDetailLoading(true);
    try {
      const data = await getSqlFileDetail(id);
      setDetail(data);
    } catch {
      message.error('加载 SQL 详情失败');
      setDetail(null);
    } finally {
      setDetailLoading(false);
    }
  }, []);

  const doSearch = useCallback(
    async (currentFilters: SearchFilters) => {
      setListLoading(true);
      setHasSearched(true);
      try {
        const params: SearchFilters = { ...currentFilters };
        if (!params.keyword?.trim()) delete params.keyword;
        const result = await searchSqlFiles(params);
        setList(result.list);
        setTotal(result.total);

        if (result.list.length > 0) {
          const first = result.list[0];
          setSelectedId(first.id);
          await loadDetail(first.id);
        } else {
          setSelectedId(null);
          setDetail(null);
        }
      } catch {
        message.error('搜索失败');
        setList([]);
        setTotal(0);
      } finally {
        setListLoading(false);
      }
    },
    [loadDetail],
  );

  const handleSelect = async (item: SqlFileListItem) => {
    setSelectedId(item.id);
    setCenterTab('detail');
    await loadDetail(item.id);
  };

  const handleViewFromAgent = async (sqlId: number) => {
    setSelectedId(sqlId);
    setCenterTab('detail');
    await loadDetail(sqlId);
  };

  const triggerAgentAction = (mode: AgentMode) => {
    if (!selectedId) {
      message.warning('请先在左侧选择一个 SQL');
      return;
    }
    setAgentAction({ mode, ts: Date.now() });
  };

  const handleFiltersChange = (patch: Partial<SearchFilters>) => {
    setFilters((prev) => ({ ...prev, ...patch }));
  };

  useEffect(() => {
    if (user) {
      loadFilterOptions();
      doSearch(DEFAULT_FILTERS);
    }
  }, [user, viewAs, loadFilterOptions, doSearch]);

  return (
    <div className="app-layout">
      <SearchToolbar
        filters={filters}
        filterOptions={filterOptions}
        onFiltersChange={handleFiltersChange}
        onSearch={() => doSearch(filters)}
        onUpload={() => setUploadOpen(true)}
      />

      <div className="app-main app-main-v2">
        <LeftSqlPanel
          items={list}
          total={total}
          loading={listLoading}
          selectedId={selectedId}
          collapsed={listCollapsed}
          onToggleCollapse={() => setListCollapsed((v) => !v)}
          onSelect={handleSelect}
          hasSearched={hasSearched}
        />

        <div className="panel-center">
          <Tabs
            activeKey={centerTab}
            onChange={setCenterTab}
            items={[
              {
                key: 'detail',
                label: 'SQL 详情',
                children: (
                  <SqlDetailPanel
                    detail={detail}
                    loading={detailLoading}
                    onExplain={() => triggerAgentAction('explain_sql')}
                    onRecommendSimilar={() => triggerAgentAction('recommend_similar_sql')}
                    onUpdated={(d) => {
                      setDetail(d);
                      doSearch(filters);
                      loadFilterOptions();
                    }}
                    onDeleted={() => {
                      doSearch(filters);
                      loadFilterOptions();
                    }}
                  />
                ),
              },
              {
                key: 'execute',
                label: '运行 SQL',
                children: <ExecutePanel detail={detail} />,
              },
            ]}
          />
        </div>

        <AgentPanel
          currentSqlId={selectedId}
          currentSqlName={detail?.file_name ?? null}
          onViewSqlDetail={handleViewFromAgent}
          actionTrigger={agentAction}
        />
      </div>

      <SqlUploadModal
        open={uploadOpen}
        onClose={() => setUploadOpen(false)}
        onSaved={() => {
          loadFilterOptions();
          doSearch(filters);
        }}
      />
    </div>
  );
}
