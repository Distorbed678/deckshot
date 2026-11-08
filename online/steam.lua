-- Loads luasteam and initializes Steam. Every failure is caught: if anything is
-- missing (Steam not running, libraries absent, unsupported OS) steam.available is false and
-- steam.error explains why, so the rest of the game keeps working offline.
local steam = { available = false, Steam = nil, error = nil, tried = false }

local APP_ID = "480" -- Spacewar, Valve's public test app

-- Steam libraries per OS: the Steamworks API library and the luasteam Lua module.
local LIBS = {
  Windows = { api = "steam_api64.dll", ext = "dll", dir = "windows" },
  Linux = { api = "libsteam_api.so", ext = "so", dir = "linux" },
}

-- Folder holding the Steam libraries: lib/<platform>/ in the repo when run with `love .`,
-- the executable's folder for a packaged build (Deckshot.exe / inside the AppImage).
local function libDir(libs)
  local src = love.filesystem.getSource()
  if love.filesystem.isFused() or src:match("%.love$") then
    return love.filesystem.getSourceBaseDirectory()
  end
  return src .. "/lib/" .. libs.dir
end

-- Tell steam_api which app we are, without depending on the working directory.
local function setAppId(ffi)
  if ffi.os == "Windows" then
    pcall(ffi.cdef, "int SetEnvironmentVariableA(const char* name, const char* value);")
    ffi.C.SetEnvironmentVariableA("SteamAppId", APP_ID)
    ffi.C.SetEnvironmentVariableA("SteamGameId", APP_ID)
  else
    pcall(ffi.cdef, "int setenv(const char* name, const char* value, int overwrite);")
    ffi.C.setenv("SteamAppId", APP_ID, 1)
    ffi.C.setenv("SteamGameId", APP_ID, 1)
  end
end

function steam.init()
  if steam.tried then return steam.available end
  steam.tried = true

  local ok, err = pcall(function()
    if love._os == "Web" then error("Online play needs the desktop version of the game") end
    local ffi = require "ffi"
    local libs = LIBS[ffi.os]
    if not libs or ffi.arch ~= "x64" then error("Online play needs 64-bit Windows or Linux") end
    local dir = libDir(libs)
    setAppId(ffi)

    -- Load the Steam API from our folder first (globally, on Linux) so luasteam's
    -- dependency on it resolves to this copy.
    local okLib, lib = pcall(ffi.load, dir .. "/" .. libs.api, true)
    if not okLib then error(libs.api .. " is missing from the game folder") end
    steam.apiLib = lib -- keep a reference so it stays loaded

    package.cpath = dir .. "/?." .. libs.ext .. ";" .. package.cpath
    local okReq, Steam = pcall(require, "luasteam")
    if not okReq then error("luasteam." .. libs.ext .. " could not be loaded: " .. tostring(Steam)) end
    if not Steam.Init() then error("Steam is not running. Start Steam, log in, then restart the game.") end
    steam.Steam = Steam
  end)

  steam.available = ok
  if not ok then
    steam.error = tostring(err):gsub("^.-:%d+: ", "")
  end
  return ok
end

function steam.update()
  if steam.available then steam.Steam.RunCallbacks() end
end

function steam.shutdown()
  if steam.available then
    pcall(steam.Steam.Shutdown)
    steam.available = false
  end
end

function steam.myId()
  if not steam.available then return nil end
  return tostring(steam.Steam.User.GetSteamID())
end

function steam.myName()
  if not steam.available then return "Player" end
  return steam.Steam.Friends.GetPersonaName()
end

return steam
