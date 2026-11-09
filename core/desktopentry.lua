-- Linux AppImage: a desktop entry and icon in the user's folders, so the taskbar shows Deckshot's
-- icon (AppRun sets the window class to "deckshot", which is what the desktop matches on).
local platform = require "core.platform"

local Entry = {}

local function write(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

function Entry.text(appimage)
  return table.concat({
    "[Desktop Entry]", "Name=Deckshot", "Comment=2D duel game: lose a round, pick a card",
    'Exec="' .. appimage .. '"', "Icon=deckshot", "StartupWMClass=deckshot", "Type=Application",
    "Categories=Game;", "Terminal=false", "",
  }, "\n")
end

function Entry.install()
  if platform.web or love.system.getOS() ~= "Linux" then return end
  local appimage, home = os.getenv("APPIMAGE"), os.getenv("HOME")
  if not appimage or not home then return end
  pcall(function()
    local base = os.getenv("XDG_DATA_HOME")
    if not base or base == "" then base = home .. "/.local/share" end
    local apps, icons = base .. "/applications", base .. "/icons/hicolor/256x256/apps"
    local file, text = apps .. "/deckshot.desktop", Entry.text(appimage)
    if read(file) == text and read(icons .. "/deckshot.png") then return end -- up to date
    os.execute(('mkdir -p "%s" "%s"'):format(apps, icons))
    write(file, text)
    local icon = love.filesystem.read("assets/icon.png")
    if icon then write(icons .. "/deckshot.png", icon) end
  end)
end

return Entry
