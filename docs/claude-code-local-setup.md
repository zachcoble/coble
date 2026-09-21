# Running Claude Code locally with full agent powers

## The problem this solves

There are two very different places Claude Code can run, and they have
different powers:

| | Claude Code on the web / in a cloud session | Claude Code CLI on your machine |
|---|---|---|
| Where it runs | Ephemeral Linux container in Anthropic's cloud | Your actual PC |
| Can see your hardware | **No** | **Yes** |
| Can read your files | Only what's in the cloned repo | Anything you point it at |
| Can run commands on your PC | **No** | **Yes** |
| Survives after the session | Only what got pushed to git | Everything, it's your disk |

If you ask a cloud session "what CPU do I have," it will answer honestly about
a container: some shared Xeon with 4 vCPUs. That is the hypervisor's hardware,
not yours. It is the same category of mistake as running `lscpu` inside a VM
and thinking you learned something about the host.

**To get an agent that can inventory your own PC, you need the CLI installed
locally.**

## Install

### Windows (native) - recommended for this use case

```powershell
irm https://claude.ai/install.ps1 | iex
```

Or via WinGet (does not auto-update; you run `winget upgrade
Anthropic.ClaudeCode` yourself):

```powershell
winget install Anthropic.ClaudeCode
```

Then:

```powershell
claude
```

First launch opens a browser to log in. Works with a Pro or Max subscription -
same account as the web app, no separate API key needed. No Administrator
rights needed to install.

Verify:

```powershell
claude --version
claude doctor    # read-only diagnostics: install health, settings errors
```

#### Install Git for Windows too

[Git for Windows](https://git-scm.com/downloads/win) is optional but worth
having. It decides which shell the agent gets:

- **Without it:** Claude Code runs commands through the **PowerShell tool**.
- **With it:** Claude Code uses Git Bash for the **Bash tool**, and the
  PowerShell tool stays available alongside it.

For this repo's work you want both - PowerShell to reach WMI and the hardware,
Bash for everything else. If Claude Code can't find Git Bash, point it at the
path in `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe"
  }
}
```

### WSL2 - only if you're doing Linux development

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

> **Careful:** WSL2 is a lightweight VM. An agent running inside WSL sees
> *virtualized* hardware, so `dmidecode` and friends report the VM, not your
> laptop. Same trap as the cloud container. If the job is "inventory this PC,"
> install on native Windows and let it drive PowerShell.

One real advantage WSL2 has: it supports Claude Code's **sandboxing**, and
native Windows does not. So the tradeoff is reach versus containment - native
Windows can touch your actual hardware, WSL2 can be locked down harder. For
hardware work, take native.

### macOS / Linux

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

## Permission modes - the "take over" setting

This is the part you were asking about. A permission mode controls how much
Claude does without stopping to ask you.

| Mode | What runs without asking |
|---|---|
| `default` (shown as **Manual**) | Prompts on first use of each tool |
| `acceptEdits` | Auto-accepts file edits and routine filesystem commands (`mkdir`, `mv`, `cp`, `touch`) inside your working directory |
| `plan` | Reads and explores, never edits your source |
| `auto` | Auto-approves tool calls, with a second model doing background safety checks |
| `dontAsk` | Auto-denies anything that would prompt |
| `bypassPermissions` | Skips prompts entirely |

**On Pro, Max, and Team plans, sessions already start in `auto` mode.** So you
may already have most of what you were reaching for. `auto` is the sweet spot:
it does not stop you every thirty seconds, but a classifier still reviews
actions against what you actually asked for.

### Switching modes

Three ways, in order of how often you'll use them:

1. **`Shift+Tab` in the CLI** - cycles through modes mid-session. This is the
   one to learn.
2. **`--permission-mode` at launch:**
   ```powershell
   claude --permission-mode acceptEdits
   claude --permission-mode auto
   ```
3. **`defaultMode` in a settings file** - makes it stick for every session.

### About `bypassPermissions`

It is the "no seatbelt" mode. It skips prompts including writes to protected
paths like `.git` and `.claude`. The docs are explicit that it is for isolated
environments - containers, throwaway VMs - not your daily driver.

As someone heading toward security work: the instinct to reach for the setting
that stops the prompts is the same instinct that ends up with `Domain Admin` on
a service account. `auto` gives you the speed without the blast radius. Use it.

## Settings files and precedence

Highest wins:

1. Managed settings (your org, via MDM)
2. `claude --settings` (one session)
3. `.claude/settings.local.json` (you, this project - gitignored)
4. `.claude/settings.json` (shared with the repo)
5. `~/.claude/settings.json` (you, every project)

**Gotcha worth knowing:** `auto` and `bypassPermissions` are ignored when set
in project or project-local settings. They only take effect from user settings
(`~/.claude/settings.json`) or managed settings, or from the
`--permission-mode` flag. This is deliberate - it stops a repo you cloned from
silently turning off your safety rails. `acceptEdits` has no such restriction.

## Using the settings template in this repo

[`templates/claude-settings.json`](../templates/claude-settings.json) is a
starting point: `acceptEdits` by default, an allowlist of read-only diagnostic
commands, and a denylist for secrets and destructive operations.

```powershell
# Per project
mkdir .claude
copy templates\claude-settings.json .claude\settings.json

# Or globally, for every project
copy templates\claude-settings.json $env:USERPROFILE\.claude\settings.json
```

Settings files are **strict JSON**. A `//` comment or a trailing comma is a
syntax error and Claude Code will report the file as broken at next start.
Run `/status` inside a session to confirm what actually loaded.

## Permission rule syntax

Rules are `Tool` or `Tool(specifier)`:

| Rule | Effect |
|---|---|
| `Bash` or `Bash(*)` | All Bash commands |
| `Bash(git log:*)` | Any `git log` command |
| `Bash(npm run build)` | Only that exact command |
| `Read(./.env)` | Reading `.env` in the current directory |
| `WebFetch(domain:example.com)` | Fetches to that domain |

**Put the `*` after the subcommand.** Everything before the first `*` is matched
literally, so `Bash(git *)` allows *every* git command including `git push
--force`, while `Bash(git log *)` allows only `git log`. Claude Code warns at
startup about an allow rule with a wildcard before the subcommand.

This is ordinary allowlist design - the same reasoning as a firewall rule or an
IAM policy. Be specific on the left of the wildcard.

## Commands worth knowing

| Command | What it does |
|---|---|
| `/permissions` | Inspect and edit permission rules interactively |
| `/status` | What settings, model, and account loaded |
| `/config` | Theme, editor mode, verbose output |
| `/model` | Switch models |
| `claude doctor` | Diagnose a broken config |
| `/login` / `/logout` | Re-authenticate |

## Sanity check after install

```powershell
claude --version
claude
```

Then at the prompt, hand it the real task:

```
Run .\scripts\Get-PCSpecs.ps1 and tell me which RAM I should buy.
```

That is the difference between the two setups. A cloud session cannot run that
against your hardware. A local session can.
