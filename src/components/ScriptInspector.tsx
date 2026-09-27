import React, { useState, useMemo } from 'react';
import { 
  FileCode, 
  Copy, 
  Check, 
  Download, 
  Sliders, 
  ShieldCheck, 
  Radio, 
  Terminal, 
  Code2
} from 'lucide-react';
import { SCRIPTS } from '../data/scripts';

export const ScriptInspector: React.FC = () => {
  const [selectedScriptId, setSelectedScriptId] = useState<string>('vccc');
  const [copied, setCopied] = useState<boolean>(false);
  const [showCustomizer, setShowCustomizer] = useState<boolean>(false);

  // Customization parameters for vccc.sh / vcpc.sh / instc.sh
  const [customParams, setCustomParams] = useState({
    displayNum: '99',
    vncResolution: '2560x1440',
    cdpPort: '9222',
    busePort: '8001',
    crwlPort: '8002',
    tailcatVersion: 'v0.7.0',
    bindHost: '127.0.0.1'
  });

  const activeScript = useMemo(() => {
    return SCRIPTS.find(s => s.id === selectedScriptId) || SCRIPTS[0];
  }, [selectedScriptId]);

  // Generate customized content dynamically
  const customizedContent = useMemo(() => {
    let raw = activeScript.content;
    if (activeScript.id === 'vccc') {
      raw = raw
        .replace(/DISPLAY=:99/g, `DISPLAY=:${customParams.displayNum}`)
        .replace(/:99/g, `:${customParams.displayNum}`)
        .replace(/2560x1440/g, customParams.vncResolution)
        .replace(/--remote-debugging-port=9222/g, `--remote-debugging-port=${customParams.cdpPort}`)
        .replace(/127\.0\.0\.1:9222/g, `${customParams.bindHost}:${customParams.cdpPort}`)
        .replace(/--port 8001/g, `--port ${customParams.busePort}`)
        .replace(/--port 8002/g, `--port ${customParams.crwlPort}`)
        .replace(/--host 127\.0\.0\.1/g, `--host ${customParams.bindHost}`);
    } else if (activeScript.id === 'instc') {
      raw = raw.replace(/v0\.7\.0/g, customParams.tailcatVersion);
    }
    return raw;
  }, [activeScript, customParams]);

  const handleCopy = () => {
    navigator.clipboard.writeText(customizedContent);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDownload = () => {
    const blob = new Blob([customizedContent], { type: 'text/x-sh' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = activeScript.filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-6">
      {/* Top Selector Ribbon */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
        <div className="flex flex-wrap items-center gap-2">
          {SCRIPTS.map((script) => (
            <button
              key={script.id}
              onClick={() => setSelectedScriptId(script.id)}
              className={`px-3.5 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 cursor-pointer transition-colors ${
                selectedScriptId === script.id
                  ? 'bg-cyan-500 text-slate-950 font-bold shadow-md shadow-cyan-500/20'
                  : 'bg-slate-800/80 text-slate-300 hover:bg-slate-700/80 border border-slate-700/60'
              }`}
            >
              <FileCode className="w-3.5 h-3.5" />
              {script.filename}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowCustomizer(!showCustomizer)}
            className={`px-3 py-2 rounded-lg text-xs font-medium flex items-center gap-1.5 cursor-pointer transition-colors ${
              showCustomizer 
                ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/40' 
                : 'bg-slate-800 text-slate-300 hover:bg-slate-700 border border-slate-700'
            }`}
          >
            <Sliders className="w-3.5 h-3.5" />
            {showCustomizer ? 'Hide Customizer' : 'Customize Params'}
          </button>

          <button
            onClick={handleCopy}
            className="px-3 py-2 bg-slate-800 hover:bg-slate-700 border border-slate-700 text-slate-200 rounded-lg text-xs font-medium flex items-center gap-1.5 cursor-pointer transition-colors"
          >
            {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
            {copied ? 'Copied!' : 'Copy Script'}
          </button>

          <button
            onClick={handleDownload}
            className="px-3 py-2 bg-cyan-600 hover:bg-cyan-500 text-white rounded-lg text-xs font-medium flex items-center gap-1.5 cursor-pointer transition-colors shadow-sm shadow-cyan-900/30"
          >
            <Download className="w-3.5 h-3.5" />
            Download .sh
          </button>
        </div>
      </div>

      {/* Script Summary & Metadata */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-4">
          <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-lg font-bold text-white flex items-center gap-2">
                  <Terminal className="w-4 h-4 text-cyan-400" />
                  {activeScript.name}
                </h3>
                <span className="text-xs text-slate-400 font-mono">File: /{activeScript.filename}</span>
              </div>
              <span className="px-2.5 py-1 text-xs rounded-full bg-slate-800 border border-slate-700 text-cyan-300 font-mono">
                {activeScript.linesCount} lines
              </span>
            </div>

            <p className="text-xs text-slate-300 leading-relaxed">
              {activeScript.description}
            </p>

            <div className="flex flex-wrap gap-1.5 pt-1">
              {activeScript.tags.map((tag) => (
                <span key={tag} className="px-2 py-0.5 rounded text-[11px] bg-slate-800 text-slate-300 border border-slate-700/60">
                  {tag}
                </span>
              ))}
            </div>
          </div>

          {/* Customizer Panel */}
          {showCustomizer && (
            <div className="bg-slate-900 border border-cyan-500/40 rounded-xl p-5 space-y-4 shadow-xl shadow-cyan-950/20">
              <div className="flex items-center justify-between border-b border-slate-800 pb-3">
                <div className="flex items-center gap-2">
                  <Sliders className="w-4 h-4 text-cyan-400" />
                  <h4 className="text-sm font-bold text-white">Interactive Parameter Customizer</h4>
                </div>
                <span className="text-[11px] text-cyan-400 font-mono">Changes apply to live script preview</span>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4 text-xs">
                {activeScript.id === 'vccc' && (
                  <>
                    <div>
                      <label className="text-slate-400 block mb-1">X11 Display Number</label>
                      <input
                        type="text"
                        value={customParams.displayNum}
                        onChange={(e) => setCustomParams({ ...customParams, displayNum: e.target.value })}
                        className="w-full bg-slate-950 border border-slate-700 rounded px-2.5 py-1.5 font-mono text-cyan-300 focus:outline-none focus:border-cyan-400"
                        placeholder="99"
                      />
                    </div>

                    <div>
                      <label className="text-slate-400 block mb-1">Screen Resolution</label>
                      <select
                        value={customParams.vncResolution}
                        onChange={(e) => setCustomParams({ ...customParams, vncResolution: e.target.value })}
                        className="w-full bg-slate-950 border border-slate-700 rounded px-2.5 py-1.5 font-mono text-cyan-300 focus:outline-none focus:border-cyan-400 cursor-pointer"
                      >
                        <option value="2560x1440">2560x1440 (2K QHD)</option>
                        <option value="1920x1080">1920x1080 (1080p FHD)</option>
                        <option value="1280x720">1280x720 (720p HD)</option>
                        <option value="3840x2160">3840x2160 (4K UHD)</option>
                      </select>
                    </div>

                    <div>
                      <label className="text-slate-400 block mb-1">Chrome CDP Port</label>
                      <input
                        type="text"
                        value={customParams.cdpPort}
                        onChange={(e) => setCustomParams({ ...customParams, cdpPort: e.target.value })}
                        className="w-full bg-slate-950 border border-slate-700 rounded px-2.5 py-1.5 font-mono text-cyan-300 focus:outline-none focus:border-cyan-400"
                        placeholder="9222"
                      />
                    </div>

                    <div>
                      <label className="text-slate-400 block mb-1">Browser-use MCP Port</label>
                      <input
                        type="text"
                        value={customParams.busePort}
                        onChange={(e) => setCustomParams({ ...customParams, busePort: e.target.value })}
                        className="w-full bg-slate-950 border border-slate-700 rounded px-2.5 py-1.5 font-mono text-cyan-300 focus:outline-none focus:border-cyan-400"
                        placeholder="8001"
                      />
                    </div>

                    <div>
                      <label className="text-slate-400 block mb-1">Crawl-MCP Port</label>
                      <input
                        type="text"
                        value={customParams.crwlPort}
                        onChange={(e) => setCustomParams({ ...customParams, crwlPort: e.target.value })}
                        className="w-full bg-slate-950 border border-slate-700 rounded px-2.5 py-1.5 font-mono text-cyan-300 focus:outline-none focus:border-cyan-400"
                        placeholder="8002"
                      />
                    </div>

                    <div>
                      <label className="text-slate-400 block mb-1">Bind Host (Security)</label>
                      <input
                        type="text"
                        value={customParams.bindHost}
                        onChange={(e) => setCustomParams({ ...customParams, bindHost: e.target.value })}
                        className="w-full bg-slate-950 border border-slate-700 rounded px-2.5 py-1.5 font-mono text-cyan-300 focus:outline-none focus:border-cyan-400"
                        placeholder="127.0.0.1"
                      />
                    </div>
                  </>
                )}

                {activeScript.id === 'instc' && (
                  <div>
                    <label className="text-slate-400 block mb-1">Default Fallback Version</label>
                    <input
                      type="text"
                      value={customParams.tailcatVersion}
                      onChange={(e) => setCustomParams({ ...customParams, tailcatVersion: e.target.value })}
                      className="w-full bg-slate-950 border border-slate-700 rounded px-2.5 py-1.5 font-mono text-cyan-300 focus:outline-none focus:border-cyan-400"
                      placeholder="v0.7.0"
                    />
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Script Code Viewer */}
          <div className="bg-slate-950 border border-slate-800 rounded-xl overflow-hidden shadow-2xl">
            <div className="bg-slate-900/90 px-4 py-2.5 border-b border-slate-800 flex items-center justify-between">
              <span className="text-xs font-mono text-slate-300 flex items-center gap-2">
                <Code2 className="w-3.5 h-3.5 text-cyan-400" />
                {activeScript.filename}
              </span>
              <button
                onClick={handleCopy}
                className="text-xs text-slate-400 hover:text-white flex items-center gap-1 cursor-pointer transition-colors"
              >
                {copied ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
                {copied ? 'Copied' : 'Copy'}
              </button>
            </div>

            <div className="p-4 font-mono text-xs overflow-x-auto max-h-[500px] overflow-y-auto leading-relaxed text-slate-300 bg-[#070b12]">
              <pre>
                <code>{customizedContent}</code>
              </pre>
            </div>
          </div>
        </div>

        {/* Security & Audit Highlights Sidebar */}
        <div className="space-y-4">
          <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-5 space-y-4">
            <h4 className="text-sm font-bold text-white flex items-center gap-2">
              <ShieldCheck className="w-4 h-4 text-emerald-400" />
              Security Architecture & Hardening
            </h4>

            <div className="space-y-2.5">
              {activeScript.securityHighlights.map((highlight, idx) => (
                <div key={idx} className="flex items-start gap-2.5 text-xs text-slate-300 bg-slate-950/40 p-2.5 rounded-lg border border-slate-800/60 leading-relaxed">
                  <div className="w-1.5 h-1.5 rounded-full bg-emerald-400 shrink-0 mt-1.5" />
                  <span>{highlight}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Network Port Matrix */}
          <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-5 space-y-3">
            <h4 className="text-sm font-bold text-white flex items-center gap-2">
              <Radio className="w-4 h-4 text-cyan-400" />
              Network Ports Used
            </h4>

            {activeScript.portsUsed.length === 0 ? (
              <p className="text-xs text-slate-500 italic">No network listening ports required for this diagnostic script.</p>
            ) : (
              <div className="space-y-2 text-xs">
                {activeScript.portsUsed.map((p, idx) => (
                  <div key={idx} className="bg-slate-950/60 p-2.5 rounded-lg border border-slate-800/80">
                    <div className="flex items-center justify-between font-mono">
                      <span className="text-cyan-400 font-bold">{p.port} ({p.protocol})</span>
                      <span className="text-[10px] text-emerald-400 bg-emerald-950/80 px-2 py-0.5 rounded border border-emerald-800/40">
                        {p.visibility}
                      </span>
                    </div>
                    <p className="text-slate-400 text-[11px] mt-1">{p.service}</p>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
