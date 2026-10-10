-- =====================================================================
-- Lib: Rumble resolver — the embed serves a jwplayer config with direct
--      links. Muxed mp4 first (hugh.cdn.rumble.cloud), else HLS
--      (hls-vod/.../playlist.m3u8 and the chunklist fallback). Slashes
--      are JSON-escaped (\/) — unescape before matching.
-- From one copy: id/animexin.lua:526-539 (resolveRumble).
-- Loaded via require_lib("rumble"). No dependencies on other libs.
--
-- Pure decode: the caller does the batch GET (Referer
-- https://rumble.com/); logging stays with the caller.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- body — the embed page. Returns a list of { url, mime } (possibly empty).
function M.resolve(body)
    if type(body) ~= "string" then return {} end
    local raw = body:gsub("\\/", "/")
    local out = {}
    local mp4 = raw:match('"url":"(https://hugh%.cdn%.rumble%.cloud/[^"]+%.mp4)"')
        or raw:match('(https://hugh%.cdn%.rumble%.cloud/[^"]+%.mp4)')
    if mp4 then out[#out + 1] = { url = mp4, mime = "mp4" } end
    local hls = raw:match('(https://rumble%.com/hls%-vod/[^"]+playlist%.m3u8)')
        or raw:match('(https://hugh%.cdn%.rumble%.cloud/[^"]+chunklist%.m3u8[^"]*)')
    if hls then out[#out + 1] = { url = hls, mime = "hls" } end
    return out
end

return M
