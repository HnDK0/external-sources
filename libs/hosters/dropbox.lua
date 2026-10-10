-- =====================================================================
-- Lib: dropbox — shared link -> direct file-CDN URL by walking the
-- redirects manually.
-- Extracted from ar/witanime.lua:1097-1115 (resolveDropbox). Both GETs
-- stay inside (binary + followRedirects=false: a 3xx of a binary
-- response comes with success = false, so the redirect is read from
-- the code + location header). Uses engine API url_resolve via the
-- origin-relative fallback only for path-absolute Locations.
-- Loaded via require_lib("dropbox"). No dependencies on other libs.
-- =====================================================================
local version = "1.0.0"

local M = {}

local MAX_HOPS = 5

local function headerValue(headers, name)
    local v = headers and (headers[name] or headers[string.lower(name)])
    if type(v) == "table" then return v[1] end
    if type(v) == "string" then return v end
    return nil
end

local function absUrl(href, base)
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(base, href)
end

-- Shared link + episode referer -> { url } or nil + reason.
function M.resolve(link, referer)
    if type(link) ~= "string" then return nil, "no link" end
    local current = link
    for _ = 1, MAX_HOPS do
        local r = http_get(current, {
            binary          = true,
            followRedirects = false,
            headers         = { ["Referer"] = referer },
        })
        -- 3xx of a binary response has success = false; look at the code.
        if r.code >= 400 then return nil, "HTTP " .. tostring(r.code) end
        local loc = headerValue(r.headers, "location")
        if not loc or loc == "" then break end
        current = absUrl(loc, current)
    end
    return { url = current }
end

return M
