# Deckshot

A fan-made game heavily inspired by [ROUNDS](https://store.steampowered.com/app/1557740/ROUNDS/) by Landfall Games, built with [LÖVE](https://love2d.org/) 11.5. It's a 2D side-view shooter for 2 to 4 players: when you lose a round, you pick an upgrade card. Cards stack, builds get silly, and the first player to the target score wins.

- **Local play:** 2 to 4 players on one computer: keyboard, up to 4 gamepads, touch screen, and bots (easy, normal, hard). Free-for-all or Teams (2v2).
- **Online play:** up to 4 players over Steam (lobby codes, invites or the public lobby browser), with bots filling empty seats.
- **LAN play:** up to 4 players on the same network, no Steam needed. Browsers and phones on the network join a desktop host by scanning a QR code.
- **Platforms:** Windows and Linux (64-bit), plus a browser version that also works on phones and tablets.

**▶ Play in your browser: https://distorbed678.github.io/deckshot/** (against bots or friends on one device; Steam play needs the desktop version)

> Deckshot started life as "Rounds Clone". It is not affiliated with or endorsed by Landfall Games, the makers of ROUNDS.

## Features

- **150 upgrade cards** across five rarities (40 common, 44 uncommon, 33 rare, 19 epic, 14 legendary): bouncing and exploding bullets, homing, lasers, black holes, orbiting shields, revives, a turret, railgun bolts, mirrored shots, melee and dash cards, trigger cards ("on block: lightning strikes every enemy") and plenty of block abilities.
- **Every card stacks**, and **40 synergies** unlock bonuses when you own the right pair (Explosive + Bouncy: every bounce explodes).
- **Cards are dealt face down:** hover one to turn it over. Rare, epic and legendary reveals sparkle.
- **Movement that feels good:** coyote time, jump buffering, variable jump height, apex hang, fast fall, a double jump and an air dash, wall slides and wall jumps, one-way platforms and corner correction.
- **Melee:** tap for a light hit, hold for a heavy lunge. Blocking a melee stuns the attacker.
- **Blocking** reflects bullets and bounces you off hazards and the arena edges (which hurt and throw you back in; the top is open).
- **55 arenas** with saws, spikes, lasers, crushers, flame jets, acid, turrets, conveyors, bounce pads, fans, crumbling and moving platforms, and breakable crates, glass, barrels, gas canisters, walls, bridges and things hanging from ropes.
- **Editors** for maps, cards and synergies, with share codes. Built-in maps and cards can be edited too (and reset). Online, the host's custom content is sent to everyone.
- **Bots** that navigate every map, lob shots over cover, block, dash and pick cards with synergies in mind.
- **Match flow:** starting cards, a pick timer online, discarding a card instead of picking, a sudden-death barrier in 3-4 player games, first to N rounds, Continue or New Match.
- **Juice:** synthesized sound effects, particles, squash and stretch, damage numbers, a kill feed, a scoreboard (Tab), a low-HP warning and slide transitions.
- **Practice range** with a dummy and any cards, a **codex** of every card and synergy with your pick statistics, and **How to Play**.
- **Custom rules:** cards offered, picks per round, starting cards, rarity chances, the card, map and synergy pools, map hazards on/off, teams and friendly fire. **Online, the host's rules are used.**
- **Settings:** window mode, monitor, resolution, VSync, FPS cap, bloom, screen shake, particles, text size, volumes, touch layout and fully rebindable controls.

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

Open **https://distorbed678.github.io/deckshot/**. Nothing to install. Play against bots, or share the keyboard. Gamepads work, and on a phone or tablet the touch controls appear when you touch the screen (turn it sideways; "Add to Home Screen" gives a full-screen app). Settings are saved in your browser. Steam play isn't available in the browser. To join a LAN game from a browser or phone, open the address (or scan the QR code) the desktop host's lobby shows (see [LAN play](#lan-play)).

### Run from source

Install [LÖVE 11.5](https://love2d.org/), then from the repository root:

```sh
love .
```

On Windows, use `lovec.exe .` if you want a console window for log output.

## Controls

All keys can be rebound in **Settings → Controls**, and **How to Play** in the game shows every scheme. Defaults:

| | Move | Jump | Aim | Fire | Block | Dash | Melee (hold: heavy) |
|---|---|---|---|---|---|---|---|
| **Local P1** | A / D | W | facing; hold W / S to aim up / down | Space | Left Shift | E | Q |
| **Local P2** | ← / → | ↑ | facing; hold ↑ / ↓ to aim up / down | Right Ctrl | Right Shift | / | . |
| **Online** | A / D | Space or W | Mouse | Left click | Right click | Left Shift | F |
| **Gamepad** | Left stick | A | Right stick | Right trigger | Left trigger / RB | B / LB | X |

- Hold **down** in the air to fall faster; **down + jump** drops through thin platforms.
- **Tab** (gamepad **Back**) shows the scoreboard. **Esc** (gamepad **Start**) pauses. **F11** or **Alt+Enter** toggles fullscreen.
- **Touch:** drag on the left half to move (push up to jump), drag on the right half to aim and fire, plus Jump, Block, Dash and Melee buttons. Move them in Settings → Controls → Touch layout.
- **Card picks:** left/right (or hover) to turn cards over and choose, fire (or click / A) to take, down to discard a card instead.

## Online play (Steam)

Online play runs on Steam's networking. It uses Steam's public test app, **Spacewar (App ID 480)**, so nobody needs to own or install anything extra.

**Requirements**
- Steam must be **running and logged in before you start the game**.
- Each player needs their **own Steam account**. You can't join your own lobby from a second copy on the same account.
- Everyone needs the **same game version**. Lobbies refuse players with a different network protocol version.
- Windows and Linux players can play together.
- No port forwarding is needed, because traffic goes through Steam's relay network.

**Hosting and joining**
1. The host picks **Online Play → Steam → Host Lobby** (public, friends only, or code only) and shares the 6-character lobby code. The **Copy Code** button helps.
2. Other players type the code, pick the lobby from **Public lobbies**, or accept an invite.
3. Everyone picks a colour. The host can add bots, chooses *Rounds*, and presses **Start Match** once at least 2 players (or bots) are in.

People who join during a match watch until the next one. If someone drops out, their slot is kept for 60 seconds so they can rejoin.

Steam invites also work, but only if the friend already has the game open. The game runs as Spacewar, so Steam can't launch it for them.

## LAN play

**Online Play → LAN** plays with computers on the same network, without Steam or accounts. Set your name at the top of the LAN screen.

1. The host presses **Host LAN Game**. The lobby shows the host's address (e.g. `192.168.1.20`), a browser link (e.g. `http://192.168.1.20:27960`) and a QR code of that link for phones.
2. Desktop players open **Online Play → LAN**. Games on the network appear in the list; press **Join**, or type the host's address.
3. Browser players open the host's browser link in any browser on the network, then choose **Online Play → LAN → Join Game**. The desktop host serves the browser version itself, so this works without internet access. (The GitHub Pages site can't join LAN games: browsers don't let a page from the internet connect to computers on your network.)
4. The host presses **Start Match** once at least 2 players are in. People can join at any time (during a match they watch until the next one), and a player who loses the connection is reconnected automatically within a minute.

Notes:
- The host uses TCP port **27960** (or the next free one, shown in the address), and games are found with a UDP broadcast on port **27961**. If a game doesn't show up in the list, type the address instead.
- The first time you host, Windows may ask whether to let the game through the firewall. Allow it on **private networks**. Only hosting needs this: joining never triggers the prompt.
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
├── main.lua, conf.lua   entry points (LÖVE needs them at the root), crash screen, window icon
├── core/                app (screen stack, virtual canvas, transitions), ui, input (keys, mouse, pads, touch,
│                        bots), touch, settings, profile (codex stats), qr, version, webkeyboard
├── game/                world (authoritative simulation), player, bullet, objects (hazards, breakables),
│                        cards + carddata + stats + triggers + synergies (data-driven cards), map, bot
├── gfx/                 fx (particles), sfx (synthesized sounds), bloom, hud
├── online/              net (message codec), snapshot, session (Steam lobby), steam (library loader),
│                        lan (LAN host/client/discovery), webbridge (browser LAN), active, presence
├── screens/             menu, localsetup, match, practice, editor_hub, editor_map, editor_cards, codex,
│                        howtoplay, credits, settings, touchlayout, cards, maps, synergies, online, lan,
│                        lobby, reconnect
├── data/maps/           the built-in maps (map editor files)
├── data/cards/          the built-in cards (card editor files)
├── data/synergies/      the built-in synergies
├── lib/windows|linux/   Steam libraries
├── web/                 the browser version's page and manifest
├── .github/workflows/   release builds and GitHub Pages deployment
├── build.sh             release builder
└── steam_appid.txt      Spacewar app id for running from source
```

- `main.lua` adds a frame-capped `love.run`. `conf.lua` starts Steam before the window exists so the overlay can hook in.
- Everything renders to a 1280×720 virtual canvas that is letterboxed to the window.
- `game/world.lua` holds the whole match state and round flow: card picks, teams, the sudden-death barrier, bots and disconnects.

### Networking model

- **Host-authoritative.** The host runs the only simulation. Clients send their input every frame (unreliable, with sequence numbers) and render what the host sends back on proxy objects that reuse the same `draw()` code.
- **Client prediction:** your own player is simulated locally right away. Snapshots carry the last input the host applied; the client resets to the host's state, replays newer inputs and blends small corrections. Other players are drawn about 70 ms behind, between real snapshots.
- **Snapshots** go out about 30 times a second: players, bullets, map objects, effects, the barrier, the current card pick, scoreboard stats, and recorded particle, sound and damage-number events. They're compact binary (`love.data.pack`), lz4-compressed when large.
- **Reliable messages** cover match start (slots, colours, teams, bots), the map, card and synergy lists (full text for custom or edited ones), rules, roster, toasts, the kill feed, votes, discards, lobby streaks and return-to-lobby.
- **Versioning:** `session.PROTOCOL` is stored in the lobby data (and sent in the LAN hello), and mismatched peers are refused.
- **Transports:** Steam uses NetworkingMessages. LAN uses one TCP connection per client to the host (`online/lan.lua`): desktop clients send length-prefixed frames, and browser clients use a WebSocket on the same port, which also serves the browser version over HTTP. In the browser, `online/webbridge.lua` talks to the page's WebSocket code through `print` and a file in the in-memory filesystem, since love.js has no sockets.

### Steam libraries

| Library | Windows | Linux | Source |
|---|---|---|---|
| Steamworks API (SDK 1.65) | `lib/windows/steam_api64.dll` | `lib/linux/libsteam_api.so` | [Steamworks.NET](https://github.com/rlabrecque/Steamworks.NET) redistributables |
| luasteam v6.0.0 | `lib/windows/luasteam.dll` | `lib/linux/luasteam.so` | [uspgamedev/luasteam](https://github.com/uspgamedev/luasteam/releases/tag/v6.0.0) |

The two libraries must come from matching SDK versions. When running from source they're loaded from `lib/<platform>/`; the packaged builds keep them next to the executable. If Steam isn't running, a library is missing, or the OS isn't supported, the game falls back to offline-only play and shows the reason on the Online screen.

### Save files

Everything is saved in the game's save folder:

- **Windows:** `%APPDATA%\LOVE\deckshot\` when run from source, `%APPDATA%\deckshot\` for the packaged exe
- **Linux:** `~/.local/share/love/deckshot/` when run from source, `~/.local/share/deckshot/` for the AppImage

| File | What's in it |
|---|---|
| `settings.txt` | settings as `key=value` lines, key bindings (`bind.<scheme>.<action>=<key>`), card pool (`card.<id>=<rarity>,<on|off>`), map and synergy pools |
| `profile.txt` | codex statistics per card |
| `user/custom_maps/`, `user/custom_cards/`, `user/custom_synergies/` | things you made in the editors |
| `user/maps/`, `user/cards/`, `user/synergies/` | your edits to built-in ones (delete a file, or use Reset, to undo) |
| `crash.txt` | the last crash report |

Settings from the old "Rounds Clone" save folder are copied over the first time Deckshot starts.

### Code notes

The game runs on LuaJIT (Lua 5.1 semantics), and the browser version on plain Lua 5.1. Use `core/bit.lua` rather than Lua 5.3+ operators. [`CLAUDE.md`](CLAUDE.md) has more detailed contributor notes, including the rules for keeping the network protocol in sync and how to write headless test harnesses.

## License

This project's source code is released under the [MIT License](LICENSE).

Bundled third-party components keep their own licenses:
- [LÖVE](https://love2d.org/) (included in the packaged builds) is under the zlib license.
- [luasteam](https://github.com/uspgamedev/luasteam) is under the MIT license.
- The Steamworks API libraries (`steam_api64.dll`, `libsteam_api.so`) are Valve redistributables covered by the [Steamworks SDK Access Agreement](https://partner.steamgames.com/documentation/sdk_access_agreement).

ROUNDS is a trademark of Landfall Games. This is an unofficial fan project.
