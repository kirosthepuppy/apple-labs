# macOS Roblox Bootstrapper

A bootstrapper and launcher for Roblox on macOS, in the spirit of Bloxstrap
and Fishstrap. The core is a single, dependency-free bash script that uses only
tools that ship with macOS (`curl`, `ditto`, `osascript`, `PlistBuddy`); an
optional native SwiftUI launcher app sits on top of it.

- **Installs and updates Roblox** directly from Roblox's CDN, choosing the
  native Apple Silicon or Intel build automatically.
- **FastFlags that stick.** Your flags are stored separately and written back
  into `Roblox.app` after every update, so updates no longer wipe them.
- **Handles website links.** `register` makes `roblox://` / `roblox-player://`
  links go through the bootstrapper, so joining from the browser also updates
  Roblox and applies your flags first.
- **A launcher app.** `register` installs `~/Applications/Roblox Bootstrapper.app`
  (with the Roblox icon): a window with a Launch button, mods, FastFlags and
  settings. Keep it in the Dock instead of Roblox so every launch updates first.
- **Mods.** Classic "oof" death sound, classic or custom mouse cursor, a custom
  font for all in-game text, and a mods folder for replacing any other file.
  Mods are re-applied after every update and removed cleanly.
- **Channels.** Can follow a non-LIVE deployment channel if you have access to one.

## Install

```sh
mkdir -p ~/.local/bin
curl -fsSL -o ~/.local/bin/roblox-bootstrapper \
  https://raw.githubusercontent.com/kirosthepuppy/macOS-bootstrapper/main/roblox-bootstrapper
chmod +x ~/.local/bin/roblox-bootstrapper

roblox-bootstrapper install     # download and install Roblox
roblox-bootstrapper register    # optional: send roblox:// links through the bootstrapper
```

If your shell can't find `roblox-bootstrapper`, add `~/.local/bin` to your PATH:
`echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc`, then open a new terminal.

(Or just clone the repo and run `./roblox-bootstrapper`.)

## The launcher app

A dark, glassy launcher with a drifting colour background and springy
animations throughout (all driven by Core Animation, so it idles at ~0% CPU;
Reduce Motion is respected).

| Page          | What it does |
|---------------|--------------|
| Home          | Big Play button with live update progress, the installed version, Restart Roblox after changes, and a "Your setup" overview that links to every page. |
| Presets       | One-click graphics profiles: Roblox default, Balanced, Performance, Quality and Potato. |
| Cursor        | Default, the classic black arrow, or your own image, with previews. |
| Font          | Any .ttf/.otf font on your Mac (searchable, shown in its own typeface) or a font file, with a live preview. |
| Game settings | Frame rate limit, anti-aliasing, texture quality, post-processing, grass and sky, plus a full FastFlag editor with JSON import/export (works with Bloxstrap/Fishstrap exports). |
| Mods          | Death sound (default, classic "oof", or your own, with previews) and the mods folder. |
| Appearance    | Five colour themes and the animated background. |
| Settings      | Close on launch, website links, channel, install location, build, reinstall. |
| Help          | Common questions, the log, and a link to report problems. |

When you click **Play** on the Roblox website, the launcher shows a small
progress window, updates and applies your mods and flags, then hands the game
link to Roblox and quits.

`register` downloads the app from this repo's
[releases](https://github.com/kirosthepuppy/macOS-bootstrapper/releases). To build
it yourself (needs the Xcode command line tools):

```sh
app/build.sh --install
```

Without the app, `register --applet` installs a tiny AppleScript link handler
instead.

## Usage

```
roblox-bootstrapper install [--force]     Install Roblox, or update it
roblox-bootstrapper launch [roblox-link]  Update if needed, apply flags, start Roblox
roblox-bootstrapper status                Installed vs. latest version, settings

roblox-bootstrapper fflags list
roblox-bootstrapper fflags set DFIntTaskSchedulerTargetFps 240
roblox-bootstrapper fflags unset DFIntTaskSchedulerTargetFps
roblox-bootstrapper fflags import flags.json
roblox-bootstrapper fflags edit | clear | apply

roblox-bootstrapper mods list | apply | clear | path

roblox-bootstrapper register [--applet] | unregister
roblox-bootstrapper install-app
roblox-bootstrapper config set INSTALL_DIR ~/Applications
roblox-bootstrapper uninstall [--purge]
```

`fflags set` stores `true`/`false` as booleans and whole numbers as integers;
anything else is stored as a string.

## Settings

| Setting       | Default         | Notes                                              |
|---------------|-----------------|----------------------------------------------------|
| `INSTALL_DIR` | `/Applications` | Use `~/Applications` if you are not an admin.      |
| `ARCH`        | `auto`          | `arm64` or `x86_64` to force a build.              |
| `CHANNEL`     | `LIVE`          | Other channels usually need a Roblox account with access. |

Set them with `config set`, or per run through `ROBLOX_INSTALL_DIR`,
`ROBLOX_ARCH` and `ROBLOX_CHANNEL`.

Everything the bootstrapper keeps (settings, `fflags.json`, a log) lives in
`~/Library/Application Support/RobloxBootstrapper`.

## How it works

1. Asks `clientsettingscdn.roblox.com/v2/client-version/MacPlayer` for the
   current version.
2. If that differs from the installed one, downloads
   `setup.rbxcdn.com/mac[/arm64]/<version>-RobloxPlayer.zip`, extracts it, and
   swaps it in as `Roblox.app` (the old copy is kept until the swap succeeds).
3. Writes your flags to `Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json`.
4. Copies everything in `~/Library/Application Support/RobloxBootstrapper/Modifications`
   over `Roblox.app/Contents/Resources`, backing up each original first so that
   removing a mod puts Roblox's file back. A font at
   `Modifications/content/fonts/CustomFont.ttf` (or `.otf`) is also wired into
   every font family.
5. `register` installs the launcher app at `~/Applications/Roblox Bootstrapper.app`
   and makes it the default handler for the Roblox URL schemes. The app carries
   its own copy of the script, which does all the work. The `--applet` fallback
   instead calls the script by its path, so re-run `register` if you move it.

Changing files inside `Roblox.app` invalidates its bundle seal (the same is
true of Bloxstrap-style FastFlags on macOS); Roblox still starts normally.
