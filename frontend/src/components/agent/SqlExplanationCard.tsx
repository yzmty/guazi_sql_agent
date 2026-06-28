/** Structured SQL explanation card. */

import { Tag, Typography } from 'antd';
import type { ExplainSqlData } from '../../types/agent';

const { Paragraph, Text } = Typography;

interface SqlExplanationCardProps {
  data: ExplainSqlData;
}

function TagRow({ label, items }: { label: string; items: string[] }) {
  if (!items?.length) return null;
  return (
    <div style={{ marginBottom: 8 }}>
      <Text type="secondary" style={{ fontSize: 12 }}>
        {label}
      </Text>
      <div style={{ marginTop: 4 }}>
        {items.map((item) => (
          <Tag key={item} style={{ marginBottom: 4 }}>
            {item}
          </Tag>
        ))}
      </div>
    </div>
  );
}

export default function SqlExplanationCard({ data }: SqlExplanationCardProps) {
  return (
    <div className="agent-card">
      <Paragraph strong style={{ marginBottom: 4 }}>
        {data.title}
      </Paragraph>
      <Paragraph>{data.summary}</Paragraph>

      <div className="agent-explain-section">
        <Text type="secondary">业务含义</Text>
        <Paragraph style={{ margin: '4px 0 8px' }}>{data.business_meaning}</Paragraph>
      </div>

      <TagRow label="主要指标" items={data.main_metrics} />
      <TagRow label="主要维度" items={data.main_dimensions} />
      <TagRow label="核心表" items={data.core_tables} />

      {data.logic_points?.length > 0 && (
        <div style={{ marginBottom: 8 }}>
          <Text type="secondary" style={{ fontSize: 12 }}>
            关键逻辑
          </Text>
          <ul style={{ margin: '4px 0', paddingLeft: 18, fontSize: 13 }}>
            {data.logic_points.map((p) => (
              <li key={p}>{p}</li>
            ))}
          </ul>
        </div>
      )}

      {data.filter_conditions && data.filter_conditions.length > 0 && (
        <div style={{ marginBottom: 8 }}>
          <Text type="secondary" style={{ fontSize: 12 }}>
            主要过滤条件
          </Text>
          <ul style={{ margin: '4px 0', paddingLeft: 18, fontSize: 13 }}>
            {data.filter_conditions.map((p) => (
              <li key={p}>{p}</li>
            ))}
          </ul>
        </div>
      )}

      {data.output_shape && (
        <div style={{ marginBottom: 8 }}>
          <Text type="secondary" style={{ fontSize: 12 }}>
            输出形态
          </Text>
          <Paragraph style={{ margin: '4px 0' }}>{data.output_shape}</Paragraph>
        </div>
      )}

      {data.applicable_questions?.length > 0 && (
        <div>
          <Text type="secondary" style={{ fontSize: 12 }}>
            适用问题
          </Text>
          <ul style={{ margin: '4px 0', paddingLeft: 18, fontSize: 13 }}>
            {data.applicable_questions.map((q) => (
              <li key={q}>{q}</li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
