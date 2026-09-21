# it-toolkit

Scripts and configuration for IT support work, plus the setup to run Claude
Code as a local agent that can actually touch the machine in front of you.

Built for two jobs:

1. **Inventory a PC well enough to order the right part** without opening it.
2. **Get Claude Code running locally** with the right permission mode, instead
   of in a cloud container that can't see your hardware.

---

## Quickstart

```powershell
git clone https://github.com/zachcoble/it-toolkit.git
cd it-toolkit

# Hardware inventory (run elevated for complete results)
.\scripts\Get-PCSpecs.ps1

# JSON, for pasting into a chat or piping elsewhere
.\scripts\Get-PCSpecs.ps1 -Json
```

Linux:

```bash
sudo ./scripts/get-pc-specs.sh
```

---

## What's here

| Path | What it is |
|---|---|
| `scripts/Get-PCSpecs.ps1` | Windows hardware inventory aimed at ordering parts |
| `scripts/get-pc-specs.sh` | Linux equivalent (dmidecode / lsblk / lspci) |
| `templates/claude-settings.json` | Claude Code permission config to copy into a project or `~/.claude/` |
| `docs/claude-code-local-setup.md` | Install the CLI, permission modes, settings precedence |
| `docs/ordering-parts.md` | Turning the script's output into a correct order |

---

## Why the cloud session couldn't tell you your PC specs

Worth understanding, because it generalizes.

A Claude Code session started from the web runs in an **ephemeral Linux
container in Anthropic's cloud**. It clones your repo and gives you an agent
with real tools - but those tools operate on the container, not on your
desktop. Asking it about your CPU gets you an honest answer about the wrong
machine:

```
Model name:   Intel(R) Xeon(R) Processor @ 2.80GHz
CPU(s):       4
Mem:          15Gi
```

That's a hypervisor slice. Your PC is not involved.

This is the same mistake as running `lscpu` inside a VM, or `dmidecode` inside
WSL, and thinking you learned something about the host. The tool is telling the
truth about the layer it's standing on. **Always know which layer you're
standing on** - it's the thing that catches people out when they start doing
virtualization and cloud work, and it's worth internalizing early.

To inventory your own hardware you need the agent running *on* that hardware:
[`docs/claude-code-local-setup.md`](docs/claude-code-local-setup.md).

---

## Permission modes, briefly

The "let it just do the work" setting you're after:

| Mode | Behavior |
|---|---|
| `default` (Manual) | Asks before each new tool |
| `acceptEdits` | Auto-accepts file edits and routine filesystem commands |
| `auto` | Auto-approves with a background safety classifier |
| `bypassPermissions` | No prompts at all - isolated VMs only |

`Shift+Tab` cycles modes mid-session. On Pro and Max plans sessions already
start in `auto`, so you may have had this the whole time.

Details, the settings-precedence gotcha, and rule syntax in
[`docs/claude-code-local-setup.md`](docs/claude-code-local-setup.md).

---

## Requirements

- **Windows script:** PowerShell 5.1+ (ships with Windows 10/11). No modules to
  install. Run as Administrator for serial numbers and full disk detail.
- **Linux script:** bash, plus `dmidecode`, `pciutils`, `util-linux` for full
  output. Degrades gracefully without them.
