import React, { useState } from 'react';
import { 
  Play, 
  Square, 
  RotateCw, 
  Activity, 
  Terminal, 
  Copy, 
  Check, 
  Trash2
} from 'lucide-react';
import { SERVICE_DEFINITIONS } from '../data/scripts';

export interface LogEntry {
  id: string;
  timestamp: string;
  serviceId: string;
  level: 'info' | 'success' | 'warn' | 'error';
  message: string;
}

interface ServiceManagerProps {
  runningServices: Record<string, boolean>;
  onToggleService: (id: string) => void;
  onStartAll: () => void;
  onStopAll: () => void;
  logs: LogEntry[];
  onClearLogs: () => void;
  onAddLog: (serviceId: string, level: 'info' | 'success' | 'warn' | 'error', message: string) => void;
}

export const ServiceManager: React.FC<ServiceManagerProps> = ({
  runningServices,
  onToggleService,
  onStartAll,
  onStopAll,
  logs,
  onClearLogs,
  onAddLog
}) => {
  const [filterService, setFilterService] = useState<string>('all');
  const [copiedCmd, setCopiedCmd] = useState<string | null>(null);

  const handleCopy = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedCmd(id);
    setTimeout(() => setCopiedCmd(null), 2000);
  };

  const handleRunHealthCheck = () => {
    onAddLog('system', 'info', '📊 Executing health probe: st (probing PIDs, listening ports, and HTTP endpoints)...');
    
    setTimeout(() => {
      SERVICE_DEFINITIONS.forEach((srv) => {
        const isRunning = runningServices[srv.id];
        if (isRunning) {
          const fakePid = 10000 + Math.floor(Math.random() * 40000);
          onAddLog(srv.id, 'success', `[${srv.name}] PID:${fakePid} RUNNING | Port ${srv.port} [LISTEN] | (HTTP OK)`);
        } else {
          onAddLog(srv.id, 'warn', `[${srv.name}] PID:------- STOPPED | Port ${srv.port} [CLOSED]`);
        }
      });
      onAddLog('system', 'info', '✅ Health probe evaluation completed.');
    }, 400);
  };

  const filteredLogs = filterService === 'all' 
    ? logs 
    : logs.filter(l => l.serviceId === filterService || l.serviceId === 'system');

  return (
    <div className="space-y-6">
      {/* Control Bar */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-5 backdrop-blur flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2">
            <Activity className="w-5 h-5 text-cyan-400" />
            Service Manager & Diagnostic Probes
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Simulates the bash functions injected into <code className="text-cyan-400 font-mono">~/.functions.sh</code> by <code className="text-cyan-400 font-mono">vccc.sh</code>.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            onClick={onStartAll}
            className="px-3.5 py-2 bg-emerald-600 hover:bg-emerald-500 text-white font-medium rounded-lg text-xs flex items-center gap-1.5 transition-colors cursor-pointer shadow-sm shadow-emerald-900/30"
          >
            <Play className="w-3.5 h-3.5" />
            Start All (vnc+chr+buse+crwl)
          </button>

          <button
            onClick={onStopAll}
            className="px-3.5 py-2 bg-rose-700/80 hover:bg-rose-600 text-white font-medium rounded-lg text-xs flex items-center gap-1.5 transition-colors cursor-pointer"
          >
            <Square className="w-3.5 h-3.5" />
            Stop All (stop_all)
          </button>

          <button
            onClick={handleRunHealthCheck}
            className="px-3.5 py-2 bg-slate-800 hover:bg-slate-700 border border-slate-700 text-slate-200 font-medium rounded-lg text-xs flex items-center gap-1.5 transition-colors cursor-pointer"
          >
            <RotateCw className="w-3.5 h-3.5 text-cyan-400" />
            Run Probe (st)
          </button>
        </div>
      </div>

      {/* Service Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {SERVICE_DEFINITIONS.map((service) => {
          const isRunning = runningServices[service.id];
          return (
            <div
              key={service.id}
              className={`border rounded-xl p-5 transition-all ${
                isRunning
                  ? 'bg-slate-900/90 border-cyan-500/40 shadow-lg shadow-cyan-950/20'
                  : 'bg-slate-900/40 border-slate-800/80'
              }`}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-white text-base">{service.name}</span>
                    <span className={`text-[10px] px-2 py-0.5 rounded-full font-medium ${
                      isRunning
                        ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                        : 'bg-slate-800 text-slate-400 border border-slate-700/60'
                    }`}>
                      {isRunning ? 'RUNNING' : 'STOPPED'}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400">{service.role}</p>
                </div>

                <button
                  onClick={() => onToggleService(service.id)}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1.5 cursor-pointer transition-colors ${
                    isRunning
                      ? 'bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 border border-rose-500/40'
                      : 'bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 border border-cyan-500/40'
                  }`}
                >
                  {isRunning ? (
                    <>
                      <Square className="w-3.5 h-3.5" />
                      Stop
                    </>
                  ) : (
                    <>
                      <Play className="w-3.5 h-3.5" />
                      Start ({service.command})
                    </>
                  )}
                </button>
              </div>

              {/* Status details */}
              <div className="mt-4 pt-3 border-t border-slate-800/80 grid grid-cols-2 gap-2 text-xs">
                <div>
                  <span className="text-slate-500 block text-[11px]">Command:</span>
                  <div className="flex items-center gap-1 font-mono text-cyan-400">
                    <span>{service.command}</span>
                    <button
                      onClick={() => handleCopy(service.command, service.command)}
                      className="text-slate-500 hover:text-slate-300 p-0.5"
                      title="Copy bash command"
                    >
                      {copiedCmd === service.command ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
                    </button>
                  </div>
                </div>

                <div>
                  <span className="text-slate-500 block text-[11px]">Bound Port:</span>
                  <span className="font-mono text-slate-300">{service.port}</span>
                </div>

                <div className="col-span-2">
                  <span className="text-slate-500 block text-[11px]">Health Probe:</span>
                  <span className="font-mono text-[11px] text-slate-400 truncate block">
                    {service.healthEndpoint}
                  </span>
                </div>
              </div>

              <div className="mt-3 bg-slate-950/60 p-2.5 rounded-lg border border-slate-800/60 text-xs text-slate-400 leading-relaxed">
                {service.description}
              </div>
            </div>
          );
        })}
      </div>

      {/* Terminal Log Output Stream */}
      <div className="bg-slate-950 border border-slate-800 rounded-xl overflow-hidden shadow-2xl">
        <div className="bg-slate-900/90 px-4 py-3 border-b border-slate-800 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <Terminal className="w-4 h-4 text-cyan-400" />
            <h3 className="font-mono text-xs font-semibold text-slate-200">
              Live Supervisor Log Stream (~/cdp/logs/*.log)
            </h3>
            <span className="text-[10px] text-slate-400 bg-slate-800 px-2 py-0.5 rounded">
              {logs.length} entries
            </span>
          </div>

          <div className="flex items-center gap-3">
            {/* Filter buttons */}
            <div className="flex items-center gap-1 text-xs">
              <span className="text-slate-500 text-[11px]">Filter:</span>
              {(['all', 'vnc', 'chr', 'buse', 'crwl'] as const).map((filterId) => (
                <button
                  key={filterId}
                  onClick={() => setFilterService(filterId)}
                  className={`px-2 py-0.5 rounded text-[11px] font-mono cursor-pointer transition-colors ${
                    filterService === filterId
                      ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/30'
                      : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  {filterId}
                </button>
              ))}
            </div>

            <button
              onClick={onClearLogs}
              className="text-slate-400 hover:text-rose-400 p-1 rounded transition-colors cursor-pointer"
              title="Clear logs"
            >
              <Trash2 className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        <div className="p-4 font-mono text-xs h-72 overflow-y-auto space-y-1.5 bg-[#080d16]">
          {filteredLogs.length === 0 ? (
            <div className="text-slate-600 italic py-8 text-center">
              No log messages yet. Click "Start" on any service or click "Run Probe (st)" to generate logs.
            </div>
          ) : (
            filteredLogs.map((log) => {
              let colorClass = 'text-slate-300';
              if (log.level === 'success') colorClass = 'text-emerald-400';
              if (log.level === 'warn') colorClass = 'text-amber-400';
              if (log.level === 'error') colorClass = 'text-rose-400';

              return (
                <div key={log.id} className="flex items-start gap-2.5 leading-relaxed hover:bg-slate-900/40 px-1.5 py-0.5 rounded">
                  <span className="text-slate-500 text-[11px] shrink-0">{log.timestamp}</span>
                  <span className="px-1.5 py-0.2 rounded text-[10px] uppercase font-bold shrink-0 bg-slate-800 text-cyan-300 border border-slate-700/60">
                    {log.serviceId}
                  </span>
                  <span className={`${colorClass} break-all`}>
                    {log.message}
                  </span>
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
};
