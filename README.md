# SameSide

Click an app in the Dock and its window on *that* screen comes forward, instead of the one you used last. Click again to go to its window on the other screen. Works with full-screen windows and windows on other desktops (Spaces): SameSide switches that screen to the right desktop. If the app has no window on that screen, macOS behaves as usual.

Unlike tools that drag your windows across screens, SameSide never moves anything. It brings up the window that's already on the screen you're using.

Website: [kartiksaxena.com/sameside](https://www.kartiksaxena.com/sameside)

A tiny menu bar app: about 10 MB of memory, no CPU while idle, no network, nothing stored. macOS 14 or later, Apple silicon and Intel.

## Install

### Option A: download

1. Download `SameSide.dmg` from [Releases](https://github.com/karticksaxena/SameSide/releases/latest).
2. Open it and drag **SameSide** onto **Applications**.
3. Open SameSide from Applications. macOS says **"SameSide" Not Opened**. Click **Done** (not Move to Bin).
   This happens because SameSide is free and not registered with Apple's paid developer program; the full source is in this repository.
4. Open **System Settings › Privacy & Security**, scroll down to **"SameSide" was blocked…** and click **Open Anyway**, then confirm. macOS only asks this once.
5. When asked, allow SameSide in **Privacy & Security › Accessibility** (on macOS 27 the list is titled "Device Control and Data Access").
6. To start it at login: **System Settings › General › Login Items › Open at Login › +** › SameSide. Leave SameSide switched on under **Background App Activity** too.

### Option B: build it yourself (no warning)

Needs only Apple's Command Line Tools (`xcode-select --install`), not Xcode.

```sh
git clone https://github.com/karticksaxena/SameSide.git
cd SameSide
./build.sh
ditto build/SameSide.app /Applications/SameSide.app
open /Applications/SameSide.app
```

Then do steps 5 and 6 above. Or paste this into an AI coding assistant (Claude Code, Codex, Cursor and the like):

> Clone https://github.com/karticksaxena/SameSide, read its README, build it with `./build.sh`, copy `build/SameSide.app` to /Applications and open it. Do not change any code.

## Uninstall

1. Menu bar icon › **Quit SameSide**.
2. Delete `/Applications/SameSide.app`.
3. Remove it from **System Settings › General › Login Items**.
4. Remove its permission: select it in the Accessibility list and click **−**, or run `tccutil reset Accessibility io.github.karticksaxena.SameSide`.

SameSide stores nothing else, so that is everything.

## Privacy

- **No network.** SameSide contains no networking code and never connects anywhere. Check with any firewall such as LuLu or Little Snitch.
- **Nothing stored.** No files, no settings, no keychain items.
- **What it reads, only while handling a Dock click:** which Dock icon is under the pointer, and the position and desktop of that app's windows. Never window titles, window contents or the screen; it does not need Screen Recording permission.
- **Logs:** one debug line per Dock click (app name, screen number). macOS does not keep debug lines; they are only visible while someone runs the `log stream` command below.
- **Accessibility permission** is used only to see clicks before the Dock and to read and focus windows. Clicks are always passed on unchanged.

## Quitting, and changing its permission safely

SameSide has no Dock icon; quit it from its menu bar icon › Quit SameSide.

Always quit it **before** you turn its Accessibility switch off, remove it from that list, or run `tccutil reset`. It watches every click, and taking the permission away while it runs can leave clicks not working until it quits. If that happens, use the keyboard: press ⌘-Space, type Terminal, press Return, then run `pkill -x SameSide`.

## How it works, and what can break

- A click watcher sees each left click before the Dock does and always passes it on unchanged.
- On a running app's Dock icon, SameSide finds the app by its bundle identifier (never by name), lists its windows on every desktop, picks the one on the clicked screen, and focuses it.
- It acts when you press, so long-pressing or dragging a running app's Dock icon also switches to that app's window.
- Focusing a window on another desktop needs private macOS functions, the same ones AltTab and yabai use (`sources/SkyLight.swift`). They are looked up when SameSide starts: if a macOS update removes one, SameSide logs which one, stops switching windows instead of failing to launch, and the Dock behaves as usual. (A function that still exists but changed how it works could misbehave; that is the risk of private functions.)

## If it stops working after a macOS update

First check that the SameSide icon is in the menu bar and its Accessibility switch is on.
Then watch its decisions and click a Dock icon:

```sh
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "io.github.karticksaxena.SameSide"'
```

(Use the full path: in zsh, `log` alone is a different built-in command.) To see whether a macOS update removed a private function SameSide needs:

```sh
/usr/bin/log show --last 1d --predicate 'subsystem == "io.github.karticksaxena.SameSide" AND messageType == error'
```

- No line at all: the Dock click was not recognised (see `dockApp` in `sources/System.swift`).
- "0 windows": the window list came back empty (see `appWindows` in `sources/System.swift`).
- "NOT focused", or the right display named but nothing switches: see `focus` in `sources/SkyLight.swift`.

## Development

`./build.sh` runs the self-check in `tests/` and builds `build/SameSide.app`; `./build.sh dmg` also makes the installer (Finder arranges its window, so allow Terminal to control Finder once). `swift tools/make-assets.swift` redraws the icon and installer background.

### Keep the permission across rebuilds

With the default ad-hoc signature every build counts as a new app and loses its Accessibility permission. Create a local signing certificate once:

```sh
cd "$(mktemp -d)"   # keep the key files out of the repo
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 \
  -subj "/CN=SameSide Dev" -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning"
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "SameSide Dev" -out dev.p12 -passout pass:sameside
security import dev.p12 -k ~/Library/Keychains/login.keychain-db -P sameside -T /usr/bin/codesign
rm key.pem cert.pem dev.p12
cd -
```

(Use `/usr/bin/openssl`: a Homebrew OpenSSL 3 writes a file format `security import` may reject.)

Then build with `SIGN_ID="SameSide Dev" ./build.sh`. Grant the permission once more after the first signed build; later builds keep it. Without the certificate, after each rebuild: quit SameSide, run `tccutil reset Accessibility io.github.karticksaxena.SameSide`, copy the new build to /Applications, open it and grant permission again.
