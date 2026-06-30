import { DeleteOutlined, InboxOutlined, PlusOutlined } from '@ant-design/icons';
import { Button, Checkbox, Input, List, Modal, Select, Space, Tag, Upload, message } from 'antd';
import type { UploadFile } from 'antd/es/upload/interface';
import { useRef, useState } from 'react';
import { batchSaveSharedSql } from '../api/sharedGroup';
import { parseSqlBatch } from '../api/sqlFiles';
import type { ParseBatchItem } from '../types/sqlFile';

const { Dragger } = Upload;
const { TextArea } = Input;

interface SharedSqlUploadModalProps {
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
}

type SharedUploadItem = ParseBatchItem & {
  storage_mode: 'public' | 'encrypted';
  is_public: boolean;
};

const EMPTY_TEMPLATE = `/*
文件: 共享SQL.sql
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

function blankItem(): SharedUploadItem {
  return {
    file_name: '新共享SQL.sql',
    valid: true,
    error: null,
    parsed: null,
    full_content: EMPTY_TEMPLATE,
    storage_mode: 'public',
    is_public: true,
  };
}

export default function SharedSqlUploadModal({ open, onClose, onSaved }: SharedSqlUploadModalProps) {
  const [items, setItems] = useState<SharedUploadItem[]>([]);
  const [parsing, setParsing] = useState(false);
  const [saving, setSaving] = useState(false);
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
      fileList.map(async (f) => ({
        file_name: f.name,
        full_content: await readFile(f.originFileObj!),
      })),
    );
    setParsing(true);
    try {
      const parsed = await parseSqlBatch(payloads);
      const mapped: SharedUploadItem[] = parsed.map((item, idx) => ({
        ...item,
        full_content: item.full_content || payloads[idx]?.full_content || '',
        storage_mode: 'public',
        is_public: true,
      }));
      setItems((prev) => [...prev, ...mapped]);
    } catch {
      message.error('解析失败');
    } finally {
      setParsing(false);
    }
  };

  const handleSave = async () => {
    const validItems = items.filter((i) => i.valid !== false);
    if (!validItems.length) {
      message.warning('没有可保存的 SQL');
      return;
    }
    setSaving(true);
    try {
      const result = await batchSaveSharedSql(
        validItems.map((i) => ({
          file_name: i.file_name,
          full_content: i.full_content ?? '',
          storage_mode: i.storage_mode,
          is_public: i.is_public,
        })),
      );
      if (result.errors?.length) {
        message.warning(`部分失败：${result.errors.slice(0, 3).join('；')}`);
      } else {
        message.success(`已保存 ${result.inserted} 条共享 SQL`);
      }
      setItems([]);
      onSaved();
      onClose();
    } catch (e: unknown) {
      message.error(
        (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
          '保存失败',
      );
    } finally {
      setSaving(false);
    }
  };

  const addBlank = () => {
    setItems((prev) => [...prev, blankItem()]);
  };

  return (
    <Modal
      title="上传共享群 SQL"
      open={open}
      onCancel={onClose}
      width={900}
      footer={[
        <Button key="cancel" onClick={onClose}>
          取消
        </Button>,
        <Button key="save" type="primary" loading={saving} onClick={handleSave}>
          保存到共享群
        </Button>,
      ]}
    >
      <Space direction="vertical" style={{ width: '100%' }} size="middle">
        <Dragger
          multiple
          accept=".sql,.txt"
          beforeUpload={() => false}
          onChange={({ fileList }) => {
            pendingFilesRef.current = fileList;
            window.clearTimeout(parseTimerRef.current);
            parseTimerRef.current = window.setTimeout(() => {
              void parseUploadFiles(pendingFilesRef.current);
            }, 300);
          }}
        >
          <p className="ant-upload-drag-icon">
            <InboxOutlined />
          </p>
          <p>拖拽或点击选择 SQL 文件（支持批量）</p>
        </Dragger>

        <Button icon={<PlusOutlined />} onClick={addBlank}>
          新建空白 SQL
        </Button>

        <List
          loading={parsing}
          dataSource={items}
          locale={{ emptyText: '请上传或新建 SQL' }}
          renderItem={(item, index) => (
            <List.Item
              actions={[
                <Button
                  key="del"
                  type="link"
                  danger
                  icon={<DeleteOutlined />}
                  onClick={() => setItems((prev) => prev.filter((_, i) => i !== index))}
                >
                  删除
                </Button>,
              ]}
            >
              <Space direction="vertical" style={{ width: '100%' }}>
                <Space wrap>
                  <Input
                    value={item.file_name}
                    onChange={(e) =>
                      setItems((prev) =>
                        prev.map((row, i) =>
                          i === index ? { ...row, file_name: e.target.value } : row,
                        ),
                      )
                    }
                    style={{ width: 280 }}
                  />
                  <Select
                    value={item.storage_mode}
                    style={{ width: 120 }}
                    onChange={(v) =>
                      setItems((prev) =>
                        prev.map((row, i) =>
                          i === index ? { ...row, storage_mode: v } : row,
                        ),
                      )
                    }
                    options={[
                      { label: '公开', value: 'public' },
                      { label: '加密', value: 'encrypted' },
                    ]}
                  />
                  <Checkbox
                    checked={item.is_public}
                    onChange={(e) =>
                      setItems((prev) =>
                        prev.map((row, i) =>
                          i === index ? { ...row, is_public: e.target.checked } : row,
                        ),
                      )
                    }
                  >
                    群内可见
                  </Checkbox>
                  {item.valid === false && <Tag color="error">{item.error || '格式无效'}</Tag>}
                  {item.storage_mode === 'encrypted' && <Tag color="purple">加密存储</Tag>}
                </Space>
                <TextArea
                  rows={8}
                  value={item.full_content ?? ''}
                  onChange={(e) =>
                    setItems((prev) =>
                      prev.map((row, i) =>
                        i === index ? { ...row, full_content: e.target.value } : row,
                      ),
                    )
                  }
                />
              </Space>
            </List.Item>
          )}
        />
      </Space>
    </Modal>
  );
}
