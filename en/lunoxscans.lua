-- ── Metadatos ─────────────────────────────────────────────────────────────────
-- Lunox Novels (lunoxscans.com) — tema WordPress Madara muy personalizado.
--   Catálogo : home "Latest Releases" (#loop-content, 39 tarjetas) + "LOAD MORE" (admin-ajax)
--   Ficha    : /series/<slug>/  → la lista completa de capítulos viene embebida en el HTML
--   Capítulo : /series/<slug>/chapter-N/ → texto en .reading-content .text-left
--   Los capítulos premium (con monedas) traen href="#" y NO se pueden leer: se omiten.
id       = "lunoxscans"
name     = "Lunox Novels"
version  = "1.0.0"
baseUrl  = "https://lunoxscans.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/lunoxscans.png"

-- ── Hélpers ───────────────────────────────────────────────────────────────────

local ajaxUrl = baseUrl .. "/wp-admin/admin-ajax.php"

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Caché de la ficha (solo para título/portada/descripción/géneros; NO para capítulos ni hash)
local _pageCache = {}
local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- La ficha pesa ~1.3 MB por los SVG de cada capítulo premium. Todo lo que no es la lista
-- de capítulos está antes de este marcador, así que se parsea solo esa parte (~78 KB).
local LIST_MARKER = 'id="lunox-chapters-list"'
local function splitBook(body)
    local pos = body:find(LIST_MARKER, 1, true)
    if not pos then return body, body end
    return body:sub(1, pos - 1), body:sub(pos)
end

local function formEncode(pairsList)
    local parts = {}
    for _, kv in ipairs(pairsList) do
        table.insert(parts, url_encode(kv[1]) .. "=" .. url_encode(kv[2]))
    end
    return table.concat(parts, "&")
end

local function coverOf(html)
    for _, attr in ipairs({ "data-src", "data-lazy-src", "src" }) do
        local v = html_attr(html, "img", attr)
        if v and v ~= "" and not string_starts_with(v, "data:") then return absUrl(v) end
    end
    return ""
end

-- Tarjetas de libro. Soporta la tarjeta del tema (.page-item-detail / .novel-card-*)
-- y la de búsqueda estándar de Madara (.c-tabs-item__content).
local function parseCards(body)
    local scope = html_select_first(body, "#loop-content")
    local src = scope and scope.html or body

    local cards = html_select(src, ".page-item-detail")
    if #cards == 0 then cards = html_select(src, ".c-tabs-item__content") end

    local items, seen = {}, {}
    for _, card in ipairs(cards) do
        local a = html_select_first(card.html, ".novel-card-title a[href]")
            or html_select_first(card.html, ".post-title a[href]")
            or html_select_first(card.html, "h3 a[href], h5 a[href]")
        if a then
            local url = absUrl(a.href)
            -- solo fichas de libro (/series/<slug>/), nunca capítulos ni taxonomías
            if url:match("/series/[^/]+/?$") and not seen[url] then
                seen[url] = true
                local title = string_clean(a.text)
                if title == "" and a.title then title = string_clean(a.title) end
                if title ~= "" then
                    table.insert(items, { title = title, url = url, cover = coverOf(card.html) })
                end
            end
        end
    end

    if #items == 0 then
        log_error("lunoxscans: 0 tarjetas (cards=" .. #cards .. ", body=" .. #body .. " bytes)")
    end
    return items
end

local function fetchCards(url)
    local r = http_get(url)
    if not r.success then
        log_error("lunoxscans: fallo " .. tostring(r.code) .. " en " .. url)
        return { items = {}, hasNext = false }
    end
    local items = parseCards(r.body)
    return { items = items, hasNext = #items > 0 }
end

-- URL de búsqueda/archivo estándar de Madara. Páginas >1 → /page/N/
local function buildSearchUrl(index, query, sort, genres, status, matchAll)
    local page = index + 1
    local u = baseUrl .. "/"
    if page > 1 then u = u .. "page/" .. page .. "/" end
    u = u .. "?s=" .. url_encode(query or "") .. "&post_type=wp-manga"
    if sort and sort ~= "" then u = u .. "&m_orderby=" .. url_encode(sort) end
    for _, g in ipairs(genres or {}) do u = u .. "&genre%5B%5D=" .. url_encode(g) end
    if matchAll then u = u .. "&op=1" end
    for _, s in ipairs(status or {}) do u = u .. "&status%5B%5D=" .. url_encode(s) end
    return u
end

-- ── Catálogo ──────────────────────────────────────────────────────────────────

-- Página 0: la home (39 tarjetas, verificado). Páginas siguientes: el mismo AJAX que usa
-- el botón "LOAD MORE" de la home (acción estándar madara_load_more), con las mismas
-- variables de consulta que publica la propia página (__madara_query_vars).
function getCatalogList(index)
    if index == 0 then
        return fetchCards(baseUrl .. "/")
    end

    local body = formEncode({
        { "action", "madara_load_more" },
        { "page", tostring(index) },
        { "template", "madara-core/content/content-archive" },
        { "vars[paged]", tostring(index + 1) },
        { "vars[posts_per_page]", "39" },
        { "vars[orderby]", "meta_value_num" },
        { "vars[meta_key]", "_latest_update" },
        { "vars[order]", "desc" },
        { "vars[post_type]", "wp-manga" },
        { "vars[post_status]", "publish" },
        { "vars[sidebar]", "full" },
        { "vars[manga_archives_item_layout]", "novel_card" },
        { "vars[meta_query][relation]", "AND" },
    })
    local r = http_post(ajaxUrl, body, {
        headers = {
            ["X-Requested-With"] = "XMLHttpRequest",
        }
    })
    if not r.success then
        log_error("lunoxscans: load_more falló code=" .. tostring(r.code) .. " index=" .. index)
        return { items = {}, hasNext = false }
    end
    local items = parseCards(r.body)
    return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
    return fetchCards(buildSearchUrl(index, query, "", nil, nil, false))
end

-- ── Detalles del libro ────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local head = splitBook(body)

    local h1 = html_select_first(head, ".post-title h1")
    if h1 then
        -- por si el tema mete una insignia (HOT/NEW) dentro del h1
        local t = string_clean(html_text(html_remove(h1.html, ".manga-title-badges", "span")))
        if t ~= "" then return t end
    end

    local og = html_attr(head, "meta[property='og:title']", "content")
    if og and og ~= "" then
        og = regex_replace(og, "\\s*[\\u2013\\u2014-]\\s*Lunox Novels\\s*$", "")
        return string_clean(og)
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local head = splitBook(body)

    local wrap = html_select_first(head, ".summary_image")
    local cover = wrap and coverOf(wrap.html) or ""
    if cover == "" then
        cover = html_attr(head, "meta[property='og:image']", "content") or ""
    end
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local head = splitBook(body)

    local el = html_select_first(head, ".manga-excerpt")
        or html_select_first(head, ".description-summary .summary__content")
    local text
    if el then
        text = html_text(html_remove(el.html, ".breadcrumb_nu", "script", "style"))
    else
        text = html_attr(head, "meta[property='og:description']", "content") or ""
    end

    text = string_normalize(text)
    -- el sitio antepone "Read novel <título> \ <título alterno>" (basura de SEO)
    text = regex_replace(text, "(?im)^[ \\t]*Read novel [^\\n]*(?:\\n|$)", "")
    text = regex_replace(text, "\\n{3,}", "\n\n")
    text = string_trim(text)
    return text ~= "" and text or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local head = splitBook(body)

    local genres = {}
    for _, a in ipairs(html_select(head, ".genres-content a")) do
        local g = string_clean(a.text)
        if g ~= "" then table.insert(genres, g) end
    end
    return genres
end

function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local head = splitBook(body)

    for _, item in ipairs(html_select(head, ".post-status .post-content_item")) do
        local h5 = html_select_first(item.html, "h5")
        if h5 and string_clean(h5.text) == "Status" then
            local el = html_select_first(item.html, ".summary-content")
            local v = el and string_clean(el.text) or ""
            if v ~= "" then return v end
        end
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local head = splitBook(body)

    local v = html_attr(head, "meta[property='article:modified_time']", "content") or ""
    local y, m, d = string.match(v, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return y and (y .. "-" .. m .. "-" .. d) or nil
end

function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local head = splitBook(body)

    local el = html_select_first(head, ".post-total-rating .total_votes")
    local n = el and string.match(string_clean(el.text), "%d+%.?%d*")
    return n or nil
end

-- ── Lista de capítulos ────────────────────────────────────────────────────────
-- La lista viene entera en la ficha, de más nuevo a más viejo. Los capítulos gratis tienen
-- href real; los premium (monedas) tienen href="#" y se omiten. Con el tiempo los premium
-- pasan a gratis ("Free after N hours"), así que SIEMPRE se descarga fresco (sin fetchPage).

function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then
        log_error("lunoxscans: getChapterList falló code=" .. tostring(r.code) .. " " .. bookUrl)
        return {}
    end

    local head, listPart = splitBook(r.body)
    local rows = html_select(listPart, "a.lunox-chapter-item")

    local chapters, premium = {}, 0
    for _, a in ipairs(rows) do
        local href = a.href
        if not href or href == "" or href == "#" then
            premium = premium + 1
        else
            local url = absUrl(href)
            local title = a:attr("data-name")
            if not title or title == "" then
                local n = html_select_first(a.html, ".lunox-chapter-name")
                title = n and n.text or ""
            end
            title = string_clean(title)
            if title == "" then title = url:match("/([^/]+)/?$") or url end
            table.insert(chapters, { title = title, url = url })
        end
    end

    -- el sitio lista de más nuevo a más viejo (data-order="desc"); el motor quiere cronológico.
    -- Se lee solo del botón de orden: buscar 'data-order="asc"' en todo el body era frágil
    -- (el JS del botón contiene esa misma cadena).
    if html_attr(r.body, "#lunox-sort-btn", "data-order") ~= "asc" then
        local rev = {}
        for i = #chapters, 1, -1 do table.insert(rev, chapters[i]) end
        chapters = rev
    end

    if premium > 0 then
        log_info("lunoxscans: " .. premium .. " capítulos premium omitidos, " .. #chapters .. " gratis")
    end
    return chapters
end

-- Huella = cuántos capítulos gratis hay + URL del más nuevo (cambia cuando un premium se libera)
function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)   -- directo, NO fetchPage
    if not r.success then return nil end
    local _, listPart = splitBook(r.body)
    local free = html_select(listPart, "a.lunox-chapter-item.free")
    if #free == 0 then return "0" end
    return tostring(#free) .. "|" .. tostring(free[1].href)
end

-- ── Texto del capítulo ────────────────────────────────────────────────────────
-- Estructura verificada: .reading-content > .text-left con solo <p> y <br>.
-- Trae una marca de agua al inicio y al final:
--   —————
--   This chapter was translated by Lunox Novels. ... visit our website: LunoxScans.com
--   —————
-- (No se usa la regla genérica del dominio de la guía: dejaría media frase suelta.)

-- Encabezado real del sitio: "5. Angel's Interest" (número + punto + título)
local CHAPTER_NUM_HEADER = "(?i)\\A[\\s\\p{Z}\\uFEFF]*\\d{1,4}\\s*[.)\\-–—:]\\s*[^\\n\\r]{0,90}[\\n\\r]+"

local WATERMARK      = "(?is)[\\u2014\\u2013-]{3,}\\s*[^\\n]*(?:translated by Lunox|LunoxScans\\.com)[^\\n]*\\s*[\\u2014\\u2013-]{3,}"
local WATERMARK_LINE = "(?im)^[^\\n]*(?:translated by Lunox|LunoxScans\\.com)[^\\n]*(?:\\n|$)"
-- Primera línea "<título en coreano/inglés> Episode N": repite el título del capítulo
local EPISODE_HEADER = "(?i)\\A\\s*[^\\n]{0,100}\\bEpisode\\s+\\d+[ \\t]*\\n+"

-- Limpieza estándar: quita el encabezado "… Chapter N" del inicio, líneas de
-- créditos (Translator/Editor/Proofreader) y basura del dominio.
local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

function getChapterText(html, url)
    if not html or html == "" then return "" end

    local el = html_select_first(html, ".reading-content .text-left")
    if not el then el = html_select_first(html, ".reading-content") end
    if not el then
        log_error("lunoxscans: sin .reading-content en " .. tostring(url) .. " (¿capítulo premium?)")
        return ""
    end

    local inner = html_remove(el.html, "script", "style", "ins", "iframe", "input", ".chapter-warning")
    local text = html_text(inner)
    if not text or text == "" then return "" end

    text = string_normalize(text)
    text = regex_replace(text, "\\r\\n?", "\n")
    text = regex_replace(text, WATERMARK, "")
    text = regex_replace(text, WATERMARK_LINE, "")
    text = regex_replace(text, EPISODE_HEADER, "")
    text = regex_replace(text, CHAPTER_NUM_HEADER, "")
    text = applyStandardContentTransforms(text)
    text = regex_replace(text, "\\n{3,}", "\n\n")
    return string_trim(text)
end

-- ── Filtros ───────────────────────────────────────────────────────────────────
-- Estos parámetros son los del buscador estándar de Madara (m_orderby, genre[], op, status[]).
-- Los géneros se intentan leer del formulario de búsqueda avanzada del sitio; si no
-- está, se usan los 7 confirmados en las fichas.

-- Los géneros del buscador Madara son estáticos (41 casillas de la página
-- /?s=&post_type=wp-manga). Se listan aquí en vez de scrapearlos: loadGenres
-- costaba 2.6-4.6 s de TTFB en cada apertura del panel de filtros.
local GENRES = {
    { value = "action",        label = "Action" },
    { value = "adult",         label = "Adult" },
    { value = "adventure",     label = "Adventure" },
    { value = "chaebol",       label = "Chaebol" },
    { value = "comedy",        label = "Comedy" },
    { value = "drama",         label = "Drama" },
    { value = "fantasy",       label = "Fantasy" },
    { value = "growth",        label = "Growth" },
    { value = "harem",         label = "Harem" },
    { value = "historical",    label = "Historical" },
    { value = "horror",        label = "Horror" },
    { value = "isekai",        label = "Isekai" },
    { value = "josei",         label = "Josei" },
    { value = "magic",         label = "Magic" },
    { value = "martial-arts",  label = "Martial Arts" },
    { value = "mature",        label = "Mature" },
    { value = "mecha",         label = "Mecha" },
    { value = "modern",        label = "Modern" },
    { value = "mystery",       label = "Mystery" },
    { value = "possession",    label = "Possession" },
    { value = "progression",   label = "Progression" },
    { value = "psychological", label = "Psychological" },
    { value = "regression",    label = "Regression" },
    { value = "reincarnation", label = "Reincarnation" },
    { value = "revenge",       label = "Revenge" },
    { value = "reverse",       label = "Reverse" },
    { value = "romance",       label = "Romance" },
    { value = "royalty",       label = "Royalty" },
    { value = "s",             label = "s" },
    { value = "school-life",   label = "School Life" },
    { value = "sci-fi",        label = "Sci-fi" },
    { value = "seinen",        label = "Seinen" },
    { value = "shoujo",        label = "Shoujo" },
    { value = "shounen",       label = "Shounen" },
    { value = "slice-of-life", label = "Slice of Life" },
    { value = "sports",        label = "Sports" },
    { value = "supernatural",  label = "Supernatural" },
    { value = "tragedy",       label = "Tragedy" },
    { value = "warrior",       label = "Warrior" },
    { value = "wuxia",         label = "Wuxia" },
    { value = "x",             label = "x" },
}

function getFilterList()
    return {
        {
            type         = "select",
            key          = "sort",
            label        = "Sort by",
            defaultValue = "latest",
            options = {
                { value = "latest",    label = "Latest update" },
                { value = "new-manga", label = "Newest" },
                { value = "views",     label = "Most views" },
                { value = "trending",  label = "Trending" },
                { value = "rating",    label = "Rating" },
                { value = "alphabet",  label = "A-Z" },
            }
        },
        {
            type    = "checkbox",
            key     = "genre",
            label   = "Genres",
            options = GENRES
        },
        {
            type         = "switch",
            key          = "genre_all",
            label        = "Match ALL selected genres",
            defaultValue = false
        },
        {
            type  = "checkbox",
            key   = "status",
            label = "Status",
            options = {
                { value = "on-going",  label = "Ongoing" },
                { value = "end",       label = "Completed" },
                { value = "on-hold",   label = "On hold" },
                { value = "canceled",  label = "Canceled" },
            }
        },
    }
end

function getCatalogFiltered(index, filters)
    local sort   = filters["sort"] or "latest"
    local genres = filters["genre_included"] or {}
    local status = filters["status_included"] or {}
    local all    = filters["genre_all"] == "true"
    return fetchCards(buildSearchUrl(index, "", sort, genres, status, all))
end
