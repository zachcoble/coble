# Agent instructions

- Inspect README, project status, existing implementation, and `git status` first.
- Preserve working functionality and user changes; prefer simple maintainable solutions and few dependencies.
- Fetch and inspect upstream before editing; use `git pull --ff-only` only with a suitable clean working tree. Never discard local work to synchronize.
- Keep credentials, database contents, customer/employer information, and machine-specific caches out of Git. Ignore rules do not remove tracked secrets.
- Run relevant checks, inspect the staged diff, and make small logical commits with descriptive messages (`docs:`, `fix:`, `feat:`, `chore:`).
- Update README/status and architecture notes when needed so another machine can continue without chat history.
- Confirm before writes to GitHub or another shared account unless the user has already authorized that concrete write. New repositories must be private by default.
- Never force-push, rewrite history, change repository visibility, delete significant data, or weaken security without explicit authorization.
- At handoff record completed work, validation, unresolved issues and next steps. Push completed reviewed work only when authorized.

This public repository contains hardware-inventory scripts and documentation. Never commit generated inventory output, serial numbers, credentials, employer information or private infrastructure details. Validate script syntax without performing destructive hardware actions. Preserve its existing default branch.
