-- profiles.lua
-- Edit this file to define your locations. The engine in init.lua doesn't
-- need to be touched.
--
-- Matching rules:
--   1. A profile matches if every device in its `fingerprint` is currently
--      attached (matched by vendorID + productID).
--   2. Among matching profiles, the one with the most fingerprint entries
--      wins ("most specific"). Alphabetical name breaks ties.
--   3. If nothing matches, the engine falls back to "laptop" (undocked).
--
-- All fields except `fingerprint` are optional. nil means "skip that switch".
--
-- Capture vendor/product IDs with:    system_profiler SPUSBDataType
-- Capture exact audio device names from the Hammerspoon Console with:
--   for _, d in ipairs(hs.audiodevice.allDevices()) do
--     print(d:name(), d:isInputDevice() and "in" or "", d:isOutputDevice() and "out" or "")
--   end
--
-- Placeholders are deliberately greppable: 0xDEAD, 0xBEEF, "FILL ME IN".

return {
  ["laptop"] = {
    -- Undocked laptop. Empty fingerprint = always matches (specificity 0).
    -- This is the fallback when nothing else matches.
    fingerprint = {},
    audioInput  = "MacBook Pro Microphone",
    audioOutput = "MacBook Pro Speakers",
    obsScene    = "Laptop",
  },

  ["home-office"] = {
    fingerprint = {
      { vendorID = 0xDEAD, productID = 0xBEEF, name = "FILL ME IN — home office dock" },
      { vendorID = 0xDEAD, productID = 0xBEEF, name = "FILL ME IN — home office audio interface or webcam" },
    },
    audioInput  = "FILL ME IN",
    audioOutput = "FILL ME IN",
    obsScene    = "Home Office",
  },

  ["work-office"] = {
    fingerprint = {
      { vendorID = 0xDEAD, productID = 0xBEEF, name = "FILL ME IN — office dock" },
    },
    audioInput  = "FILL ME IN",
    audioOutput = "FILL ME IN",
    obsScene    = "Work Office",
  },

  ["conference-room"] = {
    -- Shares the office dock; needs at least one device unique to the conf
    -- room so it out-specifies "work-office" when you're in there.
    fingerprint = {
      { vendorID = 0xDEAD, productID = 0xBEEF, name = "FILL ME IN — office dock (same as work-office)" },
      { vendorID = 0xDEAD, productID = 0xBEEF, name = "FILL ME IN — conf room speakerphone or display USB hub" },
    },
    audioInput  = "FILL ME IN",
    audioOutput = "FILL ME IN",
    obsScene    = "Conference Room",
  },
}
