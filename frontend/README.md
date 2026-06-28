# Frontend

Guazi SQL Data Agent 前端（React + Vite + TypeScript + Ant Design）。

## 安装

```bash
cd frontend
npm install
```

## 开发

```bash
npm run dev
```

访问 http://localhost:5173

开发模式下 `/api` 请求会代理到 `http://localhost:8000`。

## 构建

```bash
npm run build
npm run preview
```

## 页面结构

| 组件 | 说明 |
|------|------|
| `SearchToolbar` | 同步、搜索、筛选 |
| `SqlListPanel` | 左侧 SQL 列表 |
| `SqlDetailPanel` | 右侧详情 + 代码高亮 |
| `SqlCodeBlock` | SQL 语法高亮与复制 |

## V2 扩展

- `pages/` 下可新增 `AgentPage.tsx`、`SqlExecutePage.tsx`
- `App.tsx` 可引入 React Router 做多模块导航
