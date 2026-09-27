import React, { useState } from 'react';
import { 
  Monitor, 
  Globe, 
  Bot, 
  ShieldCheck, 
  Workflow, 
  Radio, 
  Server, 
  Lock, 
  ArrowRight, 
  Info,
  Terminal
} from 'lucide-react';

interface ArchitectureDiagramProps {
  runningServices: Record<string, boolean>;
  onToggleService: (id: string) => void;
  onNavigateToServices: () => void;
}

export const ArchitectureDiagram: React.FC<ArchitectureDiagramProps> = ({
  runningServices,
  onToggleService,
  onNavigateToServices
}) => {
  const [selectedNode, setSelectedNode] = useState<string>('chrome');

  const nodes = [
    {
      id: 'tailscale',
      name: 'Tailcat / Tailscale',
      role: 'Secure Overlay Mesh VPN',
      port: 'UDP 41641 / Mesh IP',
      color: 'from-indigo-500/20 to-indigo-900/40 border-indigo-500/50',
      icon: Lock,
      status: 'Ready',
      description: 'Zero-trust WireGuard mesh network client installed via instc.sh. Encrypts all inbound and outbound traffic, allowing safe remote access to noVNC and MCP SSE endpoints without exposing ports to the public internet.'
    },
    {
      id: 'vnc',
      name: 'TigerVNC & noVNC',
      role: 'Virtual Desktop Display',
      port: ':99 (RFB 5900) -> HTTP 6080',
      color: 'from-amber-500/20 to-amber-900/40 border-amber-500/50',
      icon: Monitor,
      status: runningServices['vnc'] ? 'Running' : 'Stopped',
      description: 'TigerVNC server creates headless virtual X11 display :99 (2560x1440 resolution) managed by Fluxbox window manager. websockify bridges RFB port 5900 to port 6080 for web-based HTML5 VNC access.'
    },
    {
      id: 'chrome',
      name: 'Google Chrome (CDP)',
      role: 'Browser Automation Runtime',
      port: '127.0.0.1:9222',
      color: 'from-cyan-500/20 to-cyan-900/40 border-cyan-500/50',
      icon: Globe,
      status: runningServices['chr'] ? 'Running' : 'Stopped',
      description: 'Official Google Chrome stable instance launched on DISPLAY=:99 with isolated profile (~/cdp/profile). Remote debugging protocol (CDP) strictly binds to localhost 127.0.0.1:9222.'
    },
    {
      id: 'buse',
      name: 'Browser-use MCP',
      role: 'Autonomous Web Agent MCP',
      port: '127.0.0.1:8001 /sse',
      color: 'from-emerald-500/20 to-emerald-900/40 border-emerald-500/50',
      icon: Bot,
      status: runningServices['buse'] ? 'Running' : 'Stopped',
      description: 'Model Context Protocol server running browser-use via mcp-proxy SSE wrapper. Connects directly to Chrome CDP at 127.0.0.1:9222 to allow AI agents to navigate, click, fill forms, and solve UI tasks.'
    },
    {
      id: 'crwl',
      name: 'Crawl-MCP (Crawl4ai)',
      role: 'AI Scraping & LLM Markdown',
      port: '127.0.0.1:8002 /sse',
      color: 'from-purple-500/20 to-purple-900/40 border-purple-500/50',
      icon: Workflow,
      status: runningServices['crwl'] ? 'Running' : 'Stopped',
      description: 'High-performance AI extraction MCP server powered by crawl4ai 0.8.9. Connects to custom Chrome CDP url to extract LLM-friendly clean Markdown and structured metadata without anti-bot blocks.'
    }
  ];

  return (
    <div className="space-y-6">
      {/* Overview Banner */}
      <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 sm:p-6 backdrop-blur">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 mb-2">
              <span className="px-2.5 py-0.5 text-xs font-semibold rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 flex items-center gap-1.5">
                <ShieldCheck className="w-3.5 h-3.5" />
                Hardened Production Architecture
              </span>
              <span className="text-xs text-slate-400">RFC 1918 / Localhost Loopback Isolation</span>
            </div>
            <h2 className="text-xl sm:text-2xl font-bold text-white tracking-tight">
              Cloud Chrome Desktop + Dual MCP Topology
            </h2>
            <p className="text-sm text-slate-300 mt-1 max-w-3xl">
              Engineered by <code className="text-cyan-400 font-mono">vccc.sh</code> and <code className="text-cyan-400 font-mono">instc.sh</code>.
              Provides a sandboxed browser automation host where LLM AI agents interact through Model Context Protocol (MCP) over private network boundaries.
            </p>
          </div>
          <button
            onClick={onNavigateToServices}
            className="self-start md:self-center px-4 py-2.5 bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-semibold rounded-lg text-xs sm:text-sm flex items-center gap-2 shadow-lg shadow-cyan-500/20 transition-all cursor-pointer"
          >
            <Radio className="w-4 h-4" />
            Launch Service Controller
          </button>
        </div>
      </div>

      {/* Interactive Topology Diagram */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-4">
          <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-5">
            <h3 className="text-sm font-semibold text-slate-300 uppercase tracking-wider mb-4 flex items-center gap-2">
              <Server className="w-4 h-4 text-cyan-400" />
              Service Pipeline & Network Flow
            </h3>

            {/* Mesh Entrance Node */}
            <div className="mb-4">
              <div 
                onClick={() => setSelectedNode('tailscale')}
                className={`p-4 rounded-xl border cursor-pointer transition-all ${
                  selectedNode === 'tailscale'
                    ? 'bg-indigo-950/40 border-indigo-400 shadow-md shadow-indigo-500/10'
                    : 'bg-slate-900/40 border-slate-800 hover:border-slate-700'
                }`}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="p-2.5 rounded-lg bg-indigo-500/20 text-indigo-400">
                      <Lock className="w-5 h-5" />
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-sm text-white">1. Tailcat Network Tunnel</span>
                        <span className="text-[10px] px-2 py-0.5 rounded bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 font-mono">
                          instc.sh
                        </span>
                      </div>
                      <p className="text-xs text-slate-400 mt-0.5">WireGuard encrypted mesh overlay (Port 41641 UDP)</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <span className="inline-block px-2 py-0.5 text-[11px] font-medium text-indigo-300 bg-indigo-950/80 rounded border border-indigo-800/60">
                      Encrypted Ingress
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <div className="flex justify-center my-2">
              <ArrowRight className="w-4 h-4 text-slate-600 rotate-90" />
            </div>

            {/* Display & Chrome Core Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* TigerVNC & noVNC */}
              <div
                onClick={() => setSelectedNode('vnc')}
                className={`p-4 rounded-xl border cursor-pointer transition-all ${
                  selectedNode === 'vnc'
                    ? 'bg-amber-950/30 border-amber-400 shadow-md shadow-amber-500/10'
                    : 'bg-slate-900/40 border-slate-800 hover:border-slate-700'
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="p-2 rounded-lg bg-amber-500/20 text-amber-400">
                    <Monitor className="w-4 h-4" />
                  </div>
                  <span className={`text-[11px] px-2 py-0.5 rounded-full font-medium ${
                    runningServices['vnc'] 
                      ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                      : 'bg-slate-800 text-slate-400'
                  }`}>
                    {runningServices['vnc'] ? 'Active (:99)' : 'Standby'}
                  </span>
                </div>
                <h4 className="font-semibold text-sm text-white">2. TigerVNC + Fluxbox</h4>
                <p className="text-xs text-slate-400 mt-1">Virtual X11 Display :99 + noVNC Web on port 6080</p>
                <div className="mt-3 flex items-center justify-between text-[11px] text-slate-400 border-t border-slate-800 pt-2 font-mono">
                  <span>RFB :5900</span>
                  <span>HTTP :6080</span>
                </div>
              </div>

              {/* Google Chrome CDP */}
              <div
                onClick={() => setSelectedNode('chrome')}
                className={`p-4 rounded-xl border cursor-pointer transition-all ${
                  selectedNode === 'chrome'
                    ? 'bg-cyan-950/30 border-cyan-400 shadow-md shadow-cyan-500/10'
                    : 'bg-slate-900/40 border-slate-800 hover:border-slate-700'
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="p-2 rounded-lg bg-cyan-500/20 text-cyan-400">
                    <Globe className="w-4 h-4" />
                  </div>
                  <span className={`text-[11px] px-2 py-0.5 rounded-full font-medium ${
                    runningServices['chr'] 
                      ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                      : 'bg-slate-800 text-slate-400'
                  }`}>
                    {runningServices['chr'] ? 'CDP Ready' : 'Standby'}
                  </span>
                </div>
                <h4 className="font-semibold text-sm text-white">3. Google Chrome Stable</h4>
                <p className="text-xs text-slate-400 mt-1">Rendered on DISPLAY=:99 with dedicated user data dir</p>
                <div className="mt-3 flex items-center justify-between text-[11px] text-slate-400 border-t border-slate-800 pt-2 font-mono">
                  <span>127.0.0.1:9222</span>
                  <span>/json/version</span>
                </div>
              </div>
            </div>

            <div className="flex justify-center my-2">
              <ArrowRight className="w-4 h-4 text-slate-600 rotate-90" />
            </div>

            {/* Dual MCP Layer */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Browser-use MCP */}
              <div
                onClick={() => setSelectedNode('buse')}
                className={`p-4 rounded-xl border cursor-pointer transition-all ${
                  selectedNode === 'buse'
                    ? 'bg-emerald-950/30 border-emerald-400 shadow-md shadow-emerald-500/10'
                    : 'bg-slate-900/40 border-slate-800 hover:border-slate-700'
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="p-2 rounded-lg bg-emerald-500/20 text-emerald-400">
                    <Bot className="w-4 h-4" />
                  </div>
                  <span className={`text-[11px] px-2 py-0.5 rounded-full font-medium ${
                    runningServices['buse'] 
                      ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                      : 'bg-slate-800 text-slate-400'
                  }`}>
                    {runningServices['buse'] ? 'SSE Port 8001' : 'Standby'}
                  </span>
                </div>
                <h4 className="font-semibold text-sm text-white">4a. Browser-use MCP</h4>
                <p className="text-xs text-slate-400 mt-1">Full autonomous agent controls (mcp-proxy --port 8001)</p>
                <div className="mt-3 flex items-center justify-between text-[11px] text-slate-400 border-t border-slate-800 pt-2 font-mono">
                  <span>BU_CDP_URL</span>
                  <span>127.0.0.1:8001</span>
                </div>
              </div>

              {/* Crawl-MCP */}
              <div
                onClick={() => setSelectedNode('crwl')}
                className={`p-4 rounded-xl border cursor-pointer transition-all ${
                  selectedNode === 'crwl'
                    ? 'bg-purple-950/30 border-purple-400 shadow-md shadow-purple-500/10'
                    : 'bg-slate-900/40 border-slate-800 hover:border-slate-700'
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="p-2 rounded-lg bg-purple-500/20 text-purple-400">
                    <Workflow className="w-4 h-4" />
                  </div>
                  <span className={`text-[11px] px-2 py-0.5 rounded-full font-medium ${
                    runningServices['crwl'] 
                      ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                      : 'bg-slate-800 text-slate-400'
                  }`}>
                    {runningServices['crwl'] ? 'SSE Port 8002' : 'Standby'}
                  </span>
                </div>
                <h4 className="font-semibold text-sm text-white">4b. Crawl-MCP (Crawl4ai)</h4>
                <p className="text-xs text-slate-400 mt-1">High-speed markdown web extraction (mcp-proxy --port 8002)</p>
                <div className="mt-3 flex items-center justify-between text-[11px] text-slate-400 border-t border-slate-800 pt-2 font-mono">
                  <span>CRAWL4AI_URL</span>
                  <span>127.0.0.1:8002</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Node Inspector Sidebar */}
        <div className="space-y-4">
          {(() => {
            const current = nodes.find(n => n.id === selectedNode) || nodes[0];
            const Icon = current.icon;
            return (
              <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-5 space-y-4">
                <div className="flex items-center gap-3">
                  <div className="p-3 rounded-xl bg-cyan-500/10 text-cyan-400 border border-cyan-500/30">
                    <Icon className="w-6 h-6" />
                  </div>
                  <div>
                    <h3 className="font-bold text-white text-base">{current.name}</h3>
                    <p className="text-xs text-slate-400">{current.role}</p>
                  </div>
                </div>

                <div className="bg-slate-950/60 rounded-lg p-3 border border-slate-800/80 space-y-2">
                  <div className="flex justify-between items-center text-xs">
                    <span className="text-slate-400">Endpoint / Port:</span>
                    <span className="font-mono text-cyan-400 font-medium">{current.port}</span>
                  </div>
                  <div className="flex justify-between items-center text-xs">
                    <span className="text-slate-400">Process State:</span>
                    <span className="font-medium text-slate-300">{current.status}</span>
                  </div>
                  <div className="flex justify-between items-center text-xs">
                    <span className="text-slate-400">Security Scope:</span>
                    <span className="text-emerald-400 font-medium">Localhost / Tailscale Only</span>
                  </div>
                </div>

                <div>
                  <h4 className="text-xs font-semibold text-slate-300 uppercase tracking-wider mb-1 flex items-center gap-1.5">
                    <Info className="w-3.5 h-3.5 text-cyan-400" />
                    Technical Details
                  </h4>
                  <p className="text-xs text-slate-300 leading-relaxed bg-slate-950/40 p-3 rounded-lg border border-slate-800/60">
                    {current.description}
                  </p>
                </div>

                {/* Key shell commands for this service */}
                <div>
                  <h4 className="text-xs font-semibold text-slate-300 uppercase tracking-wider mb-2 flex items-center gap-1.5">
                    <Terminal className="w-3.5 h-3.5 text-cyan-400" />
                    Function Definition in ~/.functions.sh
                  </h4>
                  <div className="bg-slate-950 rounded-lg p-3 font-mono text-[11px] text-slate-300 overflow-x-auto border border-slate-800/80">
                    {current.id === 'vnc' && (
                      <pre>
{`vnc() {
  Xtigervnc :99 -geometry 2560x1440 ...
  fluxbox &
  websockify --web=/usr/share/novnc \\
             6080 localhost:5900 &
}`}
                      </pre>
                    )}
                    {current.id === 'chrome' && (
                      <pre>
{`chr() {
  google-chrome-stable \\
    --remote-debugging-port=9222 \\
    --remote-debugging-address=127.0.0.1 \\
    --user-data-dir=~/cdp/profile
}`}
                      </pre>
                    )}
                    {current.id === 'buse' && (
                      <pre>
{`buse() {
  BU_CDP_URL="http://127.0.0.1:9222" \\
  mcp-proxy --port 8001 --host 127.0.0.1 \\
            -- browser-use --mcp
}`}
                      </pre>
                    )}
                    {current.id === 'crwl' && (
                      <pre>
{`crwl() {
  CRAWL4AI_BROWSER_URL="http://127.0.0.1:9222" \\
  mcp-proxy --port 8002 --host 127.0.0.1 \\
            -- crawl-mcp
}`}
                      </pre>
                    )}
                    {current.id === 'tailscale' && (
                      <pre>
{`# From instc.sh
tailcat --version
# Connects to private Tailscale Mesh
# Ingress: http://<tailscale-ip>:6080/vnc.html
# MCP: http://<tailscale-ip>:8001/sse`}
                      </pre>
                    )}
                  </div>
                </div>

                {['vnc', 'chrome', 'buse', 'crwl'].includes(current.id) && (
                  <button
                    onClick={() => {
                      const serviceKey = current.id === 'chrome' ? 'chr' : current.id;
                      onToggleService(serviceKey);
                    }}
                    className={`w-full py-2.5 px-4 rounded-lg font-medium text-xs flex items-center justify-center gap-2 cursor-pointer transition-colors ${
                      runningServices[current.id === 'chrome' ? 'chr' : current.id]
                        ? 'bg-rose-500/20 text-rose-300 hover:bg-rose-500/30 border border-rose-500/40'
                        : 'bg-cyan-500/20 text-cyan-300 hover:bg-cyan-500/30 border border-cyan-500/40'
                    }`}
                  >
                    {runningServices[current.id === 'chrome' ? 'chr' : current.id] ? (
                      <>Stop {current.name}</>
                    ) : (
                      <>Simulate Start {current.name}</>
                    )}
                  </button>
                )}
              </div>
            );
          })()}

          {/* Quick Script Reference card */}
          <div className="bg-slate-900/40 border border-slate-800 rounded-xl p-4 text-xs space-y-2">
            <span className="font-semibold text-slate-300">Target Shell Execution Order:</span>
            <ol className="list-decimal list-inside space-y-1 text-slate-400">
              <li>Run <code className="text-cyan-400">sudo bash vccc.sh</code> to install stack</li>
              <li>Terminal runs <code className="text-cyan-400">. ~/.functions.sh</code></li>
              <li>Execute <code className="text-cyan-400">st</code> to inspect health checks</li>
              <li>Inspect live output with <code className="text-cyan-400">logs</code></li>
            </ol>
          </div>
        </div>
      </div>
    </div>
  );
};
