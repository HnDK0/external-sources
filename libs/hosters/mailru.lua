-- =====================================================================
-- Lib: mail.ru — embed -> metadataUrl -> /+/video/meta/<id> -> mp4.
-- Merged from two copies: ar/anime4up.lua:907-946 and ar/witanime.lua:
-- 1438-1484 (both live 2026-10-05: the embed answers
-- "metadataUrl":"//my.mail.ru/+/video/meta/<id>", the meta JSON carries
-- videos[].url, the mp4 answers 206 on Range with the embed Referer; the
-- video_key cookie from meta is not required for playback).
-- Loaded via require_lib("mailru"). No dependencies on other libs.
--
-- The meta request is identical in both copies (same headers, same
-- timeout) and lives here; the embed page itself is fetched by the caller
-- (ar/anime4up gets it from its batch, ar/witanime requests it with the
-- my.mail.ru Referer).
-- =====================================================================
local version = "1.0.0"

local M = {}

-- meta JSON body -> list of { url, quality }, or nil + reason.
function M.parseMeta(metaBody, fallbackQuality)
    local data = json_parse(metaBody)
    local videos = type(data) == "table" and data.videos or nil
    if type(videos) ~= "table" then return nil, "no videos[] in meta" end
    local out = {}
    for _, v in ipairs(videos) do
        local u = type(v) == "table" and v.url or nil
        local key = type(v) == "table" and type(v.key) == "string" and v.key or nil
        if type(u) == "string" and u ~= "" then
            out[#out + 1] = {
                url     = u:gsub("^//", "https://"),
                quality = key and ("Mail.ru · " .. key) or fallbackQuality,
            }
        end
    end
    if #out == 0 then return nil, "no links in videos[]" end
    return out
end

-- Embed body + embed link -> list of { url, quality }, or nil + reason
-- ("no metadataUrl in embed" | "meta HTTP <code>" | a parse reason).
-- fallbackQuality is used for entries without a `key`.
function M.resolve(embedBody, embedLink, fallbackQuality)
    local meta = type(embedBody) == "string"
        and embedBody:match('metadataUrl":"([^"]+)') or nil
    if not meta then return nil, "no metadataUrl in embed" end
    local r = http_get((meta:gsub("^//", "https://")), {
        headers = {
            ["Referer"] = embedLink,
            ["X-Requested-With"] = "XMLHttpRequest",
        },
        timeout = 10000,
    })
    if not r.success then return nil, "meta HTTP " .. tostring(r.code) end
    return M.parseMeta(r.body, fallbackQuality)
end

return M
