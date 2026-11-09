-- Gameplay never talks to the visual and audio systems directly. It calls Events.fx.<name>(...)
-- and Events.sfx.<name>(...); whichever presentation modules are loaded handle them. With none
-- loaded (a dedicated host, a headless test) these calls simply do nothing.
local Events = { handlers = {} }

local function channel(name)
  return setmetatable({}, { __index = function(t, method)
    local function send(...)
      local h = Events.handlers[name]
      if h and h[method] then return h[method](...) end
    end
    rawset(t, method, send)
    return send
  end })
end

Events.fx = channel("fx")
Events.sfx = channel("sfx")

-- A presentation module registers itself for a channel.
function Events.handle(name, module)
  Events.handlers[name] = module
end

return Events
