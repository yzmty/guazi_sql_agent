/** SQL rewrite draft card — never overwrites original. Supports cross-SQL rewrite metadata. */

import { CopyOutlined, LinkOutlined, WarningOutlined } from '@ant-design/icons';
import { Alert, Button, List, Space, Table, Tag, Typography, message } from 'antd';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { oneLight } from 'react-syntax-highlighter/dist/esm/styles/prism';
import type { RewriteSqlData } from '../../types/agent';

const { Paragraph, Text } = Typography;

interface SqlRewriteCardProps {
  data: RewriteSqlData;
  onViewReference?: (sqlId: number) => void;
}

export default function SqlRewriteCard({ data, onViewReference }: SqlRewriteCardProps) {
  const isCrossSql = data.mode === 'cross_sql_rewrite';
  const isGenerate = data.mode === 'generate_sql';

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(data.rewritten_sql);
      message.success(isGenerate ? '合成 SQL 已复制' : '改写 SQL 已复制');
    } catch {
      message.error('复制失败');
    }
  };

  const alertTitle = isGenerate
    ? 'AI 合成 SQL 草稿'
    : isCrossSql
      ? 'AI 跨 SQL 改写草稿'
      : 'AI 生成的 SQL 草稿';

  return (
    <div className="agent-card">
      <Alert
        type="warning"
        showIcon
        icon={<WarningOutlined />}
        message={alertTitle}
        description={
          data.warning ||
          (isGenerate
            ? '基于知识库合成，不会自动入库，请执行前自行校验。'
            : '不会覆盖原始 SQL 文件，请执行前自行校验 JOIN 键与 GROUP BY 粒度。')
        }
        style={{ marginBottom: 12 }}
      />

      {(isCrossSql || isGenerate) && (
        <Space wrap style={{ marginBottom: 8 }}>
          {isCrossSql && data.target_dimension && (
            <Tag color="blue">目标维度：{data.target_dimension}</Tag>
          )}
          {data.semantic_used && <Tag color="processing">语义检索</Tag>}
          {isGenerate && <Tag color="purple">知识库合成</Tag>}
        </Space>
      )}

      <Paragraph>{data.summary}</Paragraph>

      {isCrossSql && data.dimension_cooccurrence && data.dimension_cooccurrence.length > 0 && (
        <div style={{ marginBottom: 12 }}>
          <Text type="secondary" style={{ fontSize: 12 }}>
            库内维度-表共现（该维度最常出现的表）
          </Text>
          <Table
            size="small"
            pagination={false}
            style={{ marginTop: 4 }}
            rowKey="table"
            dataSource={data.dimension_cooccurrence.slice(0, 6)}
            columns={[
              { title: '表', dataIndex: 'table', key: 'table', ellipsis: true },
              { title: '出现次数', dataIndex: 'count', key: 'count', width: 80 },
              {
                title: '占比',
                dataIndex: 'ratio',
                key: 'ratio',
                width: 70,
                render: (v: number) => `${Math.round(v * 100)}%`,
              },
            ]}
          />
        </div>
      )}

      {(isCrossSql || isGenerate) && data.reference_sqls && data.reference_sqls.length > 0 && (
        <div style={{ marginBottom: 12 }}>
          <Text type="secondary" style={{ fontSize: 12 }}>
            借鉴来源
          </Text>
          <List
            size="small"
            dataSource={data.reference_sqls}
            renderItem={(ref) => (
              <List.Item style={{ padding: '4px 0', flexDirection: 'column', alignItems: 'flex-start' }}>
                <Space wrap>
                  <Text>{ref.file_name}</Text>
                  <Tag>id={ref.sql_id}</Tag>
                  {onViewReference && (
                    <Button
                      type="link"
                      size="small"
                      icon={<LinkOutlined />}
                      onClick={() => onViewReference(ref.sql_id)}
                    >
                      查看
                    </Button>
                  )}
                </Space>
                <Text type="secondary" style={{ fontSize: 12 }}>
                  {ref.reason}
                </Text>
                {ref.borrowed_joins && ref.borrowed_joins.length > 0 && (
                  <Text code style={{ fontSize: 11, whiteSpace: 'pre-wrap' }}>
                    {ref.borrowed_joins.join('\n')}
                  </Text>
                )}
                {ref.grain_comparison && ref.grain_comparison.length > 0 && (
                  <Text type="warning" style={{ fontSize: 11 }}>
                    {ref.grain_comparison.join('；')}
                  </Text>
                )}
              </List.Item>
            )}
          />
        </div>
      )}

      {data.changes?.length > 0 && (
        <div style={{ marginBottom: 8 }}>
          <Text type="secondary" style={{ fontSize: 12 }}>
            改动说明
          </Text>
          <List
            size="small"
            dataSource={data.changes}
            renderItem={(item) => <List.Item style={{ padding: '2px 0' }}>• {item}</List.Item>}
          />
        </div>
      )}

      {data.risk_notes && data.risk_notes.length > 0 && (
        <div style={{ marginBottom: 8 }}>
          <Text type="secondary" style={{ fontSize: 12 }}>
            风险提示
          </Text>
          <List
            size="small"
            dataSource={data.risk_notes}
            renderItem={(item) => (
              <List.Item style={{ padding: '2px 0', color: '#d48806' }}>⚠ {item}</List.Item>
            )}
          />
        </div>
      )}

      <Button
        type="primary"
        icon={<CopyOutlined />}
        onClick={handleCopy}
        style={{ marginBottom: 8 }}
      >
        复制改写 SQL
      </Button>

      <div className="sql-code-block" style={{ maxHeight: 360 }}>
        <SyntaxHighlighter
          language="sql"
          style={oneLight}
          customStyle={{ margin: 0, padding: 12, background: '#fafafa', fontSize: 12 }}
        >
          {data.rewritten_sql}
        </SyntaxHighlighter>
      </div>
    </div>
  );
}
