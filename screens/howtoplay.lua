-- How to Play: the rules in short and the controls for every way to play.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local Input = require "core.input"
local Glyphs = require "core.glyphs"

local Screen = {}
Screen.__index = Screen

local PAGES = { "Rules", "Keyboard", "Online / Mouse", "Gamepad", "Touch" }
local TUTORIAL_RETURN = function() return require("screens.howtoplay").new() end

function Screen.new(back)
  return setmetatable({ page = 1, back = back }, Screen)
end

function Screen:close()
  if self.back then app.pop() else app.switch(require("screens.menu").new()) end
end

function Screen:keypressed(key)
  if key == "escape" then self:close()
  elseif key == "left" then self.page = (self.page - 2) % #PAGES + 1
  elseif key == "right" then self.page = self.page % #PAGES + 1 end
end

local RULES = {
  { "Win rounds", "Last player (or team) standing wins the round. First to the target score wins the match." },
  { "Lose, then pick", "Everyone who lost the round picks an upgrade card. Cards are dealt face down: hover one to turn it over. Every card stacks, and cards work together: explosive bullets that bounce explode at every bounce." },
  { "Block", "Blocking stops bullets (they bounce back at the shooter), hazards and the arena edges. It has a cooldown, so time it." },
  { "Melee", "Tap for a quick light hit, hold to charge a heavy hit that lunges forward. If the other player blocks your melee, you're stunned: the harder the hit, the longer the stun." },
  { "Movement", "Double jump and air dash are built in. Wall slide and wall jump; press down + jump to drop through thin platforms. Hold down in the air to fall faster." },
  { "King of the Hill", "An optional mode: stand alone in the moving zone to score, and first to the target wins the round. You respawn after a few seconds." },
  { "The arena", "The screen's left, right and bottom edges hurt and throw you back in; the top is open. Saws, spikes, lasers and fire hurt; crates, barrels and ropes break. When the round timer runs out, a red barrier closes in from every side." },
}

local function kv(lines, x, y, w)
  for _, l in ipairs(lines) do
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 0.8, 0.35)
    love.graphics.printf(l[1], x, y, 260, "right")
    love.graphics.setColor(1, 1, 1, 0.85)
    if l[2]:find("{", 1, true) then
      Glyphs.print(l[2], app.fonts.med, x + 290, y, w - 290, "left", { 1, 1, 1, 0.85 })
    else
      love.graphics.printf(l[2], x + 290, y, w - 290, "left")
    end
    local _, wrapped = app.fonts.med:getWrap(l[2], w - 290)
    y = y + math.max(1, #wrapped) * app.fonts.med:getHeight() + 14
  end
end

function Screen:draw()
  love.graphics.setColor(0.09, 0.09, 0.12, self.back and 0.97 or 1)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered("HOW TO PLAY", app.fonts.big, 20)
  local tw = 200
  local tx = (app.W - (#PAGES * (tw + 10) - 10)) / 2
  for i, name in ipairs(PAGES) do
    if ui.button(name, tx + (i - 1) * (tw + 10), 86, tw, 40, { font = app.fonts.med, color = i == self.page and ui.ACCENT or nil }) then
      self.page = i
    end
  end
  local x, y, w = 140, 150, 1000
  local name = Input.keyName
  local b = Settings.values.binds
  if self.page == 1 then
    kv(RULES, x - 60, y, w + 60)
  elseif self.page == 2 then
    local function scheme(s)
      return {
        { "Move", name(s.left) .. " / " .. name(s.right) }, { "Jump", name(s.up) .. " (hold for higher)" },
        { "Aim", "faces where you move; hold " .. name(s.up) .. " / " .. name(s.down) .. " to aim up / down" },
        { "Fire", name(s.fire) }, { "Block", name(s.block) }, { "Dash", name(s.dash) },
        { "Melee", name(s.melee) .. " (hold for heavy)" },
      }
    end
    love.graphics.setFont(app.fonts.title)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Player 1", x, y, w / 2, "center")
    love.graphics.printf("Player 2", x + w / 2, y, w / 2, "center")
    local function col(lines, cx)
      local yy = y + 44
      for _, l in ipairs(lines) do
        love.graphics.setFont(app.fonts.med)
        love.graphics.setColor(1, 0.8, 0.35)
        love.graphics.printf(l[1], cx, yy, 120, "right")
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.printf(l[2], cx + 140, yy, w / 2 - 150, "left")
        local _, wr = app.fonts.med:getWrap(l[2], w / 2 - 150)
        yy = yy + #wr * app.fonts.med:getHeight() + 10
      end
    end
    col(scheme(b.p1), x)
    col(scheme(b.p2), x + w / 2)
  elseif self.page == 3 then
    local o = b.online
    kv({ { "Move", name(o.left) .. " / " .. name(o.right) }, { "Jump", name(o.jump) .. " or " .. name(o.jump2) },
      { "Aim", "the mouse" }, { "Fire", name(o.fire) }, { "Block", name(o.block) },
      { "Dash", name(o.dash) .. " (toward the mouse, or the way you move)" }, { "Melee", name(o.melee) .. " (hold for heavy)" },
      { "Fast fall / drop", name(o.down) .. "  (+ jump on a thin platform)" },
      { "Scoreboard", name(o.scoreboard) }, { "Chat", name(o.chat) }, { "Menu", "Esc" } }, x, y, w)
  elseif self.page == 4 then
    kv({ { "Move", "{ls}  (down: fast fall / drop)" }, { "Aim", "{rs}" }, { "Fire", "{rt}" },
      { "Block", "{lt}  or  {rb}" }, { "Jump", "{a}" }, { "Dash", "{b}  or  {lb}" },
      { "Melee", "{x}  (hold for heavy)" }, { "Discard a card", "{y}" }, { "Scoreboard", "{back}" }, { "Pause", "{start}" },
      { "Menus", "{dpad}  and  {a},  {b} to go back" } }, x, y, w)
  else
    kv({ { "Move", "drag on the left half (push up to jump, down to drop)" },
      { "Aim and fire", "drag on the right half; it fires while you hold. A quick tap fires once." },
      { "Buttons", "Jump, Block, Dash, Melee (hold for heavy) and pause" },
      { "Layout", "Settings > Controls > Touch layout lets you move and resize the buttons" },
      { "LAN", "Phones join a computer's LAN game by scanning the QR code in its lobby" } }, x, y, w)
  end
  if ui.button("Start Tutorial", app.W / 2 - 310, 650, 300, 46, { color = ui.GOOD }) then
    app.switch(require("screens.practice").new({ tutorial = true, tutorialReturn = TUTORIAL_RETURN }))
  end
  if ui.button("Back", app.W / 2 + 10, 650, 300, 46, { back = true }) then self:close() end
end

return Screen
