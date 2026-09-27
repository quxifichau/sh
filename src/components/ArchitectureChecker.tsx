import React, { useState } from 'react';
import { 
  Cpu, 
  Terminal, 
  ExternalLink
} from 'lucide-react';

export const ArchitectureChecker: React.FC = () => {
  const [arch, setArch] = useState<'x86_64' | 'aarch64' | 'armv7l' | 'riscv64'>('x86_64');
  const [pkgManager, setPkgManager] = useState<'dpkg' | 'rpm' | 'nix' | 'docker' | 'go' | 'tarball'>('dpkg');
  const [isRoot, setIsRoot] = useState<boolean>(true);
  const [hasSudo, setHasSudo] = useState<boolean>(true);
  const [tailcatVersion, setTailcatVersion] = useState<string>('0.7.0');

  // Compute mapping as done in instc.sh & chktcsys.sh
  const getArchMapping = () => {
    switch (arch) {
      case 'x86_64':
        return { goarch: 'amd64', pkgArch: 'amd64', supported: true };
      case 'aarch64':
        return { goarch: 'arm64', pkgArch: 'arm64', supported: true };
      case 'armv7l':
        return { goarch: 'arm', pkgArch: 'armv7', supported: true };
      default:
        return { goarch: 'unknown', pkgArch: 'unknown', supported: false };
    }
  };

  const mapping = getArchMapping();

  // Compute installation path and commands
  const getSimulatedResolution = () => {
    if (!mapping.supported) {
      return {
        pathName: 'Unsupported Architecture',
        description: `CPU architecture '${arch}' is not recognized. instc.sh exits with code 1.`,
        commands: [`[-] 不受支持的 CPU 架构: ${arch}`, `exit 1`],
        downloadUrl: null,
        targetDir: null
      };
    }

    const debFile = `tailcat_${tailcatVersion}_linux_${mapping.pkgArch}.deb`;
    const rpmFile = `tailcat_${tailcatVersion}_linux_${mapping.pkgArch}.rpm`;
    const tarFile = `tailcat_${tailcatVersion}_linux_${mapping.pkgArch}.tar.gz`;

    const sudoPrefix = isRoot ? '' : (hasSudo ? 'sudo ' : '');
    const targetDir = isRoot ? '/usr/local/bin' : (hasSudo ? '/usr/local/bin' : '$HOME/.local/bin');

    if (pkgManager === 'docker') {
      return {
        pathName: 'Docker Containerized Route (chktcsys.sh)',
        description: 'Docker runtime detected. Direct container execution without modifying host packages.',
        commands: [
          'docker pull ghcr.io/tailscale/tailcat:latest',
          'docker run --rm -it --net=host ghcr.io/tailscale/tailcat:latest version'
        ],
        downloadUrl: 'ghcr.io/tailscale/tailcat:latest',
        targetDir: 'Container isolation'
      };
    }

    if (pkgManager === 'nix') {
      return {
        pathName: 'Nix Profile Installation Route',
        description: 'Nix package manager detected. Uses declarative, reproducible package profile without root privileges.',
        commands: [
          'nix profile install nixpkgs#tailcat',
          'tailcat --version'
        ],
        downloadUrl: 'nixpkgs#tailcat',
        targetDir: '~/.nix-profile/bin/tailcat'
      };
    }

    if (pkgManager === 'go') {
      return {
        pathName: 'Go Toolchain Source Build Route',
        description: 'Go toolchain detected (go version 1.22+). Compiles directly from source repository.',
        commands: [
          'go install github.com/tailscale/tailcat/cmd/tailcat@latest',
          'export PATH="$HOME/go/bin:$PATH"',
          'tailcat version'
        ],
        downloadUrl: 'github.com/tailscale/tailcat/cmd/tailcat@latest',
        targetDir: '$HOME/go/bin/tailcat'
      };
    }

    if (pkgManager === 'dpkg') {
      const url = `https://github.com/tailscale/tailcat/releases/download/v${tailcatVersion}/${debFile}`;
      return {
        pathName: 'Debian / Ubuntu Native Package (.deb)',
        description: 'Native package manager route with automatic missing dependency remediation (apt-get install -f -y).',
        commands: [
          `curl -fL --progress-bar "${url}" -o "/tmp/${debFile}"`,
          `${sudoPrefix}dpkg -i "/tmp/${debFile}" || ${sudoPrefix}apt-get install -f -y`,
          `tailcat --version`
        ],
        downloadUrl: url,
        targetDir: '/usr/bin/tailcat'
      };
    }

    if (pkgManager === 'rpm') {
      const url = `https://github.com/tailscale/tailcat/releases/download/v${tailcatVersion}/${rpmFile}`;
      return {
        pathName: 'RHEL / Fedora / CentOS Package (.rpm)',
        description: 'Native RPM manager route using dnf or yum with local dependency resolution.',
        commands: [
          `curl -fL --progress-bar "${url}" -o "/tmp/${rpmFile}"`,
          `${sudoPrefix}dnf install -y "/tmp/${rpmFile}" || ${sudoPrefix}rpm -Uvh "/tmp/${rpmFile}"`,
          `tailcat --version`
        ],
        downloadUrl: url,
        targetDir: '/usr/bin/tailcat'
      };
    }

    // Tarball fallback
    const url = `https://github.com/tailscale/tailcat/releases/download/v${tailcatVersion}/${tarFile}`;
    return {
      pathName: 'Universal Static Binary Fallback (.tar.gz)',
      description: isRoot || hasSudo 
        ? 'Fallback for non-standard distributions: extracts precompiled static binary directly into /usr/local/bin.'
        : 'Non-root fallback: extracts binary to user directory $HOME/.local/bin and prompts to update PATH.',
      commands: [
        `TMP_DIR=$(mktemp -d)`,
        `curl -fL --progress-bar "${url}" -o "$TMP_DIR/${tarFile}"`,
        `tar -xzf "$TMP_DIR/${tarFile}" -C "$TMP_DIR"`,
        `${sudoPrefix}install -m 755 "$TMP_DIR/tailcat" "${targetDir}/tailcat"`,
        ...(!isRoot && !hasSudo ? ['export PATH="$PATH:$HOME/.local/bin"'] : []),
        `tailcat --version`
      ],
      downloadUrl: url,
      targetDir: `${targetDir}/tailcat`
    };
  };

  const resolution = getSimulatedResolution();

  return (
    <div className="space-y-6">
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-5 backdrop-blur">
        <h2 className="text-xl font-bold text-white flex items-center gap-2">
          <Cpu className="w-5 h-5 text-cyan-400" />
          Cross-Platform Architecture & Toolchain Evaluator
        </h2>
        <p className="text-xs text-slate-400 mt-1">
          Interactive simulation of <code className="text-cyan-400 font-mono">chktcsys.sh</code> and <code className="text-cyan-400 font-mono">instc.sh</code> installation algorithms across architectures and Linux distributions.
        </p>
      </div>

      {/* Simulator Inputs */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        {/* Architecture */}
        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 space-y-2">
          <label className="text-xs font-semibold text-slate-300 block">
            CPU Architecture (<code className="font-mono text-cyan-400">uname -m</code>)
          </label>
          <div className="space-y-1.5 text-xs">
            {[
              { id: 'x86_64', label: 'x86_64 (Intel/AMD 64-bit)' },
              { id: 'aarch64', label: 'aarch64 / arm64 (Apple Silicon / Graviton)' },
              { id: 'armv7l', label: 'armv7l (Raspberry Pi 32-bit)' },
              { id: 'riscv64', label: 'riscv64 (Unsupported test)' }
            ].map(item => (
              <button
                key={item.id}
                onClick={() => setArch(item.id as any)}
                className={`w-full text-left px-2.5 py-1.5 rounded text-xs transition-colors cursor-pointer ${
                  arch === item.id 
                    ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 font-medium'
                    : 'text-slate-400 hover:bg-slate-800'
                }`}
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>

        {/* Package Manager */}
        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 space-y-2">
          <label className="text-xs font-semibold text-slate-300 block">
            Detected Toolchain / Package Mgr
          </label>
          <div className="space-y-1.5 text-xs">
            {[
              { id: 'dpkg', label: 'dpkg / apt (Debian, Ubuntu)' },
              { id: 'rpm', label: 'rpm / dnf / yum (RHEL, Fedora)' },
              { id: 'nix', label: 'Nix Package Manager' },
              { id: 'docker', label: 'Docker Container Runtime' },
              { id: 'go', label: 'Go Toolchain (go install)' },
              { id: 'tarball', label: 'No Toolchain (tar.gz fallback)' }
            ].map(item => (
              <button
                key={item.id}
                onClick={() => setPkgManager(item.id as any)}
                className={`w-full text-left px-2.5 py-1.5 rounded text-xs transition-colors cursor-pointer ${
                  pkgManager === item.id 
                    ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 font-medium'
                    : 'text-slate-400 hover:bg-slate-800'
                }`}
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>

        {/* User Permissions */}
        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 space-y-3">
          <label className="text-xs font-semibold text-slate-300 block">
            Execution Permissions
          </label>
          
          <div className="space-y-2 text-xs">
            <label className="flex items-center gap-2 text-slate-300 cursor-pointer">
              <input
                type="checkbox"
                checked={isRoot}
                onChange={(e) => setIsRoot(e.target.checked)}
                className="rounded border-slate-700 bg-slate-950 text-cyan-500 focus:ring-0"
              />
              <span>Running as root (<code className="font-mono text-cyan-400">id -u == 0</code>)</span>
            </label>

            {!isRoot && (
              <label className="flex items-center gap-2 text-slate-300 cursor-pointer pl-2">
                <input
                  type="checkbox"
                  checked={hasSudo}
                  onChange={(e) => setHasSudo(e.target.checked)}
                  className="rounded border-slate-700 bg-slate-950 text-cyan-500 focus:ring-0"
                />
                <span>Has <code className="font-mono text-cyan-400">sudo</code> command</span>
              </label>
            )}
          </div>

          <div className="pt-2 border-t border-slate-800">
            <label className="text-slate-400 block text-[11px] mb-1">Tailcat Version Tag</label>
            <input
              type="text"
              value={tailcatVersion}
              onChange={(e) => setTailcatVersion(e.target.value)}
              className="w-full bg-slate-950 border border-slate-700 rounded px-2.5 py-1 font-mono text-xs text-cyan-300 focus:outline-none focus:border-cyan-400"
              placeholder="0.7.0"
            />
          </div>
        </div>

        {/* Architecture Resolution Card */}
        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 space-y-3">
          <label className="text-xs font-semibold text-slate-300 block">
            Variable Mapping (<code className="font-mono text-cyan-400">instc.sh</code>)
          </label>
          <div className="bg-slate-950 p-3 rounded-lg border border-slate-800 font-mono text-xs space-y-1.5">
            <div>
              <span className="text-slate-500">ARCH: </span>
              <span className="text-cyan-300 font-bold">{arch}</span>
            </div>
            <div>
              <span className="text-slate-500">GOARCH: </span>
              <span className="text-emerald-400 font-bold">{mapping.goarch}</span>
            </div>
            <div>
              <span className="text-slate-500">PKG_ARCH: </span>
              <span className="text-amber-400 font-bold">{mapping.pkgArch}</span>
            </div>
            <div>
              <span className="text-slate-500">Target Dir: </span>
              <span className="text-indigo-300 text-[11px] truncate block">{resolution.targetDir}</span>
            </div>
          </div>
        </div>
      </div>

      {/* Evaluated Execution Flow */}
      <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-5 space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-slate-800 pb-3">
          <div>
            <span className="text-[11px] uppercase font-bold text-cyan-400 tracking-wider">
              Selected Installation Branch
            </span>
            <h3 className="text-base font-bold text-white mt-0.5">
              {resolution.pathName}
            </h3>
          </div>
          <span className="text-xs text-slate-400">
            {resolution.description}
          </span>
        </div>

        {/* Commands Generated */}
        <div className="space-y-2">
          <span className="text-xs font-semibold text-slate-300 flex items-center gap-1.5">
            <Terminal className="w-3.5 h-3.5 text-cyan-400" />
            Generated Shell Commands
          </span>
          <div className="bg-slate-950 rounded-lg p-4 font-mono text-xs space-y-1 border border-slate-800/80 overflow-x-auto text-cyan-300">
            {resolution.commands.map((cmd, i) => (
              <div key={i} className="flex items-start gap-2">
                <span className="text-slate-600 select-none">$</span>
                <span className="text-slate-200">{cmd}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Download Asset URL */}
        {resolution.downloadUrl && (
          <div className="bg-slate-950/60 p-3 rounded-lg border border-slate-800 flex items-center justify-between gap-3 text-xs">
            <div className="truncate">
              <span className="text-slate-500 text-[11px] block">Resolved Package Asset URL:</span>
              <span className="font-mono text-cyan-400 truncate block">{resolution.downloadUrl}</span>
            </div>
            <a
              href={resolution.downloadUrl.startsWith('http') ? resolution.downloadUrl : undefined}
              target="_blank"
              rel="noreferrer"
              className="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded text-xs flex items-center gap-1 shrink-0 transition-colors"
            >
              <ExternalLink className="w-3 h-3" />
              Direct Link
            </a>
          </div>
        )}
      </div>
    </div>
  );
};
