-- Steam rich presence: what friends see in their friends list. Safe without Steam.
local presence = { last = nil }

function presence.set(text)
  if text == presence.last then return end
  presence.last = text
  local steam = require "online.steam"
  if steam.available then pcall(require("online.session").setPresence, text) end
  pcall(require("online.discord").set, "Deckshot", text)
end

return presence
