<div align="center">
  <h1>Mole-AI</h1>
  <p><em>Deep clean and optimize your Mac. AI-powered system advisor.</em></p>
</div>

<p align="center">
  <a href="https://github.com/xronocode/mole-ai/releases"><img src="https://img.shields.io/github/v/tag/xronocode/mole-ai?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/tw93/mole"><img src="https://img.shields.io/badge/based%20on-tw93%2Fmole-blue?style=flat-square" alt="Based on Mole"></a>
</p>

<p align="center">
  <img src="https://gw.alipayobjects.com/zos/k/ro/ZzF8e8.png" alt="Mole - 95.50GB freed" width="1000" />
</p>

## Features

- **All-in-one toolkit**: Combines CleanMyMac, AppCleaner, DaisyDisk, and iStat Menus in a **single binary**
- **Deep cleaning**: Removes caches, logs, browser leftovers, and orphaned app data to **reclaim gigabytes of space**
- **Smart uninstaller**: Removes apps plus launch agents, preferences, and **hidden remnants**
- **Disk insights**: Visualizes usage, finds large files, **rebuilds caches**, and refreshes system services
- **Live monitoring**: Shows real-time CPU, GPU, memory, disk, and network stats
- **AI system advisor**: Analyzes your system via a connected LLM and presents interactive, risk-tagged cleanup recommendations

## Quick Start

**Install via script**

```bash
curl -fsSL https://raw.githubusercontent.com/xronocode/mole-ai/main/install.sh | bash
```

> Note: Mole-AI is built for macOS. Based on [tw93/Mole](https://github.com/tw93/mole).

**Run**

```bash
mo                           # Interactive menu
mo advisor                   # AI-powered system analysis
mo advisor --setup           # Configure AI endpoint (Ollama, OpenRouter, etc.)
mo advisor --dry-run         # Preview collected system data
mo clean                     # Deep cleanup + already-uninstalled app leftovers
mo uninstall                 # Remove installed apps + their leftovers
mo optimize                  # Refresh caches & services
mo analyze                   # Visual disk explorer
mo status                    # Live system health dashboard
mo purge                     # Clean project build artifacts
mo update                    # Update Mole-AI
mo remove                    # Remove Mole-AI from system
mo --help                    # Show help
mo --version                 # Show installed version
```

**Preview safely**

```bash
mo clean --dry-run
mo uninstall --dry-run
mo purge --dry-run

# Also works with: optimize, installer, remove, completion, touchid enable
mo clean --dry-run --debug   # Preview + detailed logs
mo optimize --whitelist      # Manage protected optimization rules
mo clean --whitelist         # Manage protected caches
mo purge --paths             # Configure project scan directories
mo analyze /Volumes          # Analyze external drives only
```

## Security & Safety Design

Mole is a local system maintenance tool, and some commands can perform destructive local operations.

Mole uses safety-first defaults: path validation, protected-directory rules, conservative cleanup boundaries, and explicit confirmation for higher-risk actions. When risk or uncertainty is high, Mole skips, refuses, or requires stronger confirmation rather than broadening deletion scope.

`mo analyze` is safer for ad hoc cleanup because it moves files to Trash through Finder instead of deleting them directly.

Review [SECURITY.md](SECURITY.md) and [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for reporting guidance, safety boundaries, and current limitations.

## Tips

- Video tutorial: Watch the [Mole tutorial video](https://www.youtube.com/watch?v=UEe9-w4CcQ0), thanks to PAPAYA 電腦教室.
- Safety and logs: `clean`, `uninstall`, `purge`, `installer`, and `remove` are destructive. Review with `--dry-run` first, and add `--debug` when needed. File operations are logged to `~/Library/Logs/mole/operations.log`. Disable with `MO_NO_OPLOG=1`. Review [SECURITY.md](SECURITY.md) and [SECURITY_AUDIT.md](SECURITY_AUDIT.md).
- App leftovers: use `mo clean` when the app is already uninstalled, and `mo uninstall` when the app is still installed.
- Navigation: Mole supports arrow keys and Vim bindings `h/j/k/l`.

## Features in Detail

### AI System Advisor

Connects to any OpenAI-compatible LLM (Ollama, OpenRouter, vLLM, LM Studio) to analyze your system and recommend cleanup actions.

```bash
$ mo advisor --setup        # Configure endpoint (URL, model, API key)
$ mo advisor                 # Full analysis pipeline

  Collect → Analyze → Report → Select → Execute

  === DISK USAGE SUMMARY ===
  | Path                              | Size  | Category        |
  |-----------------------------------|-------|-----------------|
  | ~/Library/Developer/Xcode         | 23GB  | Developer tools |
  | ~/Library/Caches                  | 12GB  | User caches     |
  | ~/.npm/_cacache                   | 2.1GB | Package cache   |

  Low Risk (Recommended):
    ✓ NPM cache (2.1GB) — fully regenerable
    ✓ User logs (60MB) — safe to clear

  Medium/High Risk:
    ⚠ Downloads (1.4GB) — user files
    ⚠ ChatGPT cache (177MB) — may need re-download

  Select items to clean [F: filter risk, Enter: confirm]:
  [x] Clear NPM cache
  [x] Clear user logs
  [ ] Downloads files

  ✓ Removed 2.2GB
```

`mo advisor --dry-run` shows collected system data without calling the LLM.
`mo advisor --auto-safe` auto-selects SAFE items and skips the menu.
`mo advisor --analyze` generates a report without prompting for deletion.

### Deep System Cleanup

```bash
$ mo clean

Scanning cache directories...

  ✓ User app cache                                           45.2GB
  ✓ Browser cache (Chrome, Safari, Firefox)                  10.5GB
  ✓ Developer tools (Xcode, Node.js, npm)                    23.3GB
  ✓ System logs and temp files                                3.8GB
  ✓ App-specific cache (Spotify, Dropbox, Slack)              8.4GB
  ✓ Trash                                                    12.3GB

====================================================================
Space freed: 95.5GB | Free space now: 223.5GB
====================================================================
```

Note: In `mo clean` -> Developer tools, Mole removes unused CoreSimulator `Volumes/Cryptex` entries and skips `IN_USE` items.

### Smart App Uninstaller

```bash
$ mo uninstall

Select Apps to Remove
═══════════════════════════
▶ ☑ Photoshop 2024            (4.2G) | Old
  ☐ IntelliJ IDEA             (2.8G) | Recent
  ☐ Premiere Pro              (3.4G) | Recent

Uninstalling: Photoshop 2024

  ✓ Removed application
  ✓ Cleaned 52 related files across 12 locations
    - Application Support, Caches, Preferences
    - Logs, WebKit storage, Cookies
    - Extensions, Plugins, Launch daemons

Note: On macOS 15 and later, Local Network permission entries can outlive app removal. Mole warns when an uninstalled app declares Local Network usage, but it does not auto-reset `/Volumes/Data/Library/Preferences/com.apple.networkextension*.plist` because that reset is global and requires Recovery mode.

====================================================================
Space freed: 12.8GB
====================================================================
```

### System Optimization

```bash
$ mo optimize

System: 5/32 GB RAM | 333/460 GB Disk (72%) | Uptime 6d

  ✓ Rebuild system databases and clear caches
  ✓ Reset network services
  ✓ Refresh Finder and Dock
  ✓ Clean diagnostic and crash logs
  ✓ Remove swap files and restart dynamic pager
  ✓ Rebuild launch services and spotlight index

====================================================================
System optimization completed
====================================================================

Use `mo optimize --whitelist` to exclude specific optimizations.
```

### Disk Space Analyzer

> Note: By default, Mole skips external drives under `/Volumes` for faster startup. To inspect them, run `mo analyze /Volumes` or a specific mount path.

```bash
$ mo analyze

Analyze Disk  ~/Documents  |  Total: 156.8GB

 ▶  1. ███████████████████  48.2%  |  📁 Library                     75.4GB  >6mo
    2. ██████████░░░░░░░░░  22.1%  |  📁 Downloads                   34.6GB
    3. ████░░░░░░░░░░░░░░░  14.3%  |  📁 Movies                      22.4GB
    4. ███░░░░░░░░░░░░░░░░  10.8%  |  📁 Documents                   16.9GB
    5. ██░░░░░░░░░░░░░░░░░   5.2%  |  📄 backup_2023.zip              8.2GB

  ↑↓←→ Navigate  |  O Open  |  F Show  |  ⌫ Delete  |  L Large files  |  Q Quit
```

### Live System Status

Real-time dashboard with health score, hardware info, and performance metrics.

```bash
$ mo status

Mole Status  Health ● 92  MacBook Pro · M4 Pro · 32GB · macOS 14.5

⚙ CPU                                    ▦ Memory
Total   ████████████░░░░░░░  45.2%       Used    ███████████░░░░░░░  58.4%
Load    0.82 / 1.05 / 1.23 (8 cores)     Total   14.2 / 24.0 GB
Core 1  ███████████████░░░░  78.3%       Free    ████████░░░░░░░░░░  41.6%
Core 2  ████████████░░░░░░░  62.1%       Avail   9.8 GB

▤ Disk                                   ⚡ Power
Used    █████████████░░░░░░  67.2%       Level   ██████████████████  100%
Free    156.3 GB                         Status  Charged
Read    ▮▯▯▯▯  2.1 MB/s                  Health  Normal · 423 cycles
Write   ▮▮▮▯▯  18.3 MB/s                 Temp    58°C · 1200 RPM

⇅ Network                                ▶ Processes
Down    ▁▁█▂▁▁▁▁▁▁▁▁▇▆▅▂  0.54 MB/s      Code       ▮▮▮▮▯  42.1%
Up      ▄▄▄▃▃▃▄▆▆▇█▁▁▁▁▁  0.02 MB/s      Chrome     ▮▮▮▯▯  28.3%
Proxy   HTTP · 192.168.1.100             Terminal   ▮▯▯▯▯  12.5%
```

Health score is based on CPU, memory, disk, temperature, and I/O load, with color-coded ranges.

Shortcuts: In `mo status`, press `k` to toggle the cat and save the preference, and `q` to quit.

When enabled, `mo status` shows a read-only alert banner for processes that stay above the configured CPU threshold for a sustained window. Use `--proc-cpu-threshold`, `--proc-cpu-window`, or `--proc-cpu-alerts=false` to tune or disable it.

#### Machine-Readable Output

Both `mo analyze` and `mo status` support a `--json` flag for scripting and automation.

`mo status` also auto-detects when its output is piped (not a terminal) and switches to JSON automatically.

```bash
# Disk analysis as JSON
$ mo analyze --json ~/Documents
{
  "path": "/Users/you/Documents",
  "overview": false,
  "entries": [
    { "name": "Library", "path": "...", "size": 80939438080, "is_dir": true },
    ...
  ],
  "large_files": [
    { "name": "backup.zip", "path": "...", "size": 8796093022 }
  ],
  "total_size": 168393441280,
  "total_files": 42187
}

# System status as JSON
$ mo status --json
{
  "host": "MacBook-Pro",
  "health_score": 92,
  "cpu": { "usage": 45.2, "logical_cpu": 8, ... },
  "memory": { "total": 25769803776, "used": 15049334784, "used_percent": 58.4 },
  "disks": [ ... ],
  "uptime": "3d 12h 45m",
  ...
}

# Auto-detected JSON when piped
$ mo status | jq '.health_score'
92
```

### Project Artifact Purge

Clean old build artifacts such as `node_modules`, `target`, `.build`, `build`, and `dist` to free up disk space.

```bash
mo purge

Select Categories to Clean - 18.5GB (8 selected)

➤ ● my-react-app       3.2GB | node_modules
  ● old-project        2.8GB | node_modules
  ● rust-app           4.1GB | target
  ● next-blog          1.9GB | node_modules
  ○ current-work       856MB | node_modules  | Recent
  ● django-api         2.3GB | venv
  ● vue-dashboard      1.7GB | node_modules
  ● backend-service    2.5GB | node_modules
```

> Note: We recommend installing `fd` on macOS.
> `brew install fd`

> Safety: This permanently deletes selected artifacts. Review carefully before confirming. Projects newer than 7 days are marked and unselected by default.

<details>
<summary><strong>Custom Scan Paths</strong></summary>

Run `mo purge --paths` to configure scan directories, or edit `~/.config/mole/purge_paths` directly:

```shell
~/Documents/MyProjects
~/Work/ClientA
~/Work/ClientB
```

When custom paths are configured, Mole scans only those directories. Otherwise, it uses defaults like `~/Projects`, `~/GitHub`, and `~/dev`.

</details>

### Installer Cleanup

Find and remove large installer files across Downloads, Desktop, Homebrew caches, iCloud, and Mail. Each file is labeled by source.

```bash
mo installer

Select Installers to Remove - 3.8GB (5 selected)

➤ ● Photoshop_2024.dmg     1.2GB | Downloads
  ● IntelliJ_IDEA.dmg       850.6MB | Downloads
  ● Illustrator_Setup.pkg   920.4MB | Downloads
  ● PyCharm_Pro.dmg         640.5MB | Homebrew
  ● Acrobat_Reader.dmg      220.4MB | Downloads
  ○ AppCode_Legacy.zip      410.6MB | Downloads
```

## Quick Launchers

Launch Mole commands from Raycast or Alfred:

```bash
curl -fsSL https://raw.githubusercontent.com/xronocode/mole-ai/main/scripts/setup-quick-launchers.sh | bash
```

Adds 5 commands: `Mole Clean`, `Mole Uninstall`, `Mole Optimize`, `Mole Analyze`, `Mole Status`.

### Raycast Setup

After running the script, complete these steps in Raycast:

1. Open Raycast Settings (⌘ + ,)
2. Go to **Extensions** → **Script Commands**
3. Click **"Add Script Directory"** (or **"+"**)
4. Add path: `~/Library/Application Support/Raycast/script-commands`
5. Search in Raycast for: **"Reload Script Directories"** and run it
6. Done! Search for `Mole Clean` or `clean`, `Mole Optimize`, or `Mole Status` to use the commands

> **Note**: The script creates the commands, but Raycast still requires a one-time manual script directory setup.

### Terminal Detection

Mole auto-detects your terminal app. iTerm2 has known compatibility issues. We highly recommend [Kaku](https://github.com/tw93/Kaku). Other good options are Alacritty, kitty, WezTerm, Ghostty, and Warp. To override, set `MO_LAUNCHER_APP=<name>`.

## AI Advisor Setup

Mole-AI's advisor works with any OpenAI-compatible endpoint.

### Local (Ollama)

```bash
# Install Ollama, then pull a model
ollama pull llama3

# Configure
mo advisor --setup
# Endpoint: http://localhost:11434/v1/chat/completions
# Model: llama3
# API key: (leave empty)
```

### Cloud (OpenRouter, etc.)

```bash
mo advisor --setup
# Endpoint: https://openrouter.ai/api/v1/chat/completions
# Model: anthropic/claude-3.5-sonnet
# API key: sk-or-v1-...
```

Config stored in `~/.config/mole/ai.conf`. API key never logged.

## Acknowledgments

Mole-AI is based on [tw93/Mole](https://github.com/tw93/mole) — an excellent macOS system maintenance CLI.

## Community Love

Thanks to everyone who helped build Mole. Go follow them. ❤️

<a href="https://github.com/tw93/Mole/graphs/contributors">
  <img src="./CONTRIBUTORS.svg?v=2" width="1000" />
</a>

<br/><br/>
Real feedback from users who shared Mole on X.

<img src="https://gw.alipayobjects.com/zos/k/dl/lovemole.jpeg" alt="Community feedback on Mole" width="1000" />

## Support

- If Mole-AI helped you, give it a star.
- Got ideas or bugs? Open an issue or PR.

## License

MIT License. Based on [tw93/Mole](https://github.com/tw93/mole) (MIT).
