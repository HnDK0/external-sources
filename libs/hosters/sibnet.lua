-- =====================================================================
-- Lib: Sibnet — shell.php player page -> the single mp4 source.
-- Extracted from ru/yummyanime.lua (resolveSibnet).
-- Loaded via require_lib("sibnet"). No dependencies on other libs.
--
-- The page body is already in hand (the caller loads it with its batch,
-- charset windows-1251), nothing is fetched here.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- page — the shared http_get_batch response for this iframe (the
-- charset comes from SIBNET_OPTS in batchPlayers of the plugin).
-- Returns a one-element list of { url, quality, headers } or nil.
function M.resolve(iframeUrl, dubbing, page)
    -- shell.php answers windows-1251; the template cuts ~35-45 requests
    -- over 2-3 minutes (403 rate-limit) — then this player is skipped
    if type(page) ~= "table" or not page.success then
        log_error("sibnet: " .. tostring(page and page.code))
        return nil
    end
    local src = page.body:match('player%.src%(%[%s*{%s*src:%s*"([^"]+)"')
        or page.body:match('src:%s*"(/v/[^"]+)"')
    if not src then return nil end
    if src:sub(1, 1) == "/" then src = "https://video.sibnet.ru" .. src end
    return {
        {
            url     = src,
            quality = "Sibnet · " .. dubbing,
            -- /v/ answers 302 to a signed mp4: the redirect will unwrap it
            -- in the player (OkHttp), the source headers apply to the whole
            -- stream. Without the video.sibnet.ru Referer it answers 403 —
            -- verified.
            headers = { ["Referer"] = "https://video.sibnet.ru/" },
        },
    }
end

return M
