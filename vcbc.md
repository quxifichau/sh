# vcbc 远端环境速查表（配合 vcbc.sh 使用）

> 用途：任务开始时整份喂给 Agent。环境由 `vcbc.sh` 安装，已在远端实测跑通。
> 核心原则：**大 HTML 不穿隧道；批量抓取交给远端本机；browser-use 只用 get_html(selector=…)**。

---

## 0. 架构与端口（一次看清）

| 端口 | 服务 | 说明 |
|---|---|---|
| 9222 | Chrome CDP | 真实 Chrome（有头，跑在 VNC :99 里），browser-use 通过 CDP 接管 |
| 8001 | browser-use MCP (SSE) | fastmcp 代理单 server，工具名**自带 `browser_` 前缀**，无额外 server 前缀 |
| 8002 | crawl MCP (SSE) | fastmcp **合并代理两个 stdio server**，工具名格式 `<server>_<tool>` |
| 6080 | noVNC | 人工看画面用 |
| 5900 | VNC | |

8002 上的工具名（⚠️ 与旧版不同，**必须带前缀**）：

- `crawl-mcp_crawl_single` — crawl-mcp 0.2.0 自带的单 URL 抓取（HTTP 优先，失败自动回退 Playwright 渲染；chromium 已由脚本装好，不再崩）
- `crawl-helper_crawl_urls_to_file` — **批量抓取首选**（见 §2）

8001 常用工具名（browser-use 0.13.10，共 16 个）：
`browser_navigate` `browser_get_html` `browser_click` `browser_type` `browser_list_tabs` `browser_switch_tab` `browser_scroll_down` `browser_press_key` `browser_take_screenshot` …

远端管理命令（写进了 `~/.functions.sh`，在 `tailcat ssh` 里直接用）：
`vnc` `chr` `buse` `crwl` `st`（状态） `logs` `stop_all`

---

## 1. SSE 接入配方（裸 curl 版，任何沙箱可用）

隧道建立后（`tailcat forward` 把远端 8001/8002 映射到本地同号端口）：

```bash
# 1) 后台挂住 SSE 长连接，收事件流
curl -sN --max-time 300 http://127.0.0.1:8002/sse > /tmp/s8002.out &
SSE_PID=$!
# 2) 等 endpoint 事件，取 session_id
sleep 1; SID=$(grep -o 'session_id=[^&"[:space:]]*' /tmp/s8002.out | head -1 | cut -d= -f2)
# 3) 所有 JSON-RPC 都 POST 到 /messages/?session_id=$SID，响应从 /tmp/s8002.out 的 data: 行里捞
post() { curl -s -X POST "http://127.0.0.1:8002/messages/?session_id=$SID" \
  -H 'Content-Type: application/json' -d "$1"; }
post '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}'
post '{"jsonrpc":"2.0","method":"notifications/initialized"}'
post '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
post '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"crawl-helper_crawl_urls_to_file","arguments":{...}}}'
# 4) 轮询 /tmp/s8002.out 里 "id":N 对应的 data: 行，直到能 JSON 解析；完事后 kill $SSE_PID
```

要点：
- **先挂 SSE 再 POST**，session_id 只在连接建立时的第一个 endpoint 事件里给。
- 每次 Bash 调用是新 shell：`SID`、`TC` 等变量要么同一条命令内定义，要么落盘到 /tmp。
- 抓响应用 `grep '"id":3'` + 逐行试 `python3 -c 'import json,sys; ...'`，别 sleep 死等。

---

## 2. 抓取决策表（按优先级从上往下选）

| 场景 | 用什么 | 一次调用示例 |
|---|---|---|
| **≥3 个 URL 的批量抓取（默认首选）** | `crawl-helper_crawl_urls_to_file` | `{"urls":[...40个...], "out_path":"/content/results.md", "concurrent":5, "header_title":"XX 搜索结果", "return_content":false}` |
| 单 URL、只要正文 | `crawl-mcp_crawl_single` | `{"url":"..."}` |
| 页面需要交互（点"下一页"、输验证码、登录后内容） | browser-use：`browser_navigate` + `browser_get_html(selector=…)` | 见 §3 |
| 搜索结果页本身（sogou/bing） | browser-use 拿链接列表，然后**全部链接一次性丢给 crawl-helper** | 见 §4 |

### crawl_urls_to_file 行为契约（实测确认）

- 抓取循环**全在远端本机**跑：并发 1–10（默认 5），单页超时 60s，`domcontentloaded` 即收，BYPASS 缓存。
- 纯 HTTP 抓不到会自动走 Playwright chromium 渲染（脚本已装好 chromium-1248）。
- 成功判据：`success` 且正文 >50 字符；否则记入 `failed[]` 并附原因（如「正文过短（N 字符），疑似验证页/空壳页」）。
- 返回 JSON：`{ok, out_path, total, success, failed[{url,error}], bytes, content?}`。
- **`return_content` 的取舍**：文件会完整写到远端 `out_path`；只有当你需要立刻读全文时才设 `true`（几十页正文可能几百 KB，穿隧道慢）。默认建议 `false`，之后按需 `tailcat ssh $TC 'sed -n "1,200p" /content/results.md'` 分段取。
- 失败 URL 不用重跑全量：把 `failed[]` 里的 URL 收集起来，**只重发一次**小批量调用（见 §5）。

---

## 3. browser-use 使用规约（硬约定）

1. **只用 `browser_get_html(selector=...)` 缩小 payload**——全页 HTML 动辄几百 KB，穿隧道是最大瓶颈。取链接列表用 `selector="a"` 或具体容器；确认页面用 `selector="h1"`。
2. **禁止调用 `extract_content`**（LLM 提取，无 OPENAI_API_KEY，永远报错；这是用户明确决定，不要再试）。
3. `browser_navigate` 作用于**当前活动 tab**；多 tab 时先 `browser_list_tabs` / `browser_switch_tab` 确认。
4. 页面是 JS 渲染时，navigate 后先 `sleep 3`～`browser_scroll_down` 一次再 get_html。
5. get_html 报 "No element found for selector" ≠ 工具坏了：先 `browser_get_html(selector="body")` 或 `curl` 直查该站源码，确认选择器真的存在（实测新版 example.com 根本没有 h1）。
6. browser-use 通过 CDP 接管 9222 的常驻 Chrome：登录态、cookie 会跨调用保留，可利用；但也意味着**别在里面登不该登的账号**。

---

## 4. 搜索引擎套路（实测有效）

### sogou（www.sogou.com）
- 直接 GET `/web?query=...` 常被弹验证码。**用 browser-use 走自然提交**：navigate 到首页 → `browser_type` 填关键词 → `browser_press_key("Enter")` → get_html 取结果。
- 结果链接是跳转链 `/link?url=...`，需要逐个解析真实 URL（navigate 后看最终地址，或 get_html 里拿 data 属性）。
- 翻页：URL 加 `&page=2` 或点"下一页"。

### bing（cn.bing.com）
- 结果页 `https://cn.bing.com/search?q=<kw>&first=11` 翻页（first=1,11,21…）。
- 结果真实 URL 藏在 `u=a1<base64url>` 参数里：`python3 -c "import base64,sys; print(base64.urlsafe_b64decode(sys.argv[1]+'==').decode('utf-8','ignore'))" '<a1后面的串>'`，**不用**逐个访问 /link 跳转。
- bing 反爬弱，get_html(selector="li.b_algo a") 一把取完标题+链接。

### 标准全流程（40 条结果量级，预计 5–10 分钟）
1. browser-use：搜索 → get_html(selector=…) 提取 top-N 标题+URL（两个引擎各 ~20 条，去重）。
2. **一次** `crawl-helper_crawl_urls_to_file` 调全部 URL → 写 `/content/results.md`。
3. 读返回 JSON 的 `failed[]`，若有可救的（超时类）重发一次小批量；验证码/登录墙类直接标记放弃。
4. 需要产物到本地：`tailcat ssh $TC 'cat /content/results.md' > /workspace/app/results.md`。

---

## 5. 失败分类与重试策略

| 症状 | 分类 | 动作 |
|---|---|---|
| 超时 / 连接重置 / "无结果返回" | 瞬态 | 重试 **1 次**，仍失败则放弃 |
| 「正文过短…疑似验证页/空壳页」 | 反爬 | 换 browser-use 人工路径试 1 次；不行就放弃并记录 |
| 302 到登录页 / 404 / 域名失效 | 数据源本身坏 | 不重试，直接标记（上次实测：编造的旧 URL 302 到博客园登录页，属测试数据问题非环境问题） |
| `crawl_single` 报浏览器错误 | 环境 | 远端执行 `crwl` 重启；再不行 `chr` 重启 Chrome 后 `crwl` |
| 8001/8002 连不上 | 隧道/服务 | 先 `tailcat forward` 重建隧道；远端 `st` 看服务，`buse`/`crwl` 重启 |

总原则：**每个 URL 最多 2 次尝试**，把时间花在推进而不是磨单点。

---

## 6. 已知坑（都踩过）

1. **8002 工具名必须带 server 前缀**（`crawl-mcp_` / `crawl-helper_`）——fastmcp 合并多 server 时自动加；旧速查表里的裸名 `crawl_single` 会报 tool not found。8001 只有单 server，工具名就是 `browser_*` 原样。
2. `tools/call` 参数结构：`{"name":"<工具名>","arguments":{...}}`，别把参数平铺在外层。
3. Bash 工具单次最长 600s：长抓取把 `--max-time` 设在 300s 内，或走「远端 tmux 跑 + 轮询日志」模式：
   `tailcat ssh $TC 'tmux send-keys -t task "cmd 2>&1 | tee /root/x.log; echo EXIT_\$?" Enter'`，之后 `tmux capture-pane -t task -p` 轮询。
4. crawl-mcp 0.2.0（不是 0.3.3，PyPI 上不存在）依赖 Python≥3.12，venv 在 `~/cdp/venv`，别用系统 python 跑它。
5. `wait_until="domcontentloaded"` 意味着重 JS 站可能拿到半渲染页——正文过短就归入反爬类处理。
6. 大文件回传用 `cat` 分段（`sed -n 'a,bp'`），别一口气拉几百 KB 进对话。

---

## 7. 任务开场检查清单（30 秒）

```bash
# 隧道在不在
curl -s -o /dev/null -w '%{http_code}\n' --max-time 2 http://127.0.0.1:8001/sse   # 期望 200
curl -s -o /dev/null -w '%{http_code}\n' --max-time 2 http://127.0.0.1:8002/sse   # 期望 200
# 不在 → tailcat forward 重建；还不行 → tailcat ssh $TC 'st' 看远端服务
```
