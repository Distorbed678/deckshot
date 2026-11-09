-- The Community browser's connection to GitHub: lists and downloads the maps and custom cards in
-- the repo's community/ folder. Additions arrive as pull requests, so nothing here needs a login.
-- Downloads run in a thread through curl (as the updater does), so the game never hangs. Desktop only.
local Community = {
  TREE_URL = "https://api.github.com/repos/Distorbed678/deckshot/git/trees/main?recursive=1",
  RAW_URL = "https://raw.githubusercontent.com/Distorbed678/deckshot/main/",
  NEW_FILE_URL = "https://github.com/Distorbed678/deckshot/new/main/community/",
  entries = { maps = {}, cards = {} }, state = "idle", contents = {},
}

local WORKER = [[
require "love.timer"
local requests, results = ...
while true do
  local job = requests:demand()
  local p = io.popen('curl -L -s -f -m 25 --max-filesize 2000000 "' .. job.url .. '"', "r")
  local body = p and p:read("*a") or nil
  local closed = p and p:close()
  results:push({ key = job.key, body = (body and #body > 0) and body or nil, ok = closed ~= nil and closed ~= false })
end
]]

local thread, requests, results

local function ensureThread()
  if thread then return end
  requests, results = love.thread.newChannel(), love.thread.newChannel()
  thread = love.thread.newThread(WORKER)
  thread:start(requests, results)
end

local function ask(key, url)
  ensureThread()
  requests:push({ key = key, url = url })
end

-- Only plain names ever reach the command line, whatever a pull request's file is called.
local function safeName(name)
  return name:match("^[%w_%-]+%.txt$") ~= nil and #name <= 64
end
Community.safeName = safeName

function Community.refresh()
  Community.state = "loading"
  Community.error = nil
  ask("tree", Community.TREE_URL)
end

-- Fetch one file's text (kind: "maps" or "cards"); it appears in Community.contents when ready.
function Community.fetch(kind, file)
  local path = "community/" .. kind .. "/" .. file
  if Community.contents[path] ~= nil or not safeName(file) then return end
  Community.contents[path] = false
  ask(path, Community.RAW_URL .. path)
end

function Community.text(kind, file)
  return Community.contents["community/" .. kind .. "/" .. file]
end

local function readTree(body)
  local out = { maps = {}, cards = {} }
  for kind, file in body:gmatch('"path"%s*:%s*"community/(%a+)/([^"/]+)"') do
    if out[kind] and safeName(file) then out[kind][#out[kind] + 1] = file end
  end
  table.sort(out.maps)
  table.sort(out.cards)
  return out
end

function Community.update()
  if not results then return end
  while true do
    local r = results:pop()
    if not r then break end
    if r.key == "tree" then
      if r.body then
        Community.entries, Community.state = readTree(r.body), "ready"
      else
        Community.state, Community.error = "failed", "Couldn't reach GitHub. Check your connection and try again."
      end
    else
      Community.contents[r.key] = r.body or "failed"
    end
  end
end

-- GitHub's own "new file" page, filled in; a visitor without access is walked through a pull request.
-- Very long files don't fit in a link, so those go on the clipboard to paste. Returns "link" or "paste".
function Community.submit(kind, fileName, text)
  local function escape(s)
    return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
  end
  local base = Community.NEW_FILE_URL .. kind .. "?filename=" .. escape(fileName)
  local full = base .. "&value=" .. escape(text)
  if #full <= 7000 then
    love.system.openURL(full)
    return "link"
  end
  pcall(love.system.setClipboardText, text)
  love.system.openURL(base)
  return "paste"
end

return Community
