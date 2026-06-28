import { DeleteOutlined, InboxOutlined, PlusOutlined } from '@ant-design/icons';
import { Button, Input, List, Modal, Space, Tag, Upload, message } from 'antd';
import type { UploadFile } from 'antd/es/upload/interface';
import { useRef, useState } from 'react';
import { batchSaveSql, parseSqlBatch } from '../api/sqlFiles';
import type { ParseBatchItem } from '../types/sqlFile';

const { Dragger } = Upload;
const { TextArea } = Input;

interface SqlUploadModalProps {
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
}

const EMPTY_TEMPLATE = `/*
文件: 新SQL.sql
指标: 示例指标
业务: C1
场景: 示例场景
标签: 标签1|标签2
维度: 维度1
核心表: db.table
作者: 作者名
描述: 简要描述
*/
SELECT 1
`;

function formatApiError(e: unknown): string {
  const err = e as {
    response?: { status?: number; data?: { detail?: unknown } };
    message?: string;
  };
  const detail = err.response?.data?.detail;
  if (typeof detail === 'string') return detail;
  if (Array.isArray(detail)) {
    return detail
      .map((item) => {
        if (typeof item === 'string') return item;
        if (item && typeof item === 'object' && 'msg' in item) return String(item.msg);
        return JSON.stringify(item);
      })
      .join('；');
  }
  if (err.response?.status === 401) return '登录已过期，请重新登录后再导入';
  if (err.response?.status === 413) return '一次导入的文件太多或太大，请分批导入（建议每次 20 个以内）';
  return err.message || '解析失败，请检查网络或稍后重试';
}

export default function SqlUploadModal({ open, onClose, onSaved }: SqlUploadModalProps) {
  const [items, setItems] = useState<ParseBatchItem[]>([]);
  const [parsing, setParsing] = useState(false);
  const [saving, setSaving] = useState(false);
  const parsedUidsRef = useRef<Set<string>>(new Set());
  const pendingFilesRef = useRef<UploadFile[]>([]);
  const parseTimerRef = useRef<number>();

  const readFile = (file: File): Promise<string> =>
    new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result || ''));
      reader.onerror = reject;
      reader.readAsText(file, 'UTF-8');
    });

  const parseUploadFiles = async (fileList: UploadFile[]) => {
    const payloads = await Promise.all(
      fileList.map(async (f) => {
        const blob = f.originFileObj;
        if (!blob) {
          throw new Error(`无法读取文件 ${f.name}，请重新选择`);
        }
        return {
          file_name: f.name,
          full_content: await readFile(blob),
        };
      }),
    );
    setParsing(true);
    try {
      const PARSE_CHUNK = 20;
      const allParsed: ParseBatchItem[] = [];
      for (let i = 0; i < payloads.length; i += PARSE_CHUNK) {
        const chunk = payloads.slice(i, i + PARSE_CHUNK);
        const parsed = await parseSqlBatch(chunk);
        allParsed.push(...parsed);
      }
      setItems((prev) => [...prev, ...allParsed]);
      const invalid = allParsed.filter((p) => !p.valid);
      if (invalid.length) {
        message.warning(
          `${invalid.length} 个文件注释块格式有问题，可在列表中查看具体原因`,
          6,
        );
      }
    } catch (e) {
      message.error(formatApiError(e));
    } finally {
      setParsing(false);
    }
  };

  const queueFilesForParse = (fileList: UploadFile[]) => {
    const newFiles = fileList.filter(
      (f) => f.originFileObj && !parsedUidsRef.current.has(f.uid),
    );
    if (!newFiles.length) return;

    newFiles.forEach((f) => parsedUidsRef.current.add(f.uid));
    pendingFilesRef.current.push(...newFiles);

    window.clearTimeout(parseTimerRef.current);
    parseTimerRef.current = window.setTimeout(() => {
      const batch = pendingFilesRef.current.splice(0);
      if (batch.length) {
        void parseUploadFiles(batch);
      }
    }, 400);
  };

  const updateItemContent = (index: number, full_content: string) => {
    setItems((prev) => {
      const next = [...prev];
      next[index] = { ...next[index], full_content };
      return next;
    });
  };

  const reparseItem = async (index: number) => {
    const item = items[index];
    if (!item.full_content) return;
    setParsing(true);
    try {
      const [parsed] = await parseSqlBatch([
        { file_name: item.file_name, full_content: item.full_content },
      ]);
      setItems((prev) => {
        const next = [...prev];
        next[index] = parsed;
        return next;
      });
    } finally {
      setParsing(false);
    }
  };

  const handleSave = async () => {
    const toSave = items.filter((i) => (i.full_content || '').trim());
    if (!toSave.length) {
      message.warning('请先添加 SQL 文件');
      return;
    }
    setSaving(true);
    try {
      // 保存前在服务端重新解析，不依赖前端「已识别」状态
      const CHUNK = 15;
      let totalInserted = 0;
      let totalUpdated = 0;
      const allErrors: string[] = [];

      for (let i = 0; i < toSave.length; i += CHUNK) {
        const chunk = toSave.slice(i, i + CHUNK);
        const result = await batchSaveSql(
          chunk.map((item) => ({
            file_name: item.file_name,
            full_content: item.full_content || '',
          })),
        );
        totalInserted += result.inserted;
        totalUpdated += result.updated;
        allErrors.push(...result.errors);
      }

      if (allErrors.length) {
        message.warning(
          `保存完成：新增 ${totalInserted}，更新 ${totalUpdated}；失败 ${allErrors.length} 条。${allErrors.slice(0, 2).join('；')}`,
          10,
        );
      } else {
        message.success(`保存成功：新增 ${totalInserted} 条，更新 ${totalUpdated} 条`);
      }
      if (totalInserted + totalUpdated > 0) {
        onSaved();
        setItems([]);
        onClose();
      }
    } catch (e: unknown) {
      const err = e as { response?: { data?: { detail?: string } } };
      message.error(err.response?.data?.detail || '保存失败，请刷新页面后重试');
    } finally {
      setSaving(false);
    }
  };

  const handleClose = () => {
    window.clearTimeout(parseTimerRef.current);
    parsedUidsRef.current.clear();
    pendingFilesRef.current = [];
    setItems([]);
    onClose();
  };

  return (
    <Modal
      title="导入 SQL（拖拽或粘贴）"
      open={open}
      onCancel={handleClose}
      width={900}
      footer={
        <Space>
          <Button onClick={handleClose}>取消</Button>
          <Button type="primary" loading={saving} onClick={handleSave}>
            确认保存
          </Button>
        </Space>
      }
    >
      <Dragger
        multiple
        accept=".sql"
        showUploadList={false}
        beforeUpload={() => false}
        onChange={({ fileList }) => queueFilesForParse(fileList)}
        disabled={parsing}
      >
        <p className="ant-upload-drag-icon">
          <InboxOutlined />
        </p>
        <p className="ant-upload-text">点击或拖拽 .sql 文件到此处</p>
        <p className="ant-upload-hint">支持批量导入，需包含标准注释块 /* ... */</p>
      </Dragger>

      <Button
        icon={<PlusOutlined />}
        style={{ marginTop: 12 }}
        onClick={() =>
          setItems((prev) => [
            ...prev,
            {
              file_name: `新SQL-${prev.length + 1}.sql`,
              valid: false,
              error: null,
              parsed: null,
              full_content: EMPTY_TEMPLATE,
            },
          ])
        }
      >
        手动新增 SQL
      </Button>

      <List
        style={{ marginTop: 16, maxHeight: 420, overflow: 'auto' }}
        dataSource={items}
        renderItem={(item, index) => (
          <List.Item
            actions={[
              <Button key="parse" size="small" onClick={() => reparseItem(index)}>
                重新识别
              </Button>,
              <Button
                key="del"
                size="small"
                danger
                icon={<DeleteOutlined />}
                onClick={() => setItems((prev) => prev.filter((_, i) => i !== index))}
              />,
            ]}
          >
            <List.Item.Meta
              title={
                <Space>
                  {item.file_name}
                  {item.valid ? (
                    <Tag color="green">已识别</Tag>
                  ) : (
                    <Tag color="red">{item.error || '待识别'}</Tag>
                  )}
                </Space>
              }
              description={
                item.valid && item.parsed ? (
                  <Space wrap size={[4, 4]}>
                    <Tag>业务: {String(item.parsed.business || '-')}</Tag>
                    <Tag>场景: {String(item.parsed.scene || '-')}</Tag>
                    <Tag>指标: {String(item.parsed.metric_raw || '-')}</Tag>
                  </Space>
                ) : null
              }
            />
            <TextArea
              rows={6}
              value={item.full_content || ''}
              onChange={(e) => updateItemContent(index, e.target.value)}
              style={{ width: '100%', fontFamily: 'monospace', fontSize: 12 }}
            />
          </List.Item>
        )}
      />
    </Modal>
  );
}
