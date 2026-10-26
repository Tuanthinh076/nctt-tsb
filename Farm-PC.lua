-- UwUNCTT Farm PC | nctt | desktop mouse / keyboard input
local source = game:HttpGet("https://raw.githubusercontent.com/Tuanthinh076/nctt-tsb/refs/heads/main/UwUNCTT.lua?v=2.3.1")
local chunk, reason = loadstring(source)
assert(chunk, reason)
return chunk("PC")

