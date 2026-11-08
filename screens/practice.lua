-- Practice range: you against a dummy that can't die, with any cards you like (C / the Cards button).
local Settings = require "core.settings"

local Practice = {}

-- opts.tutorial: the guided first-run steps on top of the range.
function Practice.new(opts)
  opts = opts or {}
  local Touch = require "core.touch"
  local Input = require "core.input"
  local kind = Touch.enabled and "touch" or (Input.pads()[1] and Settings.values.padOnline and "pad1") or "p1"
  local Map = require "game.map"
  local map = Map.byId.open_field or Map.list[1]
  return require("screens.match").newLocal(99, {
    setup = { { kind = kind, color = 1, team = 1 }, { kind = "dummy", color = 2, team = 2 } },
    map = map, practice = true, tutorial = opts.tutorial, tutorialReturn = opts.tutorialReturn,
    returnTo = nil,
  })
end

return Practice
