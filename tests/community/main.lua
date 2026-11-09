io.stdout:setvbuf("no")
package.path = os.getenv("DECKSHOT_REPO") .. "/?.lua;" .. package.path
function love.load()
  local Map = require "game.map"
  local CardData = require "game.carddata"
  local Community = require "core.community"
  local bad = 0
  local function fail(name, why) bad = bad + 1; print("FAIL " .. name .. ": " .. why) end
  local function each(kind, check)
    for _, f in ipairs(love.filesystem.getDirectoryItems("community/" .. kind)) do
      if not Community.safeName(f) then
        fail(f, "file names may only use letters, numbers, - and _, and end in .txt")
      else
        local text = love.filesystem.read("community/" .. kind .. "/" .. f)
        if #text > 64 * 1024 then fail(f, "over 64 KB") else check(f, text) end
      end
    end
  end
  each("maps", function(f, text)
    local m, err = Map.parse(text)
    if not m then fail(f, tostring(err)) else print("OK map " .. m.name) end
  end)
  each("cards", function(f, text)
    local ok, def = pcall(CardData.parse, text)
    if not ok or not def then fail(f, "doesn't load as a card") else print("OK card " .. def.name) end
  end)
  print(bad == 0 and "END" or "FAILED")
  love.event.quit(bad == 0 and 0 or 1)
end
