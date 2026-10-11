-- =====================================================================
-- Lib: stream-source helpers for videohost extractors: push (dedup by
--      url) + isSkipped (shared dead-host skip list) + hostLabel.
-- Loaded via require_lib("sources"); uses require_lib("urls").
-- =====================================================================
local version = "1.0.0"

local urls = require_lib("urls")

local M = {}

-- =====================================================================
-- Stream list dedup
-- =====================================================================

-- Append src to list unless its url was already seen. `seen` is a
-- url -> true table kept by the caller. Semantics are byte-identical to
-- the six inline copies (ar/witanime.lua:1331, ar/animephoenix.lua:656,
-- ar/anime4up.lua:357, ar/anime3rb.lua:402, ru/yummyanime.lua:515 and
-- the url-dedup core of pushCandidate in ar/anime4up.lua:547).
function M.push(list, seen, src)
    if type(src) ~= "table" then return end
    local url = src.url
    if type(url) ~= "string" or url == "" or seen[url] then return end
    seen[url] = true
    list[#list + 1] = src
end

-- Readable alias for migration of the pushSource-named copies.
M.pushSource = M.push

-- =====================================================================
-- Dead-host skip list
-- =====================================================================

-- Hosts that never yield a direct link over plain HTTP. Matched by
-- substring against the lowercased host, so "mega.nz" also covers
-- www.mega.nz and any subdomain. Union of the six plugin SKIP lists
-- (verified live 2026-10-05..10-07 where noted); hosts that have a
-- working resolver in some plugin (drive.google, uqload, ok.ru,
-- dood/playmogo, ...) are deliberately NOT here — each plugin decides
-- which resolvers it wires up.
-- Reasons are single-language (Russian, the dominant log language of
-- the ar/* plugins that consume skipReason before network calls).
local SKIP = {
    -- Encrypted/chunked streams the engine cannot play (verbatim mega
    -- reason from ar/witanime.lua:790, copied in 3+ plugins).
    { sub = "mega.nz",   reason = "поток зашифрован AES-CTR и отдаётся чанками с Range — в движке нет крипто и частичных запросов" },
    { sub = "mega.io",   reason = "поток зашифрован AES-CTR и отдаётся чанками с Range — в движке нет крипто и частичных запросов" },
    -- Google Docs preview is JS-only (drive.google handled by urls.driveDirectUrl).
    { sub = "docs.google", reason = "Google Docs: превью на JS" },
    -- Download-page hosts: link goes through a JS download page / session token.
    { sub = "mediafire", reason = "страница загрузки с JS, прямой ссылки в ответе нет" },
    { sub = "gofile",    reason = "токен сессии выдаёт JS страницы" },
    -- TLS/HTTP dead (ar/witanime.lua:794, ar/anime4up.lua:376).
    { sub = "dsvplay",   reason = "TLS-хендшейк не проходит (curl rc=35) — проверено и с браузерным UA (живьём 2026-10-07)" },
    -- JS player on their side, Google Drive itself handled separately
    -- (ar/anime4up.lua:377).
    { sub = "gdriveplayer", reason = "JS-плеер (file.js) на стороне gdriveplayer — сам Google Drive обрабатывается отдельно" },
    -- Parked domains / HTTP black holes (ar/animephoenix.lua:672-675,
    -- ar/anime4up.lua:380-384).
    { sub = "vidbem",    reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа router.parklogic.com, а не плеер (живьём 2026-10-05)" },
    { sub = "fembed",    reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа router.parklogic.com, а не плеер (живьём 2026-10-05)" },
    { sub = "vup",       reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа router.parklogic.com, а не плеер (живьём 2026-10-05)" },
    { sub = "uptostream", reason = "DNS/TLS жив, HTTP не отвечает (живьём 2026-10-05)" },
    { sub = "rubyvidhub", reason = "TCP не отвечает (мертв)" },
    { sub = "streamruby", reason = "TCP не отвечает (мертв)" },
    { sub = "rubystm",   reason = "TCP не отвечает (мертв)" },
    { sub = "turbovidhls", reason = "соединение не устанавливается (000)" },
    { sub = "larhu",     reason = "парковка parklogic, а CDN fav.larhu.website без DNS-записи A/AAAA (живьём 2026-10-05)" },
    { sub = "vadbam",    reason = "парковка parklogic: embed отдаёт страницу редиректа router.parklogic.com (живьём 2026-10-05)" },
    -- SPA shells / JS stubs with no direct link in HTML (id/anichin.lua:433,
    -- id/animexin.lua:367).
    { sub = "odysee",    reason = "SPA-оболочка, подписи LBRY недоступны" },
    { sub = "strwish",   reason = "JS-заглушка (StreamWish), прямой ссылки в HTML нет" },
    { sub = "listeamed", reason = "JS-заглушка (VidGuard), прямой ссылки в HTML нет" },
    { sub = "short.icu", reason = "соединение не устанавливается (000)" },
    { sub = "short.ink", reason = "соединение не устанавливается (000)" },
    { sub = "abyssplayer", reason = "media в странице шифруется в lite.bundle.js" },
    { sub = "racaty",    reason = "гейт-хостер, ответ 502" },
}

-- Skip reason for a URL (or bare host), nil if the host is workable.
-- Call BEFORE any network request — that is the "hard timeout" for
-- known-dead hosts (same contract as the inline skipReason copies).
function M.isSkipped(url)
    if type(url) ~= "string" then return nil end
    local host = urls.hostOf(url)
    if host == "" then host = url:lower() end
    for _, s in ipairs(SKIP) do
        if host:find(s.sub, 1, true) then return s.reason end
    end
    return nil
end

-- Alias matching the inline function name used before migration.
M.skipReason = M.isSkipped

-- =====================================================================
-- Host label
-- =====================================================================

-- Display label for a hoster: host without the leading "www.", original
-- case kept (union of ar/animephoenix.lua:691 and ar/anime4up.lua:429 —
-- identical bodies). Distinct from urls.hostOf, which lowercases and is
-- meant for registry lookups, not UI.
function M.hostLabel(url)
    local host = (url or ""):match("^https?://([^/]+)") or url
    return (host or ""):gsub("^www%.", "")
end

return M
