#!/usr/bin/env node
/**
 * 法宝桥 (Bridge) — 游戏 <-> ZCode 桌面端
 *
 * 派发方式：直接往桌面端的 automations 表插一行「立即到期」的自动化任务。
 * 桌面端调度器会在 ~15 秒内认领它，并创建一个**原生桌面会话**（tasks 表里
 * cron_automation_id 指向我们）。于是：
 *   - 观众能在 ZCode 桌面端界面里看到它真的在跑        ✅ 可见性
 *   - 它就是一个正常会话，可以在桌面端继续多轮对话      ✅ 多轮交互
 *
 * 这条路子取代了原来的 `zcode.cjs --prompt`（那条 CLI 路子会话不进桌面端）。
 *
 * 零依赖：只用 node 内置的 node:sqlite（Node >= 22.5）。
 *
 * 启动：  node bridge.js
 * 端口：  7777
 */

const http = require('node:http');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const { DatabaseSync } = require('node:sqlite');

const PORT = 7777;
const DB_PATH = path.join(os.homedir(), '.zcode', 'v2', 'tasks-index.sqlite');

// 专用沙盒目录。yolo 模式下 Agent 在这里可以无审批读写，所以**不要**指向真实项目目录。
// 搞乱了直接删掉重建即可。
//
// ⚠️ 必须是 ZCode 桌面端已注册的项目，否则任务不会出现在界面里。
//    注册方法：在桌面端「打开文件夹」选中它一次（写进 ~/.zcode/v2/setting.json 的 recentProjects）。
const DEFAULT_CWD = process.env.ZCODE_WORKSPACE
  || path.resolve(__dirname, '..', '..', '演示沙盒');

// 直接抄桌面端已跑通的值 —— 见技术笔记第五节的教训。
const PROVIDER = 'glm';
const MODEL = 'builtin:bigmodel-coding-plan/GLM-5.3';

// 用户已拍板（2026-08-28）：yolo + 专用沙盒目录。
//
// yolo = 免审批一路跑完。build 模式会卡在权限审批上等人点「批准」，
// 无人值守就是无限等待，路演会演砸 —— 所以演示必须 yolo。
//
// 代价是：游戏里点一下，Agent 就能在工作目录里无审批写文件/跑命令。
// 因此工作目录**必须**是下面那个专用沙盒，不要指向真实项目目录。
const MODE = process.env.ZCODE_MODE || 'yolo';

const SETTING_PATH = path.join(os.homedir(), '.zcode', 'v2', 'setting.json');

/**
 * 确认工作目录已注册进 ZCode 桌面端的 recentProjects。
 *
 * 没注册的话任务照样会跑、也会在 tasks 表里生成会话，但**桌面端界面里看不见** ——
 * 表现就是「点了去修炼，ZCode 那边什么都没有」，实际上它在后台跑得好好的。
 * 这个坑踩过一次，所以这里自动补上。
 */
function ensureWorkspaceRegistered(ws) {
  try {
    const raw = fs.readFileSync(SETTING_PATH, 'utf8');
    const cfg = JSON.parse(raw);
    const list = Array.isArray(cfg.recentProjects) ? cfg.recentProjects : [];
    if (list.includes(ws)) return { ok: true, already: true };

    fs.writeFileSync(SETTING_PATH + '.bak', raw);      // 先备份再动
    cfg.recentProjects = [ws, ...list];
    fs.writeFileSync(SETTING_PATH, JSON.stringify(cfg, null, 2));
    return { ok: true, already: false };
  } catch (e) {
    return { ok: false, error: String(e.message || e) };
  }
}

let db;
function getDb() {
  // 每次重开，避免长时间持有句柄跟桌面端抢锁。
  if (db) { try { db.close(); } catch {} }
  db = new DatabaseSync(DB_PATH);
  return db;
}

/** 派发一条任务，返回 automationId */
function dispatch({ title, prompt, cwd }) {
  const now = Date.now();
  const automationId = `automation-fabao-${now}-${Math.floor(Math.random() * 1e6)}`;
  const ws = cwd || DEFAULT_CWD;

  const d = getDb();
  d.prepare(`
    INSERT INTO automations (
      automation_id, title, cron_expr, prompt, model, provider,
      workspace_key, workspace_path, workspace_identity, target_task_id,
      bot_delivery_target, location_kind,
      recurring, max_runs, end_at, schedule_rule, schedule_edited_by_user,
      run_count, enabled, lifecycle_status,
      next_run_at, last_run_at, running, claimed_at,
      dispatch_status, dispatch_attempts, retry_at, last_error,
      mode, thought_level, created_at, updated_at
    ) VALUES (
      ?, ?, '0 0 * * *', ?, ?, ?,
      ?, ?, NULL, NULL,
      NULL, 'local',
      0, 1, NULL, NULL, 0,
      0, 1, 'active',
      ?, NULL, 0, NULL,
      'idle', 0, NULL, NULL,
      ?, NULL, ?, ?
    )
  `).run(
    automationId, title || '修仙任务', prompt, MODEL, PROVIDER,
    ws, ws,
    now,          // next_run_at = 现在 -> 立即到期
    MODE, now, now
  );

  return automationId;
}

/** 查一条任务的状态 */
function status(automationId) {
  const d = getDb();
  const auto = d.prepare(
    `SELECT dispatch_status, run_count, last_error FROM automations WHERE automation_id = ?`
  ).get(automationId);

  const task = d.prepare(
    `SELECT task_id, title, task_status FROM tasks
     WHERE cron_automation_id = ? AND deleted = 0
     ORDER BY updated_at DESC LIMIT 1`
  ).get(automationId);

  // 游戏只关心四种状态，翻译成修仙话术在游戏侧做。
  let phase = 'pending';                       // 已派发，等桌面端认领
  if (task) {
    if (task.task_status === 'running') phase = 'running';
    else if (task.task_status === 'completed') phase = 'completed';
    else if (task.task_status === 'error') phase = 'error';
    else phase = 'running';
  }
  if (auto && auto.last_error) phase = 'error';

  return {
    automationId,
    phase,
    dispatchStatus: auto ? auto.dispatch_status : 'missing',
    taskId: task ? task.task_id : null,
    taskTitle: task ? task.title : null,
    taskStatus: task ? task.task_status : null,
    error: auto ? auto.last_error : null,
  };
}

/** 清理我们自己造的、已经跑完的 automation 行（桌面端上限 20 条，别塞爆） */
function prune() {
  const d = getDb();
  const r = d.prepare(`
    DELETE FROM automations
    WHERE automation_id LIKE 'automation-fabao-%'
      AND run_count > 0
      AND automation_id NOT IN (
        SELECT cron_automation_id FROM tasks
        WHERE cron_automation_id IS NOT NULL
          AND task_status = 'running' AND deleted = 0
      )
  `).run();
  return r.changes;
}

// ---------------------------------------------------------------- HTTP

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (req.method === 'OPTIONS') return send(res, 204, {});

  if (url.pathname === '/health') {
    return send(res, 200, {
      ok: true, db: DB_PATH, workspace: DEFAULT_CWD,
      workspaceRegistered: registration.ok,
      workspaceAddedThisRun: registration.ok && !registration.already,
      mode: MODE,
    });
  }

  if (url.pathname === '/status' && req.method === 'GET') {
    const id = url.searchParams.get('id');
    if (!id) return send(res, 400, { ok: false, error: 'missing id' });
    try {
      return send(res, 200, { ok: true, ...status(id) });
    } catch (e) {
      return send(res, 500, { ok: false, error: String(e.message || e) });
    }
  }

  if (url.pathname === '/dispatch' && req.method === 'POST') {
    let raw = '';
    req.on('data', (c) => { raw += c; if (raw.length > 1e6) req.destroy(); });
    req.on('end', () => {
      try {
        const body = raw ? JSON.parse(raw) : {};
        if (!body.prompt) return send(res, 400, { ok: false, error: 'missing prompt' });
        prune();
        const id = dispatch(body);
        console.log(`[派发] ${body.title || '(无标题)'} -> ${id}`);
        return send(res, 200, { ok: true, automationId: id });
      } catch (e) {
        console.error('[派发失败]', e);
        return send(res, 500, { ok: false, error: String(e.message || e) });
      }
    });
    return;
  }

  send(res, 404, { ok: false, error: 'not found' });
});

let registration = { ok: false };

server.listen(PORT, '127.0.0.1', () => {
  registration = ensureWorkspaceRegistered(DEFAULT_CWD);
  console.log(`法宝桥已就位  http://127.0.0.1:${PORT}`);
  console.log(`  数据库    ${DB_PATH}`);
  console.log(`  工作目录  ${DEFAULT_CWD}`);
  console.log(`  POST /dispatch  {title, prompt, cwd?}`);
  console.log(`  GET  /status?id=<automationId>`);
  if (!registration.ok) {
    console.log('');
    console.log('  ⚠️  工作目录没能注册进 ZCode（%s）', registration.error);
    console.log('     任务照样会跑，但桌面端界面里看不见它。');
    console.log('     手动补救：在 ZCode 里「打开文件夹」选一次上面那个工作目录。');
  } else if (!registration.already) {
    console.log('');
    console.log('  ✅ 已把工作目录注册进 ZCode 的最近项目。');
    console.log('     ⚠️  需要重启一次 ZCode 桌面端，它才会读到。');
  }
});
