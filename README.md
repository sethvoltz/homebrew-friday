# homebrew-friday

[Homebrew](https://brew.sh/) tap for [Friday](https://github.com/sethvoltz/friday) — a local-first headless agent daemon with a SvelteKit dashboard.

## Install

```bash
brew install sethvoltz/friday/friday
brew services start friday
```

The formula declares `postgresql@18` and `cloudflared` (recommended) as dependencies; both get installed if missing. First-time install builds Friday's TypeScript + SvelteKit from source (~5–10 minutes). Subsequent `brew upgrade friday` runs pull the latest commit on `main` and rebuild.

## What this tap installs

- `friday` — the CLI (`friday setup`, `friday start`, `friday status`, etc.)
- `friday-supervisor` — the launchd-supervised entrypoint that forks daemon + dashboard + zero-cache as children with proper process-group cascade-stop semantics (see [ADR-028](https://github.com/sethvoltz/friday/blob/main/docs/decisions.md#adr-028) in the source repo).
- A launchd plist (`homebrew.mxcl.friday`) that runs `friday-supervisor` with `RunAtLoad: true` (Friday comes back after reboot) and `KeepAlive` on crash.

## Supervision model

`brew services start friday` brings up:

- **daemon** — `localhost:7610`. Owns the Claude Agent SDK, worker registry, Postgres mutators, SSE channel.
- **dashboard** — `localhost:7615`. SvelteKit + Svelte 5; BetterAuth; the public surface behind the Cloudflare Tunnel.
- **zero-cache** — `localhost:4848`. Rocicorp Zero sync sidecar; internal-only behind the dashboard's `/api/sync` WS proxy.

`brew services stop friday` cascade-stops every descendant in 5 seconds. The FRI-83 zombie failure mode (tmux's `kill-session` leaving worker pools alive) is structurally closed.

cloudflared is supervised separately — `brew services start cloudflared` for the public tunnel, lifecycle independent of Friday's stack.

## Versioning

The formula currently tracks `main`. Tagged releases will be added once the release pipeline lands. `brew upgrade friday` re-pulls and rebuilds.

## Reporting issues

Use [the source repo's issue tracker](https://github.com/sethvoltz/friday/issues), not this tap. The tap is purely a Homebrew packaging surface.
