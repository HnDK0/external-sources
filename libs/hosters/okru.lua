-- =====================================================================
-- Lib: ok.ru resolver — data-options (entity-encoded) -> JSON ->
--      flashvars.metadata -> stream candidates.
-- Merged from five copies: ar/anime4up.lua:662, ar/animephoenix.lua:849,
-- ar/witanime.lua:1536, id/anichin.lua:471, id/animexin.lua:484.
-- Loaded via require_lib("okru"). No dependencies on other libs.
-- =====================================================================
local version = "1.0.0"

local M = {}

local OKRU_REFERER = "https://ok.ru/"

-- body — the ok.ru player page. The caller does the http_get (four of the
-- five copies receive the body from a batch; ar/witanime.lua:1536 fetches
-- the page itself and keeps doing that on its side).
-- Returns a list of { url, mime, name?, referer }; empty list when nothing
-- was parsed. Logging is plugin-specific and stays with the caller.
function M.resolveOkRu(body)
    if type(body) ~= "string" then return {} end
    local opts = body:match('data%-options="([^"]+)"')
    if not opts then return {} end
    opts = opts:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<")
        :gsub("&gt;", ">"):gsub("&amp;", "&")
    local ok, data = pcall(json_parse, opts)
    if not ok or type(data) ~= "table" or type(data.flashvars) ~= "table" then
        return {}
    end
    local meta = data.flashvars.metadata
    if type(meta) == "string" then
        local mok, m = pcall(json_parse, meta)
        meta = mok and type(m) == "table" and m or nil
    end
    if type(meta) ~= "table" then return {} end

    local out = {}
    -- The manifest URL carries no media extension: type it explicitly,
    -- otherwise media3 treats it as progressive (id/animexin.lua:482).
    if type(meta.hlsManifestUrl) == "string" and meta.hlsManifestUrl ~= "" then
        out[#out + 1] = {
            url = meta.hlsManifestUrl,
            mime = "hls",
            referer = OKRU_REFERER,
        }
    end
    -- videos[] are progressive renditions served without an extension.
    if type(meta.videos) == "table" then
        for _, v in ipairs(meta.videos) do
            local u = type(v) == "table" and v.url or nil
            if type(u) == "string" and u ~= "" then
                out[#out + 1] = {
                    url = u,
                    mime = "mp4",
                    name = type(v.name) == "string" and v.name or nil,
                    referer = OKRU_REFERER,
                }
            end
        end
    end
    return out
end

return M
