# macOS Roblox Bootstrapper

A small, dependency-free bootstrapper for Roblox on macOS, in the spirit of
Bloxstrap. It is a single bash script that uses only tools that ship with
macOS (`curl`, `ditto`, `osascript`, `PlistBuddy`).

- **Installs and updates Roblox** directly from Roblox's CDN, choosing the
  native Apple Silicon or Intel build automatically.
- **FastFlags that stick.** Your flags are stored separately and written back
  into `Roblox.app` after every update, so updates no longer wipe them.
- **Handles website links.** `register` makes `roblox://` / `roblox-player://`
  links go through the bootstrapper, so joining from the browser also updates
  Roblox and applies your flags first.
- **Channels.** Can follow a non-LIVE deployment channel if you have access to one.

## Install

```sh
curl -fsSL -o ~/bin/roblox-bootstrapper \
  https://raw.githubusercontent.com/kirosthepuppy/macOS-bootstrapper/main/roblox-bootstrapper
chmod +x ~/bin/roblox-bootstrapper

roblox-bootstrapper install     # download and install Roblox
roblox-bootstrapper register    # optional: send roblox:// links through the bootstrapper
```

(Or just clone the repo and run `./roblox-bootstrapper`.)

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

roblox-bootstrapper register | unregister
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
4. `register` builds a tiny AppleScript app at
   `~/Applications/Roblox Bootstrapper.app` that forwards links to the script,
   and makes it the default handler for the Roblox URL schemes. It calls the
   script by its path, so re-run `register` if you move the script.
