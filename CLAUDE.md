# Deckshot (LÖVE 11.5 / LuaJIT)

A clone of the game ROUNDS: 2D side-view duels where the round loser picks an upgrade card. Local play is 2 players on one keyboard. Online play supports up to 4 players over Steam (AppID 480 "Spacewar") or LAN (Online Play → Steam / LAN); both use the Online control scheme.

## Running and checking
- **Linux dev machine (current):** `love` 11.5 and `luajit` are on the PATH and Steam is installed. Run with `love .` from the repo root. Check syntax with `luajit -bl file.lua > /dev/null`. Headless harnesses run with `love <harnessDir>`. Save folder: `~/.local/share/love/deckshot/`.
- **Windows PC:** LÖVE 11.5 may be at `%LOCALAPPDATA%\Programs\love-11.5-win64` (`love.exe`, plus `lovec.exe`, which prints to the console); if it isn't, download `love-11.5-win64.zip` into the scratchpad and syntax-check by `loadfile`-ing every file in a harness. Steam is **not installed** there, and neither are `zip`, `gh` or Python (Windows' `tar.exe -a -c -f x.zip` makes zips; Node and Chrome are installed). Checked-out files use CRLF (`core.autocrlf=true`). From Git Bash, `npx love.js` silently does nothing: run `node <npm-cache>/_npx/*/node_modules/love.js/index.js` instead. Put `io.stdout:setvbuf("no")` in harnesses, or redirected output is lost.
- The desktop game runs on **LuaJIT (Lua 5.1)**, so don't use `//`, `&`/`|` or other 5.4 features. Use `love.data.pack`, and get bit operations with `require "core.bit"` (never `require "bit"` directly).
- **The game also runs in the browser** (love.js, plain Lua 5.1: no JIT, no `ffi`, no `bit`, no `goto`, no luasocket). `core/platform.lua` sets `platform.web` (from `love._os == "Web"`). On the web: no Steam, LAN join only (through `online/webbridge.lua`), no custom `love.run` (love.js drives frames), `Settings.applyWindow` does nothing (the page owns the canvas), the Video tab shows only the effects options, and Quit is hidden. Anything new that touches the window, files outside the save folder, native libraries or `ffi` must be guarded with `platform.web`.
- Without Steam (or on an unsupported OS) `online/steam.lua` fails gracefully and online play is disabled.

## Building releases
`./build.sh [all|linux|windows|web|love]` (Linux; needs curl, zip, unzip, and Node.js for `web`) writes to `dist/`:
- `Deckshot.love`: the game files (everything except `lib/`, `*.md`, `*.sh`, `steam_appid.txt` and build output).
- `Deckshot-x86_64.AppImage`: LÖVE's AppImage with `Deckshot.love`, the Steam `.so` files and `web/` at the AppDir root. `FUSE_PATH` is set in `AppRun`, so the game runs fused.
- `Deckshot-windows-x64.zip`: `Deckshot.exe` (love.exe with the .love appended), LÖVE's DLLs, the Steam DLLs and `web/`.
- Both desktop packages carry the browser build in `web/` (`copy_web`; the web build runs first) so a LAN host can serve it to browsers.
- `web/`: `npx love.js@11.4.1 -c` output (compatibility mode: no SharedArrayBuffer, so it works on GitHub Pages) with `web/index.html` replacing love.js's page. The page sizes the canvas drawing buffer to its on-screen size and sends a `resize` event so LÖVE renders at native resolution. It also stops `fullscreenchange` events before SDL sees them, because otherwise SDL treats the page's fullscreen as its own and stops following the canvas size.
- **GitHub Pages:** `.github/workflows/pages.yml` runs `./build.sh web` and deploys `dist/web` on every published release and on manual dispatch (`release.yml` dispatches it, because a release created with the workflow token doesn't fire the release event). Live at https://distorbed678.github.io/deckshot/. The `github-pages` environment allows deploys from `main` and from tags matching `v*` (releases run from their tag); a new tag scheme needs adding under Settings → Environments.

The LÖVE runtimes and appimagetool are downloaded once into `build/cache/` (gitignored). If you add asset folders, make sure `build_love` doesn't exclude them.

## Workflow: commit and release every change
**After every bug fix or change, commit it, push it and publish a GitHub release, unless the user says not to commit or release yet.**
1. Run the relevant checks first (syntax check, headless harnesses, screenshots).
2. Commit with a descriptive message and push to `main`. If the push can't find credentials (the global `credential.helper` is `cache`), push with `git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main`.
3. Publish by pushing an annotated version tag (works from Windows or Linux, no `gh` needed locally). `.github/workflows/release.yml` then runs `./build.sh all` on Linux, checks both packages contain the game, the Steam libraries and `web/`, creates the release with both files, and starts the Pages deploy:

       git tag -a vX.Y.Z --cleanup=verbatim -F <notes.md> && git push origin vX.Y.Z

   - The tag message is the release notes: what was fixed or changed, and whether online play is still compatible with the previous version (if `session.PROTOCOL` was bumped, say so). The workflow appends the download table and SHA-256 checksums. `--cleanup=verbatim` keeps `#` headings (git would strip them as comments).
   - On Linux you can still build and smoke-test locally first (`./build.sh all`, launch the AppImage and confirm it loads the bundled Steam libraries). If the change could affect the browser version, test a web build in headless Firefox/Chrome (see Testing).
4. Versioning: bump the patch version (v0.1.1 → v0.1.2) for fixes and small changes, and the minor version (v0.1.x → v0.2.0) for feature batches. Check the latest tag with `git ls-remote --tags origin`.
5. Check the runs: `gh run list --repo Distorbed678/deckshot --limit 2`, or without `gh`, `curl -s https://api.github.com/repos/Distorbed678/deckshot/actions/runs?per_page=3` (public repo).

## Architecture
`main.lua` and `conf.lua` stay at the repo root (LÖVE requires it). Modules are required by dotted path, e.g. `require "game.world"`, `require "online.net"`.

| Path | Role |
|---|---|
| `main.lua` / `conf.lua` | Entry points. `conf.lua` calls `steam.init()` before the window exists so the Steam overlay can hook. `main.lua` overrides `love.run` to add the max-FPS cap and handles F11 / Alt+Enter. |
| `core/app.lua` | Screen stack (`switch`/`push`/`pop`). Everything is laid out in 1280×720 units and letterboxed to the window, but `app.canvas` and `app.fonts.*` are built with a `dpiscale` equal to the window scale, so rendering happens at native resolution (rebuilt in `app.updateViewport` when the window size changes). Always draw through `app.fonts` and `app.canvas`; never cache them across frames. `app.mouse()` returns virtual coordinates. |
| `core/ui.lua` | Immediate-mode widgets (`button`, `cycler`, `textField`, `panel`). Only the top screen's widgets get input. Arrows/Enter for navigation. `ui.capturing` hands navigation keys to a screen that's waiting for a key to bind. |
| `core/input.lua` | Input sources: `keys(binds)` (local), `mouse(binds)` (online, mouse aim), `remote()`. Bindings are the live `Settings.values.binds.{p1,p2,online}` tables (keys or `mouse1`..`mouse5`). Jump and block use **press counters** (`jumpCount`, `blockCount`), not events. `pickHover` carries the picker's selection to the host. |
| `core/settings.lua` | Persisted settings, key binding (`Settings.bind` swaps conflicts), window/VSync application, and `Settings.cardRules()` (gameplay rules from the settings). |
| `game/world.lua` | **Authoritative simulation**: players, bullets, wells, round flow (`countdown → playing → roundOver → cardPick → matchOver`), sequential card picks (`pickQueue` → `pick`, lowest score first, `picksPerRound` each), continue/new match, disconnects. `World.rules` holds the gameplay rules. It emits `world.on.{toast,roster,pick,matchOver}`. |
| `game/player.lua` / `game/bullet.lua` | Gameplay. Players read `self.input` (see `core/input.lua`), never the keyboard directly. `self.game` is the World. Blocking reflects any enemy bullet (`Bullet:hitPlayer`); `Player:blocked()` handles Parry. |
| `game/cards.lua` | Card list with rarities and specials (`reroll`, `tableflip`, `shrine`). `card.index` is used over the network and `card.id` (from the name) in the settings file. `Cards.applyRules(rules)` sets each card's current `rarity`/`disabled` and the rarity weights used by `deal`; `card.baseRarity` is the default. |
| `game/map.lua` | Arenas (25). New ones use `Sym(name, spawnA, spawnB, half, center)`, which mirrors `half` rects around x = 640 and builds the 4 spawns. `map.index` goes over the network (snapshot), `map.id` into the settings file. `Map.random(exclude, disabled)` honours the map pool (`rules.maps`, host only). |
| `gfx/fx.lua`, `gfx/bloom.lua`, `gfx/hud.lua` | Particles (with network recorder), bloom pass, HUD/card drawing. `hud.drawScores` lays card names out itself (`hud.cardChips`) and returns their rects; `screens/match.lua` shows `hud.drawCardTooltip` for the one under the mouse. |
| `online/net.lua` | Binary message codec (`love.data.pack`) plus `net.loopback(loss)`, an in-process transport for tests. |
| `online/snapshot.lua` | Host→client world snapshots (~30 Hz, lz4 when large), including fx events and the current card pick. |
| `online/active.lua` | Which session the lobby/match/settings screens use (`active.get()`): the Steam `session` or `lan`. Both have the same interface (`kind`, `members`, `isHost`, `hostId`, `myId()`, `transport`, `popEvents`, `popMessages`, `leave`, `setRounds`, `publishRules`, `setJoinable`, `MAX_PLAYERS`). `onEntered` calls `active.use`. Screens that serve both must not `require "online.session"` directly. |
| `online/lan.lua` | LAN session. The host runs one TCP server (port 27960, or +1..9 if busy) and tells connections apart by their first bytes: `RCL1` = desktop client (`[u32 len][msg]` frames), `GET /lan` WebSocket = browser client, any other GET = serve the browser build (`dist/web` from source, `web/` next to the exe when packaged). UDP 27961 answers `RCLQ` discovery broadcasts. LAN control messages are kinds 200-204 (HELLO/WELCOME/REJECT/MEMBERS/PING); game messages (< 200) pass through. Peers are `"host"` and `"lan<n>"`. Bind to `"0.0.0.0"`, never `"*"` (luasocket then makes IPv6-only sockets). |
| `online/webbridge.lua` + `web/index.html` | Browser LAN connection. Lua prints `ESC LAN <cmd>` lines; the page's `Module.print` handles them synchronously and rewrites `/tmp/rclan.bin` (MEMFS, read with `io.open`) with the state and all unacknowledged messages, and Lua acks by sequence number. The page sends its own PINGs so a background tab isn't timed out. LAN only works on an `http:` page (the one the host serves). |
| `online/session.lua` / `online/steam.lua` | Steam lobby (create, join by code via lobby-list filters, invites, members) and the NetworkingMessages transport. `steam.lua` loads the Steam API via ffi (`steam_api64.dll` / `libsteam_api.so`, globally), then `require`s `luasteam` from the same folder: `lib/windows/` or `lib/linux/` when run from source, the executable's folder in a packaged build. |
| `screens/` | `menu`, `settings` (overlay with Video / Controls / Gameplay tabs), `cards` (card pool editor) and `maps` (map pool editor), both pushed from settings, `online` (Steam / LAN choice, then the Steam page: host / join by code), `lan` (name, host, games found, join by address; in the browser, join the page's host), `lobby` (Steam or LAN info panel by `session.kind`), `match`. |
| `lib/windows/`, `lib/linux/` | Steam native libraries (not packed into the .love; `build.sh` copies them next to the executable). |
| `steam_appid.txt` | `480`, for Steam when the game is started from the repo root. |

### Online model
- The host runs `World`, applies remote inputs (INPUT packets with sequence numbers), and broadcasts snapshots.
- Clients don't simulate. They build proxy tables with the `Player`/`Bullet` metatables and reuse the same `draw()` code.
- **If you add a field that `Player:draw`/`Bullet:draw` reads, add it to `online/snapshot.lua` and `Match:applySnapshot` (`screens/match.lua`)**, or clients won't see it.
- Card picks are sequential. The current pick (slot, serial, hover, options, queue) travels in every snapshot so everyone watches it. The picker's hover rides in INPUT (`pickHover`) and the choice is CHOOSE(index, serial); a stale serial is ignored.
- Match-over votes: clients send VOTE (continue / new match); the host's `world.votes` travels in the snapshot (one byte per player) and the host's buttons show the tally. Votes are only a suggestion; the host's buttons decide.
- Gameplay rules (cards offered, picks per round, rarity weights, per-card rarity/disabled) come from the **host's** settings: the host sends RULES after START and again on New Match, and clients call `Cards.applyRules`. Local play and the host build them with `Settings.cardRules()`.

## Rules and gotchas
- **Bump `session.PROTOCOL`** whenever the wire format, card order (`Cards.list` indices) or map list changes. Peers with different versions refuse to join.
- **Every card must stack.** Card abilities in `BASE` (player.lua) are **counts of copies, never booleans** (0 = not owned; remember `0` is truthy in Lua, so test `> 0`). When extra copies don't simply add to a stat, give the card a `stack` line describing what they do; `hud.drawCard` shows it. Bullets keep boolean flags (`ghost`, `laser`, `mine`) for drawing and snapshots, with the copy count alongside (`ghostLevel`, `sticky`, `blackhole`, `splitsLeft`).
- New gameplay effects must work with up to 4 players. Use `world:enemiesOf(p)` and `world:nearestEnemy(p, x, y)`, never assume a single opponent.
- Every map needs 4 spawns (`spawns[1..4]`) that land on solid ground. After adding maps, run a harness that spawns a player at every spawn of every map and checks it lands (not inside a wall, not falling out).
- `Player:hit(amount, dx, dy, knock, source)`: always pass the attacker as `source` (Thorns and Frostback need it). Damage goes through armor, then the Shield Generator shield, then Decay/HP.
- Bullets spawned by other bullets (Shrapnel shards, Hydra heads) use `Bullet:spawnChild`, which marks them `isChild` and zeroes chain effects so they can't multiply. Cluster mini-blasts are `isCluster` clones. Keep new chain effects behind these flags.
- `Player:draw` also reads `shield` and `stats.sentry`; both travel in the snapshot.
- `fx.*` calls on the host are recorded into `fx.recorder` and replayed on clients. Keep fx calls deterministic in shape (`burst`, `ring`, `addShake`, `clear`).
- Steam binaries (in `lib/`) must match an SDK version. Currently `luasteam.dll` / `luasteam.so` are **v6.0.0** (luasteam GitHub release, built for SDK 1.65). `steam_api64.dll` / `libsteam_api.so` are SDK **1.65**, taken from Steamworks.NET `com.rlabrecque.steamworks.net/Plugins/`. A mismatch shows up as "The specified procedure could not be found" (Windows) or an undefined-symbol error (Linux). Windows and Linux players can play together.
- `love.window.setMode` fails while a canvas is active, and screens draw (and handle widget clicks) on `app.canvas`. Always change the window through `Settings.applyWindow()`: it defers to `Settings.update()` (called from `love.update`) when a canvas is active. In the settings screen, window mode, monitor, resolution and VSync are pending until **Apply**.
- Settings are saved to `settings.txt` in the LÖVE save folder (flat `key=value`, plus `bind.<scheme>.<action>=key` and `card.<id>=<rarity>,<on|off>` lines). `Settings.resetBinds` mutates in place because input states hold references to the bind tables.

## Testing approach (headless, no Steam needed)
Put test harnesses in the session scratchpad, not the repo. Pattern:
```lua
package.path = "<repo>/?.lua;" .. package.path   -- lets require "game.world" find <repo>/game/world.lua
dofile("<repo>/main.lua")          -- defines love.load/update/draw/run; override love.run to drive the test yourself
love.keyboard.isDown = function(...) ... end   -- fake input
```
- **Local/UI:** drive `love.keypressed`, read state with `require("core.app").base()`, and screenshot with `app.canvas:newImageData():encode("png", name)` after `love.draw()`.
- **Network:** `hub = net.loopback(0.1)`, then `Match.newClient(slots, i, winScore, hub:endpoint(id), "H", nil, {popEvents=fn})` and `Match.newHost(slots, winScore, hub:endpoint("H"), {popEvents=fn})`. Construct clients **before** the host, because `newClient` resets `fx.recorder`. Set `fx.recorder = nil` while updating clients, and compare client proxies with `host.world.players`.
- Give the harness its own `conf.lua` with a separate `t.identity` (and one per process if running several in parallel, since they share `settings.txt`). Run with `love <harnessDir>` under `timeout`, then view the screenshots.
- **Browser build:** serve `dist/web` with `python3 -m http.server`, then drive it with `puppeteer-core` (installed in the scratchpad) using the system Firefox (`browser: "firefox", executablePath: "/usr/bin/firefox", headless: true`). Map game coordinates to page clicks through the canvas's `getBoundingClientRect()`. In Firefox's protocol the space key is `" "`, not `"Space"`. Check the console for Lua errors.
- **LAN (real sockets):** run two LÖVE processes with separate identities: a host harness that calls `lan.host(...)` and `app.base():start()` once `#lan.members >= 2`, and a client harness that opens `screens.lan`, joins the first of `s.games` and fakes keys. Compare the host's `world.players[2]` with the client's `proxies`. For browser clients, set `lan.webDirCache` to a love.js build and drive `http://127.0.0.1:27960/` with puppeteer (Chrome works too).
- **Real Steam (Linux, Steam running):** override `love.filesystem.getSource` to return the repo path, then `require("online.steam").init()`.

## About the user
Develops on Linux (CachyOS) now; previously Windows 11. Builds the game in feature batches and asks for many features at once. Wants the game to keep a ROUNDS feel. Controls are rebindable in Settings; the defaults are P1 WASD, Space fire, L-Shift block; P2 arrows, R-Ctrl fire, R-Shift block.
