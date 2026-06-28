/** AI Agent conversation panel — multi-turn + streaming. */

import {
  DeleteOutlined,
  PlusOutlined,
  RobotOutlined,
  SendOutlined,
} from '@ant-design/icons';
import { Badge, Button, Input, Select, Space, Spin, Tag, Typography, message } from 'antd';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  conversationChat,
  conversationChatStream,
  createConversation,
  deleteConversation,
  getConversation,
  getIndexStats,
  listConversations,
  type ConversationSummary,
  type IndexStats,
} from '../../api/conversations';
import type { AgentMessage, AgentMode, AgentResponseData } from '../../types/agent';
import ChatMessage from './ChatMessage';

const { Text } = Typography;
const { TextArea } = Input;

interface AgentPanelProps {
  currentSqlId: number | null;
  currentSqlName: string | null;
  onViewSqlDetail: (sqlId: number) => void;
  actionTrigger?: { mode: AgentMode; ts: number } | null;
}

function newId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

function recordToAgentMessage(rec: {
  id: number;
  role: string;
  content: string;
  mode?: string;
  data?: Record<string, unknown>;
  created_at?: string;
}): AgentMessage {
  return {
    id: String(rec.id),
    role: rec.role as 'user' | 'assistant',
    text: rec.content,
    mode: rec.mode as AgentMode | undefined,
    data: rec.data as AgentResponseData | undefined,
    createdAt: rec.created_at || new Date().toISOString(),
  };
}

export default function AgentPanel({
  currentSqlId,
  currentSqlName,
  onViewSqlDetail,
  actionTrigger,
}: AgentPanelProps) {
  const [conversations, setConversations] = useState<ConversationSummary[]>([]);
  const [activeConversationId, setActiveConversationId] = useState<number | null>(null);
  const [messages, setMessages] = useState<AgentMessage[]>([]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [indexStats, setIndexStats] = useState<IndexStats | null>(null);
  const [streamEnabled, setStreamEnabled] = useState(true);
  const scrollRef = useRef<HTMLDivElement>(null);

  const refreshConversations = useCallback(async () => {
    try {
      const items = await listConversations();
      setConversations(items);
    } catch {
      /* ignore */
    }
  }, []);

  const refreshIndexStats = useCallback(async () => {
    try {
      const stats = await getIndexStats();
      setIndexStats(stats);
    } catch {
      /* ignore */
    }
  }, []);

  const loadConversation = useCallback(async (id: number) => {
    const data = await getConversation(id);
    setActiveConversationId(id);
    setMessages(data.messages.map(recordToAgentMessage));
  }, []);

  useEffect(() => {
    void refreshConversations();
    void refreshIndexStats();
    const timer = window.setInterval(() => void refreshIndexStats(), 8000);
    return () => window.clearInterval(timer);
  }, [refreshConversations, refreshIndexStats]);

  useEffect(() => {
    requestAnimationFrame(() => {
      scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
    });
  }, [messages, loading]);

  const ensureConversation = async (): Promise<number> => {
    if (activeConversationId) return activeConversationId;
    const conv = await createConversation(currentSqlId);
    setActiveConversationId(conv.id);
    await refreshConversations();
    return conv.id;
  };

  const appendMessage = (msg: AgentMessage) => {
    setMessages((prev) => [...prev, msg]);
  };

  const handleResponse = (resp: {
    success: boolean;
    mode?: AgentMode | 'chat';
    data?: AgentResponseData;
    message?: string;
  }) => {
    if (!resp.success) {
      appendMessage({
        id: newId(),
        role: 'assistant',
        mode: resp.mode,
        error: resp.message || '请求失败',
        createdAt: new Date().toISOString(),
      });
      return;
    }
    const data = resp.data;
    appendMessage({
      id: newId(),
      role: 'assistant',
      mode: resp.mode,
      text: data?.summary,
      data,
      createdAt: new Date().toISOString(),
    });
  };

  const sendMessage = async (text: string, mode?: AgentMode) => {
    const trimmed = text.trim();
    if (!trimmed || loading) return;

    appendMessage({
      id: newId(),
      role: 'user',
      text: trimmed,
      mode,
      createdAt: new Date().toISOString(),
    });
    setInput('');
    setLoading(true);

    let streamPlaceholderId: string | null = null;

    try {
      const convId = await ensureConversation();
      if (streamEnabled) {
        streamPlaceholderId = newId();
        appendMessage({
          id: streamPlaceholderId,
          role: 'assistant',
          text: '',
          streaming: true,
          mode: 'chat',
          createdAt: new Date().toISOString(),
        });
        const placeholderId = streamPlaceholderId;
        await conversationChatStream(convId, trimmed, currentSqlId, {
          onToken: (token) => {
            setMessages((prev) =>
              prev.map((m) =>
                m.id === placeholderId
                  ? {
                      ...m,
                      text: (m.text || '') + token,
                      streaming: true,
                      mode: 'chat',
                    }
                  : m,
              ),
            );
          },
          onComplete: (resp) => {
            const isStructured =
              resp.event === 'result' ||
              (resp.mode != null && resp.mode !== 'chat');

            if (isStructured) {
              setMessages((prev) => {
                const rest = prev.filter((m) => m.id !== placeholderId);
                if (!resp.success) {
                  return [
                    ...rest,
                    {
                      id: newId(),
                      role: 'assistant',
                      mode: resp.mode,
                      error: resp.message || '请求失败',
                      createdAt: new Date().toISOString(),
                    },
                  ];
                }
                const data = resp.data as AgentResponseData | undefined;
                return [
                  ...rest,
                  {
                    id: newId(),
                    role: 'assistant',
                    mode: resp.mode,
                    text: data && 'summary' in data ? data.summary : undefined,
                    data,
                    createdAt: new Date().toISOString(),
                  },
                ];
              });
              return;
            }

            setMessages((prev) =>
              prev.map((m) => {
                if (m.id !== placeholderId) return m;
                if (!resp.success) {
                  return {
                    ...m,
                    streaming: false,
                    error: resp.message || '请求失败',
                    text: undefined,
                  };
                }
                const data = resp.data as AgentResponseData | undefined;
                const summary =
                  data && 'summary' in data && typeof data.summary === 'string'
                    ? data.summary
                    : m.text || '';
                return {
                  ...m,
                  text: summary,
                  data,
                  streaming: false,
                  mode: 'chat',
                };
              }),
            );
          },
        });
      } else {
        const resp = await conversationChat(convId, trimmed, currentSqlId);
        handleResponse(resp);
      }
      await refreshConversations();
    } catch {
      message.error('Agent 请求失败，请确认后端已启动');
      if (streamPlaceholderId) {
        setMessages((prev) =>
          prev
            .filter((m) => m.id !== streamPlaceholderId)
            .concat({
              id: newId(),
              role: 'assistant',
              error: 'Agent 请求失败',
              createdAt: new Date().toISOString(),
            }),
        );
      } else {
        appendMessage({
          id: newId(),
          role: 'assistant',
          error: 'Agent 请求失败',
          createdAt: new Date().toISOString(),
        });
      }
    } finally {
      setLoading(false);
    }
  };

  const runDirectAction = async (mode: AgentMode, userText: string) => {
    if (!currentSqlId && mode !== 'find_sql' && mode !== 'generate_sql') {
      appendMessage({
        id: newId(),
        role: 'assistant',
        error: '请先在左侧选择一个 SQL 作为上下文。',
        createdAt: new Date().toISOString(),
      });
      return;
    }
    await sendMessage(userText, mode);
  };

  useEffect(() => {
    if (!actionTrigger) return;
    if (actionTrigger.mode === 'explain_sql') {
      void runDirectAction('explain_sql', '解释当前 SQL');
    } else if (actionTrigger.mode === 'recommend_similar_sql') {
      void runDirectAction('recommend_similar_sql', '推荐相似 SQL');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [actionTrigger?.ts]);

  const handleNewConversation = async () => {
    const conv = await createConversation(currentSqlId);
    setActiveConversationId(conv.id);
    setMessages([]);
    await refreshConversations();
  };

  const handleDeleteConversation = async () => {
    if (!activeConversationId) return;
    await deleteConversation(activeConversationId);
    setActiveConversationId(null);
    setMessages([]);
    await refreshConversations();
    message.success('已删除会话');
  };

  const indexLabel =
    indexStats && indexStats.pending + indexStats.queue_pending > 0
      ? `索引中 ${indexStats.ready}/${indexStats.total}`
      : indexStats
        ? `已索引 ${indexStats.ready}/${indexStats.total}`
        : null;

  return (
    <div className="panel-agent">
      <div className="agent-header">
        <Space wrap>
          <RobotOutlined style={{ fontSize: 18, color: '#1677ff' }} />
          <Text strong>AI SQL Agent</Text>
          {indexLabel && (
            <Tag color={indexStats?.failed ? 'error' : 'processing'}>{indexLabel}</Tag>
          )}
        </Space>
        <Text type="secondary" style={{ fontSize: 12, display: 'block', marginTop: 4 }}>
          当前上下文：{currentSqlName || '无'} · 语义检索 + 多轮对话
        </Text>
        <Space wrap style={{ marginTop: 8, width: '100%' }}>
          <Select
            size="small"
            style={{ flex: 1, minWidth: 140 }}
            placeholder="选择历史会话"
            value={activeConversationId ?? undefined}
            onChange={(v) => void loadConversation(v)}
            options={conversations.map((c) => ({
              value: c.id,
              label: c.title,
            }))}
            allowClear
            onClear={() => {
              setActiveConversationId(null);
              setMessages([]);
            }}
          />
          <Button size="small" icon={<PlusOutlined />} onClick={() => void handleNewConversation()}>
            新对话
          </Button>
          <Button
            size="small"
            danger
            icon={<DeleteOutlined />}
            disabled={!activeConversationId}
            onClick={() => void handleDeleteConversation()}
          />
        </Space>
      </div>

      <div className="agent-messages" ref={scrollRef}>
        {messages.length === 0 && (
          <div className="agent-welcome">
            <Text type="secondary">
              输入自然语言对话，或：找 SQL / 解释 / 改写 / 加维度 / 生成 SQL。自由追问支持流式打字机。
            </Text>
          </div>
        )}
        {messages.map((msg) => (
          <ChatMessage key={msg.id} message={msg} onViewDetail={onViewSqlDetail} />
        ))}
        {loading && !messages.some((m) => m.streaming) && (
          <div className="agent-loading">
            <Spin size="small" /> <Text type="secondary">思考中...</Text>
          </div>
        )}
      </div>

      <div className="agent-input-area">
        <Space wrap size={[4, 4]} style={{ marginBottom: 8 }}>
          {[
            { label: '找 SQL', text: '找相关 SQL' },
            { label: '解释', text: '解释这个 SQL', mode: 'explain_sql' as AgentMode, need: true },
            { label: '相似', text: '推荐相似 SQL', mode: 'recommend_similar_sql' as AgentMode, need: true },
            { label: '改写', text: '把这个 SQL 改成最近30天', mode: 'rewrite_sql' as AgentMode, need: true },
            {
              label: '加维度',
              text: '加上城市维度',
              mode: 'cross_sql_rewrite' as AgentMode,
              need: true,
            },
            {
              label: '生成 SQL',
              text: '根据知识库帮我写一条停售分析 SQL',
              mode: 'generate_sql' as AgentMode,
              need: false,
            },
          ].map((action) => (
            <Button
              key={action.label}
              size="small"
              disabled={Boolean(action.need && !currentSqlId)}
              onClick={() => {
                if (action.mode) {
                  void runDirectAction(action.mode, action.text);
                } else {
                  setInput('找 ');
                }
              }}
            >
              {action.label}
            </Button>
          ))}
          <Badge
            status={streamEnabled ? 'processing' : 'default'}
            text={
              <Button type="link" size="small" onClick={() => setStreamEnabled((v) => !v)}>
                {streamEnabled ? '流式开' : '流式关'}
              </Button>
            }
          />
        </Space>
        <Space.Compact style={{ width: '100%' }} className="agent-input-compact">
          <TextArea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="输入问题，可连续追问..."
            autoSize={{ minRows: 3, maxRows: 6 }}
            className="agent-textarea"
            onPressEnter={(e) => {
              if (!e.shiftKey) {
                e.preventDefault();
                void sendMessage(input);
              }
            }}
          />
          <Button
            type="primary"
            icon={<SendOutlined />}
            loading={loading}
            onClick={() => void sendMessage(input)}
            style={{ height: 'auto' }}
          >
            发送
          </Button>
        </Space.Compact>
      </div>
    </div>
  );
}
