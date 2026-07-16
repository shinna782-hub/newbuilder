---
name: feishu-article-collector
description: |
  收集微信公众号/飞书文章并写入飞书多维表格。
  唯一触发指令：资讯。
---

# Feishu Article Collector

Collect articles from URLs and write them to a Feishu bitable.

> 状态：早期版本。首次使用前，请配置自己的表格环境变量和分类选项。

## 触发指令
`资讯`

## Workflow

### Step 1: Fetch Articles

**微信公众号文章（mp.weixin.qq.com）：**使用当前 Agent 已审查并获授权的微信文章提取能力，读取原始标题、作者、发布日期、摘要和正文。

**飞书文档/其他页面：**使用当前 Agent 已审查并获授权的网页或飞书文档读取能力。

> 不要依赖某台电脑上的固定脚本路径；如果运行环境没有合适的提取能力，应先向用户说明并请求安装或授权。

### Step 2: Extract Article Info

**微信公众号文章：**
提取器应返回 title、date/date_timestamp 和 summary，直接使用：
- **标题**: from `result["title"]` — already exact, no manipulation needed
- **日期**: from `result["date_timestamp"]` — Unix ms timestamp
- **梗概**: from `result["summary"]`

**非微信公众号页面：**
Extract manually from fetched content:
- **标题**: **MUST exactly match the original article's full title** — including all characters, punctuation, and subtitle text (e.g. "丨", "——", "【", etc.). **Never truncate, shorten, or omit any part of the title.**
  1. **First try**: Extract title from article content
  2. **If content doesn't have it**: Try Feishu API to get WeChat meta title
  3. **If still unavailable**: Ask the user — do NOT fabricate or guess
  ⚠️ **禁止擅自取标题** — 必须从文章内容或API提取，只有在两者都无法获取时才询问用户
- **梗概**: First 2-3 paragraphs summarizing the key points (~150 chars)
- **日期**: **CRITICAL — when the user provides a date in their message (e.g. "2.27 https://..." or "2026.3.1 https://..."), that is the publication date.** Use the date provided by the user directly. Only search the article content for the date if the user does NOT provide one. WeChat articles display the date at the top or bottom of the article body (e.g. "2026年4月8日" or "Apr 8, 2026").
  - **飞书文档日期**：飞书 API 返回的 `node_create_time` 是 UTC+8 北京时间的时间戳（秒），转换为毫秒后直接用 `pytz` 计算：
    ```python
    import datetime, pytz
    beijing = pytz.timezone('Asia/Shanghai')
    beijing_dt = beijing.localize(datetime.datetime.fromtimestamp(node_create_time))
    # Or for a known date: beijing_dt = beijing.localize(datetime.datetime(y, m, d, 0, 0, 0))
    ts_ms = int(beijing_dt.timestamp() * 1000)
    ```
    **不要用 `utcfromtimestamp()` 减 8 小时**，那样会多减一天。
- **领域**: Choose from the enum values listed below — see Classification Priority for rules
- **链接来源**: 微信公众号 / 飞书 / B站

#### 领域枚举值（已确认）
`"人"的培养 / AI硬件 / Agent玩法 / AI交互产品 / AI行业洞见 / 基座模型更新 / AI应用场景及案例 / Skills工具 / Vibe Coding经验和方法论 / AI视频生成 / 热点事件与大会 / Agent技术干货 / AI游戏开发 / Claude Code玩法 / Hermes玩法 / AI Native组织与职业 / 小白入门 / Agent记忆 / Codex玩法 / 创业经验 / 增长营销 / 知识库管理 / 不确定（让用户来选）`

#### 分类优先级规则
0. 讲AI时代下人的自我提升和突破 → 「"人"的培养」
1. 命中「ai交互产品 / ai视频生成 / ai游戏开发」→ 优先归属这些
2. 跟Claude Code相关 → 「Claude Code玩法」
3. 跟Hermes Agent相关 → 「Hermes玩法」
4. 讲Skills的使用/玩法/汇总 → 「skills工具」；讲Skills的技术原理/机制 → 「Agent技术干货」
5. 跟Agent技术相关 → 「Agent技术干货」
6. 都命中不了，但属于AI应用案例 → 「AI应用场景及案例」
7. 其他已有枚举按名称语义归属

#### ⚠️ 分类判断原则：标题 + 梗概综合决策
**必须结合「文章标题」和「文章梗概」两者共同判断分类**，不能仅凭标题关键词机械匹配。操作步骤：
1. 先读标题获取表面信息
2. 再读梗概理解文章实际核心内容
3. 综合判断——如果标题说的是AI工具但梗概实际在讲组织变革，应归「AI native组织与职业」而非「工具」类；如果梗概在讲工作流经验而非工具本身，应归「vibe coding经验」而非「行业洞见」
4. 遇到模糊案例时，以梗概的实际topic为准，而非标题的字面意思

#### ⚠️ 新增枚举值规则
**严禁擅自新增枚举值。** 如果文章不符合任何已有分类，先回复用户询问「归为哪类」或「是否需要新增」，得到确认后再写入。

### Step 3: Get Feishu Token
Read credentials from the current process environment. Never commit credentials or table identifiers to the repository.

```bash
: "${FEISHU_APP_ID:?FEISHU_APP_ID is not set}"
: "${FEISHU_APP_SECRET:?FEISHU_APP_SECRET is not set}"
curl -s -X POST 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d "{\"app_id\":\"${FEISHU_APP_ID}\",\"app_secret\":\"${FEISHU_APP_SECRET}\"}"
```

### Step 4: Batch Create Records
```bash
: "${FEISHU_ARTICLE_BITABLE_APP_TOKEN:?FEISHU_ARTICLE_BITABLE_APP_TOKEN is not set}"
: "${FEISHU_ARTICLE_BITABLE_TABLE_ID:?FEISHU_ARTICLE_BITABLE_TABLE_ID is not set}"
curl -s -X POST "https://open.feishu.cn/open-apis/bitable/v1/apps/${FEISHU_ARTICLE_BITABLE_APP_TOKEN}/tables/${FEISHU_ARTICLE_BITABLE_TABLE_ID}/records/batch_create" \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "records": [{
      "fields": {
        "文章标题": "...",
        "文章内容梗概": "...",
        "领域": "...",
        "文章发布日期": <timestamp_ms>,
        "链接来源": "...",
        "文章链接": {"link": "..."}
      }
    }]
  }'
```

### Step 5: Verify Write Success
After every write (batch_create or single record update), you MUST verify by reading back the record with the returned `record_id`. If the record cannot be found (returns RecordIdNotFound), the write actually failed — you must retry the write operation until verification passes. Do not report success to the user until verification confirms the record exists in the table.

```bash
# Verify a record exists
curl -s -X GET "https://open.feishu.cn/open-apis/bitable/v1/apps/${FEISHU_ARTICLE_BITABLE_APP_TOKEN}/tables/${FEISHU_ARTICLE_BITABLE_TABLE_ID}/records/<record_id>" \
  -H 'Authorization: Bearer <token>'
```

## Key Rules
- **微信公众号文章 → 使用专用提取能力**，准确读取标题、日期和摘要
- **其他页面 → 使用已审查的通用网页读取能力**
- Always use batch_create (faster, one API call)
- SingleSelect fields: pass as plain string, not object
- Date field: Unix timestamp in **milliseconds**
- **⚠️ Article title must EXACTLY match the original article title — never fabricate or rewrite titles**
  - For WeChat: use the extractor's original `title` directly
  - For other pages: extract from article content or API, ask user if unavailable
- **⚠️ Use the extractor's original publication timestamp for WeChat articles** — do NOT guess from the current date
- Article summary should be concise (~150 chars), capture the core insight
- 微信公众号 dates are typically in Chinese format (e.g. "2026年4月8日")
- ⚠️ Do NOT fill 阅读进度 by default — that field is for the user to fill in manually. **However, if the user explicitly asks you to update the reading status (e.g. "更新成已完成"), you CAN update it.**
- **⚠️ After writing to the bitable, ALWAYS return the full record summary to the user for review** — include title, date, category, and link
