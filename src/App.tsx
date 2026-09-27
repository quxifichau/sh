import React, { useState } from 'react';
import { Header } from './components/Header';
import { ArchitectureDiagram } from './components/ArchitectureDiagram';
import { ServiceManager, LogEntry } from './components/ServiceManager';
import { ScriptInspector } from './components/ScriptInspector';
import { ArchitectureChecker } from './components/ArchitectureChecker';
import { TerminalSimulator } from './components/TerminalSimulator';

export const App: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'overview' | 'services' | 'scripts' | 'arch-tester' | 'terminal'>('overview');

  const [runningServices, setRunningServices] = useState<Record<string, boolean>>({
    vnc: true,
    chr: true,
    buse: true,
    crwl: false,
  });

  const [logs, setLogs] = useState<LogEntry[]>([
    {
      id: 'log-0',
      timestamp: '00:00:01',
      serviceId: 'system',
      level: 'info',
      message: 'System initialization complete. Loaded functions from ~/.functions.sh'
    },
    {
      id: 'log-1',
      timestamp: '00:00:02',
      serviceId: 'vnc',
      level: 'success',
      message: 'TigerVNC launched on display :99 (2560x1440, RFB port 5900)'
    },
    {
      id: 'log-2',
      timestamp: '00:00:03',
      serviceId: 'vnc',
      level: 'success',
      message: 'websockify web proxy ready at http://127.0.0.1:6080/vnc.html'
    },
    {
      id: 'log-3',
      timestamp: '00:00:04',
      serviceId: 'chr',
      level: 'success',
      message: 'Google Chrome CDP bound to 127.0.0.1:9222 (isolated profile ~/cdp/profile)'
    },
    {
      id: 'log-4',
      timestamp: '00:00:05',
      serviceId: 'buse',
      level: 'success',
      message: 'Browser-use MCP started via mcp-proxy on 127.0.0.1:8001 /sse'
    }
  ]);

  const addLog = (serviceId: string, level: 'info' | 'success' | 'warn' | 'error', message: string) => {
    const now = new Date();
    const timeStr = now.toTimeString().split(' ')[0];
    const newEntry: LogEntry = {
      id: `log-${Date.now()}-${Math.random()}`,
      timestamp: timeStr,
      serviceId,
      level,
      message
    };
    setLogs((prev) => [...prev, newEntry]);
  };

  const handleToggleService = (id: string) => {
    setRunningServices((prev) => {
      const willRun = !prev[id];
      if (willRun) {
        addLog(id, 'success', `Service [${id}] started successfully via supervisor.`);
      } else {
        addLog(id, 'warn', `Service [${id}] received SIGTERM -> process terminated.`);
      }
      return { ...prev, [id]: willRun };
    });
  };

  const handleStartAll = () => {
    setRunningServices({
      vnc: true,
      chr: true,
      buse: true,
      crwl: true,
    });
    addLog('system', 'info', '🚀 Initiating sequential boot: vnc -> chr -> buse -> crwl');
    addLog('vnc', 'success', 'TigerVNC + Fluxbox (:99) and noVNC (6080) active.');
    addLog('chr', 'success', 'Google Chrome CDP active on 127.0.0.1:9222.');
    addLog('buse', 'success', 'Browser-use MCP active on SSE port 8001.');
    addLog('crwl', 'success', 'Crawl-MCP active on SSE port 8002.');
  };

  const handleStopAll = () => {
    setRunningServices({
      vnc: false,
      chr: false,
      buse: false,
      crwl: false,
    });
    addLog('system', 'warn', '🛑 Executing stop_all: Gracefully shutting down all services...');
    addLog('crwl', 'info', 'Crawl-MCP stopped.');
    addLog('buse', 'info', 'Browser-use MCP stopped.');
    addLog('chr', 'info', 'Google Chrome stopped.');
    addLog('vnc', 'info', 'TigerVNC & websockify stopped.');
  };

  const runningCount = Object.values(runningServices).filter(Boolean).length;

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col font-sans">
      <Header
        activeTab={activeTab}
        setActiveTab={setActiveTab}
        runningServicesCount={runningCount}
      />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6">
        {activeTab === 'overview' && (
          <ArchitectureDiagram
            runningServices={runningServices}
            onToggleService={handleToggleService}
            onNavigateToServices={() => setActiveTab('services')}
          />
        )}

        {activeTab === 'services' && (
          <ServiceManager
            runningServices={runningServices}
            onToggleService={handleToggleService}
            onStartAll={handleStartAll}
            onStopAll={handleStopAll}
            logs={logs}
            onClearLogs={() => setLogs([])}
            onAddLog={addLog}
          />
        )}

        {activeTab === 'scripts' && <ScriptInspector />}

        {activeTab === 'arch-tester' && <ArchitectureChecker />}

        {activeTab === 'terminal' && (
          <TerminalSimulator
            runningServices={runningServices}
            onToggleService={handleToggleService}
            onStartAll={handleStartAll}
            onStopAll={handleStopAll}
            onAddLog={addLog}
          />
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-slate-900 bg-slate-950 py-6 text-center text-xs text-slate-500">
        <div className="max-w-7xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-2">
          <span>
            Imported from <strong className="text-slate-400">quxifichau/sh</strong> · AI Studio Web Runtime
          </span>
          <span className="text-slate-600">
            Tailcat · TigerVNC & noVNC · Google Chrome CDP · Browser-use & Crawl-MCP
          </span>
        </div>
      </footer>
    </div>
  );
};
export default App;
