-- UwUNCTT Farm Mobile | nctt | native touch GUI only
local source = game:HttpGet("https://raw.githubusercontent.com/Tuanthinh076/nctt-tsb/refs/heads/main/UwUNCTT.lua?v=2.4.2")
local chunk, reason = loadstring(source)
assert(chunk, reason)
return chunk("Mobile")
