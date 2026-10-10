-- =====================================================================
-- Lib: Dailymotion resolver — id -> player/metadata -> HLS master.
-- Merged from four copies: ar/anime4up.lua:715, ar/witanime.lua:1693,
-- id/anichin.lua:502, id/animexin.lua:447.
-- Loaded via require_lib("dailymotion"). No dependencies on other libs.
-- =====================================================================
local version = "1.0.0"

local M = {}

local DM_URL = "https://www.dailymotion.com"

local function dmHeaders(referer)
    return {
        ["Accept"]  = "*/*",
        ["Referer"] = referer or (DM_URL .. "/"),
        ["Origin"]  = DM_URL,
    }
end

-- body — the player/metadata/video/... JSON -> list of { url, mime="hls" }.
-- qualities.auto[] first (anichin/animexin), then a regex fallback for the
-- case when the schema changes: the JSON escapes slashes
-- (application\/x-mpegURL), so unescape before matching.
function M.parseMetadata(body)
    if type(body) ~= "string" then return {} end
    local data = json_parse(body)
    local out = {}
    if type(data) == "table" and type(data.qualities) == "table"
        and type(data.qualities.auto) == "table" then
        for _, q in ipairs(data.qualities.auto) do
            if type(q) == "table" and type(q.url) == "string" and q.url ~= "" then
                out[#out + 1] = { url = q.url, mime = "hls" }
            end
        end
    end
    if #out == 0 then
        local flat = body:gsub("\\/", "/")
        local m = flat:match('"auto"%s*:%s*%[{%s*"type"%s*:%s*"application[^"]*mpegURL","url"%s*:%s*"([^"]+)"')
            or flat:match('(https://[^"]+%.m3u8[^"]*)')
        if m then out[#out + 1] = { url = m, mime = "hls" } end
    end
    return out
end

-- link -> list of { url, mime="hls" }.
-- Primary path: the video id alone is enough (live check 2026-10-05,
-- ar/anime4up.lua:701). Signed fallback from ar/witanime.lua:1693 — the
-- page is fetched only when the primary path returned nothing:
-- dmInternalData {ts, v1st} -> metadata with dmV1st/dmTs params.
-- Subtitles/password-error handling of that copy is plugin-specific and
-- stays with the caller.
function M.resolveDailymotion(link)
    if type(link) ~= "string" or link == "" then return {} end
    local id = link:match("[?&]video=([^&#]+)")
    if not id then
        local path = (link:match("^[^?#]*") or ""):gsub("/+$", "")
        id = path:match("([^/]+)$")
    end
    if not id or id == "" then return {} end
    local encodedId = url_encode(id)

    local metaUrl = DM_URL .. "/player/metadata/video/" .. encodedId .. "?locale=en-US"
    local r = http_get(metaUrl, { headers = dmHeaders(link), timeout = 10000 })
    local out = r.success and M.parseMetadata(r.body) or {}
    if #out > 0 then return out end

    local page = http_get(link, { timeout = 10000 })
    if not page.success or type(page.body) ~= "string" then return {} end
    local internal = page.body:match('"dmInternalData":(.-)</script>')
    local ts = internal and internal:match('"ts":([^,]+)') or nil
    local v1st = internal and internal:match('"v1st":"([^"]+)"') or nil
    if not ts or not v1st then return {} end

    local signed = DM_URL .. "/player/metadata/video/" .. encodedId
        .. "?locale=en-US&dmV1st=" .. v1st .. "&dmTs=" .. ts .. "&is_native_app=0"
    r = http_get(signed, { headers = dmHeaders(link), timeout = 10000 })
    return r.success and M.parseMetadata(r.body) or {}
end

return M
