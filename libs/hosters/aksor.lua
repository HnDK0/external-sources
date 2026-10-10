-- =====================================================================
-- Lib: Aksor — api/video/<md5 from the iframe URL> JSON -> quality list.
-- Extracted from ru/yummyanime.lua (aksorApiUrl + resolveAksor).
-- Loaded via require_lib("aksor"). No dependencies on other libs.
--
-- The API response comes from the caller's batch (keyed by the iframe),
-- nothing is fetched here; apiUrl is exported because the caller's
-- batchPlayers builds the batch request from it. The player page itself
-- only fills q1080, the other qualities come back null.
-- =====================================================================
local version = "1.0.0"

local M = {}

local AKSOR_QUALITIES = {
    { key = "q1080", label = "1080" },
    { key = "q720",  label = "720" },
    { key = "q480",  label = "480" },
}

-- URL of the api/video/<md5> request; nil on an empty md5 (the caller
-- then skips the batch entry, as before).
function M.apiUrl(iframeUrl)
    local md5 = iframeUrl:gsub("[?#].*$", ""):match("([^/]+)$")
    if not md5 or md5 == "" then return nil end
    return "https://player.aksor.tv/api/video/" .. md5
end

-- page — the shared http_get_batch response for api/video/<md5> (see
-- batchPlayers in the plugin): in pages the answer lives under the iframe
-- key while the request goes to the API URL.
-- A nil/empty md5 in the iframe → quiet skip, as before (no request).
-- Returns a list of { url, quality } or nil.
function M.resolve(iframeUrl, dubbing, page)
    if not M.apiUrl(iframeUrl) then return nil end
    if type(page) ~= "table" or not page.success then
        log_error("aksor: api " .. tostring(page and page.code))
        return nil
    end
    local data = json_parse(page.body)
    local quals = type(data) == "table" and data.qualities or nil
    if type(quals) ~= "table" then return nil end
    local out = {}
    for _, q in ipairs(AKSOR_QUALITIES) do
        local u = quals[q.key]
        if type(u) == "string" and u ~= "" then
            -- Aksor paths may contain a space ("SHIZA Project"): without
            -- %20 the URL does not pass, and the engine plays .mpd even
            -- without headers
            local enc = (u:gsub(" ", "%%20"))
            out[#out + 1] = {
                url     = enc,
                quality = "Aksor · " .. dubbing .. " · " .. q.label .. "p",
            }
        end
    end
    return out
end

return M
