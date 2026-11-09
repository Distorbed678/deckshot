-- Saved matches: pick one to watch.
local app = require "core.app"
local ui = require "core.ui"
local Replay = require "online.replay"

local Screen = {}
Screen.__index = Screen

function Screen.new()
  return setmetatable({ files = Replay.list(), scroll = { y = 0 } }, Screen)
end

function Screen:keypressed(key)
  if key == "escape" then app.switch(require("screens.menu").new()) end
end

function Screen:wheelmoved(_, dy) ui.wheel(self.scroll, dy) end

function Screen:watch(file, asVideo)
  local T, err = Replay.open(file)
  if not T then
    self.message = err
    return
  end
  local net = require "online.net"
  local Match = require "screens.match"
  local first = T.entries[1]
  if not first or net.kind(first.data) ~= net.MSG.START then
    self.message = "That replay is damaged"
    return
  end
  local winScore, slots = net.decodeStart(first.data)
  local m = Match.newClient(slots, 0, winScore, T, "H", nil, { popEvents = function() return {} end })
  m.replayView = T
  if asVideo then
    local w, h = app.canvas:getDimensions()
    m.videoOut = Replay.startVideo(file, w, h)
    T.speed = 1
  end
  app.switch(m)
end

function Screen:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered("REPLAYS", app.fonts.huge, 50)
  if self.message then app.centered(self.message, app.fonts.med, 130, { 1, 0.55, 0.45 }) end
  local x, w, y0, h = 340, 600, 170, 440
  if #self.files == 0 then
    app.centered("No saved matches yet. Use Save Replay when a match ends.", app.fonts.med, 300, { 1, 1, 1, 0.6 })
  end
  ui.beginScroll(self.scroll, x, y0, w, h, #self.files * 60)
  local y = y0 - (self.scroll.y or 0)
  for _, f in ipairs(self.files) do
    local label = f:gsub("%.dsr$", ""):gsub("_", "  "):gsub("(%d%d)%-(%d%d)%-(%d%d)$", "%1:%2:%3")
    if ui.button(label, x, y, w - 240, 50, { font = app.fonts.med }) then self:watch(f) end
    if ui.button("Video", x + w - 232, y, 104, 50, { font = app.fonts.small, disabled = not Replay.hasFfmpeg() }) then self:watch(f, true) end
    if ui.button("Delete", x + w - 120, y, 110, 50, { font = app.fonts.small }) then
      love.filesystem.remove(Replay.DIR .. f)
      self.files = Replay.list()
      break
    end
    y = y + 60
  end
  ui.endScroll(self.scroll)
  if #self.files > 0 and not Replay.hasFfmpeg() then
    app.centered("Saving as a video needs ffmpeg installed on this computer.", app.fonts.small, 618, { 1, 1, 1, 0.5 })
  end
  if ui.button("Back", app.W / 2 - 120, 640, 240, 48, { back = true }) then app.switch(require("screens.menu").new()) end
end

return Screen
