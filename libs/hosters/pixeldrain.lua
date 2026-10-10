-- =====================================================================
-- Lib: pixeldrain — /u/<id> (or /api/file/<id>) embed link -> direct
-- https://pixeldrain.com/api/file/<id> mp4 (the site serves the file
-- without Referer/cookies).
-- Extracted from es/hentaila.lua:259-265 (the pdrain branch of
-- resolveEmbed).
-- Loaded via require_lib("pixeldrain"). No dependencies on other libs.
-- No HTTP: the file URL is a deterministic mapping of the embed link.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- server — имя сервера из разметки сайта, url — ссылка эмбеда.
-- Контракт двух возвратов:
--   src, true  — это pixeldrain: src = { url, mime = "mp4" } или nil, если
--                id файла не распознан — ветка эмбеда коротко замыкается,
--                фоллбэки других хостеров НЕ применяются (как в оригинале);
--   nil, false — не pixeldrain, продолжаем разбор.
function M.resolve(server, url)
    if type(url) ~= "string" then return nil, false end
    local lower = type(server) == "string" and server:lower() or ""
    if lower ~= "pdrain" and not url:find("pixeldrain", 1, true) then
        return nil, false
    end
    local fileId = url:match("/u/([%w_%-]+)") or url:match("/api/file/([%w_%-]+)")
    if not fileId then return nil, true end
    return { url = "https://pixeldrain.com/api/file/" .. fileId, mime = "mp4" }, true
end

return M
