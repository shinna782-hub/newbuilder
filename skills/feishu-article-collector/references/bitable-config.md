# Feishu Bitable Configuration

## Bitable Info
- **app_token**: environment variable `FEISHU_ARTICLE_BITABLE_APP_TOKEN`
- **table_id**: environment variable `FEISHU_ARTICLE_BITABLE_TABLE_ID`

## Fields & Types
| Field Name | Type | Notes |
|---|---|---|
| 文章标题 | Text | Primary field |
| 文章内容梗概 | Text | Summary, ~100-200 chars |
| 领域 | SingleSelect | See options below |
| 文章发布日期 | DateTime | Unix timestamp in ms (e.g. 1744166400000) |
| 链接来源 | SingleSelect | 微信公众号/飞书/B站 |
| 文章来源 | SingleSelect | 人工精选/自动采集 |
| 文章链接 | URL | {"link": "url"} |
| 阅读进度 | SingleSelect | 已完成 |
| 阅读速记 | Text | Optional notes |
| 该条记录添加日期 | DateTime | Auto-filled, not needed |

## SingleSelect Options
### 领域
- 龙虾小白入门
- 小龙虾玩法
- ai交互产品
- 行业洞见
- 基座模型更新
- 应用场景案例
- skills
- vibe coding
- ai视频生成
- 热点动态
- 既有选项不适用，让用户来定

### 链接来源
- 飞书
- 微信公众号
- B站

### 文章来源
- 人工精选
- 自动采集

### 阅读进度
- 已完成

## Feishu API Credentials
```
app_id: read from FEISHU_APP_ID
app_secret: read from FEISHU_APP_SECRET
```

## Date Conversion
Python: `int(datetime.datetime(YEAR, MONTH, DAY, 0, 0, tzinfo=datetime.timezone(datetime.timedelta(hours=8))).timestamp() * 1000)`

⚠️ WeChat dates are NOT Unix epoch — always look for the actual date INSIDE the article text. Common mistakes:
- Guessing "前两天" as days ago instead of reading the actual publish date
- Assuming article date = today minus N days

Do not hard-code example dates from a personal dataset. Convert the actual publication date for each article.
