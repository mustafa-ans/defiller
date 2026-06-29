--[[============================================================
  Defiller - auto-skip engine  (VLC interface script / luaintf)

  Runs in the background while VLC plays. Four times a second it checks
  the playback position and, whenever it enters a saved skip range, it
  instantly jumps to the end of that range. Fully automatic - no button.

  Skip ranges are written by the companion extension (defiller.lua) to:
      <vlc-config-dir>/defiller-<sanitized filename>.skip
  One range per line:  START,END   (seconds, e.g.  90,120 )
  Blank lines and lines starting with # are ignored.

  Install: copy to  <vlc-config>/lua/intf/  then either launch with
      vlc --extraintf=luaintf --lua-intf=defiller-intf
  or make it always-on in vlcrc (extraintf=luaintf, lua-intf=defiller-intf).
============================================================]]--

local US           = 1000000   -- VLC measures time in microseconds
local POLL_US      = 250000     -- poll every 0.25 s
local RELOAD_EVERY = 8          -- re-read the .skip file ~ every 2 s
local EDGE         = 0.10       -- skip a range only if > 0.1 s remains in it

local cur_key  = nil
local segments = {}
local counter  = 0

local function path_sep(dir)
  if dir and string.find(dir, "\\", 1, true) then return "\\" end
  return "/"
end

local function config_dir()
  if vlc.config and vlc.config.configdir then
    local ok, d = pcall(vlc.config.configdir)
    if ok and d and d ~= "" then return d end
  end
  return "."
end

local function storage_path(key)
  local d = config_dir()
  return d .. path_sep(d) .. "defiller-" .. key .. ".skip"
end

local function basename_from_uri(uri)
  if not uri then return nil end
  local decoded = uri
  if vlc.strings and vlc.strings.decode_uri then
    local ok, d = pcall(vlc.strings.decode_uri, uri)
    if ok and d then decoded = d end
  end
  decoded = decoded:gsub("[?#].*$", "")
  return decoded:match("([^/\\]+)$") or decoded
end

local function sanitize(s) return (s:gsub("[^%w%._%-]", "_")) end

local function current_uri()
  local ok, item = pcall(function() return vlc.input.item() end)
  if ok and item then
    local ok2, uri = pcall(function() return item:uri() end)
    if ok2 and uri and uri ~= "" then return uri end
  end
  local ok3, id = pcall(function() return vlc.playlist.current() end)
  if ok3 and id then
    local ok4, it = pcall(function() return vlc.playlist.get(id) end)
    if ok4 and it and it.path and it.path ~= "" then return it.path end
  end
  return nil
end

local function load_segments(key)
  local segs = {}
  if not key then return segs end
  local f = io.open(storage_path(key), "r")
  if not f then return segs end
  for line in f:lines() do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local s, e = line:match("^%s*([%d%.]+)%s*,%s*([%d%.]+)")
      if s and e then
        s, e = tonumber(s), tonumber(e)
        if s and e and e > s then table.insert(segs, { s = s, e = e }) end
      end
    end
  end
  f:close()
  table.sort(segs, function(a, b) return a.s < b.s end)
  return segs
end

local function alive()
  if vlc.misc and vlc.misc.should_die then return not vlc.misc.should_die() end
  return true
end

local function nap()
  if vlc.misc and vlc.misc.mwait and vlc.misc.mdate then
    vlc.misc.mwait(vlc.misc.mdate() + POLL_US)
  else
    local t0 = os.clock(); while os.clock() - t0 < 0.25 do end
  end
end

while alive() do
  pcall(function()
    local input = vlc.object.input()
    if not input then cur_key, segments = nil, {}; return end

    local uri = current_uri()
    local key = uri and sanitize(basename_from_uri(uri) or "unknown") or nil
    if not key then return end

    if key ~= cur_key then
      cur_key = key; segments = load_segments(key); counter = 0
    else
      counter = counter + 1
      if counter >= RELOAD_EVERY then counter = 0; segments = load_segments(key) end
    end

    if #segments > 0 then
      local t = vlc.var.get(input, "time")
      if t then
        t = t / US
        for _, seg in ipairs(segments) do
          if t >= seg.s and (seg.e - t) > EDGE then
            vlc.var.set(input, "time", math.floor(seg.e * US))
            break
          end
        end
      end
    end
  end)
  nap()
end
