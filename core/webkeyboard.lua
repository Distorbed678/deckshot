-- Browser only: the phone's on-screen keyboard for text fields. When a text field is focused on a
-- touch device, Lua prints "\27KBD show"; the page focuses a hidden <input> (which opens the
-- keyboard) and buffers what's typed. Every frame Lua prints "\27KBD poll"; the page writes the
-- buffer to /tmp/rckbd.txt and clears it, so nothing is read twice. "\b" = backspace, "\n" = enter.
local platform = require "core.platform"

local kb = { shown = false }
local FILE = "/tmp/rckbd.txt"

function kb.update()
  if not platform.web then return end
  local ui = require "core.ui"
  local Touch = require "core.touch"
  local typing = ui.textWasActive and true or false
  if typing ~= kb.typing then -- so the page lets the space key through to the text box
    kb.typing = typing
    print("\27KBD typing " .. (typing and "1" or "0"))
  end
  local want = ui.textWasActive and Touch.enabled
  if want and not kb.shown then
    print("\27KBD show")
    kb.shown = true
  elseif not want and kb.shown then
    print("\27KBD hide")
    kb.shown = false
  end
  if not kb.shown then return end
  print("\27KBD poll")
  local f = io.open(FILE, "rb")
  if not f then return end
  local text = f:read("*a") or ""
  f:close()
  if text == "" then return end
  local app = require "core.app"
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if ch == "\b" then
      app.keypressed("backspace")
    elseif ch == "\n" then
      app.keypressed("return")
    else
      app.textinput(ch)
    end
  end
end

return kb
