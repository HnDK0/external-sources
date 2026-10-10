-- =====================================================================
-- Lib: vkvideo — video_ext.php -> "files"{} -> mp4_144 .. mp4_1080.
-- Merged from ar/anime4up.lua:869-916 (resolveVkVideo), live 2026-10-05
-- and 2026-10-07.
-- Loaded via require_lib("vk"). No dependencies on other libs.
--
-- Scheme: id from the link (video-<oid>_<id> / clip-<oid>_<id> /
-- ?oid=&id=) -> https://vk.com/video_ext.php?oid=&id=[&hash=] -> the
-- JSON-lookalike "files" block with mp4_144 … mp4_1080. vkvideo.ru loops
-- on redirects to login.vk.ru, so the request always goes to vk.com.
--
-- The HTTP call stays here exactly as in the caller: Referer vk.com,
-- windows-1251 for the body, 10s timeout. The srcAg signature inside the
-- URLs comes from the UA of the video_ext request — the engine sends
-- Chrome Android and okcdn answers 206 to any player UA regardless of
-- Referer, so the UA is deliberately NOT overridden here.
-- =====================================================================
local version = "1.0.0"

local VK_EXT = "https://vk.com/video_ext.php"
local VK_REF = "https://vk.com/"

local M = {}

-- Embed link -> video_ext URL (oid, id and the optional hash), or nil
-- when the link carries no ids.
function M.videoExtUrl(link)
    if type(link) ~= "string" then return nil end
    local oid, vid = link:match("/video_(-?%d+)_(-?%d+)")
        or link:match("/clip_(-?%d+)_(-?%d+)")
    if not oid then
        oid = link:match("[?&]oid=(-?%d+)")
        vid = link:match("[?&]id=(-?%d+)")
    end
    if not (oid and vid) then return nil end
    local url = VK_EXT .. "?oid=" .. oid .. "&id=" .. vid
    local hash = link:match("[?&]hash=([%w_%-]+)")
    if hash then url = url .. "&hash=" .. hash end
    return url
end

-- Embed link -> list of { url, quality = "VK · <q>p", mime = "mp4",
-- referer = "https://vk.com/" } sorted by height descending, or nil +
-- reason ("no oid/id in link" | "video_ext HTTP <code>" |
-- "no files{} in video_ext" | "no mp4 in files{}").
-- mime is explicit: the okcdn URLs carry no media extension while the
-- body is mp4 bytes, a mime = "hls" guess would make media3 fail on the
-- missing #EXTM3U header (live 2026-10-07).
function M.resolve(link)
    local url = M.videoExtUrl(link)
    if not url then return nil, "no oid/id in link" end
    local r = http_get(url, {
        headers = { ["Referer"] = VK_REF },
        charset = "windows-1251",
        timeout = 10000,
    })
    if not r.success then return nil, "video_ext HTTP " .. tostring(r.code) end
    local files = r.body:match('"files":{(.-)}')
    if not files then return nil, "no files{} in video_ext" end
    local variants = {}
    for q, u in files:gmatch('"mp4_(%d+)":"([^"]+)"') do
        variants[#variants + 1] = { q = tonumber(q) or 0, u = u:gsub("\\/", "/") }
    end
    table.sort(variants, function(a, b) return a.q > b.q end)
    local out = {}
    for _, v in ipairs(variants) do
        out[#out + 1] = {
            url     = v.u,
            quality = "VK · " .. v.q .. "p",
            mime    = "mp4",
            referer = VK_REF,
        }
    end
    if #out == 0 then return nil, "no mp4 in files{}" end
    return out
end

return M
