-- =====================================================================
-- Lib: videas.fr (app.videas.fr embed) — direct HLS/MP4 in the embed
-- markup. NOT videa.hu (that is require_lib("videa"), a different domain
-- with the RC4/XML obfuscation).
-- Extracted from ar/witanime.lua:1048-1071 (resolveVideas): the embed
-- markup is foreign listing markup with the CDN playlist right in it —
-- in the preload tag and in the JSON data-embed. Only the body parsing
-- lives here; the HTTP GET and the bare directLinks fallback (the
-- plugin's own scan) stay with the caller.
-- Loaded via require_lib("videas"). No dependencies on other libs.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- Embed body -> list of direct URLs, possibly empty. The preload href
-- is the most reliable; the JSON "src" field with an .m3u8 is the
-- second pattern of the inline copy.
function M.parse(body)
    local out = {}
    if type(body) ~= "string" then return out end
    local url = body:match('<link[^>]+rel="preload"[^>]+href="([^"]+)"')
        or body:match('"src"%s*:%s*"(https?://[^"]+%.m3u8[^"]*)"')
    if url then out[#out + 1] = url end
    return out
end

return M
