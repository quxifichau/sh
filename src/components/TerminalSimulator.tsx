import React, { useState, useRef, useEffect } from 'react';
import { CornerDownLeft, Trash2 } from 'lucide-react';

interface TerminalSimulatorProps {
  runningServices: Record<string, boolean>;
  onToggleService: (id: string) => void;
  onStartAll: () => void;
  onStopAll: () => void;
  onAddLog: (serviceId: string, level: 'info' | 'success' | 'warn' | 'error', message: string) => void;
}

interface HistoryItem {
  id: string;
  command: string;
  output: string[];
  isError?: boolean;
}

export const TerminalSimulator: React.FC<TerminalSimulatorProps> = ({
  runningServices,
  onToggleService,
  onStartAll,
  onStopAll,
  onAddLog
}) => {
  const [input, setInput] = useState<string>('');
  const [history, setHistory] = useState<HistoryItem[]>([
    {
      id: 'init-1',
      command: '. ~/.functions.sh',
      output: [
        '✅ Sourced ~/.functions.sh with aliases: vnc, chr, buse, crwl, st, logs, stop_all',
        'Type "help" to view all available commands or click quick action buttons below.'
      ]
    }
  ]);
  const [commandIndex, setCommandIndex] = useState<number>(-1);
  const commandHistoryRef = useRef<string[]>(['. ~/.functions.sh']);

  const terminalEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    terminalEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [history]);

  const executeCommand = (cmdText: string) => {
    const trimmed = cmdText.trim();
    if (!trimmed) return;

    commandHistoryRef.current.push(trimmed);
    setCommandIndex(-1);

    const parts = trimmed.split(' ');
    const mainCmd = parts[0].toLowerCase();

    let outputLines: string[] = [];
    let isError = false;

    switch (mainCmd) {
      case 'help':
        outputLines = [
          'AVAILABLE SHELL COMMANDS (~/.functions.sh & tools):',
          '  vnc       - Launch TigerVNC (:99) + Fluxbox + noVNC (websockify 6080)',
          '  chr       - Launch Google Chrome with CDP on 127.0.0.1:9222',
          '  buse      - Launch Browser-use MCP on SSE port 8001',
          '  crwl      - Launch Crawl-MCP (crawl4ai) on SSE port 8002',
          '  st        - Check real-time PID, port listener, and HTTP probe status',
          '  stop_all  - Gracefully terminate all running services via SIGTERM/SIGKILL',
          '  chpw      - Playwright headless runner hook (vcpc.sh)',
          '  tailcat   - Tailscale mesh client (try "tailcat version" or "tailcat status")',
          '  clear     - Clear terminal history',
          '  uname -m  - Display system CPU architecture (x86_64)'
        ];
        break;

      case 'vnc':
        if (runningServices['vnc']) {
          outputLines = ['🖥️  [vnc] TigerVNC & noVNC already running on port 6080'];
        } else {
          onToggleService('vnc');
          onAddLog('vnc', 'success', 'Terminal initiated: vnc -> TigerVNC (:99) & noVNC (6080) started.');
          outputLines = [
            '🖥️  [vnc] 启动 TigerVNC...',
            '🖥️  [vnc] Xtigervnc :99 -geometry 2560x1440 -depth 24 -rfbport 5900',
            '🖥️  [vnc] 启动 Fluxbox 窗口管理器...',
            '🖥️  [vnc] 启动 noVNC (websockify 6080)...',
            '✅ [vnc] 启动成功: http://127.0.0.1:6080/vnc.html'
          ];
        }
        break;

      case 'chr':
        if (runningServices['chr']) {
          outputLines = ['🌐 [chr] Google Chrome already running with CDP on 127.0.0.1:9222'];
        } else {
          onToggleService('chr');
          onAddLog('chr', 'success', 'Terminal initiated: chr -> Google Chrome CDP active on 127.0.0.1:9222.');
          outputLines = [
            '🌐 [chr] 启动 Chrome (CDP: 127.0.0.1:9222)...',
            '  - 等待 Chrome CDP 协议就绪 (/json/version)...',
            '✅ [chr] Chrome CDP 就绪 (127.0.0.1:9222)'
          ];
        }
        break;

      case 'buse':
        if (runningServices['buse']) {
          outputLines = ['🤖 [buse] Browser-use MCP already running on port 8001'];
        } else {
          onToggleService('buse');
          onAddLog('buse', 'success', 'Terminal initiated: buse -> Browser-use MCP listening on SSE port 8001.');
          outputLines = [
            '🤖 [buse] 启动 Browser-use MCP (127.0.0.1:8001)...',
            '  - BU_CDP_URL="http://127.0.0.1:9222"',
            '  - mcp-proxy --port 8001 --host 127.0.0.1 -- browser-use --mcp',
            '✅ [buse] Browser-use MCP 已启动 (SSE: 127.0.0.1:8001)'
          ];
        }
        break;

      case 'crwl':
        if (runningServices['crwl']) {
          outputLines = ['🕷️  [crwl] Crawl-MCP already running on port 8002'];
        } else {
          onToggleService('crwl');
          onAddLog('crwl', 'success', 'Terminal initiated: crwl -> Crawl-MCP listening on SSE port 8002.');
          outputLines = [
            '🕷️  [crwl] 启动 Crawl-MCP (127.0.0.1:8002)...',
            '  - CRAWL4AI_BROWSER_URL="http://127.0.0.1:9222"',
            '  - mcp-proxy --port 8002 --host 127.0.0.1 -- crawl-mcp',
            '✅ [crwl] Crawl-MCP 已启动 (SSE: 127.0.0.1:8002)'
          ];
        }
        break;

      case 'st':
        onAddLog('system', 'info', 'Terminal initiated: st probe executed.');
        outputLines = [
          '📊 ===== 服务健康状态 =====',
          `  [noVNC 桌面]          ${runningServices['vnc'] ? 'PID:18420 RUNNING   端口 6080  [LISTEN]   (HTTP OK)' : 'PID:------- STOPPED   端口 6080  [CLOSED]'}`,
          `  [Chrome (CDP)]        ${runningServices['chr'] ? 'PID:18456 RUNNING   端口 9222  [LISTEN]   (HTTP OK)' : 'PID:------- STOPPED   端口 9222  [CLOSED]'}`,
          `  [Browser-use]         ${runningServices['buse'] ? 'PID:18502 RUNNING   端口 8001  [LISTEN]' : 'PID:------- STOPPED   端口 8001  [CLOSED]'}`,
          `  [Crawl-MCP]           ${runningServices['crwl'] ? 'PID:18531 RUNNING   端口 8002  [LISTEN]' : 'PID:------- STOPPED   端口 8002  [CLOSED]'}`,
          '==========================='
        ];
        break;

      case 'start_all':
        onStartAll();
        onAddLog('system', 'info', 'Terminal initiated: start_all executed.');
        outputLines = [
          '🚀 Sequentially starting all services (vnc -> chr -> buse -> crwl)...',
          '✅ All 4 services started.'
        ];
        break;

      case 'stop_all':
        onStopAll();
        onAddLog('system', 'warn', 'Terminal initiated: stop_all executed.');
        outputLines = [
          '🛑 按序停止全部服务...',
          '  - 正在停止 Crawl-MCP...',
          '  - 正在停止 Browser-use...',
          '  - 正在停止 Google Chrome...',
          '  - 正在停止 TigerVNC & noVNC...',
          '✅ 全部服务已停止'
        ];
        break;

      case 'clear':
        setHistory([]);
        setInput('');
        return;

      case 'uname':
        if (parts[1] === '-m') {
          outputLines = ['x86_64'];
        } else {
          outputLines = ['Linux ai-studio-cloud-worker 6.6.0-linux-amd64 #1 SMP x86_64 GNU/Linux'];
        }
        break;

      case 'tailcat':
        if (parts[1] === 'version' || parts[1] === '--version') {
          outputLines = [
            'tailcat version v0.7.0 (linux/amd64)',
            'commit: a1c94b2f (official release)'
          ];
        } else if (parts[1] === 'status') {
          outputLines = [
            '# Tailscale Mesh Status',
            '100.112.44.89   cloud-mcp-node    user@   linux   - active; direct',
            '100.84.19.120   macbook-pro       user@   darwin  - idle'
          ];
        } else {
          outputLines = [
            'Tailcat: Tailscale Mesh Client',
            'Usage: tailcat [version|status|up|down|ip]'
          ];
        }
        break;

      case 'chpw':
        outputLines = [
          '🎭 Initializing Playwright CLI config...',
          '   Config written to ~/.playwright/cli.config.json',
          '   cdpEndpoint: http://127.0.0.1:9222',
          '   Chrome connection test: Connected to Google Chrome 133.0'
        ];
        break;

      default:
        outputLines = [
          `bash: ${mainCmd}: command not found`,
          'Type "help" to view supported supervisor commands.'
        ];
        isError = true;
        break;
    }

    setHistory(prev => [
      ...prev,
      {
        id: `cmd-${Date.now()}`,
        command: trimmed,
        output: outputLines,
        isError
      }
    ]);
    setInput('');
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      executeCommand(input);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      const hist = commandHistoryRef.current;
      if (hist.length > 0) {
        const nextIndex = commandIndex === -1 ? hist.length - 1 : Math.max(0, commandIndex - 1);
        setCommandIndex(nextIndex);
        setInput(hist[nextIndex]);
      }
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      const hist = commandHistoryRef.current;
      if (commandIndex !== -1) {
        const nextIndex = commandIndex + 1;
        if (nextIndex >= hist.length) {
          setCommandIndex(-1);
          setInput('');
        } else {
          setCommandIndex(nextIndex);
          setInput(hist[nextIndex]);
        }
      }
    }
  };

  return (
    <div className="space-y-4">
      {/* Quick Action Ribbon */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-3 flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs text-slate-400 font-medium mr-1">Quick Run:</span>
          {(['st', 'vnc', 'chr', 'buse', 'crwl', 'stop_all', 'tailcat version', 'help'] as const).map(cmd => (
            <button
              key={cmd}
              onClick={() => executeCommand(cmd)}
              className="px-2.5 py-1 bg-slate-800 hover:bg-slate-700 text-cyan-300 font-mono text-xs rounded border border-slate-700 cursor-pointer transition-colors"
            >
              {cmd}
            </button>
          ))}
        </div>

        <button
          onClick={() => setHistory([])}
          className="text-xs text-slate-400 hover:text-rose-400 flex items-center gap-1 cursor-pointer transition-colors px-2 py-1"
        >
          <Trash2 className="w-3.5 h-3.5" />
          Clear Screen
        </button>
      </div>

      {/* Terminal Window */}
      <div className="bg-[#05080f] border border-slate-800 rounded-xl overflow-hidden shadow-2xl font-mono text-xs flex flex-col h-[520px]">
        {/* Terminal Header */}
        <div className="bg-slate-900/90 px-4 py-2.5 border-b border-slate-800 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="flex gap-1.5">
              <div className="w-3 h-3 rounded-full bg-rose-500/80" />
              <div className="w-3 h-3 rounded-full bg-amber-500/80" />
              <div className="w-3 h-3 rounded-full bg-emerald-500/80" />
            </div>
            <span className="text-slate-400 text-xs ml-2">root@cloud-mcp-host: ~/cdp</span>
          </div>
          <span className="text-[11px] text-slate-500">bash 5.2 / interactive</span>
        </div>

        {/* Terminal Scroll Body */}
        <div className="p-4 flex-1 overflow-y-auto space-y-3">
          {history.map((item) => (
            <div key={item.id} className="space-y-1">
              <div className="flex items-center gap-2 text-cyan-400">
                <span className="text-emerald-400">root@cloud-mcp-host:~/cdp#</span>
                <span className="text-white font-semibold">{item.command}</span>
              </div>
              <div className="pl-4 space-y-0.5">
                {item.output.map((line, lIdx) => (
                  <div
                    key={lIdx}
                    className={`${item.isError ? 'text-rose-400' : 'text-slate-300'} whitespace-pre-wrap leading-relaxed`}
                  >
                    {line}
                  </div>
                ))}
              </div>
            </div>
          ))}
          <div ref={terminalEndRef} />
        </div>

        {/* Terminal Command Input Prompt */}
        <div className="bg-slate-900/70 border-t border-slate-800/80 p-3 flex items-center gap-2">
          <span className="text-emerald-400 shrink-0 font-bold">root@cloud-mcp-host:~/cdp#</span>
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Type a command (e.g. st, vnc, chr, buse, crwl, help)..."
            className="flex-1 bg-transparent text-white font-mono text-xs focus:outline-none focus:ring-0 placeholder:text-slate-600"
            autoFocus
          />
          <button
            onClick={() => executeCommand(input)}
            className="p-1.5 bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 rounded cursor-pointer transition-colors"
          >
            <CornerDownLeft className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
    </div>
  );
};
