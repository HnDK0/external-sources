-- =====================================================================
-- Lib: D.Tube resolver — the player is a SPA, but the JSON cover
--      https://api.d.tube/videos/<id> is open -> video_url (master.m3u8).
-- Merged from two copies: id/anichin.lua:536-543 and id/animexin.lua:
-- 510-517 (the parse was identical; animexin also typed the stream as
-- hls, which is kept — the URL always ends in master.m3u8).
-- Loaded via require_lib("dtube"). No dependencies on other libs.
--
-- Pure decode: the caller does the batch GET (Referer
-- https://play.d.tube/); logging stays with the caller.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- body — the JSON cover of the video.
-- Returns a list of { url, mime = "hls" } (possibly empty).
function M.resolve(body)
    if type(body) ~= "string" then return {} end
    local ok, data = pcall(json_parse, body)
    if not ok or type(data) ~= "table" then return {} end
    local url = data.video_url
    if type(url) ~= "string" or url == "" then return {} end
    return { { url = url, mime = "hls" } }
end

return M
