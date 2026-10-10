-- =====================================================================
-- Lib: uqload — embed (301 -> uqload.vc) -> packed-JS -> jwplayer sources.
-- Merged from two copies: ar/anime4up.lua:827-869 (packedMediaUrls,
-- resolveUqload; packedMediaUrls is also the parser of the vidmoly player
-- there) and ar/animephoenix.lua:792-827. packedMediaUrls was byte-identical
-- in both; resolveUqload differed only in the wrapper (pushed candidates vs
-- a URL list) and stays with the callers as a thin adapter.
-- Loaded via require_lib("uqload"); uses require_lib("hls") and engine
-- API unpack_packed ("" when there is no packer).
--
-- Live 2026-10-05: /embed-<id>.html serves an unpacked
-- jwplayer("vplayer").setup({sources:[{file:"…/master.m3u8?…"}]}).
-- The jwplayer config only exists unpacked, so a bare sources: pattern
-- over the body never matches; file:"…" also holds subs/logos, hence the
-- media-extension filter of the hls lib.
-- =====================================================================
local version = "1.0.0"

local hls = require_lib("hls")

local M = {}

-- Links to streams from the player body: unpacked text + original.
function M.packedMediaUrls(body)
    if type(body) ~= "string" then return {} end
    local text = body
    local un = unpack_packed(body)
    if un ~= "" then text = un .. "\n" .. body end
    local out, seen = {}, {}
    local function add(u)
        if seen[u] or not string_starts_with(u, "http") then return end
        if not hls.hasMediaExt(u) then return end
        seen[u] = true
        out[#out + 1] = u:gsub("\\/", "/"):gsub("&amp;", "&")
    end
    for u in text:gmatch('file:%s*"([^"]+)"') do add(u) end
    for u in text:gmatch("file:%s*'([^']+)'") do add(u) end
    for u in text:gmatch('"file"%s*:%s*"([^"]+)"') do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+%.m3u8[^"'%s<>\\]*]]) do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+%.mp4[^"'%s<>\\]*]]) do add(u) end
    return out
end

-- Embed body -> list of stream URLs, or nil + reason when the packed-JS
-- holds no media (caller logs with its own prefix).
function M.resolve(body)
    local urls = M.packedMediaUrls(body)
    if #urls == 0 then return nil, "no sources in packed-JS" end
    return urls
end

return M
