# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Building

Open `lil-agents.xcodeproj` in Xcode and build the `LilAgents` scheme. No command-line build system is configured.

## Architecture Overview

This is a macOS AppKit application that displays animated characters walking on the Dock, providing a GUI for Claude Code CLI.

### Core Components

**`LilAgentsController`** — Central coordinator running a `CVDisplayLink` tick loop. Calculates Dock geometry from `com.apple.dock` defaults, positions characters above the Dock area.

**`WalkerCharacter`** — Individual character with:
- AVPlayerLayer for transparent HEVC video animation
- Per-character `size` stored in UserDefaults (`"{name}Size"`)
- Manages popover terminal window and Claude session lifecycle

**`ClaudeSession`** — Claude Code CLI interaction via NDJSON streaming (`--output-format stream-json`). Strict permission mode with in-app Allow/Deny prompts via `--permission-prompt-tool stdio`.

**`ShellEnvironment`** — Resolves user's login shell PATH via `/bin/zsh -l -i -c env` to locate the `claude` binary. Caches results. Removes `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT` from spawned process environment to prevent nested session detection.

**`TerminalView`** — AppKit view rendering themed terminal with basic Markdown support, permission bar, and auto-scrolling.

**`PopoverTheme`** — Centralized styling (colors, fonts) for terminal UI.

### Key Patterns

- **Dock positioning**: Reads `tilesize`, `persistent-apps`, `persistent-others`, `show-recents` from `com.apple.dock` defaults to calculate Dock width
- **Window level**: Characters use `NSWindow.Level.statusBar + i` where i is sorted by x-position
- **CLI discovery**: `ShellEnvironment.findBinary()` checks shell PATH first, then fallback paths like `~/.local/bin`, `/opt/homebrew/bin`
- **Per-character config**: Each WalkerCharacter persists its size via UserDefaults with name-prefixed keys
