-- HManga.asia plugin para NoveLA (v1.1.0)
-- Fuente manga (imágenes) en español.
--
-- Cómo funciona el sitio:
--  - Cada capítulo es un POST de WordPress cuyas páginas están en un array
--    JS: pages=["url1","url2",...] dentro de <div id="hm-post-body">.
--  - Las series multi-capitulo tienen página /series/... con la lista.
--  - Las imágenes se sirven con lazy-load (data-src) y el sitio usa
--    Cloudflare (NoveLA lo resuelve con su bypass integrado).
--
-- 1.2.0: filtro de géneros (se extraen de /catalogo/ en runtime) + avif.
-- 1.2.1: índice de géneros corregido a /etiquetas/ (archivos /tags/{slug}/).
-- 1.2.2: getBookGenres quita el contador del final ("Ahegao 2515" → "Ahegao").

id       = "hmanga_asia"
name     = "HManga"
version  = "1.2.2"
baseUrl  = "https://hmanga.asia"
language = "es"
content_type = "manga"
referer  = "https://hmanga.asia/"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/hmanga_asia.png"

-- ── Helpers ──────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local _pageCache = {}

local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if not r.success then
        sleep(400)
        r = http_get(url)
    end
    if not r.success then return nil end
    _pageCache[url] = r.body
    return r.body
end

-- URL real de una imagen (los temas WP cargan con lazy-load)
local function imgSrc(el)
    if not el then return "" end
    for _, attr in ipairs({ "data-src", "data-lazy-src", "data-original", "data-lazyload", "data-url" }) do
        local v = el:attr(attr)
        if v and v ~= "" then return v end
    end
    if el.src and el.src ~= "" then return el.src end
    local ss = el:attr("srcset") or el:attr("data-srcset") or ""
    if ss ~= "" then
        local first = string.match(ss, "([^,%s]+)")
        if first then return first end
    end
    return ""
end

local function isBadImage(src)
    if not src or src == "" then return true end
    local s = string.lower(src)
    if string_ends_with(s, ".svg") then return true end
    local bad = { "logo", "icon", "avatar", "gravatar", "badge", "banner",
                  "emoji", "smiley", "counter", "blank", "spacer", "advert",
                  "/ads", "doubleclick", "analytic", "pixel" }
    for _, b in ipairs(bad) do
        if string.find(s, b, 1, true) then return true end
    end
    return false
end

local function imageExtOk(u)
    local clean = string.match(u, "^(.-)%?") or u
    local ext = string.lower(string.match(clean, "%.(%a+)$") or "")
    return ext == "jpg" or ext == "jpeg" or ext == "png"
        or ext == "webp" or ext == "gif" or ext == "avif"
end

-- Solo enlaces a POSTS del sitio (filtra menú, tags, autores, series, ads)
local function isPostUrl(url)
    if not url or url == "" then return false end
    local u = string.lower(url)
    if string_starts_with(u, "#") then return false end
    local hm = string_starts_with(u, "https://hmanga.asia/")
        or string_starts_with(u, "http://hmanga.asia/")
        or string_starts_with(u, "/")
    if not hm then return false end
    local bad = { "/tag/", "/tags/", "/category/", "/autor/", "/author/", "/series/",
                  "/feed", "/wp-", "?s=", "/search", "/page/", "wp-json",
                  ".xml", "comment", "/descarga", "2257", "privacy", "terms",
                  "/catalogo", "/etiquetas" }
    for _, b in ipairs(bad) do
        if string.find(u, b, 1, true) then return false end
    end
    return true
end

-- ── Páginas de imágenes (núcleo del plugin) ──────────────────────────────

-- URLs de imagen embebidas en texto/JS (respaldos)
local function urlsFromText(text)
    local found, seen = {}, {}
    if not text or text == "" then return found end
    for u in string.gmatch(text, "https?://[^\"'<>%s%)%]]+%.%a+") do
        u = string.gsub(u, "&amp;", "&")
        u = absUrl(u)
        if imageExtOk(u) and not isBadImage(u) and not seen[u] then
            seen[u] = true
            table.insert(found, u)
        end
    end
    return found
end

function getPageList(html, url)
    if not html or html == "" then return {} end

    local pages, seen = {}, {}
    local function add(u)
        u = absUrl(u or "")
        if u == "" or seen[u] then return end
        if not imageExtOk(u) or isBadImage(u) then return end
        seen[u] = true
        table.insert(pages, u)
    end

    -- 1) El tema guarda las páginas en un array JS:
    --    pages=["https://.../01.jpg","https://.../02.jpg",...]
    --    (se busca en el HTML crudo: funciona aunque el script esté
    --     ofuscado por Cloudflare Rocket Loader)
    local arr = string.match(html, "pages%s*=%s*%[([%s%S]-)%]")
    if arr then
        for u in string.gmatch(arr, "https?://[^\"',%s%)%]]+") do
            add(u)
        end
        if #pages > 0 then return pages end
    end

    -- 2) Fallback: imágenes directas dentro del contenedor del post
    local body = html_select_first(html, "#hm-post-body")
    local scope = body and body.html or html
    for _, el in ipairs(html_select(scope, "img")) do
        add(imgSrc(el))
    end

    -- 3) Fallback: URLs de imagen sueltas en el HTML del post
    if #pages == 0 then
        for _, u in ipairs(urlsFromText(scope)) do add(u) end
    end

    return pages
end

function getChapterText(html, url)
    -- Las fuentes manga no usan texto; las páginas van en getPageList
    return ""
end

-- ── Catálogo ──────────────────────────────────────────────────────────────

local CARD_SELECTORS = { "div.card.post", ".card.post", "article", ".post" }

local function parseCard(cardHtml)
    local titleEl = html_select_first(cardHtml,
        "a[rel='bookmark'], h2 a[href], h3 a[href], .entry-title a[href], .post-title a[href]")
    local url, title = "", ""
    if titleEl then
        url = titleEl.href or ""
        title = string_clean(titleEl.text)
    end
    if url == "" then
        local a = html_select_first(cardHtml, "a[href]")
        if a then url = a.href or "" end
    end
    local cover = ""
    local img = html_select_first(cardHtml, "img.wp-post-image")
            or html_select_first(cardHtml, "img[data-src]")
            or html_select_first(cardHtml, "img")
    if img then cover = absUrl(imgSrc(img)) end
    if title == "" and img then title = string_clean(img:attr("alt") or "") end
    return url, title, cover
end

local function parseCatalog(html)
    local items, seen = {}, {}

    local cards
    for _, sel in ipairs(CARD_SELECTORS) do
        local found = html_select(html, sel)
        if #found >= 3 then cards = found; break end
    end

    if cards then
        for _, card in ipairs(cards) do
            local url, title, cover = parseCard(card.html)
            url = absUrl(url)
            if isPostUrl(url) and title ~= "" and not seen[url] then
                seen[url] = true
                table.insert(items, { title = title, url = url, cover = cover })
            end
        end
    else
        -- Fallback: enlaces de título sueltos
        for _, a in ipairs(html_select(html, "a[rel='bookmark'], h2 a[href], h3 a[href]")) do
            local u = absUrl(a.href or "")
            local t = string_clean(a.text)
            if isPostUrl(u) and t ~= "" and not seen[u] then
                seen[u] = true
                table.insert(items, { title = t, url = u, cover = "" })
            end
        end
    end

    return items
end

function getCatalogList(index)
    local page = (index or 0) + 1
    local url = baseUrl
    if page > 1 then url = baseUrl .. "/page/" .. page .. "/" end
    local html = fetchPage(url)
    if not html then return { items = {}, hasNext = false } end
    local items = parseCatalog(html)
    return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
    local page = (index or 0) + 1
    local q = url_encode(query or "")
    local url
    if page <= 1 then
        url = baseUrl .. "/?s=" .. q
    else
        url = baseUrl .. "/page/" .. page .. "/?s=" .. q
    end
    local html = fetchPage(url)
    if not html then return { items = {}, hasNext = false } end
    local items = parseCatalog(html)
    return { items = items, hasNext = #items > 0 }
end

-- ── Filtro por género (índice: /etiquetas/ → /tags/{slug}/) ───────────────

local GENRE_INDEX_URL = baseUrl .. "/etiquetas/"
local _genreCache = nil

local function getGenres()
    if _genreCache then return _genreCache end
    local genres = {}
    local html = fetchPage(GENRE_INDEX_URL)
    if html then
        local seen = {}
        for _, a in ipairs(html_select(html, "a[href*='/tags/']")) do
            local href = absUrl(a.href or "")
            local name = string_clean(a.text or "")
            name = string.gsub(name, "%s*%d+%s*$", "")
            name = string_trim(name)
            if name ~= "" and href ~= "" and not seen[href] then
                seen[href] = true
                table.insert(genres, { value = href, label = name })
            end
        end
        table.sort(genres, function(x, y) return x.label < y.label end)
    end
    _genreCache = genres
    log_error("hmanga_asia: " .. tostring(#genres) .. " generos en /etiquetas/")
    return genres
end

function getFilterList()
    local genres = getGenres()
    if #genres == 0 then return {} end
    local options = { { value = "", label = "Todo" } }
    for _, g in ipairs(genres) do
        table.insert(options, { value = g.value, label = g.label })
    end
    return {
        {
            type         = "select",
            key          = "genre",
            label        = "Género",
            defaultValue = "",
            options      = options
        }
    }
end

function getCatalogFiltered(index, filters)
    local genreUrl = filters and filters["genre"] or ""
    if genreUrl == "" then return getCatalogList(index) end

    local page = (index or 0) + 1
    local url = tostring(genreUrl)
    if page > 1 then
        -- WP: /tags/milf/page/2/
        url = string.gsub(url, "/$", "") .. "/page/" .. tostring(page) .. "/"
    end

    local html = fetchPage(url)
    if not html then return { items = {}, hasNext = false } end
    local items = parseCatalog(html)
    return { items = items, hasNext = #items > 0 }
end

-- ── Lista de capítulos ────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local base = string.gsub(bookUrl or "", "#.*$", "")

    -- Las series multi-capitulo tienen página /series/... con la lista
    local html = fetchPage(base)
    if html then
        local seriesA = html_select_first(html, "a[href*='/series/']")
        if seriesA and seriesA.href then
            local sHtml = fetchPage(seriesA.href)
            if sHtml then
                local items = parseCatalog(sHtml)
                if #items > 0 then
                    -- La lista del sitio es de más nuevo a más antiguo;
                    -- se invierte para orden de lectura
                    local chapters = {}
                    for i = #items, 1, -1 do
                        table.insert(chapters, {
                            title = items[i].title,
                            url = items[i].url
                        })
                    end
                    return chapters
                end
            end
        end
    end

    -- One-shot: un único "capítulo" con todas las páginas del post
    return { { title = "Leer", url = base } }
end

-- ── Detalles del libro ────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return nil end
    local el = html_select_first(html, "h1.entry-title, h1")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return nil end
    local cover = html_attr(html, "meta[property='og:image']", "content")
    if cover == "" then
        cover = html_attr(html, "meta[name='twitter:image']", "content")
    end
    if cover == "" then
        local pages = getPageList(html, bookUrl)
        if #pages > 0 then cover = pages[1] end
    end
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return nil end
    local d = html_attr(html, "meta[name='description']", "content")
    if d == "" then
        d = html_attr(html, "meta[property='og:description']", "content")
    end
    return d ~= "" and string_trim(d) or nil
end

function getBookGenres(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return {} end
    local genres, seen = {}, {}
    for _, a in ipairs(html_select(html, "a[rel='tag']")) do
        -- El texto del enlace incluye el contador: "Ahegao 2515" → "Ahegao"
        local g = string_clean(a.text)
        g = string.gsub(g, "%s*%(?%d+%)?%s*$", "")
        g = string_trim(g)
        if g ~= "" and not seen[g] then
            seen[g] = true
            table.insert(genres, g)
        end
    end
    return genres
end

function getBookLastUpdate(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return nil end
    local v = html_attr(html, "meta[property='og:updated_time']", "content")
    if v == "" then v = html_attr(html, "meta[property='article:modified_time']", "content") end
    if v == "" then v = html_attr(html, "meta[property='article:published_time']", "content") end
    if v == "" then
        local t = html_select_first(html, "time[datetime]")
        if t then v = t:attr("datetime") or "" end
    end
    local y, m, d = string.match(v or "", "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return y and (y .. "-" .. m .. "-" .. d) or nil
end
