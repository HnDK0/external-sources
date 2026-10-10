-- Hentaila — video plugin for NoveLA (content_type = "video")
-- Ported from the CloudStream extension Hentaila.kt (selectors + embed parsing).
-- NOT tested against the live site: adjust selectors if the layout changed.

id           = "hentaila"
name         = "Hentaila"
version      = "1.1.0"
baseUrl      = "https://hentaila.com"
language     = "es"
content_type = "video"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/hentaila.png"

-- ── Guard: old app builds without require_lib ────────────────────────────────
-- Top-level must load without require_lib (otherwise the plugin silently
-- disappears from the sources list) — pcall-tryLib pattern (latanime M9):
-- the error is kept in libErr and reported from ensureLibs.
local libErr = nil
local HAS_LIBS = type(require_lib) == "function"

local function tryLib(name)
    if not HAS_LIBS then return nil end
    local ok, res = pcall(require_lib, name)
    if not ok then libErr = tostring(res) return nil end
    return res
end

local MP4UPLOAD = tryLib("mp4upload")
local PIXELDRAIN = tryLib("pixeldrain")

-- User-facing strings stay in Spanish (plugin language = "es"), like
-- es/latanime.lua. show_error is async in production, hence error(..., 0).
local function ensureLibs()
    if not HAS_LIBS then
        show_error("Se requiere actualizar NoveLA", "Este complemento usa bibliotecas comunes (require_lib). Actualice la aplicación a la última versión.")
        error("Se requiere la última versión de la aplicación (require_lib)", 0)
    end
    if not MP4UPLOAD or not PIXELDRAIN then
        show_error("Bibliotecas no cargadas", "Abra la pantalla de extensiones y pulse actualizar; después reinicie la aplicación. " .. (libErr or ""))
        error("Bibliotecas comunes no cargadas", 0)
    end
end

local CATALOG = baseUrl .. "/catalogo"
-- Same selector as the Kotlin source; "\\/" is the escaped slash in "group/item".
local CARD_SEL = "div.grid.grid-cols-2 article.group\\/item"

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Episode URLs look like /media/<slug>/<n>; the book URL is /media/<slug>.
local function bookUrlOf(url)
    return url:match("^(.-/media/[^/?#]+)") or url
end

local _pageCache = {}
local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    log_error("Hentaila: request failed (HTTP " .. tostring(r.code) .. ") " .. url)
    return nil
end

local function parseCards(body)
    local items = {}
    for _, card in ipairs(html_select(body, CARD_SEL)) do
        local title = ""
        local h3 = html_select_first(card.html, "h3")
        if h3 then title = string_clean(h3.text) end
        if title == "" then
            local sr = html_select_first(card.html, "span.sr-only")
            if sr then title = string_clean(sr.text) end
        end
        local a = html_select_first(card.html, "a")
        if title ~= "" and a and a.href ~= "" then
            table.insert(items, {
                title = title,
                url   = bookUrlOf(absUrl(a.href)),
                cover = absUrl(html_attr(card.html, "img", "src"))
            })
        end
    end
    return items
end

local function fetchCatalog(query)
    local r = http_get(CATALOG .. query)
    if not r.success then
        log_error("Hentaila: catalog failed (HTTP " .. tostring(r.code) .. ")")
        return { items = {}, hasNext = false }
    end
    local items = parseCards(r.body)
    return { items = items, hasNext = #items > 0 }
end

-- ── Catalog / search ──────────────────────────────────────────────────────────

function getCatalogList(index)
    ensureLibs()
    return fetchCatalog("?order=latest_added&page=" .. (index + 1))
end

function getCatalogSearch(index, query)
    ensureLibs()
    if not query or query == "" then return { items = {}, hasNext = false } end
    return fetchCatalog("?search=" .. url_encode(query) .. "&page=" .. (index + 1))
end

-- ── Book details ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    ensureLibs()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    ensureLibs()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "img.aspect-poster", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    ensureLibs()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "div.entry.text-lead p")
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    ensureLibs()
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local function collect(selector)
        local genres, seen = {}, {}
        for _, a in ipairs(html_select(body, selector)) do
            local g = string_clean(a.text)
            if g ~= "" and not seen[g:lower()] then
                seen[g:lower()] = true
                table.insert(genres, g)
            end
        end
        return genres
    end

    -- Same container as the CloudStream source, then looser fallbacks.
    local genres = collect('div.flex-wrap.gap-2 a[href*="genre="]')
    if #genres == 0 then genres = collect('main a[href*="genre="]') end
    if #genres == 0 then genres = collect('a[href*="catalogo?genre"]') end
    if #genres == 0 then
        log_error("Hentaila: no genres found for " .. bookUrl)
    end
    return genres
end

-- ── Episodes ──────────────────────────────────────────────────────────────────

local function loadEpisodes(bookUrl)
    -- Direct request (not cached): chapters are parsed from the book page HTML.
    local r = http_get(bookUrl)
    if not r.success then
        log_error("Hentaila: episodes failed (HTTP " .. tostring(r.code) .. ")")
        return {}
    end

    local list, seen, allNumbered = {}, {}, true
    for _, ep in ipairs(html_select(r.body, CARD_SEL)) do
        local a = html_select_first(ep.html, "a")
        if a and a.href ~= "" then
            local url = absUrl(a.href)
            if not seen[url] then
                seen[url] = true
                local numEl = html_select_first(ep.html, "div.bg-line span")
                local num = numEl and tonumber(string_trim(numEl.text)) or nil
                if not num then allNumbered = false end
                local nameEl = html_select_first(ep.html, "div.bg-line")
                local title = nameEl and string_clean(nameEl.text) or ""
                if title == "" then
                    title = "Episodio " .. tostring(num or (#list + 1))
                end
                table.insert(list, { title = title, url = url, num = num })
            end
        end
    end

    -- Engine expects oldest → newest.
    if allNumbered then
        table.sort(list, function(x, y) return x.num < y.num end)
    end

    local chapters = {}
    for _, ep in ipairs(list) do
        table.insert(chapters, { title = ep.title, url = ep.url })
    end
    return chapters
end

function getChapterList(bookUrl)
    ensureLibs()
    return loadEpisodes(bookUrl)
end

function getChapterListHash(bookUrl)
    ensureLibs()
    local chapters = loadEpisodes(bookUrl)
    if #chapters == 0 then return nil end
    return tostring(#chapters) .. "|" .. chapters[#chapters].url
end

-- ── Video resolution ──────────────────────────────────────────────────────────

local function origin(url)
    local scheme, host = url:match("^(https?)://([^/?#]+)")
    if not scheme then return nil end
    return scheme .. "://" .. host .. "/"
end

-- Best-effort extraction of a direct stream from an embed page.
local function scanEmbedPage(embedUrl)
    local r = http_get(embedUrl)
    if not r.success then return nil, nil end
    local body = r.body:gsub("\\/", "/")
    local hls = body:match('(https?://[^"\'%s\\]+%.m3u8[^"\'%s\\]*)')
    if hls then return hls, "hls" end
    local mp4 = body:match('src:%s*"(https?://[^"]+%.mp4[^"]*)"')
        or body:match('(https?://[^"\'%s\\]+%.mp4[^"\'%s\\]*)')
    if mp4 then return mp4, "mp4" end
    return nil, nil
end

-- Maps one embed entry to a playable source, or nil.
local function resolveEmbed(server, url)
    local lower = server:lower()

    -- Internal CDN: /play/ is the player page, /m3u8/ is the playlist.
    if url:find("cdn.hvidserv.com/play/", 1, true) then
        return {
            url     = url:gsub("/play/", "/m3u8/"),
            mime    = "hls",
            headers = { ["sec-fetch-site"] = "same-origin" },
        }
    end

    -- PixelDrain: /u/<id> page → /api/file/<id> direct file (lib pixeldrain).
    -- Второй возврат resolve — «это pixeldrain»: при нераспознанном id ветка
    -- коротко замыкается в nil, фоллбэки ниже не применяются.
    local pdrain, isPdrain = PIXELDRAIN.resolve(server, url)
    if isPdrain then return pdrain end

    -- MP4Upload: needs the embed page's Referer; file URL comes from
    -- player.src inside the page (lib mp4upload).
    if lower == "mp4upload" or url:find("mp4upload", 1, true) then
        local r = http_get(url)
        if not r.success then return nil end
        local u, mime, ref = MP4UPLOAD.extractMp4upload(r.body:gsub("\\/", "/"))
        if u then
            return { url = u, mime = mime, headers = { ["Referer"] = ref } }
        end
        return nil
    end

    -- HLS / unknown servers: direct playlist, or scan the embed page.
    if url:find("%.m3u8") then
        return { url = url, mime = "hls", headers = origin(url) and { ["Referer"] = origin(url) } or nil }
    end
    local stream, mime = scanEmbedPage(url)
    if stream then
        local src = { url = stream, mime = mime }
        local ref = origin(url)
        if ref then src.headers = { ["Referer"] = ref } end
        return src
    end
    return nil
end

function getVideoList(episodeUrl)
    ensureLibs()
    local r = http_get(episodeUrl)
    if not r.success then
        log_error("Hentaila: episode page failed (HTTP " .. tostring(r.code) .. ")")
        return {}
    end

    -- Embeds are serialized inside the SvelteKit bootstrap script:
    --   embeds:{DUB:[{server:"X",url:"Y"},...],SUB:[...]},downloads
    local embeds = r.body:match("embeds:{(.-)},downloads")
    if not embeds then
        log_error("Hentaila: embeds block not found in " .. episodeUrl)
        return {}
    end
    embeds = embeds:gsub("\\/", "/")

    local sources, seen = {}, {}
    for _, track in ipairs({ "SUB", "DUB" }) do
        local list = embeds:match(track .. ":%[(.-)%]")
        if list then
            for server, url in list:gmatch('{server:"([^"]+)",%s*url:"([^"]+)"') do
                if not seen[url] then
                    seen[url] = true
                    local src = resolveEmbed(server, url)
                    if src then
                        src.quality = track .. " · " .. server
                        table.insert(sources, src)
                    else
                        log_info("Hentaila: skipped " .. track .. " " .. server .. " " .. url)
                    end
                end
            end
        end
    end

    return sources
end

-- ── Filters ───────────────────────────────────────────────────────────────────
-- The site expects LOWERCASE genre slugs (the CloudStream source calls
-- .lowercase() on them), e.g. ?genre=casadas or ?genre=juegos sexuales.

-- Genres the site's UI exposes that we never list (sexualised minors).
local BLOCKED_GENRES = { loli = true, lolicon = true }

-- Fallback list, used when discovery from the site finds nothing.
local STATIC_GENRES = {
    { "casadas", "Casadas" }, { "ahegao", "Ahegao" }, { "chikan", "Chikan" },
    { "anal", "Anal" }, { "enfermeras", "Enfermeras" }, { "futanari", "Futanari" },
    { "hardcore", "Hardcore" }, { "incesto", "Incesto" }, { "milfs", "milfs" },
    { "juegos sexuales", "Juegos Sexuales" }, { "maids", "Sirvientas" },
    { "netorare", "Netorare" }, { "ninfomania", "Ninfomanía" }, { "ninjas", "Ninjas" },
    { "orgias", "Orgías" }, { "succubus", "Súcubo" }, { "teacher", "Profesoras" },
    { "tentaculos", "Tentáculos" }, { "tetonas", "Pechonas" }, { "vanilla", "Vainilla" },
    { "virgenes", "Vírgenes" }, { "bondage", "Bondage" }, { "threesome", "Trío" },
    { "elfas", "Elfas" }, { "paizuri", "Paizuri" }, { "gal", "Gal" },
    { "oyakodon", "Oyakodon" }, { "shota", "shota" }, { "petit", "petit" },
    -- Not in the CloudStream list; harmless if the site has no such slug.
    { "escolares", "Escolares" }, { "harem", "Harem" }, { "yuri", "Yuri" },
    { "yaoi", "Yaoi" }, { "ecchi", "Ecchi" }, { "romance", "Romance" },
    { "3d", "3D" }, { "gore", "Gore" },
}

local function urlDecode(s)
    s = s:gsub("%+", " ")
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

local function titleCase(s)
    return (s:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

local _genreCache = nil

-- Reads every genre link / checkbox on /catalogo, then merges the static list.
local function discoverGenres()
    if _genreCache then return _genreCache end

    local found, order = {}, {}
    local function add(slug, label)
        slug = string_trim(urlDecode(slug or "")):lower()
        if slug == "" or BLOCKED_GENRES[slug] or found[slug] then return end
        label = string_clean(label or "")
        if label == "" then label = titleCase(slug) end
        found[slug] = label
        table.insert(order, slug)
    end

    local r = http_get(CATALOG)
    if r.success then
        for _, a in ipairs(html_select(r.body, 'a[href*="genre="]')) do
            add(a.href:match("[?&]genre=([^&#]+)"), a.text)
        end
        for _, inp in ipairs(html_select(r.body, 'input[name="genre"]')) do
            local v = inp:attr("value")
            local lbl = inp:attr("aria-label")
            add(v, (lbl and lbl ~= "") and lbl or v)
        end
    else
        log_error("Hentaila: genre discovery failed (HTTP " .. tostring(r.code) .. ")")
    end

    for _, g in ipairs(STATIC_GENRES) do add(g[1], g[2]) end

    local options = {}
    for _, slug in ipairs(order) do
        table.insert(options, { value = slug, label = found[slug] })
    end
    table.sort(options, function(x, y) return x.label:lower() < y.label:lower() end)

    _genreCache = options
    return options
end

function getFilterList()
    ensureLibs()
    return {
        {
            type         = "select",
            key          = "order",
            label        = "Ordenar por",
            defaultValue = "latest_added",
            options = {
                { value = "latest_added",    label = "Últimos añadidos" },
                { value = "latest_released", label = "Últimos estrenados" },
            }
        },
        {
            type         = "select",
            key          = "status",
            label        = "Estado",
            defaultValue = "all",
            options = {
                { value = "all",     label = "Todos" },
                { value = "emision", label = "En emisión" },
            }
        },
        {
            type    = "checkbox",
            key     = "genre",
            label   = "Géneros",
            options = discoverGenres()
        },
    }
end

function getCatalogFiltered(index, filters)
    ensureLibs()
    if type(filters) ~= "table" then filters = {} end

    local order = filters["order"]
    if type(order) ~= "string" or order == "" then order = "latest_added" end
    local q = "?order=" .. url_encode(order)

    local status = filters["status"]
    if type(status) == "string" and status ~= "" and status ~= "all" then
        q = q .. "&status=" .. url_encode(status)
    end

    -- Checkbox "genre" arrives as filters["genre_included"] (array of values).
    -- Lowercased because the site only matches lowercase slugs.
    local genres = filters["genre_included"]
    if type(genres) == "table" then
        for _, g in ipairs(genres) do
            if type(g) == "string" and g ~= "" then
                q = q .. "&genre=" .. url_encode(g:lower())
            end
        end
    end

    log_info("Hentaila: filtered -> " .. CATALOG .. q .. "&page=" .. (index + 1))
    return fetchCatalog(q .. "&page=" .. (index + 1))
end
