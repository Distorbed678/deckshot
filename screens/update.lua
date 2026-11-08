-- The update prompt on the main menu: what's new, Update Now / Later, then download progress.
local app = require "core.app"
local ui = require "core.ui"
local Version = require "core.version"
local Updater = require "core.updater"

local Screen = {}
Screen.__index = Screen

function Screen.new() return setmetatable({ scroll = { y = 0 } }, Screen) end

function Screen:keypressed(key)
  if key == "escape" and Updater.state ~= "downloading" and Updater.state ~= "installing" then
    Updater.state = "idle"
    app.pop()
  end
end

function Screen:wheelmoved(_, dy) ui.wheel(self.scroll, dy) end
function Screen:update() Updater.update() end

function Screen:draw()
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local px, py, pw, ph = 190, 90, 900, 540
  ui.panel(px, py, pw, ph, 1)
  local rel = Version.release
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("Version " .. rel.version .. " is available", px, py + 20, pw, "center")
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.55)
  love.graphics.printf("You have " .. Version.VERSION, px, py + 58, pw, "center")

  local font = app.fonts.small
  local tw = pw - 90
  local _, wr = font:getWrap(rel.notes or "", tw)
  local top = py + 90
  local viewH = ph - 236
  local y = ui.beginScroll(self.scroll, px + 30, top, pw - 60, viewH, #wr * font:getHeight())
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.printf(rel.notes or "", px + 40, y, tw, "left")
  ui.endScroll(self.scroll)

  local by = py + ph - 74
  local st = Updater.state
  if st == "downloading" or st == "installing" then
    local bw = pw - 120
    love.graphics.setColor(1, 1, 1, 0.12)
    love.graphics.rectangle("fill", px + 60, by + 8, bw, 16, 8, 8)
    love.graphics.setColor(ui.GOOD)
    love.graphics.rectangle("fill", px + 60, by + 8, bw * Updater.progress, 16, 8, 8)
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.75)
    love.graphics.printf(st == "installing" and "Installing..." or ("Downloading " .. math.floor(Updater.progress * 100) .. "%"),
      px, by + 32, pw, "center")
    return
  end
  local canInstall = Updater.asset(rel) ~= nil
  if st == "failed" then
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(ui.BAD)
    love.graphics.printf(tostring(Updater.error) .. " Your game wasn't changed.", px + 20, by - 26, pw - 40, "center")
  elseif not canInstall then
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.printf("This copy can't update itself. Download the new version from github.com/" .. Version.REPO .. "/releases",
      px + 20, by - 26, pw - 40, "center")
  end
  local bw = 300
  if canInstall then
    if ui.button(st == "failed" and "Try Again" or "Update Now", px + pw / 2 - bw - 10, by, bw, 52, { color = ui.GOOD }) then
      Updater.start(rel)
    end
    if ui.button("Later", px + pw / 2 + 10, by, bw, 52, { back = true }) then
      Updater.state = "idle"
      app.pop()
    end
  elseif ui.button("Close", px + pw / 2 - bw / 2, by, bw, 52, { back = true }) then
    Updater.state = "idle"
    app.pop()
  end
end

return Screen
