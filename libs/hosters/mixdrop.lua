-- =====================================================================
-- Lib: mixdrop (MDCore.wurl)
-- Loaded via require_lib("mixdrop"); uses require_lib("urls").
-- =====================================================================
local version = "1.1.0"

local urls = require_lib("urls")

local M = {}

function M.extractMixdrop(both, embedUrl)
    local u = both:match('MDCore%.wurl%s*=%s*"([^"]+)"')
    if u then return urls.resolve(u, embedUrl), "mp4", urls.origin(embedUrl) end
    return nil
end

return M
