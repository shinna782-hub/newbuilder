---
name: fragment-collector
description: |
  收集群聊或各类软件中的碎片信息（图片/文字/链接），提炼主要内容并写入飞书多维表格。
  唯一触发指令：碎片。
---

# Fragment Collector - 碎片收集

将群聊或各类软件中的图片/文字/链接碎片提炼整理到飞书多维表格。

> 状态：早期版本。首次使用前，请按自己的飞书多维表格字段完成配置。

## 触发指令
`碎片`

## 目标多维表格
- **App Token**: 环境变量 `FRAGMENT_COLLECTOR_BITABLE_APP_TOKEN`
- **Table ID**: 环境变量 `FRAGMENT_COLLECTOR_BITABLE_TABLE_ID`
- **表名**: 碎片化信息整理

## 字段映射

| 字段名 | 类型 | 说明 |
|--------|------|------|
| 内容摘要 | Text | 总结主要内容 |
| 类型 | MultiSelect | 图片/链接/文字 |
| 来源 | SingleSelect | 用户发送/小红书/B站 |
| 原始图片 | Attachment | 用户发送的图片附件 |
| 完整原文 | Text | 用户发送的完整文字 |
| 链接标题 | Text | 从链接提取的原始标题 |
| URL | URL | 链接地址 |
| 标签 | MultiSelect | 认知/素材/方法论/行业/工具/AI/开发效率/infra |
| 精彩语录 | Text | 图片/截图中的有价值金句 |
| 添加日期 | DateTime | 自动填充当前日期 |
| 状态 | SingleSelect | 待看/已看，默认为空 |

## 工作流程

### Step 1: 分析用户输入
解析用户消息，识别以下内容类型：
- **图片**: 用户发送的图片附件（截图、照片等）
- **文字**: 用户直接发送的文字内容
- **链接**: 用户发送的 URL 链接

### Step 2: 获取 Feishu Token
从当前进程的环境变量读取飞书凭据，不要把凭据写入 Skill、仓库或日志。

```bash
: "${FEISHU_APP_ID:?FEISHU_APP_ID is not set}"
: "${FEISHU_APP_SECRET:?FEISHU_APP_SECRET is not set}"
curl -s -X POST 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d "{\"app_id\":\"${FEISHU_APP_ID}\",\"app_secret\":\"${FEISHU_APP_SECRET}\"}"
```

### Step 3: 确定字段值

#### 类型（MultiSelect）
根据实际内容类型设置：
- 图片 → `["图片"]`
- 文字 → `["文字"]`
- 链接 → `["链接"]`
- 混合 → `["图片", "文字"]` 等组合

#### 来源（SingleSelect）
根据内容来源判断：
- 用户直接发送 → `用户发送`
- 小红书链接/截图 → `小红书`
- B站链接/截图 → `B站`

#### 内容摘要
用 50-150 字总结核心内容，提炼最有价值的信息点。

#### 精彩语录
如果截图或文字中有值得引用的金句、原话，单独提取出来。

#### 标签（MultiSelect）
从以下已有选项中选择（可多选）：
- `认知` - 思维、观点、认知升级相关
- `素材` - 创作素材、设计参考
- `方法论` - 方法、流程、框架
- `行业` - 行业观察、趋势
- `工具` - 工具推荐、使用技巧
- `AI` - 人工智能相关
- `开发效率` - 编程、开发提效
- `infra` - 基础设施相关

**严禁擅自新增标签**。如果内容无法归类到已有标签，先询问用户确认。

#### 链接标题 & URL
如果用户发送了链接：
- URL 字段：直接使用链接
- 链接标题：使用 `web_fetch` 或 `curl` 抓取页面标题

#### 原始图片 & 完整原文
- 图片：通过 Feishu 消息附件接口获取并上传
- 文字：直接填入完整原文字段

### Step 4: 上传图片附件（如有）

使用 bitable 上传附件接口或通过 Feishu 文件上传接口获取 file_token。

### Step 5: 写入记录

```bash
: "${FRAGMENT_COLLECTOR_BITABLE_APP_TOKEN:?FRAGMENT_COLLECTOR_BITABLE_APP_TOKEN is not set}"
: "${FRAGMENT_COLLECTOR_BITABLE_TABLE_ID:?FRAGMENT_COLLECTOR_BITABLE_TABLE_ID is not set}"
curl -s -X POST "https://open.feishu.cn/open-apis/bitable/v1/apps/${FRAGMENT_COLLECTOR_BITABLE_APP_TOKEN}/tables/${FRAGMENT_COLLECTOR_BITABLE_TABLE_ID}/records" \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "fields": {
      "内容摘要": "...",
      "类型": ["图片", "文字"],
      "来源": "用户发送",
      "原始图片": [{"file_token": "..."}],
      "完整原文": "...",
      "链接标题": "...",
      "URL": {"link": "https://..."},
      "标签": ["认知", "AI"],
      "精彩语录": "..."
    }
  }'
```

**注意**：
- DateTime 字段 `添加日期` 设置 `auto_fill: true`，创建记录时会自动填充
- `状态` 字段默认留空，由用户手动填写

### Step 6: 验证写入成功
读取返回的 record_id，确认记录已写入。

## 关键规则

- **标签收敛原则**：严禁无限制新增标签。如果有内容无法归类，回复用户询问是否需要新增
- **标题精确**：链接标题必须从页面内容提取，禁止臆造
- **状态默认空**：创建记录时状态字段留空，等用户手动填写或主动要求更新
- **图片优先**：有图片时优先处理图片中的信息（OCR 识别、视觉信息提取）
- **混合内容**：同时发送图片+文字+链接时，全部处理并在类型字段标注所有涉及类型
