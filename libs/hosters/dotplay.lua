-- =====================================================================
-- Lib: dotplay.net — embed → /api.php?code= → base64 video_url field.
-- Extracted from ar/witanime.lua:872-907 (resolveDotplay). Both GETs
-- live here (same as the inline copy): the embed raises a cookie, the
-- api.php round trip is the actual resolve. Uses engine API
-- base64_decode_bytes (guarded by the caller's ensureEngine).
-- Loaded via require_lib("dotplay"). No dependencies on other libs.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- Embed link -> list of { url } or nil + reason. api.php is the API of
-- dotplay itself: a foreign host (4shared comes up in yonaplay answers)
-- answers HTML instead of JSON, so the request is checked up front and
-- no network call is made for a foreign host.
function M.resolve(link)
    if type(link) ~= "string" then return nil, "no link" end
    local code = link:match("/embed/([^/?#]+)")
    local origin = link:match("^(https?://[^/]+)") or ""
    if not code or not origin:lower():find("dotplay.net", 1, true) then
        return nil, "not a dotplay link: " .. tostring(link)
    end
    -- The embed raises a cookie; api.php answers without it too, so the
    -- failure of this GET is not fatal.
    http_get(link, { headers = { ["Referer"] = "https://mid.yonaplay.net/" } })

    local api = origin .. "/api.php?code=" .. url_encode(code)
    local r = http_get(api, {
        headers = {
            ["Accept"]  = "application/json",
            ["Referer"] = link,
        },
    })
    if not r.success then return nil, "HTTP " .. tostring(r.code) end
    local data = json_parse(r.body)
    local url = data and data.video_url and base64_decode_bytes(data.video_url)
    if not url or #url == 0 then return nil, "empty video_url" end
    -- The meaningful part is before '|' (a signature/time follows).
    local raw = url:match("^([^|]+)") or ""
    if raw == "" then return nil, "empty video_url" end
    return { { url = raw } }
end

return M
