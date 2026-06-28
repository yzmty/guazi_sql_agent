/** SQL recommendation list card (find / recommend modes). */

import { Button, Card, Typography } from 'antd';
import type { SqlRecommendationItem } from '../../types/agent';

const { Text, Paragraph } = Typography;

interface SqlRecommendationCardProps {
  summary: string;
  results: SqlRecommendationItem[];
  onViewDetail: (sqlId: number) => void;
  llmUsed?: boolean;
  semanticUsed?: boolean;
}

export default function SqlRecommendationCard({
  summary,
  results,
  onViewDetail,
  llmUsed,
  semanticUsed,
}: SqlRecommendationCardProps) {
  return (
    <div className="agent-card">
      <Paragraph style={{ marginBottom: 8 }}>{summary}</Paragraph>
      {semanticUsed && (
        <Text type="secondary" style={{ fontSize: 11, display: 'block' }}>
          已使用语义向量检索
        </Text>
      )}
      {!llmUsed && !semanticUsed && (
        <Text type="secondary" style={{ fontSize: 11 }}>
          （基于本地检索）
        </Text>
      )}
      {results.map((item) => (
        <Card
          key={item.sql_id}
          size="small"
          style={{ marginTop: 8 }}
          actions={[
            <Button type="link" key="view" onClick={() => onViewDetail(item.sql_id)}>
              查看详情
            </Button>,
          ]}
        >
          <Text strong>{item.file_name}</Text>
          {item.business && (
            <Paragraph
              type="secondary"
              style={{ margin: '4px 0', fontSize: 12 }}
              ellipsis={{ rows: 1 }}
            >
              业务：{item.business}
            </Paragraph>
          )}
          {item.scene && (
            <Paragraph
              style={{ margin: '4px 0', fontSize: 12, color: '#666' }}
              ellipsis={{ rows: 2 }}
            >
              {item.scene}
            </Paragraph>
          )}
          <Text style={{ fontSize: 12, color: '#1677ff' }}>{item.reason}</Text>
        </Card>
      ))}
      {results.length === 0 && (
        <Text type="secondary">未找到相关 SQL</Text>
      )}
    </div>
  );
}
