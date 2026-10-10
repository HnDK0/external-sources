-- =====================================================================
-- Lib: mp4upload
-- Loaded via require_lib("mp4upload"). No dependencies on other libs.
-- =====================================================================
local M = {}

function M.extractMp4upload(both)
    local u = both:match('player%.src%(%s*"([^"]+)"')
        or both:match('player%.src%(%s*{.-src%s*:%s*"([^"]+)"')
        or both:match('src%s*:%s*"(https?://[^"]+%.mp4[^"]*)"')
    if u then return u, "mp4", "https://www.mp4upload.com/" end
    return nil
end

return M
