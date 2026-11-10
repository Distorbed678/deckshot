#!/usr/bin/env bash
# Builds release packages into dist/ (run on Linux):
#   dist/Deckshot-x86_64.AppImage     Linux: one self-contained executable
#   dist/Deckshot-windows-x64.zip     Windows: Deckshot.exe + DLLs, unzip and run
#   dist/web/                            Browser version (love.js)
#   dist/site/                           GitHub Pages: the landing page, with the game under play/
# The Linux and Windows packages also carry the browser version (web/ next to the game), which a
# desktop LAN host serves so browsers on the network can join (online/lan.lua).
#
# Usage: ./build.sh [all|linux|windows|web|site|love]     (default: all)
#   love = only build dist/Deckshot.love (runs anywhere with `love Deckshot.love`)
#   all  = love + web + linux + windows (web is skipped when Node.js (npx) isn't installed)
#
# Needs: curl, zip, unzip (and Node.js for web). The LÖVE runtimes and appimagetool are
# downloaded on the first build into build/cache/ (gitignored); love.js comes from npm.
set -euo pipefail

NAME="Deckshot"
TITLE="Deckshot"
LOVE_VERSION="11.5"
LOVEJS_VERSION="11.4.1" # love.js (LÖVE 11 for the browser), from npm

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
CACHE="$BUILD/cache"
DIST="$ROOT/dist"
TARGET="${1:-all}"

LOVE_URL="https://github.com/love2d/love/releases/download/$LOVE_VERSION"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

for tool in curl zip unzip; do
  command -v "$tool" >/dev/null || die "'$tool' is required (e.g. sudo pacman -S $tool)"
done

# download URL FILE: fetch once into the cache.
download() {
  local url="$1" dest="$CACHE/$2"
  if [ ! -s "$dest" ]; then
    log "Downloading $2" >&2
    curl -fL --retry 3 --progress-bar -o "$dest.part" "$url" || die "download failed: $url"
    mv "$dest.part" "$dest"
  fi
  printf '%s' "$dest"
}

# The game itself: every file in the repo except tooling, docs, native libraries (lib/) and build output.
build_love() {
  local out="$DIST/$NAME.love"
  log "Packing $NAME.love"
  rm -f "$out"
  (cd "$ROOT" && zip -9 -q -r "$out" . \
    -x '.git/*' '.github/*' '.claude/*' 'build/*' 'dist/*' 'docs/*' 'lib/*' 'web/*' 'site/*' '*.md' '*.sh' 'tools/*' 'tests/*' 'community/*' 'legacy/*' 'assets/art/*' '.gitignore' 'steam_appid.txt')
  local files
  files="$(unzip -Z1 "$out")"
  grep -qx 'main.lua' <<<"$files" || die "$NAME.love has no main.lua"
  grep -qx 'data/maps/order.txt' <<<"$files" || die "$NAME.love has no maps"
}

build_linux() {
  local appimage tool appdir
  appimage="$(download "$LOVE_URL/love-$LOVE_VERSION-x86_64.AppImage" "love-$LOVE_VERSION-x86_64.AppImage")"
  tool="$(download "$APPIMAGETOOL_URL" "appimagetool-x86_64.AppImage")"
  chmod +x "$appimage" "$tool"

  log "Building Linux AppImage"
  rm -rf "$BUILD/linux"
  mkdir -p "$BUILD/linux"
  (cd "$BUILD/linux" && "$appimage" --appimage-extract >/dev/null)
  appdir="$BUILD/linux/squashfs-root"

  # LÖVE's AppRun runs "$FUSE_PATH" as a fused game when it is set. The Steam libraries
  # sit next to the .love, which is where steam.lua looks for them in a fused build.
  cp "$DIST/$NAME.love" "$appdir/$NAME.love"
  cp "$ROOT/lib/linux/libsteam_api.so" "$ROOT/lib/linux/luasteam.so" "$ROOT/steam_appid.txt" "$appdir/"
  copy_web "$appdir"
  sed -i "s|^#FUSE_PATH=\"\$APPDIR/my_game.love\"|FUSE_PATH=\"\$APPDIR/$NAME.love\"|" "$appdir/AppRun"
  grep -q "^FUSE_PATH=" "$appdir/AppRun" || die "could not set FUSE_PATH in AppRun"
  # The window's class ties it to our desktop entry; without this the taskbar shows LÖVE's icon.
  sed -i '1a export SDL_VIDEO_X11_WMCLASS=deckshot SDL_VIDEO_WAYLAND_WMCLASS=deckshot' "$appdir/AppRun"

  # Our icon instead of LÖVE's.
  rm -f "$appdir"/love.svg "$appdir"/love.png "$appdir"/.DirIcon
  cp "$ROOT/assets/icon.png" "$appdir/$NAME.png"
  cp "$ROOT/assets/icon.png" "$appdir/.DirIcon"
  rm -f "$appdir"/*.desktop
  cat > "$appdir/$NAME.desktop" <<EOF
[Desktop Entry]
Name=$TITLE
Comment=2D duel game: lose a round, pick a card
Exec=$NAME
Icon=$NAME
StartupWMClass=deckshot
Type=Application
Categories=Game;
Terminal=false
EOF

  rm -f "$DIST/$NAME-x86_64.AppImage"
  if ! ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$appdir" "$DIST/$NAME-x86_64.AppImage" \
    > "$BUILD/linux/appimagetool.log" 2>&1; then
    cat "$BUILD/linux/appimagetool.log" >&2
    die "appimagetool failed"
  fi
  chmod +x "$DIST/$NAME-x86_64.AppImage"
}

build_windows() {
  local zipfile src out
  zipfile="$(download "$LOVE_URL/love-$LOVE_VERSION-win64.zip" "love-$LOVE_VERSION-win64.zip")"

  log "Building Windows package"
  rm -rf "$BUILD/windows"
  mkdir -p "$BUILD/windows"
  unzip -q "$zipfile" -d "$BUILD/windows/runtime"
  src="$(dirname "$(find "$BUILD/windows/runtime" -name love.exe | head -n 1)")"
  [ -f "$src/love.exe" ] || die "love.exe not found in $zipfile"

  # Our icon instead of LÖVE's. This has to happen before the .love is appended.
  (cd "$BUILD/windows" && npx --yes resedit-cli@3.1.1 --in "$src/love.exe" --out "$BUILD/windows/love-icon.exe" \
    --icon "1,$ROOT/lib/windows/icon.ico") || die "could not set the Windows icon"

  # A fused exe is love.exe with the .love appended. Steam DLLs go next to it.
  out="$BUILD/windows/$NAME"
  mkdir -p "$out"
  cat "$BUILD/windows/love-icon.exe" "$DIST/$NAME.love" > "$out/$NAME.exe"
  cp "$src"/*.dll "$src/license.txt" "$out/"
  cp "$ROOT/lib/windows/steam_api64.dll" "$ROOT/lib/windows/luasteam.dll" "$ROOT/steam_appid.txt" "$out/"
  copy_web "$out"

  rm -f "$DIST/$NAME-windows-x64.zip"
  (cd "$BUILD/windows" && zip -9 -q -r "$DIST/$NAME-windows-x64.zip" "$NAME")
}

# Browser build: love.js compiles nothing; it packages the .love next to a prebuilt
# LÖVE-for-WebAssembly. Compatibility mode (-c) needs no special server headers, so it
# works on GitHub Pages. Our own page (web/index.html) replaces love.js's default one.
build_web() {
  command -v npx >/dev/null || die "Node.js (npx) is required for the web build"
  log "Building web version"
  rm -rf "$DIST/web"
  npx --yes "love.js@$LOVEJS_VERSION" -c -t "$TITLE" -m 67108864 "$DIST/$NAME.love" "$DIST/web" >/dev/null \
    || die "love.js failed"
  cp "$ROOT/web/index.html" "$DIST/web/index.html"
  cp "$ROOT/web/manifest.json" "$DIST/web/manifest.json"
  cp "$ROOT/web/bridge.html" "$ROOT/web/peerjs.min.js" "$DIST/web/" # internet play: the bridge page and PeerJS
  rm -rf "$DIST/web/theme"
  touch "$DIST/web/.nojekyll"
  [ -f "$DIST/web/love.wasm" ] && [ -f "$DIST/web/game.data" ] || die "web build is incomplete"
}

# The GitHub Pages site: the landing page (site/) at the root and the game under play/.
build_site() {
  log "Building the site"
  local out="$DIST/site"
  rm -rf "$out"
  mkdir -p "$out/media" "$out/fonts"
  cp "$ROOT/site/index.html" "$out/index.html"
  cp "$ROOT"/docs/media/{logo,card-pick,arena-1,arena-2,arena-3,recap,editor,cut-glass_cannon,cut-hydra,cut-black_hole}.png "$out/media/"
  cp "$ROOT/docs/media/gameplay.gif" "$out/media/"
  cp "$ROOT/assets/icon.png" "$out/media/icon.png"
  cp "$ROOT"/assets/fonts/*.ttf "$out/fonts/"
  cp -r "$DIST/web" "$out/play"
  touch "$out/.nojekyll"
}

# The browser version inside a desktop package (DIR/web), for LAN hosts to serve.
copy_web() {
  if [ -f "$DIST/web/index.html" ]; then
    mkdir -p "$1/web"
    cp "$DIST/web/index.html" "$DIST/web/game.js" "$DIST/web/game.data" "$DIST/web/love.js" "$DIST/web/love.wasm" \
      "$DIST/web/bridge.html" "$DIST/web/peerjs.min.js" "$1/web/"
  else
    log "No dist/web: this package's LAN host won't serve the browser version"
  fi
}

# Web first, so the desktop packages can include it.
maybe_web() {
  if command -v npx >/dev/null; then build_web; else rm -rf "$DIST/web"; log "Skipping web build (Node.js not installed)"; fi
}

mkdir -p "$CACHE" "$DIST"
case "$TARGET" in
  all) build_love; maybe_web; build_linux; build_windows ;;
  linux) build_love; maybe_web; build_linux ;;
  windows) build_love; maybe_web; build_windows ;;
  web) build_love; build_web ;;
  site) build_love; build_web; build_site ;;
  love) build_love ;;
  *) die "unknown target '$TARGET' (use all, linux, windows, web, site or love)" ;;
esac

log "Done:"
ls -lh "$DIST"
