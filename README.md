# Ensachage 🍏

A macOS **menu-bar background agent** that watches the real **lock screen**.
Every time someone **fails to unlock** your Mac, it silently captures a webcam
photo of whoever is at the keyboard and records it in a journal. Click any
journal line to open its detail and view the captured photo.

## Requirements

- macOS 14+
- Xcode 16+ (developed with Xcode 26)
- A Mac with a camera

## Build & run

```sh
make run      # build (Debug) and launch the agent (icon appears in the menu bar)
make build    # build only
make release  # build the Release configuration
make clean    # remove ./build
make open     # open the project in Xcode
make reset    # wipe saved settings, journal and photos
```

`make run` signs with automatically-managed signing (team `J88M2A5FAK`,
bundle id `com.darkweak.ensachage.app`).

> The app is an **agent** (`LSUIElement`): it launches with **no Dock icon** —
> look for the 🛡️ lock icon in the menu bar (open the journal, toggle monitoring,
> take a test photo, open Settings, quit). The **Dock icon appears while the
> journal or Settings window is open** and disappears again when you close them
> (the app switches its activation policy between `.regular` and `.accessory`).

## How failed-unlock detection works

macOS exposes **no public API** for "the user mistyped the lock-screen password",
so `LockMonitor` combines two public signals:

1. **Screen-lock state** — the `com.apple.screenIsLocked` /
   `com.apple.screenIsUnlocked` distributed notifications.
2. **Unlock authentication failures** — a live stream of the unified log
   (`/usr/bin/log stream --level info`). By **default** it matches a single,
   verified, failure-only signature: a **wrong password** at the lock screen
   (`opendirectoryd`: `ODRecordVerifyPassword failed`). A correct password logs
   *succeeded*, and **locking / display sleep log nothing** — so none of those
   take a photo.

A log match counts as an intrusion **only while the screen is locked**, which
filters out unrelated auth failures (sudo, ssh…). Matches are debounced (2 s) so
one mistyped password yields one event → one photo.

> **Fingerprint & YubiKey PIN are opt-in (experimental).** Their log text is
> hardware/OS-specific and the biometric subsystem emits readiness noise around
> lock/display-sleep, which can cause false photos. Enable from **Settings ▸
> Avancé ▸ "Inclure empreinte + code PIN"**, then tune with `make watch-auth`
> (fail an unlock with that method and paste the matching line into the predicate
> box). Because the agent spawns `/usr/bin/log`, the **App Sandbox is disabled**.

## Project layout

| Concern | File | Notes |
|---|---|---|
| App entry / scenes | `EnsachageApp.swift` | `MenuBarExtra` + `Window` + `Settings`; bootstraps on launch |
| Menu bar dropdown | `Views/MenuContent.swift` | status, toggle, open journal, test, quit |
| Coordinator | `Models/AppModel.swift` | `@MainActor @Observable`; ties everything together |
| Lock detection | `Services/LockMonitor.swift` | lock state + unified-log streaming |
| Camera | `Services/CameraCapture.swift` | AVFoundation single-frame capture |
| E-mail alerts | `Services/SMTPClient.swift`, `Services/Keychain.swift` | background SMTP-over-TLS + Keychain password |
| Apple Mail send | `Services/MailAppSender.swift` | scripts Mail.app using a configured account (no credentials) |
| iMessage alerts | `Services/IMessageSender.swift` | scripts Messages.app via `osascript` (best-effort) |
| Settings | `Models/AppSettings.swift` | `UserDefaults`-backed, saved on every change |
| Journal store | `Models/LogStore.swift` | JSON + photos in Application Support |
| Journal / detail | `Views/MainView.swift`, `HistorySidebar.swift`, `LogDetailView.swift` | click a line → see the photo |
| Preferences | `Views/SettingsView.swift` | monitoring, capture, login item, predicate |

### Data locations (sandbox disabled)

```
~/Library/Application Support/Ensachage/
├── history.json        # the journal
└── Images/<uuid>.jpg   # one photo per failed unlock
```

Settings live in `UserDefaults` for `com.darkweak.ensachage.app`.

## First launch & permissions

- **Camera permission is requested on the first launch** (the system prompt).
  Re-grant later from the orange banner in the journal window or **Settings ▸
  Général**.
- Monitoring needs to read the system log; macOS may prompt the first time the
  agent streams it. Grant access for detection to work.
- Optional: **Settings ▸ Général ▸ "Lancer à l'ouverture de session"** registers
  the agent as a login item (via `SMAppService`).

## Sending an event to the owner

Open the journal, select an event, and use the actions above the photo:

- **Partager (AirDrop, Mail…)** — opens the macOS share sheet with the captured
  photo attached, so you can **AirDrop** it to another device, send it by **Mail**,
  Messages, save to Notes, etc.
- **Envoyer au propriétaire** — one click opens a **pre-addressed e-mail** (with
  the photo attached) to the address set in **Settings ▸ Général ▸ Propriétaire**.
  Falls back to a `mailto:` compose window if Mail has no account configured.

> The share sheet / "Envoyer au propriétaire" buttons are a **review-and-send**
> action you trigger from the journal. AirDrop inherently needs the picker UI and
> a nearby device, so it can't be automated.

## Automatic e-mail alerts (SMTP)

For a hands-off alert that fires **even while the screen is locked**, Ensachage
can e-mail the owner automatically on each failed unlock, with the photo
attached. Set the owner's address in **Settings ▸ Général ▸ Propriétaire**, then
in **Settings ▸ E-mail** pick a **sending method**:

**A. Apple Mail account (no credentials)** — reuse an account already configured
in the Mail app:

1. Choose **Méthode d'envoi → Compte Apple Mail**. This requests the **Mail
   Automation permission** (approve it while unlocked).
2. Click **Rafraîchir les comptes** and pick the address to **send from**.
3. Click **Envoyer un e-mail de test**, then enable auto-notify.

Mail's own account settings handle delivery — nothing is stored by Ensachage.

**B. Direct SMTP** — a built-in SMTP-over-TLS client (no Mail app involved):

1. Choose **Méthode d'envoi → Serveur SMTP**.
2. Fill in **server**, **port** (465, implicit TLS), **username**, **password**.
   - Gmail: `smtp.gmail.com` + a **Google App Password**.
   - iCloud: `smtp.mail.me.com` + an **app-specific password**.
3. Click **Envoyer un e-mail de test**, then enable auto-notify.

> 🔒 The SMTP password is stored in the **macOS Keychain**, never in plain
> settings. Only implicit TLS (port 465) is supported — `NWConnection` cannot
> upgrade a plaintext connection to STARTTLS mid-stream. Network access works
> because the app runs **without the sandbox**.

## Automatic iMessage alerts (best-effort)

Ensachage can also send an **iMessage** (with the photo) to the owner's phone /
iMessage address on each failed unlock. Configure it in **Settings ▸ iMessage**:
enter the number/address and enable the toggle.

**Enabling the toggle immediately requests the Messages Automation permission**
(via `AEDeterminePermissionToAutomateTarget`) so you can approve it now, while
unlocked — rather than on a later locked-screen failure where the prompt couldn't
be answered. If you deny it, the toggle switches back off with an explanation.

> ⚠️ There is **no public API** to send iMessages — this scripts the Messages
> app via Apple events, which Apple has been **deprecating**. It requires:
> - Messages signed into the owner's iMessage account on this Mac,
> - a one-time **Automation** permission ("Ensachage → control Messages",
>   under System Settings ▸ Privacy & Security ▸ Automation),
> - and it may silently fail on the newest macOS.
>
> Sending to your **own** number is fine — it appears as a note-to-self thread on
> all your devices. Because of the deprecation, **e-mail remains the most reliable
> channel**; treat iMessage as a bonus.

## Manual test plan

1. `make reset && make run` — first launch **asks for camera permission**; the
   menu-bar 🛡️ icon appears and the journal window opens once.
2. In the menu, confirm **"Surveillance active"**, then click **"Prendre une
   photo (test)"** → a "Photo de test" entry appears; click it to see the photo
   (verifies the camera path).
3. Lock the screen (Ctrl+Cmd+Q) and type a **wrong** password. Unlock for real.
   → exactly one **"Échec de déverrouillage"** entry (📷), then a
   **"Déverrouillage réussi"** entry. **Locking and the successful unlock take no
   photo.** Click the failure → photo.
4. Lock the screen and **do nothing** (or just wait past display sleep), then
   unlock correctly → **no photo** is taken.
5. For **fingerprint / YubiKey PIN**: enable the experimental option in
   **Settings ▸ Avancé**, then if a real failure isn't detected, run
   `make watch-auth`, fail an unlock with that method, and paste the captured line
   into the predicate box → **Appliquer**.
6. **Auto e-mail:** configure **Settings ▸ E-mail**, click **Envoyer un e-mail de
   test** (expect a ✓), enable auto-notify, then fail a real unlock → the owner
   receives an e-mail with the photo, even with the screen locked.
6. Toggle settings, quit, relaunch → settings are remembered.
