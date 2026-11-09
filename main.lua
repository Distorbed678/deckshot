local app = require "core.app"
local steam = require "online.steam"
local session = require "online.session"
local lan = require "online.lan"
local Settings = require "core.settings"
local Bloom = require "gfx.bloom"
local platform = require "core.platform"
local sfx = require "gfx.sfx"
local Glyphs = require "core.glyphs"

-- A friendly crash screen: the error is saved to crash.txt in the save folder, and can be copied.
function love.errorhandler(msg)
  msg = tostring(msg)
  local trace = debug.traceback("Error: " .. msg, 2):gsub("\n[^\n]+$", "")
  pcall(love.filesystem.write, "crash.txt", os.date("%Y-%m-%d %H:%M:%S") .. "\n" .. trace .. "\n")
  print(trace)
  if not love.window or not love.graphics or not love.event then return end
  if not love.graphics.isCreated() or not love.window.isOpen() then
    if not pcall(love.window.setMode, 800, 600) then return end
  end
  love.graphics.reset()
  pcall(love.graphics.setCanvas)
  if love.mouse then love.mouse.setVisible(true); love.mouse.setGrabbed(false) end
  if love.audio then love.audio.stop() end
  local font = love.graphics.newFont(16)
  local big = love.graphics.newFont(28)
  local copied = false
  local function draw()
    local w, h = love.graphics.getDimensions()
    love.graphics.clear(0.09, 0.09, 0.12)
    love.graphics.setColor(1, 0.55, 0.15)
    love.graphics.setFont(big)
    love.graphics.printf("Deckshot crashed", 40, 40, w - 80, "left")
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.setFont(font)
    love.graphics.printf("Sorry! The error was saved to crash.txt in the game's save folder (" ..
      love.filesystem.getSaveDirectory() .. ").\n\nC: copy the error   R: restart   Esc: quit" ..
      (copied and "\n\nCopied to the clipboard." or ""), 40, 90, w - 80, "left")
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.printf(trace, 40, 210, w - 80, "left")
    love.graphics.present()
  end
  return function()
    love.event.pump()
    for e, a in love.event.poll() do
      if e == "quit" then return 1 end
      if e == "keypressed" and a == "escape" then return 1 end
      if e == "keypressed" and a == "c" then
        pcall(love.system.setClipboardText, trace)
        copied = true
      end
      if e == "keypressed" and a == "r" then return "restart" end
    end
    draw()
    if love.timer then love.timer.sleep(0.1) end
  end
end

-- The window and taskbar icon (the .exe and AppImage icons are set in build.sh).
local function setIcon()
  if platform.web or not love.window or not love.window.setIcon then return end
  local ok, img = pcall(love.image.newImageData, "assets/icon.png")
  if ok then pcall(love.window.setIcon, img) end
end

function love.load(args)
  setIcon()
  require("core.desktopentry").install()
  love.keyboard.setKeyRepeat(false)
  Settings.load()
  Settings.apply()
  require("core.achievements").check(true) -- progress from before achievements existed
  app.load()
  app.showFps = Settings.values.showFps
  Bloom.load(app.W, app.H)
  sfx.load()

  steam.init() -- normally already done in conf.lua; this is a no-op then
  session.init()
  session.onEntered = function()
    require("online.active").use(session)
    app.switch(require("screens.lobby").new())
  end
  lan.onEntered = function()
    require("online.active").use(lan)
    app.switch(require("screens.lobby").new())
  end

  app.instant()
  app.switch(require("screens.splash").new())

  -- Launched from a Steam invite: "+connect_lobby <id>"
  for i, a in ipairs(args or {}) do
    if a == "+connect_lobby" and args[i + 1] then session.joinLobby(args[i + 1]) end
  end
end

require "gfx.fx"
require "gfx.sfx"
require "gfx.objectview"
require "gfx.playerview"
require "gfx.bulletview"

function love.update(dt)
  dt = math.min(dt, 1 / 30)
  steam.update()
  session.update()
  lan.update()
  Settings.update()
  sfx.update()
  require("gfx.music").update(dt)
  pcall(require("online.discord").update, dt)
  require("core.webkeyboard").update()
  app.update(dt)
  require("online.voice").update()
  lan.flush()
end

function love.draw()
  app.draw()
end

function love.keypressed(key, scancode, isrepeat)
  Glyphs.use("keys")
  local alt = love.keyboard.isDown("lalt", "ralt")
  if not platform.web and not isrepeat and (key == "f11" or ((key == "return" or key == "kpenter") and alt)) then
    Settings.toggleFullscreen()
    return
  end
  app.keypressed(key, scancode, isrepeat)
end

function love.keyreleased(key)
  app.keyreleased(key)
end

function love.mousepressed(x, y, button)
  app.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
  app.mousereleased(x, y, button)
end

function love.wheelmoved(x, y)
  app.wheelmoved(x, y)
end

function love.mousemoved(x, y, dx, dy, istouch)
  if not istouch and math.abs(dx or 0) + math.abs(dy or 0) > 2 then Glyphs.use("keys") end
  app.mousemoved()
end

function love.gamepadaxis(joystick, axis, value)
  if math.abs(value) > 0.5 then Glyphs.use("pad", joystick) end
end

function love.textinput(t)
  app.textinput(t)
end

-- Touch: drives the touch controls; touches also arrive as mouse clicks for menus.
function love.touchpressed(id, x, y)
  Glyphs.use("touch")
  local Touch = require "core.touch"
  local first = not Touch.enabled
  Touch.pressed(id, x, y)
  local v = Settings.values
  if first and Touch.enabled and platform.web and not v.mobileDefaults then
    -- A phone or tablet: lighter effects by default.
    v.mobileDefaults, v.bloom, v.particles = true, false, 1
    Settings.applyEffects()
    Settings.save()
  end
end

function love.touchmoved(id, x, y)
  require("core.touch").moved(id, x, y)
end

function love.touchreleased(id)
  require("core.touch").released(id)
end

function love.gamepadpressed(joystick, button)
  Glyphs.use("pad", joystick)
  app.gamepadpressed(joystick, button)
end

function love.focus(focused)
  sfx.focus(focused, Settings.values.muteUnfocused)
end

-- LÖVE 11.5's default loop plus an optional frame cap (Settings.values.maxFps).
-- Not in the browser: love.js drives frames itself, and sleeping would block the page.
if not platform.web then
  function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    if love.timer then love.timer.step() end

    local dt = 0
    local nextFrame = love.timer.getTime()
    return function()
      if love.event then
        love.event.pump()
        for name, a, b, c, d, e, f in love.event.poll() do
          if name == "quit" then
            if not love.quit or not love.quit() then return a or 0 end
          end
          love.handlers[name](a, b, c, d, e, f)
        end
      end

      dt = love.timer.step()
      if love.update then love.update(dt) end

      if love.graphics and love.graphics.isActive() then
        love.graphics.origin()
        love.graphics.clear(love.graphics.getBackgroundColor())
        if love.draw then love.draw() end
        love.graphics.present()
      end

      local cap = Settings.values.maxFps
      if cap and cap > 0 then
        local now = love.timer.getTime()
        nextFrame = math.max(nextFrame + 1 / cap, now - 1 / cap)
        local wait = nextFrame - now
        -- Sleep for most of the wait, then spin for precision.
        if wait > 0.002 then love.timer.sleep(wait - 0.0015) end
        while love.timer.getTime() < nextFrame do end
      else
        nextFrame = love.timer.getTime()
        love.timer.sleep(0.001)
      end
    end
  end
end

function love.quit()
  session.leave()
  lan.leave()
  steam.shutdown()
end
