# Deckshot

A fan-made game heavily inspired by [ROUNDS](https://store.steampowered.com/app/1557740/ROUNDS/) by Landfall Games, built with [LÖVE](https://love2d.org/) 11.5. It's a 2D side-view shooter for 2 to 4 players: when you lose a round, you pick an upgrade card. Cards stack, builds get silly, and the first player to the target score wins.

- **Local play:** 2 players on one keyboard.
- **Online play:** up to 4 players over Steam, joining with a 6-character lobby code.
- **LAN play:** up to 4 players on the same network, no Steam needed. Browsers on the network can join a desktop host.
- **Platforms:** Windows and Linux (64-bit), plus a browser version for local play and joining LAN games.

**▶ Play in your browser: https://distorbed678.github.io/deckshot/** (local 2-player; Steam play needs the desktop version)

> Deckshot started life as "Rounds Clone". It is not affiliated with or endorsed by Landfall Games, the makers of ROUNDS.

## Features

- **100 upgrade cards** across five rarities: 30 common, 26 uncommon, 20 rare, 14 epic and 10 legendary. They include bouncing and exploding bullets, homing, lasers, black holes, orbiting shields, revives, shields, a turret, piercing railgun bolts, mirrored shots and plenty of block abilities.
- **Every card stacks.** Stat cards add up, and ability cards get stronger with each copy (for example more back shots, bigger mine blasts or wider lasers). Each card shows what extra copies do.
- **Blocking reflects bullets** back at the shooter. The *Reflector* card sends extra bullets back.
- **Special cards:** *Reroll* (re-deals your hand), *Table Flip* (rerolls every card you own while keeping their rarities) and *Shrine of Order* (as in Risk of Rain 2: for each rarity, all your cards of that rarity become copies of one of them).
- **25 arenas**, each with spawns for 4 players. Use the map pool to choose which ones appear.
- **Card info in game:** hover a card name under a player's score to see what it does.
- **Card picks in turn order:** every player except the round winner picks, lowest score first. Everyone watches the current picker's hand and sees which card they're hovering.
- **Match flow:** first to N rounds. After a win you can *Continue* (+3 rounds) or start a *New Match*. Online, players vote and the host sees the votes before choosing.
- **Custom rules:** choose how many cards are offered (2–6) and how many picks you get per round (1–5), set the chance of each rarity, use the card pool editor to change any card's rarity or disable it, and use the map pool to turn arenas on or off. **Online, the host's rules are used.**
- **Settings:** window mode, monitor, resolution, VSync (off/on/adaptive), FPS cap, bloom, screen shake, particles and fully rebindable controls.

## Download and install

### Linux (AppImage)

1. Download `Deckshot-x86_64.AppImage` (see [Releases](../../releases), or [build it yourself](#building-releases)).
2. Make it executable and run it:
   ```sh
   chmod +x Deckshot-x86_64.AppImage
   ./Deckshot-x86_64.AppImage
   ```
   If it fails to start because FUSE is missing, run `./Deckshot-x86_64.AppImage --appimage-extract-and-run` instead.

### Windows

1. Download `Deckshot-windows-x64.zip` (see [Releases](../../releases), or [build it yourself](#building-releases)).
2. Unzip it anywhere and run `Deckshot\Deckshot.exe`. Keep the DLLs next to the exe.

### Browser

Open **https://distorbed678.github.io/deckshot/**. Nothing to install. Both players share the keyboard, settings are saved in your browser, and the **Fullscreen** button above the game gives a bigger view. Steam play isn't available in the browser. To join a LAN game from a browser, open the address the desktop host's lobby shows (see [LAN play](#lan-play)).

### Run from source

Install [LÖVE 11.5](https://love2d.org/), then from the repository root:

```sh
love .
```

On Windows, use `lovec.exe .` if you want a console window for log output.

## Controls

All controls can be rebound in **Settings → Controls**. These are the defaults:

| | Move | Jump | Aim | Fire | Block |
|---|---|---|---|---|---|
| **Local P1** | A / D | W | Facing direction; hold W / S to aim 45° up / down | Space | Left Shift |
| **Local P2** | ← / → | ↑ | Facing direction; hold ↑ / ↓ to aim 45° up / down | Right Ctrl | Right Shift |
| **Online** | A / D | Space or W | Mouse | Left click | Right click |

- **Online only:** hold **S** in the air to fast-fall.
- **Esc** opens the pause/menu screen. **F11** or **Alt+Enter** toggles fullscreen.
- **Card picks:** use your left/right keys and your fire key (local play). Online, click a card, or use A/D with Space.
- **LAN games use the Online controls**, the same as Steam games.

## Online play (Steam)

Online play runs on Steam's networking. It uses Steam's public test app, **Spacewar (App ID 480)**, so nobody needs to own or install anything extra.

**Requirements**
- Steam must be **running and logged in before you start the game**.
- Each player needs their **own Steam account**. You can't join your own lobby from a second copy on the same account.
- Everyone needs the **same game version**. Lobbies refuse players with a different network protocol version.
- Windows and Linux players can play together.
- No port forwarding is needed, because traffic goes through Steam's relay network.

**Hosting and joining**
1. The host picks **Online Play → Host Lobby** and shares the 6-character lobby code. The **Copy Code** button helps.
2. Other players pick **Online Play**, type the code and join.
3. The host chooses *Rounds to win* and presses **Start Match** once at least 2 players are in.

Steam invites also work, but only if the friend already has the game open. The game runs as Spacewar, so Steam can't launch it for them.

## LAN play

**Online Play → LAN** plays with computers on the same network, without Steam or accounts. Set your name at the top of the LAN screen.

1. The host presses **Host LAN Game**. The lobby shows the host's address (e.g. `192.168.1.20`) and a browser link (e.g. `http://192.168.1.20:27960`).
2. Desktop players open **Online Play → LAN**. Games on the network appear in the list; press **Join**, or type the host's address.
3. Browser players open the host's browser link in any browser on the network, then choose **Online Play → LAN → Join Game**. The desktop host serves the browser version itself, so this works without internet access. (The GitHub Pages site can't join LAN games: browsers don't let a page from the internet connect to computers on your network.)
4. The host presses **Start Match** once at least 2 players are in. New players can join while the host is in the lobby.

Notes:
- The host uses TCP port **27960** (or the next free one, shown in the address), and games are found with a UDP broadcast on port **27961**. If a game doesn't show up in the list, type the address instead.
- The first time you host, Windows may ask whether to let the game through the firewall. Allow it on **private networks**.
- Everyone needs the **same game version** as the host.
- Only desktop players can host. Browsers can only join.

## Building releases

`build.sh` builds release packages on Linux. It needs `curl`, `zip` and `unzip`, plus [Node.js](https://nodejs.org/) for the browser version.

```sh
./build.sh            # everything (the web build is skipped if Node.js isn't installed)
./build.sh linux      # AppImage only
./build.sh windows    # Windows zip only
./build.sh web        # browser version only
./build.sh love       # just the .love file
```

Output goes to `dist/`:

| File | What it is |
|---|---|
| `Deckshot-x86_64.AppImage` | Single-file Linux executable. LÖVE's AppImage with the game, the Steam libraries and the browser version (served to browsers by a LAN host). |
| `Deckshot-windows-x64.zip` | `Deckshot.exe` (LÖVE's `love.exe` with the game appended), LÖVE's DLLs, the Steam DLLs and `web/` (the browser version, served to browsers by a LAN host). |
| `Deckshot.love` | The game files only. Runs anywhere with `love Deckshot.love`, but without Steam libraries. |
| `web/` | The browser version: [love.js](https://github.com/Davidobot/love.js) (LÖVE compiled to WebAssembly) with the game, using the page in `web/index.html`. Serve the folder over HTTP to test it locally, e.g. `python3 -m http.server -d dist/web`. |

Pushing a version tag (`git tag -a v1.2.3 --cleanup=verbatim -F notes.md && git push origin v1.2.3`) runs `.github/workflows/release.yml`, which builds both packages on Linux, publishes the GitHub release with the tag message as its notes (plus downloads and SHA-256 checksums), and then runs `.github/workflows/pages.yml` to deploy the browser version to GitHub Pages. You can also run the Pages workflow by hand from the Actions tab.

The LÖVE 11.5 runtimes and `appimagetool` are downloaded once from their official GitHub releases into `build/cache/`.

## Technical details

### Project layout

```
deckshot/
├── main.lua, conf.lua   entry points (LÖVE needs them at the root)
├── core/                app (screen stack, virtual canvas), ui, input, settings
├── game/                world (authoritative simulation), player, bullet, cards, map
├── gfx/                 fx (particles), bloom, hud
├── online/              net (message codec), snapshot, session (Steam lobby), steam (library loader),
│                        lan (LAN host/client/discovery), webbridge (browser LAN), active (current session)
├── screens/             menu, settings, cards (card pool editor), maps (map pool editor), online, lan, lobby, match
├── lib/
│   ├── windows/         steam_api64.dll, luasteam.dll
│   └── linux/           libsteam_api.so, luasteam.so
├── web/index.html       the browser version's page
├── .github/workflows/   GitHub Pages deployment of the browser version
├── build.sh             release builder
└── steam_appid.txt      Spacewar app id for running from source
```

- `main.lua` adds a frame-capped `love.run`. `conf.lua` starts Steam before the window exists so the overlay can hook in.
- Everything renders to a 1280×720 virtual canvas that is letterboxed to the window.
- `game/world.lua` holds the whole match state and round flow, including the card pick queue and disconnects.

### Networking model

- **Host-authoritative.** The host runs the only simulation. Clients send their input every frame (unreliable, with sequence numbers) and render what the host sends back. Clients reuse the same `draw()` code on lightweight proxy objects.
- **Snapshots** go out about 30 times a second. They are compact binary (`love.data.pack`), lz4-compressed when large, and include particle and screen-shake events so effects look the same everywhere.
- **Reliable messages** cover match start, roster/cards, toasts, return-to-lobby and the gameplay **rules** (cards offered, picks per round, rarity weights, per-card overrides). The host sends the rules at match start and again on New Match.
- **Card picks:** the current pick (picker, hand, hover, queue) travels in every snapshot. The picker's hover rides along with their input, and their choice is tagged with a serial number so a late or duplicate click can't take the wrong card.
- **Versioning:** `session.PROTOCOL` is stored in the lobby data (and sent in the LAN hello), and mismatched peers are refused.
- **Transports:** Steam uses NetworkingMessages. LAN uses one TCP connection per client to the host (`online/lan.lua`): desktop clients send length-prefixed frames, and browser clients use a WebSocket on the same port, which also serves the browser version over HTTP. In the browser, `online/webbridge.lua` talks to the page's WebSocket code through `print` and a file in the in-memory filesystem, since love.js has no sockets.

### Steam libraries

| Library | Windows | Linux | Source |
|---|---|---|---|
| Steamworks API (SDK 1.65) | `lib/windows/steam_api64.dll` | `lib/linux/libsteam_api.so` | [Steamworks.NET](https://github.com/rlabrecque/Steamworks.NET) redistributables |
| luasteam v6.0.0 | `lib/windows/luasteam.dll` | `lib/linux/luasteam.so` | [uspgamedev/luasteam](https://github.com/uspgamedev/luasteam/releases/tag/v6.0.0) |

The two libraries must come from matching SDK versions. When running from source they're loaded from `lib/<platform>/`; the packaged builds keep them next to the executable. If Steam isn't running, a library is missing, or the OS isn't supported, the game falls back to offline-only play and shows the reason on the Online screen.

### Settings file

Settings are saved as plain `key=value` lines in `settings.txt`:

- **Windows:** `%APPDATA%\LOVE\deckshot\` when run from source, `%APPDATA%\deckshot\` for the packaged exe
- **Linux:** `~/.local/share/love/deckshot/` when run from source, `~/.local/share/deckshot/` for the AppImage

Key bindings are stored as `bind.<scheme>.<action>=<key>`, and card pool overrides as `card.<id>=<rarity>,<on|off>`.

### Code notes

The game runs on LuaJIT (Lua 5.1 semantics). Use the `bit` library rather than Lua 5.3+ operators. [`CLAUDE.md`](CLAUDE.md) has more detailed contributor notes, including the rules for keeping the network protocol in sync and how to write headless test harnesses.

## License

This project's source code is released under the [MIT License](LICENSE).

Bundled third-party components keep their own licenses:
- [LÖVE](https://love2d.org/) (included in the packaged builds) is under the zlib license.
- [luasteam](https://github.com/uspgamedev/luasteam) is under the MIT license.
- The Steamworks API libraries (`steam_api64.dll`, `libsteam_api.so`) are Valve redistributables covered by the [Steamworks SDK Access Agreement](https://partner.steamgames.com/documentation/sdk_access_agreement).

ROUNDS is a trademark of Landfall Games. This is an unofficial fan project.
