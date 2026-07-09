# Fika for iOS

A native SwiftUI companion for **[Fika](https://github.com/Arsenije/Fika)** — the quiet,
local-first memory for the people in your life. This app is a thin client for the Fika
**sidecar** (a FastAPI server that embeds [khora](https://github.com/DeytaHQ/khora)) running
on your Mac. The phone and the desktop app talk to the **same** server, so they share one
database and namespace and stay in sync automatically.

```
iPhone (this app)  ─┐
                    ├─ HTTP over your Wi-Fi ─▶  Fika sidecar on your Mac  ─▶  khora (embedded)
Fika desktop app   ─┘
```

There are no accounts and no cloud — it's just you and your Mac on the same network.

## What's here

- **Home** — a serendipity feed: someone to think of today, people to reach out to, and
  "you both love X" connections.
- **People** — everyone you've added, each with a profile, moments timeline, interests/places,
  related people, reminders, and a photo.
- **Add a person** — a short guided flow (name → how you know them → a few tailored questions →
  three words), with voice input.
- **Ask** — grounded Q&A over your own notes ("who's into running?", "when did I last see Maya?"),
  a "Teach Fika this" card when it doesn't know yet, and "remind me to…" capture.
- **Reminders** — person-linked nudges.
- **Settings** — your Mac's address, connection status, OpenAI spend, your own "me" profile, and
  the memory toggle.
- **Voice + photos** — dictate moments (transcribed by the server) and set per-person avatars.

## Setup

### 1. Run the Fika server on your Mac

In your [Fika](https://github.com/Arsenije/Fika) checkout (needs the LAN-server change):

```bash
scripts/serve.sh              # 0.0.0.0:8765, always reachable while it runs
# or install it always-on:
scripts/install-service.sh
ipconfig getifaddr en0        # note your Mac's LAN IP, e.g. 192.168.1.4
```

### 2. Build the app

- Open `Fika-iOS.xcodeproj` in **Xcode 16+**.
- Set your signing team on the **Fika** target (Signing & Capabilities → Team). The bundle id
  is `com.arsenije.fika` — change it if that id is taken on your account.
- Pick your iPhone (or a Simulator) and **Run**.

> The project uses Xcode 16 filesystem-synchronized groups: everything under `Fika/` is compiled
> automatically, so you never hand-edit the project to add a file.

### 3. Connect

Open the **Settings** tab and enter your Mac's IP and port (`8765`), then **Test connection**.
If you set `FIKA_TOKEN` on the server, put the same value in the Token field.

## Notes

- **Same Wi-Fi.** The phone must be on the same network as your Mac. On first connect, iOS asks
  for Local Network permission — allow it.
- **Simulator** talks to the Mac too; `127.0.0.1` also works from the Simulator since it shares
  the host, but using the LAN IP is simplest and matches a real device.
- **No HTTPS.** This is a local prototype; App Transport Security is relaxed for plaintext LAN
  traffic (see `Fika/Info.plist`). Don't ship this as-is to the App Store without adding TLS/auth.
- **Single writer.** Run only one sidecar against the data dir at a time — the desktop app
  detects and reuses the standalone server rather than starting a second one.
