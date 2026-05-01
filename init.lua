-- av-pain-reliever
-- Location-aware AV switcher for macOS.
-- Watches USB events, fingerprints the current dock setup, and switches
-- system audio defaults + OBS scene to match. Profiles live in profiles.lua;
-- the engine here doesn't need editing for new locations.

local DEBOUNCE_SECONDS = 1.5
local FALLBACK_PROFILE = "laptop"
local OBS_CMD_SEARCH_PATHS = {
  "/opt/homebrew/bin/obs-cmd",
  "/usr/local/bin/obs-cmd",
  os.getenv("HOME") .. "/.cargo/bin/obs-cmd",
}
local LOG_DIR = os.getenv("HOME") .. "/.hammerspoon/logs"
local LOG_PATH = LOG_DIR .. "/av-pain-reliever.log"

local log = hs.logger.new("av", "info")

local function ensureLogDir()
  if not hs.fs.attributes(LOG_DIR) then
    hs.fs.mkdir(LOG_DIR)
  end
end

local function appendLog(line)
  ensureLogDir()
  local f = io.open(LOG_PATH, "a")
  if not f then return end
  f:write(os.date("%Y-%m-%d %H:%M:%S "), line, "\n")
  f:close()
end

local function logInfo(msg)
  log.i(msg)
  appendLog("INFO  " .. msg)
end

local function logWarn(msg)
  log.w(msg)
  appendLog("WARN  " .. msg)
end

local function findObsCmd()
  for _, path in ipairs(OBS_CMD_SEARCH_PATHS) do
    if hs.fs.attributes(path) then return path end
  end
  return nil
end

local OBS_CMD_PATH = findObsCmd()
if not OBS_CMD_PATH then
  logWarn("obs-cmd not found in " .. table.concat(OBS_CMD_SEARCH_PATHS, ", ") ..
          " — OBS scene switching will be skipped. Install with: cargo install obs-cmd")
end

local profiles = require("profiles")

-- Build a set of currently-attached (vid, pid) pairs.
local function attachedKeySet()
  local set = {}
  for _, d in ipairs(hs.usb.attachedDevices() or {}) do
    if d.vendorID and d.productID then
      set[string.format("%d:%d", d.vendorID, d.productID)] = true
    end
  end
  return set
end

-- Pick the most-specific matching profile. Ties broken alphabetically by name.
-- Returns the profile name (string).
local function resolveProfile()
  local present = attachedKeySet()
  local best, bestSpecificity = nil, -1
  local names = {}
  for name in pairs(profiles) do table.insert(names, name) end
  table.sort(names)

  for _, name in ipairs(names) do
    local p = profiles[name]
    local matches = true
    for _, fp in ipairs(p.fingerprint or {}) do
      local key = string.format("%d:%d", fp.vendorID or 0, fp.productID or 0)
      if not present[key] then matches = false; break end
    end
    if matches then
      local spec = #(p.fingerprint or {})
      if spec > bestSpecificity then
        best, bestSpecificity = name, spec
      end
    end
  end

  return best or FALLBACK_PROFILE
end

local function setAudioDevice(deviceName, kind)
  local d = hs.audiodevice.findDeviceByName(deviceName)
  if not d then
    logWarn(string.format("audio %s device '%s' not found — skipping", kind, deviceName))
    return
  end
  if kind == "input" then
    if not d:isInputDevice() then
      logWarn(string.format("audio device '%s' exists but is not an input — skipping", deviceName))
      return
    end
    if d:setDefaultInputDevice() then
      logInfo("set default input: " .. deviceName)
    else
      logWarn("setDefaultInputDevice failed for: " .. deviceName)
    end
  else
    if not d:isOutputDevice() then
      logWarn(string.format("audio device '%s' exists but is not an output — skipping", deviceName))
      return
    end
    if d:setDefaultOutputDevice() then
      logInfo("set default output: " .. deviceName)
    else
      logWarn("setDefaultOutputDevice failed for: " .. deviceName)
    end
  end
end

local function switchObsScene(sceneName)
  if not OBS_CMD_PATH then
    logWarn("OBS scene switch requested ('" .. sceneName .. "') but obs-cmd is not installed — skipping")
    return
  end
  local task = hs.task.new(OBS_CMD_PATH, function(exitCode, stdOut, stdErr)
    if exitCode == 0 then
      logInfo("OBS scene switched: " .. sceneName)
    else
      logWarn(string.format("obs-cmd exit %d for scene '%s': %s",
        exitCode, sceneName, (stdErr or "") .. (stdOut or "")))
    end
  end, { "scene", "switch", sceneName })
  task:start()
end

local lastAppliedProfile = nil

local function applyProfile(name)
  if name == lastAppliedProfile then
    logInfo("profile unchanged (" .. name .. "), no-op")
    return
  end

  local p = profiles[name]
  if not p then
    logWarn("resolved profile '" .. name .. "' not in profiles.lua — falling back to " .. FALLBACK_PROFILE)
    name = FALLBACK_PROFILE
    p = profiles[FALLBACK_PROFILE]
    if not p then
      logWarn("fallback profile '" .. FALLBACK_PROFILE .. "' missing too — aborting apply")
      return
    end
  end

  logInfo("applying profile: " .. name)

  if p.audioInput then setAudioDevice(p.audioInput, "input") end
  if p.audioOutput then setAudioDevice(p.audioOutput, "output") end
  if p.obsScene then switchObsScene(p.obsScene) end

  hs.notify.new({
    title = "AV Pain Reliever",
    informativeText = "Switched to: " .. name,
  }):send()

  lastAppliedProfile = name
end

-- Debounced re-evaluation. USB events arrive in bursts; coalesce them.
local pendingTimer = nil

local function evaluateAndApply()
  pendingTimer = nil
  local resolved = resolveProfile()
  logInfo("evaluation → " .. resolved)
  applyProfile(resolved)
end

local function scheduleEvaluate()
  if pendingTimer then pendingTimer:stop() end
  pendingTimer = hs.timer.doAfter(DEBOUNCE_SECONDS, evaluateAndApply)
end

-- Public for reload safety: keep watcher in a global so GC doesn't kill it.
avWatcher = hs.usb.watcher.new(function(event)
  logInfo(string.format("USB %s: %s (vid=%s pid=%s)",
    event.eventType or "?",
    event.productName or "?",
    tostring(event.vendorID),
    tostring(event.productID)))
  scheduleEvaluate()
end)
avWatcher:start()

logInfo("av-pain-reliever loaded (obs-cmd: " .. (OBS_CMD_PATH or "MISSING") .. ")")

-- Snapshot audio devices and attached USB devices on load. Useful for
-- (a) initial setup — copy device names into profiles.lua — and
-- (b) post-mortem when a profile fails to find a device the user expected.
logInfo("--- audio devices ---")
for _, d in ipairs(hs.audiodevice.allDevices()) do
  logInfo(string.format("  %q  in=%s out=%s",
    d:name() or "?",
    tostring(d:isInputDevice()),
    tostring(d:isOutputDevice())))
end
logInfo("--- attached USB devices ---")
for _, d in ipairs(hs.usb.attachedDevices() or {}) do
  logInfo(string.format("  vid=0x%04x pid=0x%04x  %q",
    d.vendorID or 0, d.productID or 0, d.productName or "?"))
end
logInfo("--- end snapshot ---")

-- Apply current state immediately so reloads (cmd+ctrl+R) re-sync without
-- waiting for the next USB event.
applyProfile(resolveProfile())
