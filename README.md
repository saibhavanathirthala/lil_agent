# lil agents

![lil agents](hero-thumbnail.png)

Tiny AI companions that live on your macOS dock.

**Bruce** and **Jazz** walk back and forth above your dock. Click one to open a Claude terminal. They walk, they think, they vibe.

## features

- Animated characters rendered from transparent HEVC video
- Click a character to chat with Claude in a themed popover terminal
- Strict permissions — every tool action requires explicit Allow/Deny in the app
- Four visual themes: Peach, Midnight, Cloud, Moss
- Slash commands: `/clear`, `/copy`, `/help` in the chat input
- Copy last response button in the title bar
- Thinking bubbles with playful phrases while Claude works
- Sound effects on completion
- First-run onboarding with a friendly welcome

## requirements

- macOS Sonoma (14.0+) — including Sequoia (15.x)
- Apple Silicon Mac (arm64)
- [Claude Code](https://claude.ai/download) CLI installed and logged in:
  ```bash
  brew install --cask claude-code
  claude auth login
  ```

## building

Open `lil-agents.xcodeproj` in Xcode and hit run.

## privacy

lil agents runs entirely on your Mac.

- **Your data stays local.** The app plays bundled animations and calculates your dock size to position the characters. No project data, file paths, or personal information is collected or transmitted by the app.
- **Claude Code.** Conversations are handled by the Claude CLI running locally on your machine. lil agents does not intercept, store, or transmit your chat content. Any data sent to Anthropic is governed by their terms and privacy policy.
- **Authentication.** Claude login is managed by the Claude CLI (`~/.claude`), not stored in this app.
- **No analytics.** No login, no user database, no analytics in the app.

## license

MIT License. See [LICENSE](LICENSE) for details.
