import { PlayCircleOutlined, SettingOutlined } from '@ant-design/icons';
import { Alert, Button, DatePicker, Input, Space, Spin, Table, Typography, message } from 'antd';
import dayjs, { type Dayjs } from 'dayjs';
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  LocalBridgeNotConfiguredError,
  LocalBridgeUnavailableError,
  detectSqlParams,
  executeSql,
  fetchLocalBridgeStatus,
  tryAutoConfigureFromStash,
} from '../api/execute';
import type { LocalBridgeStatus } from '../api/localBridge';
import { useAuth } from '../context/AuthContext';
import type { SqlFileDetail } from '../types/sqlFile';
import LocalBridgeSetupModal from './LocalBridgeSetupModal';
import SqlCodeBlock from './SqlCodeBlock';
const { Title, Paragraph, Text } = Typography;

const START_ALIASES = new Set([
  'start',
  'start_date',
  'begin',
  'begin_date',
  'dt_start',
  'date_start',
]);

const END_ALIASES = new Set([
  'end',
  'end_date',
  'finish',
  'finish_date',
  'dt_end',
  'date_end',
  'date_y_m_d',
  'date_ymd',
]);

function defaultValueForParam(name: string, start: Dayjs, end: Dayjs): string {
  const lower = name.toLowerCase();
  if (START_ALIASES.has(lower)) return start.format('YYYY-MM-DD');
  if (END_ALIASES.has(lower)) return end.format('YYYY-MM-DD');
  return '';
}

interface ExecutePanelProps {
  detail: SqlFileDetail | null;
}

export default function ExecutePanel({ detail }: ExecutePanelProps) {
  const { user } = useAuth();
  const [sql, setSql] = useState('');
  const [placeholders, setPlaceholders] = useState<string[]>([]);
  const [paramValues, setParamValues] = useState<Record<string, string>>({});
  const [startDate, setStartDate] = useState<Dayjs | null>(dayjs().subtract(7, 'day'));
  const [endDate, setEndDate] = useState<Dayjs | null>(dayjs());
  const [loading, setLoading] = useState(false);
  const [bridgeStatus, setBridgeStatus] = useState<LocalBridgeStatus | null>(null);
  const [setupOpen, setSetupOpen] = useState(false);
  const [executedViaLocal, setExecutedViaLocal] = useState(false);
  const [result, setResult] = useState<{
    columns: string[];
    rows: unknown[][];
    row_count: number;
    truncated: boolean;
  } | null>(null);

  const refreshBridgeStatus = useCallback(async () => {
    await tryAutoConfigureFromStash();
    const status = await fetchLocalBridgeStatus(false);
    setBridgeStatus(status);
    return status;
  }, []);

  useEffect(() => {
    void refreshBridgeStatus();
    const timer = window.setInterval(() => {
      void refreshBridgeStatus();
    }, 5000);
    return () => window.clearInterval(timer);
  }, [refreshBridgeStatus]);

  useEffect(() => {
    const content = detail?.sql_content || '';
    setSql(content);
    setResult(null);
    if (content) {
      detectSqlParams(content)
        .then(setPlaceholders)
        .catch(() => setPlaceholders([]));
    } else {
      setPlaceholders([]);
    }
  }, [detail]);

  useEffect(() => {
    if (!startDate || !endDate) return;
    setParamValues((prev) => {
      const next = { ...prev };
      for (const name of placeholders) {
        if (!next[name]?.trim()) {
          next[name] = defaultValueForParam(name, startDate, endDate);
        }
      }
      return next;
    });
  }, [placeholders, startDate, endDate]);

  const missingParams = useMemo(
    () => placeholders.filter((p) => !paramValues[p]?.trim()),
    [placeholders, paramValues],
  );

  const handleRun = async () => {
    if (!startDate || !endDate) {
      message.warning('请先选择起止日期');
      return;
    }
    if (!sql.trim()) {
      message.warning('没有可执行的 SQL');
      return;
    }
    if (missingParams.length) {
      message.warning(`请填写占位符: ${missingParams.join(', ')}`);
      return;
    }
    setLoading(true);
    try {
      const res = await executeSql({
        sql,
        start_date: startDate.format('YYYY-MM-DD'),
        end_date: endDate.format('YYYY-MM-DD'),
        params: paramValues,
        sql_file_id: detail?.id,
      });
      setResult(res);
      setExecutedViaLocal(Boolean(res.viaLocalBridge));
      if (res.truncated) {
        message.info(`结果已截断，仅显示前 ${res.row_count} 行`);
      }
    } catch (e: unknown) {
      if (e instanceof LocalBridgeNotConfiguredError) {
        message.warning('请先配置本地 Doris 账号');
        setSetupOpen(true);
      } else if (e instanceof LocalBridgeUnavailableError) {
        message.error(
          '云端无法连接 Doris。请连接 VPN 后运行 scripts/start-local-bridge.ps1，再点击运行。',
        );
      } else {
        const msg =
          (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
          (e instanceof Error ? e.message : '执行失败');
        message.error(msg);
      }
      setResult(null);
      setExecutedViaLocal(false);
    } finally {
      setLoading(false);
    }
  };

  const columns = result?.columns.map((c) => ({
    title: c,
    dataIndex: c,
    key: c,
    ellipsis: true,
  }));

  const dataSource = result?.rows.map((row, idx) => {
    const obj: Record<string, unknown> = { key: idx };
    result.columns.forEach((col, i) => {
      obj[col] = row[i];
    });
    return obj;
  });

  return (
    <div className="execute-panel detail-content">
      <Title level={4} style={{ marginTop: 0 }}>
        运行 SQL
      </Title>
      <Paragraph type="secondary">
        连接 Doris 执行当前 SQL。所有 <Text code>${'{}'}</Text>{' '}
        占位符都会在运行前替换为实际值；起止日期会自动填入常见参数名（如 start、date_y_m_d）。
        云端部署无法直连内网 Doris 时，会自动通过本机「Doris 执行助手」查数（需 VPN）。
      </Paragraph>

      {bridgeStatus?.available && bridgeStatus.configured && (
        <Alert
          type="success"
          showIcon
          style={{ marginBottom: 12 }}
          message={`本地 Doris 已连接（${bridgeStatus.user || '已配置'}），SQL 将通过本机 VPN 执行`}
        />
      )}

      {bridgeStatus?.available && !bridgeStatus.configured && (
        <Alert
          type="warning"
          showIcon
          style={{ marginBottom: 12 }}
          message="本地助手已启动，正在等待自动配置 Doris 账号"
          description="请确认已用 Doris 账号登录；若仍未配置，可点「配置账号」手动填写。"
          action={
            <Button size="small" icon={<SettingOutlined />} onClick={() => setSetupOpen(true)}>
              配置账号
            </Button>
          }
        />
      )}

      {bridgeStatus && !bridgeStatus.available && (
        <Alert
          type="info"
          showIcon
          style={{ marginBottom: 12 }}
          message="查数需启动本地 Doris 助手"
          description={
            <>
              双击项目里的 <Text code>启动Doris助手.bat</Text>（需 VPN），保持窗口打开后再点「运行」。
              登录时会自动用同一账号配置，无需单独填 Doris 密码。
            </>
          }
        />
      )}

      <Alert
        type="info"
        showIcon
        style={{ marginBottom: 12 }}
        message={
          placeholders.length
            ? `检测到 ${placeholders.length} 个占位符: ${placeholders.map((p) => `\${${p}}`).join(', ')}`
            : '当前 SQL 中没有 ${} 占位符'
        }
      />

      <Space wrap style={{ marginBottom: 12 }}>
        <span>起始日期</span>
        <DatePicker
          value={startDate}
          onChange={(d) => {
            setStartDate(d);
            if (d && placeholders.length) {
              setParamValues((prev) => {
                const next = { ...prev };
                for (const name of placeholders) {
                  if (START_ALIASES.has(name.toLowerCase())) {
                    next[name] = d.format('YYYY-MM-DD');
                  }
                }
                return next;
              });
            }
          }}
        />
        <span>结束日期</span>
        <DatePicker
          value={endDate}
          onChange={(d) => {
            setEndDate(d);
            if (d && placeholders.length) {
              setParamValues((prev) => {
                const next = { ...prev };
                for (const name of placeholders) {
                  if (END_ALIASES.has(name.toLowerCase())) {
                    next[name] = d.format('YYYY-MM-DD');
                  }
                }
                return next;
              });
            }
          }}
        />
        <Button
          type="primary"
          icon={<PlayCircleOutlined />}
          loading={loading}
          onClick={handleRun}
        >
          运行
        </Button>
      </Space>

      {placeholders.length > 0 && (
        <div className="meta-section" style={{ marginBottom: 16 }}>
          <div className="meta-label">占位符替换值</div>
          <Space direction="vertical" style={{ width: '100%' }} size="small">
            {placeholders.map((name) => (
              <Space key={name} wrap>
                <Text code>{`\${${name}}`}</Text>
                <Input
                  style={{ width: 200 }}
                  placeholder="替换值"
                  value={paramValues[name] || ''}
                  onChange={(e) =>
                    setParamValues((prev) => ({ ...prev, [name]: e.target.value }))
                  }
                />
              </Space>
            ))}
          </Space>
        </div>
      )}

      {detail && (
        <div className="meta-section">
          <div className="meta-label">待执行 SQL（来自：{detail.file_name}）</div>
          <SqlCodeBlock code={sql} fileName={detail.file_name} />
        </div>
      )}

      {loading && (
        <div style={{ textAlign: 'center', padding: 24 }}>
          <Spin tip="查询执行中，请稍候..." />
        </div>
      )}

      <LocalBridgeSetupModal
        open={setupOpen}
        onClose={() => setSetupOpen(false)}
        onConfigured={() => void refreshBridgeStatus()}
        defaultUser={user?.email}
      />

      {result && !loading && (
        <div className="meta-section" style={{ marginTop: 16 }}>
          <div className="meta-label">
            查询结果（{result.row_count} 行{result.truncated ? '，已截断' : ''}
            {executedViaLocal ? '，经本地 VPN 执行' : ''}）
          </div>
          <Table
            size="small"
            scroll={{ x: true, y: 400 }}
            columns={columns}
            dataSource={dataSource}
            pagination={{ pageSize: 50 }}
          />
        </div>
      )}
    </div>
  );
}
