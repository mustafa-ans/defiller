--[[ ============================================================
  Defiller  -  auto-skip filler in local video, for VLC
  ------------------------------------------------------------
  Mark start/end ranges (filler, recaps, intros, "next episode"
  previews). Once you SAVE them, the companion background engine
  (defiller-intf.lua) skips those ranges AUTOMATICALLY during
  normal playback -- no button to press.

  THIS PANEL is just for MARKING and SAVING ranges. Workflow:
    1. Play the episode. Open this panel (View > Defiller).
    2. At the filler start, click Mark Start.
    3. Let it play to the filler end, click Mark End -- this SAVES the
       range and closes the panel. It skips automatically from now on.
    4. To mark another section, reopen the panel (View > Defiller, a
       single click) and repeat. If you close mid-mark, your Start is
       remembered and pre-filled next time, even after a restart.
  Saved ranges live in a small, shareable ".skip" text file per
  video and are skipped automatically from then on.

  INSTALL (current user):
    Windows: %APPDATA%\vlc\lua\extensions\   (this file)
             %APPDATA%\vlc\lua\intf\          (defiller-intf.lua, the engine)
  ------------------------------------------------------------
  License: MIT.  100% offline. No network access.
============================================================ ]]

local US          = 1000000               -- VLC "time" variable is microseconds
local FILE_PREFIX = "defiller-"
local FILE_SUFFIX = ".skip"
local PEND_SUFFIX = ".pending"            -- un-committed Start/End (QoL persistence)

-- Dialog grid: keep these stable so the ranges dropdown can be rebuilt.
local LIST_COL, LIST_ROW, LIST_CW = 1, 7, 3

-- Runtime state -------------------------------------------------
local dlg                 -- dialog handle
local w        = {}       -- widget handles
local segments = {}       -- list of { s = startSeconds, e = endSeconds }
local cur_uri  = nil      -- uri of the current file (used to re-enqueue)
local cur_name = nil      -- human-friendly name
local cur_key  = nil      -- sanitized storage key (basename)

----------------------------------------------------------------
-- Small helpers (defined before anything that uses them)
----------------------------------------------------------------
local function log(m)
  if vlc and vlc.msg then vlc.msg.info("[Defiller] " .. tostring(m)) end
end

local function get_input()
  return vlc.object.input()
end

-- Current playback position, in seconds (or nil if nothing playing).
local function now_seconds()
  local inp = get_input()
  if not inp then return nil end
  local ok, t = pcall(vlc.var.get, inp, "time")
  if not ok or not t then return nil end
  return t / US
end

local function current_item_uri()
  local item = vlc.input.item()
  if not item then return nil end
  local ok, u = pcall(function() return item:uri() end)
  if ok then return u end
  return nil
end

local function current_item_name()
  local item = vlc.input.item()
  if not item then return nil end
  local ok, n = pcall(function() return item:name() end)
  if ok and n and n ~= "" then return n end
  return nil
end

local function basename_from_uri(uri)
  if not uri then return nil end
  local decoded = uri
  if vlc.strings and vlc.strings.decode_uri then
    local ok, d = pcall(vlc.strings.decode_uri, uri)
    if ok and d then decoded = d end
  end
  decoded = decoded:gsub("[?#].*$", "")              -- drop any query/fragment
  local base = decoded:match("([^/\\]+)$") or decoded -- text after last slash
  return base
end

local function sanitize(s)
  return (s:gsub("[^%w%._%-]", "_"))
end

local function config_dir()
  if vlc.config and vlc.config.configdir then
    local ok, d = pcall(vlc.config.configdir)
    if ok and d and d ~= "" then return d end
  end
  return "."
end

local function path_sep(dir)
  if dir and string.find(dir, "\\", 1, true) then return "\\" end
  return "/"
end

local function storage_path(key)
  local dir = config_dir()
  return dir .. path_sep(dir) .. FILE_PREFIX .. key .. FILE_SUFFIX
end

local function pending_path(key)
  local dir = config_dir()
  return dir .. path_sep(dir) .. FILE_PREFIX .. key .. PEND_SUFFIX
end

local function fmt(t)
  if not t then return "?" end
  local m = math.floor(t / 60)
  local s = t - m * 60
  return string.format("%d:%05.2f", m, s)
end

----------------------------------------------------------------
-- Segment list logic
----------------------------------------------------------------
local function sort_merge()
  table.sort(segments, function(a, b) return a.s < b.s end)
  local merged = {}
  for _, seg in ipairs(segments) do
    local last = merged[#merged]
    if last and seg.s <= last.e then
      if seg.e > last.e then last.e = seg.e end       -- merge overlapping ranges
    else
      table.insert(merged, { s = seg.s, e = seg.e })
    end
  end
  segments = merged
end

local function add_segment(s, e)
  if not s or not e then return false, "Enter a numeric start and end (in seconds)." end
  if s < 0 then s = 0 end
  if e <= s then return false, "End must be greater than start." end
  table.insert(segments, { s = s, e = e })
  sort_merge()
  return true
end

-- The parts of the file we DO want to play = complement of the skips.
local function keep_segments()
  sort_merge()
  local keeps = {}
  local cursor = 0
  for _, seg in ipairs(segments) do
    if seg.s > cursor then
      table.insert(keeps, { s = cursor, e = seg.s })
    end
    if seg.e > cursor then cursor = seg.e end
  end
  table.insert(keeps, { s = cursor, e = nil })         -- final keep runs to EOF
  return keeps
end

----------------------------------------------------------------
-- Persistence  (plain-text ".skip" format; human-readable + shareable)
----------------------------------------------------------------
local function save_list()
  if not cur_key then return false, "No file is open." end
  sort_merge()
  local path = storage_path(cur_key)
  local f, err = io.open(path, "w")
  if not f then return false, "Cannot write file: " .. tostring(err) end
  f:write("# Defiller skip list\n")
  f:write("# file: " .. tostring(cur_name or cur_key) .. "\n")
  f:write("# Each line below is one skip range in seconds:  START,END\n")
  f:write("# Lines starting with # are ignored. Edit freely.\n")
  for _, seg in ipairs(segments) do
    f:write(string.format("%.3f,%.3f\n", seg.s, seg.e))
  end
  f:close()
  return true, path
end

local function load_key(key)
  segments = {}
  local path = storage_path(key)
  local f = io.open(path, "r")
  if not f then return end
  for line in f:lines() do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local s, e = line:match("^%s*([%d%.]+)%s*,%s*([%d%.]+)")
      if s and e then
        table.insert(segments, { s = tonumber(s), e = tonumber(e) })
      end
    end
  end
  f:close()
  sort_merge()
end

-- Pending = the half-finished Start/End for THIS video. Saved to disk so it
-- survives closing the panel or restarting the PC, then pre-filled on reopen.
local function save_pending()
  if not cur_key then return end
  local s = (w.start_in and w.start_in:get_text()) or ""
  local e = (w.end_in   and w.end_in:get_text())   or ""
  local f = io.open(pending_path(cur_key), "w")
  if f then f:write(tostring(s) .. "\n" .. tostring(e) .. "\n"); f:close() end
end

local function load_pending(key)
  if not key then return "", "" end
  local f = io.open(pending_path(key), "r")
  if not f then return "", "" end
  local s = f:read("*l") or ""
  local e = f:read("*l") or ""
  f:close()
  return s, e
end

local function clear_pending()
  if not cur_key then return end
  local f = io.open(pending_path(cur_key), "w")
  if f then f:write("\n\n"); f:close() end   -- blank lines = nothing pending
end

local function load_current()
  cur_uri  = current_item_uri()
  cur_name = current_item_name()
  if cur_uri then
    local base = basename_from_uri(cur_uri)
    cur_name = cur_name or base
    cur_key  = sanitize(base or "unknown")
    load_key(cur_key)
  else
    cur_key  = nil
    segments = {}
  end
end

----------------------------------------------------------------
-- Apply skips now by rebuilding the playlist (optional preview;
-- the background engine already skips saved ranges automatically).
----------------------------------------------------------------
local function apply_and_play()
  if not cur_uri then return false, "No file is playing." end
  if #segments == 0 then return false, "No skip ranges defined yet." end
  local keeps = keep_segments()
  local items = {}
  for _, k in ipairs(keeps) do
    local options = {}
    if k.s and k.s > 0 then
      table.insert(options, "start-time=" .. string.format("%.3f", k.s))
    end
    if k.e then
      table.insert(options, "stop-time=" .. string.format("%.3f", k.e))
    end
    table.insert(items, { path = cur_uri, options = options })
  end
  vlc.playlist.clear()
  vlc.playlist.add(items)
  return true
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local function set_status(m)
  if w.status then w.status:set_text(tostring(m)) end
end

local function refresh_time()
  local t = now_seconds()
  if w.cur then w.cur:set_text("Now at: " .. (t and fmt(t) or "-")) end
end

local function refresh_list()
  if not dlg then return end
  if w.list then dlg:del_widget(w.list) end
  w.list = dlg:add_dropdown(LIST_COL, LIST_ROW, LIST_CW, 1)
  for i, seg in ipairs(segments) do
    w.list:add_value(string.format("%d.   %s  ->  %s", i, fmt(seg.s), fmt(seg.e)), i)
  end
end

local function refresh_all()
  if not dlg then return end
  if w.file then
    w.file:set_text("File: " .. (cur_name or "(nothing playing)"))
  end
  refresh_list()
  refresh_time()
end

-- Button callbacks (global so the dialog can reference them) -----
function on_refresh_time()
  refresh_time()
end

function on_mark_start()
  local t = now_seconds()
  if t and w.start_in then w.start_in:set_text(string.format("%.2f", t)) end
  save_pending()
  refresh_time()
  set_status("Start marked. Play to the filler end, then click Mark End - it saves the range and closes.")
end

function on_mark_end()
  local t = now_seconds()
  if t and w.end_in then w.end_in:set_text(string.format("%.2f", t)) end
  refresh_time()
  -- Auto-add: commit the range immediately when Start+End are valid, so the
  -- user goes straight from Mark End to a save-ready range (one less click).
  local s = tonumber(w.start_in:get_text())
  local e = tonumber(w.end_in:get_text())
  local ok, err = add_segment(s, e)
  if ok then
    clear_pending()
    local saved, info = save_list()
    if saved then
      -- Auto-close: deactivating the extension makes the NEXT View>Defiller a
      -- single click (fixes the 2-press reopen when adding multiple ranges).
      vlc.deactivate()
      return
    end
    refresh_list()
    w.start_in:set_text("")
    w.end_in:set_text("")
    set_status("Range added, but SAVE FAILED: " .. tostring(info) .. "  Try 'Save list'.")
  else
    save_pending()
    set_status("End marked, but not added yet: " .. err .. " Fix it, then click 'Add skip range'.")
  end
end

function on_add()
  local s = tonumber(w.start_in:get_text())
  local e = tonumber(w.end_in:get_text())
  local ok, err = add_segment(s, e)
  if not ok then set_status(err); return end
  refresh_list()
  w.start_in:set_text("")
  w.end_in:set_text("")
  clear_pending()
  set_status(string.format("Range added (%d total). Click 'Save list' to skip it automatically.", #segments))
end

function on_delete()
  local id = w.list and w.list:get_value()
  if not id or not segments[id] then set_status("Pick a range in the list first."); return end
  table.remove(segments, id)
  refresh_list()
  set_status("Deleted. Remember to Save list.")
end

function on_save()
  local ok, info = save_list()
  if ok then set_status("Saved. These ranges now skip automatically during playback.")
  else set_status("Save failed: " .. tostring(info)) end
end

function on_apply()
  on_save()
  local ok, err = apply_and_play()
  if ok then
    set_status("Previewing with skips applied (the engine also does this automatically).")
  else
    set_status("Cannot play: " .. tostring(err))
  end
end

local function build_widgets()
  w = { status = nil }
  w.title = dlg:add_label("<b>Defiller</b>  -  mark filler once; it skips automatically", 1, 1, 4, 1)
  w.file  = dlg:add_label("File: (nothing playing)", 1, 2, 4, 1)

  w.cur = dlg:add_label("Now at: -", 1, 3, 2, 1)
  dlg:add_button("Refresh time", on_refresh_time, 3, 3, 1, 1)
  dlg:add_button("Mark Start", on_mark_start, 4, 3, 1, 1)

  dlg:add_label("Start (s):", 1, 4, 1, 1)
  w.start_in = dlg:add_text_input("", 2, 4, 1, 1)
  dlg:add_label("End (s):", 3, 4, 1, 1)
  w.end_in = dlg:add_text_input("", 4, 4, 1, 1)

  dlg:add_button("Mark End", on_mark_end, 1, 5, 2, 1)
  dlg:add_button("Add skip range", on_add, 3, 5, 2, 1)

  dlg:add_label("<b>Skip ranges</b> (mm:ss.ss)", 1, 6, 4, 1)
  -- dropdown is created in refresh_list() at (LIST_COL, LIST_ROW)
  dlg:add_button("Delete selected", on_delete, 4, 7, 1, 1)

  dlg:add_button("Save list", on_save, 1, 8, 2, 1)
  dlg:add_button("Preview skips", on_apply, 3, 8, 2, 1)

  w.status = dlg:add_label("Tip: Mark Start -> play to the filler end -> Mark End. It saves & closes; reopen for the next.", 1, 9, 4, 1)
end

local function show_dialog()
  if dlg then dlg:delete() end
  dlg = vlc.dialog("Defiller")
  build_widgets()
  refresh_all()
  -- QoL: restore any half-finished Start/End for this video.
  local ps, pe = load_pending(cur_key)
  if w.start_in and ps and ps ~= "" then w.start_in:set_text(ps) end
  if w.end_in   and pe and pe ~= "" then w.end_in:set_text(pe) end
  if (ps and ps ~= "") or (pe and pe ~= "") then
    set_status("Restored your in-progress mark for this video:  Start=" ..
               ((ps and ps ~= "") and ps or "-") .. "   End=" ..
               ((pe and pe ~= "") and pe or "-") .. ".  Continue, or Add + Save.")
  end
end

----------------------------------------------------------------
-- VLC extension entry points
----------------------------------------------------------------
function descriptor()
  return {
    title     = "Defiller",
    version   = "1.1",
    author    = "vlc_timestamps",
    url       = "",
    shortdesc = "Defiller - auto-skip filler in local video",
    description = "Mark start/end ranges to skip (filler, recaps, intros). "
              .. "Saves a small, shareable .skip list per video; the background "
              .. "engine then skips those ranges automatically during playback.",
    capabilities = { "input-listener" }   -- so input_changed() is called on file change
  }
end

function activate()
  log("activate")
  load_current()
  show_dialog()
end

function deactivate()
  log("deactivate")
  if dlg then dlg:delete() end
  dlg = nil
end

-- Closing the panel (X) deactivates the extension so the View-menu item
-- un-checks; clicking it again cleanly reopens the panel.
function close()
  vlc.deactivate()
end

function meta_changed() end

-- Called when the playing input changes (new file).
-- IMPORTANT: only refresh DATA here, never touch dialog widgets. This callback
-- runs on VLC's input thread; manipulating widgets from it deadlocks the dialog.
function input_changed()
  load_current()
end
