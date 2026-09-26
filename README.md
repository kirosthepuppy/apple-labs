# Apple Labs

A bootstrapper and launcher for Roblox on macOS and Windows, in the spirit of Bloxstrap
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
- **A launcher app, Apple Labs.** `register` installs `~/Applications/Apple Labs.app`
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
  https://raw.githubusercontent.com/kirosthepuppy/apple-labs/main/Apple%20Labs
chmod +x ~/.local/bin/roblox-bootstrapper

roblox-bootstrapper install     # download and install Roblox
roblox-bootstrapper register    # optional: send roblox:// links through the bootstrapper
```

If your shell can't find `roblox-bootstrapper`, add `~/.local/bin` to your PATH:
`echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc`, then open a new terminal.

(Or just clone the repo and run `./Apple\ Labs`.)

## The launcher app (Apple Labs)

A dark, toy-like launcher: a sidebar with a sliding selection,
chunky 3D buttons that press in and spring back, and a slowly drifting grid of
Roblox-style studs over coloured glows. Every continuous animation runs on
Core Animation, so it idles at ~0% CPU, and Reduce Motion is respected.

| Section  | What it does |
|----------|--------------|
| Play     | Greets you with your Roblox avatar, shows your last game's artwork and live player count with a big Play button that rejoins it (with update progress and a confetti burst), a "Jump back in" row of recent games, and your loadout at a glance. |
| Graphics | **Presets** (Roblox default, Balanced, Performance, Quality, Potato, with speed/looks meters), **Engine** settings (anti-aliasing, textures, grass, sky), and a full **FastFlags** editor with search and JSON import/export (works with Bloxstrap/Fishstrap exports; flags Roblox ignores are marked). Roblox only reads [allowlisted FastFlags](https://devforum.roblox.com/t/allowlist-for-local-client-configuration-via-fast-flags/3966569) since September 2025, so the frame rate is set in Roblox's own menu. |
| Style    | **Cursor** (default, classic arrow, or your own image, with a live preview), **Font** for the game (any .ttf/.otf on your Mac, each shown in its own typeface), **Sound** (default, classic "oof", or your own, with previews), and the **Files** mods folder. |
| Launcher | **Look**: themes (Glass, Obsidian, Neon, Lava, Mint, Arctic, Sakura, or Custom with your own colours, an optional background picture (with dim and blur) and a "Surprise me" button), the launcher's font (Avenir Next, SF Pro, Futura, Gill Sans, SF Rounded, SF Mono), interface size (80–130%, also ⌘+ / ⌘− / ⌘0), and motion. **Accounts**: switch Roblox accounts. **General**: close on launch (off by default, so the launcher stays open while you play), website links, recent games, channel, install location, build, reinstall. **Help**. |

The **Glass** theme makes the window see-through, with your desktop frosted
behind it.

### Account switching

Click your account at the bottom of the sidebar to switch accounts. A saved account
is a copy of the Roblox app's own sign-in (its cookie jar), kept only on this
Mac in the launcher's data folder with owner-only permissions; switching swaps
it in while Roblox is closed. The launcher never sees your password, and
removing an account only makes the launcher forget it. **Add account** saves
the current account, signs the Roblox app out on this Mac and opens it so you
can sign in to another one; it's saved when you quit Roblox. The same works
from Terminal with `roblox-bootstrapper accounts`. Website Play buttons use
whichever account is signed in on roblox.com in your browser.

Recent games come from Roblox's own log files on your Mac; their names,
pictures and player counts come from Roblox's public web APIs. Turn this off
under Launcher › General. ⌘1–⌘4 switch sections.

When you click **Play** on the Roblox website, the launcher shows a small
progress window, updates and applies your mods and flags, then hands the game
link to Roblox and quits.

`register` downloads the app from this repo's
[releases](https://github.com/kirosthepuppy/apple-labs/releases). To build
it yourself (needs the Xcode command line tools):

```sh
app/build.sh --install
```

Without the app, `register --applet` installs a tiny AppleScript link handler
instead.

## Windows

Apple Labs also runs on Windows 10 and 11: the same launcher (sidebar, themes
including Glass and Custom with a background picture, Play card, recent games,
graphics presets and FastFlags, cursor/font/death-sound mods, account
switching) as a single `Apple Labs.exe`. It needs nothing else installed.

1. Download `Apple-Labs-Windows.zip` from the
   [releases](https://github.com/kirosthepuppy/apple-labs/releases) and unzip it.
2. Run `Apple Labs.exe`. It copies itself to `%LocalAppData%\AppleLabs`, adds
   Start menu and desktop shortcuts and an entry in Settings › Apps, and takes
   over Play buttons on roblox.com (turn that off in Launcher › General).
   Windows SmartScreen may warn that it doesn't recognise the app: choose
   **More info**, then **Run anyway**.

Roblox itself is downloaded straight from Roblox's servers into
`%LocalAppData%\AppleLabs\Versions`, with your FastFlags and mods written in
before every launch. Uninstall from Settings › Apps or Launcher › General.

To build it yourself (on Windows, macOS or Linux, with the .NET SDK):

```sh
dotnet build windows/AppleLabs.csproj -c Release
```

`AppleLabs.exe --cli help` lists commands for scripting it.

## Usage

```
roblox-bootstrapper install [--force]     Install Roblox, or update it
roblox-bootstrapper launch [roblox-link]  Update if needed, apply flags, start Roblox
roblox-bootstrapper status                Installed vs. latest version, settings

roblox-bootstrapper fflags list
roblox-bootstrapper fflags set FIntDebugForceMSAASamples 4
roblox-bootstrapper fflags unset FIntDebugForceMSAASamples
roblox-bootstrapper fflags import flags.json
roblox-bootstrapper fflags edit | clear | apply

roblox-bootstrapper mods list | apply | clear | path

roblox-bootstrapper accounts [list] | save | add
roblox-bootstrapper accounts use <name> | remove <name>

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
5. `register` installs the launcher app at `~/Applications/Apple Labs.app` (moving
   one installed under its old name, `Roblox Bootstrapper.app`) and makes it the default handler for the Roblox URL schemes. The app carries
   its own copy of the script, which does all the work. The `--applet` fallback
   instead calls the script by its path, so re-run `register` if you move it.

Changing files inside `Roblox.app` invalidates its bundle seal (the same is
true of Bloxstrap-style FastFlags on macOS); Roblox still starts normally.
