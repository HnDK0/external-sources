-- =====================================================================
-- Lib: stream helpers for videohost extractors: pickStream (generic
--      m3u8/mp4 scan) + hasMediaExt (mime typing of extension-less URLs).
-- Loaded via require_lib("hls"); uses require_lib("urls").
-- =====================================================================
local version = "1.0.0"

local urls = require_lib("urls")

local M = {}

-- =====================================================================
-- Generic stream scan
-- =====================================================================

function M.pickStream(t, embedUrl)
    -- 1) absolute URL
    local hls = t:match([=[(https?://[^"'%s\<>]+%.m3u8[^"'%s\<>]*)]=])
    if hls then return hls, "hls" end

    -- 2) quoted, relative or protocol-relative
    for _, q in ipairs({ '"', "'" }) do
        for s in t:gmatch(q .. "([^" .. q .. "\r\n]+)" .. q) do
            if #s < 600 and not s:find("%s") and s:lower():find(".m3u8", 1, true) then
                return urls.resolve(s, embedUrl), "hls"
            end
        end
    end

    -- 3) direct mp4
    local mp4 = t:match([=[(https?://[^"'%s\<>]+%.mp4[^"'%s\<>]*)]=])
    if mp4 then return mp4, "mp4" end
    for _, q in ipairs({ '"', "'" }) do
        for s in t:gmatch(q .. "(//[^" .. q .. "\r\n]+)" .. q) do
            if #s < 600 and not s:find("%s") and s:lower():find(".mp4", 1, true) then
                return urls.resolve(s, embedUrl), "mp4"
            end
        end
    end
    return nil, nil
end

-- =====================================================================
-- Media extension check
-- =====================================================================

-- Does the URL path (before "?" / "#") end with a media extension?
-- Without it media3 types the stream as progressive and fails on an HLS
-- body (rationale: ar/anime4up.lua:328). Union of the three plugin copies
-- (ar/anime4up.lua:330, ar/animephoenix.lua:45, ar/witanime.lua:1958):
-- .mkv comes from animephoenix and is progressive too, so it must not be
-- typed as "hls".
function M.hasMediaExt(u)
    local base = u:match("^[^%?#]*") or u
    return base:match("%.m3u8$") ~= nil
        or base:match("%.mp4$") ~= nil
        or base:match("%.mkv$") ~= nil
end

return M
