/** SQL syntax-highlighted code block with copy button. */

import { CopyOutlined } from '@ant-design/icons';
import { Button, message, Space } from 'antd';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { oneLight } from 'react-syntax-highlighter/dist/esm/styles/prism';

interface SqlCodeBlockProps {
  code: string;
  fileName?: string;
}

export default function SqlCodeBlock({ code, fileName }: SqlCodeBlockProps) {
  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      message.success('SQL 已复制到剪贴板');
    } catch {
      message.error('复制失败，请手动选择复制');
    }
  };

  return (
    <div>
      <Space style={{ marginBottom: 8 }}>
        <Button type="primary" icon={<CopyOutlined />} onClick={handleCopy}>
          复制 SQL
        </Button>
        {fileName && (
          <span style={{ color: '#888', fontSize: 12 }}>{fileName}</span>
        )}
      </Space>
      <div className="sql-code-block">
        <SyntaxHighlighter
          language="sql"
          style={oneLight}
          customStyle={{ margin: 0, padding: 16, background: '#fafafa' }}
          showLineNumbers
        >
          {code || '-- 无 SQL 内容'}
        </SyntaxHighlighter>
      </div>
    </div>
  );
}
