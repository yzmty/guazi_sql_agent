/** Single chat message bubble. */

import { Typography } from 'antd';
import type { AgentMessage } from '../../types/agent';
import SqlExplanationCard from './SqlExplanationCard';
import SqlRecommendationCard from './SqlRecommendationCard';
import SqlRewriteCard from './SqlRewriteCard';

const { Text } = Typography;

interface ChatMessageProps {
  message: AgentMessage;
  onViewDetail: (sqlId: number) => void;
}

function isStructuredMode(message: AgentMessage): boolean {
  const mode = message.data?.mode;
  return (
    mode === 'find_sql' ||
    mode === 'recommend_similar_sql' ||
    mode === 'explain_sql' ||
    mode === 'rewrite_sql' ||
    mode === 'cross_sql_rewrite' ||
    mode === 'generate_sql'
  );
}

export default function ChatMessage({ message, onViewDetail }: ChatMessageProps) {
  const isUser = message.role === 'user';
  const structured = isStructuredMode(message);
  const showChatText =
    !structured &&
    (message.streaming ||
      message.data?.mode === 'chat' ||
      (!message.data && Boolean(message.text)));

  const chatText =
    message.text ||
    (message.data?.mode === 'chat' && 'summary' in message.data
      ? message.data.summary
      : '');

  return (
    <div className={`chat-message ${isUser ? 'chat-message-user' : 'chat-message-assistant'}`}>
      <div className="chat-message-bubble">
        {isUser ? (
          <Text>{message.text}</Text>
        ) : message.error ? (
          <Text type="danger">{message.error}</Text>
        ) : (
          <>
            {showChatText && (
              <Text style={{ whiteSpace: 'pre-wrap' }}>
                {chatText}
                {message.streaming && !chatText && (
                  <Text type="secondary">思考中...</Text>
                )}
                {message.streaming && chatText && (
                  <span className="chat-stream-cursor">▋</span>
                )}
              </Text>
            )}
            {message.data?.mode === 'find_sql' && (
              <SqlRecommendationCard
                summary={message.data.summary}
                results={message.data.results}
                onViewDetail={onViewDetail}
                llmUsed={message.data.llm_used}
                semanticUsed={message.data.semantic_used}
              />
            )}
            {message.data?.mode === 'recommend_similar_sql' && (
              <SqlRecommendationCard
                summary={message.data.summary}
                results={message.data.results}
                onViewDetail={onViewDetail}
                llmUsed={message.data.llm_used}
              />
            )}
            {message.data?.mode === 'explain_sql' && (
              <SqlExplanationCard data={message.data} />
            )}
            {(message.data?.mode === 'rewrite_sql' ||
              message.data?.mode === 'cross_sql_rewrite' ||
              message.data?.mode === 'generate_sql') && (
              <SqlRewriteCard data={message.data} onViewReference={onViewDetail} />
            )}
          </>
        )}
      </div>
    </div>
  );
}
