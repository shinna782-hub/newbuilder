---
name: ai-play-tracker
description: |
  记录待体验的 AI 玩法、AI 新工具、AI 新模型并写入飞书多维表格。
  唯一触发指令：小妙招。
---

# AI Play Tracker - 待体验AI玩法记录

记录你想体验的 AI 玩法、AI 新工具、AI 新模型。

> 状态：早期版本。首次使用前，请按自己的飞书多维表格字段完成配置。

## 触发关键词
`小妙招`

## 目标多维表格
- App Token: 环境变量 `AI_PLAY_TRACKER_BITABLE_APP_TOKEN`
- Table ID: 环境变量 `AI_PLAY_TRACKER_BITABLE_TABLE_ID`
- 名称：每天一个AI小妙招

## 字段映射
| 字段名 | 类型 | 说明 |
|--------|------|------|
| AI小妙招 | Text | 用户发送内容的第一行（必填） |
| 补充介绍 | Text | 从文章/链接提取的额外信息，与原文重复时可不写 |
| 用户原文 | Text | 用户发送的原始消息（含链接、描述），不做任何删改 |
| 妙招类型 | SingleSelect | 新产品/玩法/新模型/skill |
| 添加时间 | DateTime | 自动填充当前时间 |
| 体验状态 | SingleSelect | 待体验/已体验/体验中（新增时默认填「待体验」） |

## 字段填充规则

### AI小妙招
- 取用户发送内容的**第一行**作为名称
- 不需要【】包裹

### 用户原文
- 用户发的原始消息，含链接、描述等全部内容
- **不包含** "小妙招"三个字和第一行（第一行作为 AI小妙招 名称单独存放）

### 补充介绍
- 从文章内容/链接中提取额外信息
- **如果和用户原文重复，则不写**
- 包含相关链接（官网/GitHub等）

### 妙招类型参考
| 类型 | 适用场景 |
|------|---------|
| 新产品 | 独立工具/应用/平台 |
| 玩法 | 使用技巧、方法论、配置方案 |
| 新模型 | 模型更新、Agent框架 |
| skill | 技能包、prompt集合 |

### 体验状态
- 新增记录时默认填写「待体验」
- 用户要求更新时再改为其他状态

## 工作流程

### Step 1: 获取 Feishu Token
从当前进程的环境变量读取飞书凭据，不要把凭据写入 Skill、仓库或日志。

```bash
: "${FEISHU_APP_ID:?FEISHU_APP_ID is not set}"
: "${FEISHU_APP_SECRET:?FEISHU_APP_SECRET is not set}"
curl -s -X POST 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d "{\"app_id\":\"${FEISHU_APP_ID}\",\"app_secret\":\"${FEISHU_APP_SECRET}\"}"
```

### Step 2: 创建记录
```bash
: "${AI_PLAY_TRACKER_BITABLE_APP_TOKEN:?AI_PLAY_TRACKER_BITABLE_APP_TOKEN is not set}"
: "${AI_PLAY_TRACKER_BITABLE_TABLE_ID:?AI_PLAY_TRACKER_BITABLE_TABLE_ID is not set}"
curl -s -X POST "https://open.feishu.cn/open-apis/bitable/v1/apps/${AI_PLAY_TRACKER_BITABLE_APP_TOKEN}/tables/${AI_PLAY_TRACKER_BITABLE_TABLE_ID}/records" \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "fields": {
      "AI小妙招": "<第一行内容>",
      "补充介绍": "<从文章提取的额外信息>",
      "用户原文": "<完整原始消息>",
      "妙招类型": "<类型>",
      "体验状态": "待体验"
    }
  }'
```

### Step 3: 返回结果供用户检查
写入完成后，必须把记录内容返回给用户核对。

## 使用方式

用户发送内容时，识别为记录请求并按上述规则处理。
- "帮我更新 XXX 的状态为已体验" → 更新记录
- 批量发送时，逐条处理

## 注意事项
- 用户原文不做任何删改，含链接就存链接，含描述就存描述
- 一条消息算一条记录，不拆分
- 更新状态时根据用户提供的名称或链接定位记录
