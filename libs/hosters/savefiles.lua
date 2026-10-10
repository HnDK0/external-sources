-- =====================================================================
-- Lib: savefiles
-- Loaded via require_lib("savefiles"). No dependencies on other libs.
--
-- Embed URL: https://savefiles.com/e/{code}
-- CF challenge is on GET /e/{code} and GET /dl only; POST /dl works
-- without cf_clearance (verified 2026-10-10).
-- Response: JWPlayer setup with sources[{file: HLS}].
-- =====================================================================
local M = {}

local EMBED_TIMEOUT = 12000

function M.extractSavefiles(embedUrl)
    local code = embedUrl:match("/e/([%w_-]+)")
    if not code then return nil end

    local body = "op=embed&file_code=" .. code .. "&auto=1&referer="
    local r = http_post("https://savefiles.com/dl", body, {
        timeout = EMBED_TIMEOUT,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Origin"] = "https://savefiles.com",
            ["Referer"] = "https://savefiles.com/e/" .. code,
        },
    })
    if not r.success or not r.body then return nil end

    local u = r.body:match('sources:%s*%[%s*{%s*file:%s*"([^"]+)"')
        or r.body:match('file:%s*"(https?://[^"]+%.m3u8[^"]*)"')
    if not u then return nil end
    return u, "hls", "https://savefiles.com/"
end

return M
