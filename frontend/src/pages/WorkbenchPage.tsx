/** Main workbench: SQL library + Agent + Execute tabs. */

import { message, Tabs } from 'antd';
import { useCallback, useEffect, useState } from 'react';
import {
  getSharedFilterOptions,
  getSharedGroupStatus,
  getSharedSqlDetail,
  joinSharedGroup,
  listSharedSqlFiles,
  type LibraryScope,
  type SharedGroupStatus,
} from '../api/sharedGroup';
import { getFilterOptions, getSqlFileDetail, searchSqlFiles } from '../api/sqlFiles';
import { useAuth } from '../context/AuthContext';
import AgentPanel from '../components/agent/AgentPanel';
import ExecutePanel from '../components/ExecutePanel';
import LeftSqlPanel from '../components/LeftSqlPanel';
import SearchToolbar from '../components/SearchToolbar';
import SharedGroupMemberModal from '../components/SharedGroupMemberModal';
import SharedSqlDetailPanel, { type SharedSqlDetail } from '../components/SharedSqlDetailPanel';
import SharedSqlUploadModal from '../components/SharedSqlUploadModal';
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
  const [libraryMode, setLibraryMode] = useState<LibraryScope>('personal');
  const [groupStatus, setGroupStatus] = useState<SharedGroupStatus | null>(null);
  const [memberModalOpen, setMemberModalOpen] = useState(false);
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
  const [sharedDetail, setSharedDetail] = useState<SharedSqlDetail | null>(null);
  const [listLoading, setListLoading] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [agentAction, setAgentAction] = useState<{ mode: AgentMode; ts: number } | null>(
    null,
  );
  const [listCollapsed, setListCollapsed] = useState(false);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [sharedUploadOpen, setSharedUploadOpen] = useState(false);
  const [centerTab, setCenterTab] = useState('detail');

  const loadGroupStatus = useCallback(async (): Promise<SharedGroupStatus | null> => {
    try {
      const status = await getSharedGroupStatus();
      setGroupStatus(status);
      return status;
    } catch {
      setGroupStatus(null);
      return null;
    }
  }, []);

  const loadSharedFilterOptions = useCallback(async () => {
    try {
      const options = await getSharedFilterOptions();
      setFilterOptions(options);
    } catch {
      // optional
    }
  }, []);

  const loadFilterOptions = useCallback(async () => {
    try {
      const options = await getFilterOptions();
      setFilterOptions(options);
    } catch {
      // optional
    }
  }, []);

  const loadPersonalDetail = useCallback(async (id: number) => {
    setDetailLoading(true);
    try {
      const data = await getSqlFileDetail(id);
      setDetail(data);
      setSharedDetail(null);
    } catch {
      message.error('加载 SQL 详情失败');
      setDetail(null);
    } finally {
      setDetailLoading(false);
    }
  }, []);

  const loadSharedDetail = useCallback(async (id: number) => {
    setDetailLoading(true);
    try {
      const data = await getSharedSqlDetail(id);
      setSharedDetail(data);
      setDetail(null);
    } catch (e: unknown) {
      const msg =
        (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
        '加载共享 SQL 详情失败';
      message.error(msg);
      setSharedDetail(null);
    } finally {
      setDetailLoading(false);
    }
  }, []);

  const doPersonalSearch = useCallback(
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
          await loadPersonalDetail(first.id);
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
    [loadPersonalDetail],
  );

  const doSharedSearch = useCallback(
    async (currentFilters: SearchFilters) => {
      if (!groupStatus?.can_access) {
        setList([]);
        setTotal(0);
        setSelectedId(null);
        setSharedDetail(null);
        return;
      }
      setListLoading(true);
      setHasSearched(true);
      try {
        const params: SearchFilters = { ...currentFilters };
        if (!params.keyword?.trim()) delete params.keyword;
        const result = await listSharedSqlFiles(params);
        setList(result.list);
        setTotal(result.total);
        if (result.list.length > 0) {
          const first = result.list[0];
          setSelectedId(first.id);
          await loadSharedDetail(first.id);
        } else {
          setSelectedId(null);
          setSharedDetail(null);
        }
      } catch (e: unknown) {
        const msg =
          (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
          '加载共享 SQL 失败';
        message.error(msg);
        setList([]);
        setTotal(0);
      } finally {
        setListLoading(false);
      }
    },
    [groupStatus?.can_access, loadSharedDetail],
  );

  const doSearch = useCallback(() => {
    if (libraryMode === 'shared') {
      return doSharedSearch(filters);
    }
    return doPersonalSearch(filters);
  }, [libraryMode, doSharedSearch, filters, doPersonalSearch]);

  const handleSelect = async (item: SqlFileListItem) => {
    setSelectedId(item.id);
    setCenterTab('detail');
    if (libraryMode === 'shared') {
      await loadSharedDetail(item.id);
    } else {
      await loadPersonalDetail(item.id);
    }
  };

  const handleViewFromAgent = async (sqlId: number) => {
    setSelectedId(sqlId);
    setCenterTab('detail');
    if (libraryMode === 'shared') {
      await loadSharedDetail(sqlId);
    } else {
      await loadPersonalDetail(sqlId);
    }
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

  const handleLibraryModeChange = (mode: LibraryScope) => {
    setLibraryMode(mode);
    setSelectedId(null);
    setDetail(null);
    setSharedDetail(null);
    setList([]);
    setTotal(0);
    setHasSearched(false);
    if (mode === 'shared') {
      void loadGroupStatus().then((status) => {
        if (status?.can_access) {
          void loadSharedFilterOptions();
          void doSharedSearch(DEFAULT_FILTERS);
        }
      });
    } else {
      void doPersonalSearch(filters);
    }
  };

  const handleJoinGroup = async () => {
    try {
      const status = await joinSharedGroup();
      setGroupStatus(status);
      message.success(status.can_access ? '已加入共享群' : '已提交入群申请，等待群主审批');
      if (status.can_access) {
        await loadSharedFilterOptions();
        await doSharedSearch(filters);
      }
    } catch (e: unknown) {
      message.error(
        (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
          '申请失败',
      );
    }
  };

  useEffect(() => {
    if (user) {
      void loadGroupStatus();
      if (libraryMode === 'personal') {
        loadFilterOptions();
        doPersonalSearch(DEFAULT_FILTERS);
      }
    }
  }, [user, viewAs, loadFilterOptions, doPersonalSearch, loadGroupStatus, libraryMode]);

  useEffect(() => {
    if (user && libraryMode === 'shared' && groupStatus?.can_access) {
      void loadSharedFilterOptions();
      void doSharedSearch(filters);
    }
  }, [user, libraryMode, groupStatus?.can_access]);

  const sharedAccessBlocked = libraryMode === 'shared' && !groupStatus?.can_access;
  const sharedPending = groupStatus?.status === 'pending';

  const executeDetail =
    libraryMode === 'shared' && sharedDetail
      ? ({
          ...sharedDetail,
          file_path: null,
          updated_at: null,
          index_error: null,
          indexed_at: null,
        } as SqlFileDetail)
      : detail;

  return (
    <div className="app-layout">
      <SearchToolbar
        filters={filters}
        filterOptions={filterOptions}
        onFiltersChange={handleFiltersChange}
        onSearch={doSearch}
        onUpload={() =>
          libraryMode === 'shared' ? setSharedUploadOpen(true) : setUploadOpen(true)
        }
        libraryMode={libraryMode}
        onLibraryModeChange={handleLibraryModeChange}
        sharedAccessBlocked={sharedAccessBlocked}
        sharedPending={sharedPending}
        onJoinSharedGroup={handleJoinGroup}
        onManageMembers={() => setMemberModalOpen(true)}
        isSharedOwner={!!groupStatus?.is_owner}
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
          title={libraryMode === 'shared' ? '共享群 SQL' : undefined}
        />

        <div className="panel-center">
          <Tabs
            activeKey={centerTab}
            onChange={setCenterTab}
            items={[
              {
                key: 'detail',
                label: libraryMode === 'shared' ? '共享 SQL 详情' : 'SQL 详情',
                children:
                  libraryMode === 'shared' ? (
                    <SharedSqlDetailPanel
                      detail={sharedDetail}
                      loading={detailLoading}
                      onExplain={() => triggerAgentAction('explain_sql')}
                      onRecommendSimilar={() => triggerAgentAction('recommend_similar_sql')}
                      onDeleted={() => doSharedSearch(filters)}
                    />
                  ) : (
                    <SqlDetailPanel
                      detail={detail}
                      loading={detailLoading}
                      onExplain={() => triggerAgentAction('explain_sql')}
                      onRecommendSimilar={() => triggerAgentAction('recommend_similar_sql')}
                      onUpdated={(d) => {
                        setDetail(d);
                        doPersonalSearch(filters);
                        loadFilterOptions();
                      }}
                      onDeleted={() => {
                        doPersonalSearch(filters);
                        loadFilterOptions();
                      }}
                    />
                  ),
              },
              {
                key: 'execute',
                label: '运行 SQL',
                children: <ExecutePanel detail={executeDetail} />,
              },
            ]}
          />
        </div>

        <AgentPanel
          currentSqlId={selectedId}
          currentSqlName={
            libraryMode === 'shared'
              ? (sharedDetail?.file_name ?? null)
              : (detail?.file_name ?? null)
          }
          libraryScope={libraryMode}
          onViewSqlDetail={handleViewFromAgent}
          actionTrigger={agentAction}
          disabled={sharedAccessBlocked}
        />
      </div>

      <SqlUploadModal
        open={uploadOpen}
        onClose={() => setUploadOpen(false)}
        onSaved={() => {
          loadFilterOptions();
          doPersonalSearch(filters);
        }}
      />

      <SharedSqlUploadModal
        open={sharedUploadOpen}
        onClose={() => setSharedUploadOpen(false)}
        onSaved={() => doSharedSearch(filters)}
      />

      <SharedGroupMemberModal
        open={memberModalOpen}
        onClose={() => setMemberModalOpen(false)}
      />
    </div>
  );
}
