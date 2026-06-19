# lil agents

![lil agents](hero-thumbnail.png)

Tiny AI companions that live on your macOS dock.

**Bruce** and **Jazz** walk back and forth above your dock. Click one to open a Claude terminal. They walk, they think, they vibe.

## features

- Animated characters rendered from transparent HEVC video
- Click a character to chat with Claude in a themed popover terminal
- **Jazz** — manual reminders plus **Google Calendar alerts 10 min before meetings**
- **Bruce** — Claude AI chat with strict Allow/Deny permissions
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

### Google Calendar (Jazz) — one-time developer setup

Jazz reads your primary Google Calendar to alert you 10 minutes before meetings.

**Google Cloud (once):**

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project and enable **Google Calendar API**.
2. Create an **OAuth client ID** (type: **Desktop app**).
3. Add authorized redirect URI: `http://127.0.0.1`
4. Go to **Audience** and add your Gmail address(es) as **Test users**.

**Before building the app:**

1. Copy `LilAgents/GoogleOAuthSecrets.example.plist` to `LilAgents/GoogleOAuthSecrets.plist`
2. Paste your **Client ID** and **Client Secret** into that file
3. Build in Xcode (the plist is bundled into the app — never commit it to git)

**In the app:** click Jazz, then **Connect Google Calendar**, then sign in. No paste fields.

OAuth tokens are stored in your Mac Keychain. Only calendar read access is requested.

## building

Open `lil-agents.xcodeproj` in Xcode and hit run.

## privacy

lil agents runs entirely on your Mac.

- **Your data stays local.** The app plays bundled animations and calculates your dock size to position the characters. No project data, file paths, or personal information is collected or transmitted by the app.
- **Claude Code.** Conversations are handled by the Claude CLI running locally on your machine. lil agents does not intercept, store, or transmit your chat content. Any data sent to Anthropic is governed by their terms and privacy policy.
- **Google Calendar.** If you connect Google Calendar, Jazz reads upcoming events from Google's API using OAuth. Event data is used only for local alerts and is not stored or sent elsewhere.
- **Authentication.** Claude login is managed by the Claude CLI (`~/.claude`), not stored in this app. Google OAuth tokens are stored locally on your Mac (UserDefaults).
- **No analytics.** No login, no user database, no analytics in the app.

## license

MIT License. See [LICENSE](LICENSE) for details.
