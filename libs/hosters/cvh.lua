-- =====================================================================
-- Lib: CVH (cdnvideohub.com player API) — URL resolution only.
-- Extracted from ru/yummyanime.lua (voiceLabel, cvhVideoUrl,
-- cvhSourceFrom).
-- Loaded via require_lib("cvh"). No dependencies on other libs.
--
-- The playlist/detail part (shikimori_id -> plapi.cdnvideohub.com) stays
-- in the plugin: it shares the session caches of the plugin and its
-- http_get calls. Here only the per-video URL and its response parsing:
-- the caller batches the GETs (batchCvh) and hands the response back.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- Same player API base as CVH_API in the plugin (that one serves the
-- playlist, this one the single video).
local CVH_API = "https://plapi.cdnvideohub.com/api/v1/player/sv"

-- The voice label of a playlist element — the quality caption of the
-- source and the key the player remembers the choice by, it must be
-- distinctive.
local function voiceLabel(item)
    local studio = type(item.voiceStudio) == "string" and item.voiceStudio or ""
    local vtype  = type(item.voiceType) == "string" and item.voiceType or ""
    local label
    if studio ~= "" and vtype ~= "" then
        label = studio .. " (" .. vtype .. ")"
    elseif studio ~= "" then
        label = studio
    elseif vtype ~= "" then
        label = vtype
    else
        label = "vk" .. tostring(item.vkId)
    end
    return string_clean(label)
end

-- nil vkId (a playlist without an identifier) → nil: batchCvh skips the
-- request, pages[nil] then returns nil and no source is produced.
function M.videoUrl(vkId)
    if vkId == nil then return nil end
    return CVH_API .. "/video/" .. vkId
end

-- A CVH video response → a source. No stream headers are set: the signed
-- okcdn segments (.../sig/<signature>/...) answer 400 when the request
-- carries Referer or Origin. Verified: without them a segment answers
-- 200, with them 400 for any User-Agent. Referer/Origin are only needed
-- for the plugin's own API requests (CVH_HDR there).
-- Returns { url, quality } or nil.
function M.sourceFrom(item, r)
    if type(r) ~= "table" or not r.success then return nil end
    local data = json_parse(r.body)
    local hls = data and data.sources and data.sources.hlsUrl
    if type(hls) ~= "string" or hls == "" then return nil end
    return { url = hls, quality = voiceLabel(item) }
end

return M
