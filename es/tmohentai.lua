-- =====================================================================
-- Plugin: TMOHentai (v5.1 - Lector corregido)
-- Target: NoveLA (content_type = "manga")
-- Base URL: https://tmohentai.app
--
-- Cambios v5.1 (solo capitulos / lector):
--   * getChapterList lee los enlaces reales /view_uploads/<id> de la ficha
--     (el id de la obra no siempre es el id del upload).
--   * getPageList sigue el flujo real del lector TMO:
--       /view_uploads/ID -> pagina intermedia con redireccion JS
--       -> /viewer/<hash>/paginated -> /viewer/<hash>/cascade (todas las imgs)
--   * Las imagenes se leen de data-original / data-src / src.
-- =====================================================================

id           = "tmohentai"
name         = "TMOHentai"
version      = "5.1.0"
baseUrl      = "https://tmohentai.app"
language     = "es"
content_type = "manga"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/tmohentai.png"
referer      = "https://tmohentai.app/"

-- =====================================================================
-- FUNCIONES DE AYUDA (HELPERS)
-- =====================================================================

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
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    log_error("TMOHentai: Error de red (HTTP " .. tostring(r.code) .. ") en " .. url)
    return nil
end

local function extractId(url)
    return url:match("/library/[^/]+/(%d+)") or url:match("/view_uploads/(%d+)")
end

-- =====================================================================
-- CATÁLOGO Y BÚSQUEDA
-- =====================================================================

local function parseCards(body)
    local items = {}

    for _, a in ipairs(html_select(body, "a")) do
        local href = a.href
        if href and href:find("/library/") then
            local title = string_clean(a:attr("title") or a.text)
            local img = html_select_first(a.html, "img")
            local cover = img and (img:attr("src") or img:attr("data-src")) or ""

            if title ~= "" and href ~= "" then
                table.insert(items, {
                    title = title,
                    url   = absUrl(href),
                    cover = absUrl(cover)
                })
            end
        end
    end

    local seen, unique = {}, {}
    for _, item in ipairs(items) do
        if not seen[item.url] then
            seen[item.url] = true
            table.insert(unique, item)
        end
    end
    return unique
end

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/biblioteca?page=" .. page
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCards(r.body)
    local hasNext = #items > 0
    return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
    if index > 0 or not query or query == "" then return { items = {}, hasNext = false } end
    local url = baseUrl .. "/biblioteca?search=" .. url_encode(query)
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    return { items = parseCards(r.body), hasNext = false }
end

-- =====================================================================
-- DETALLES DEL LIBRO (OBRA)
-- =====================================================================

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local cover = html_attr(body, "img", "src")
    if cover == "" or not cover:find("storage") then
        local firstImg = html_select_first(body, "img[src*='storage']")
        cover = firstImg and firstImg:attr("src") or ""
    end
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local el = html_select_first(body, "div.sinopsis, div.description, p.description")
    if el then
        local text = string_trim(el.text)
        if text ~= "" and text ~= "No hay descripción disponible para esta obra." then
            return text
        end
    end
    return nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local genres = {}
    local seen = {}

    for _, a in ipairs(html_select(body, "a")) do
        local href = a.href
        if href and href:find("/tag/") then
            local tag = string_clean(a.text)
            if tag ~= "" and not seen[tag:lower()] then
                seen[tag:lower()] = true
                table.insert(genres, tag)
            end
        end
    end

    return genres
end

function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local status = body:match("Ongoing") and "En curso" or nil
    if not status then
        status = body:match("Complete") and "Completo" or nil
    end
    return status
end

-- =====================================================================
-- CAPÍTULOS
-- =====================================================================
-- La ficha de la obra contiene enlaces /view_uploads/<id_upload>.
-- Ese id NO siempre coincide con el id de la obra, asi que se leen de
-- la pagina. Solo si no hay ninguno se construye la URL con el id de obra.

local GENERIC_LABELS = {
    [""] = true, ["leer"] = true, ["ver"] = true, ["read"] = true,
    ["leer ahora"] = true, ["ver ahora"] = true, ["iniciar lectura"] = true,
    ["leer online"] = true, ["leer obra"] = true,
}

function getChapterList(bookUrl)
    local chapters, seen = {}, {}

    -- Lectura directa (no cacheada): la lista debe estar siempre al dia.
    local r = http_get(bookUrl)
    if r.success then
        for _, a in ipairs(html_select(r.body, "a[href*='/view_uploads/']")) do
            local u = absUrl(a.href)
            if u ~= "" and not seen[u] then
                seen[u] = true
                table.insert(chapters, { title = string_clean(a.text or ""), url = u })
            end
        end
    else
        log_error("TMOHentai: getChapterList HTTP " .. tostring(r.code) .. " en " .. bookUrl)
    end

    -- Fallback: construir la URL con el id de la obra
    if #chapters == 0 then
        local id = extractId(bookUrl)
        if not id then
            log_error("TMOHentai: No se pudo extraer ID de " .. bookUrl)
            return {}
        end
        return { { title = "Leer obra completa", url = baseUrl .. "/view_uploads/" .. id } }
    end

    if #chapters == 1 then
        if GENERIC_LABELS[chapters[1].title:lower()] then
            chapters[1].title = "Leer obra completa"
        end
        return chapters
    end

    -- Varios uploads: el sitio los lista del mas nuevo al mas viejo.
    local ordered = {}
    for i = #chapters, 1, -1 do table.insert(ordered, chapters[i]) end
    for i, ch in ipairs(ordered) do
        if GENERIC_LABELS[ch.title:lower()] then ch.title = "Capítulo " .. i end
    end
    return ordered
end

-- =====================================================================
-- LECTOR: RESOLUCION DEL VISOR Y EXTRACCION DE IMAGENES
-- =====================================================================

local BAD_WORDS = { "logo", "avatar", "icon", "favicon", "banner", "sprite",
                    "loading", "placeholder", "captcha", "blank" }

local function isBadImg(u)
    local l = u:lower()
    for _, w in ipairs(BAD_WORDS) do
        if l:find(w, 1, true) then return true end
    end
    return false
end

-- Atributo real de la imagen (lazy-load incluido).
local function imgSrc(el)
    for _, k in ipairs({ "data-original", "data-src", "data-lazy-src", "src" }) do
        local v = el:attr(k)
        if v and v ~= "" and not v:find("^data:") then return absUrl(v) end
    end
    return ""
end

local VIEWER_SELECTORS = {
    "div.viewer-container img",
    "img.viewer-img",
    "img.viewer-image",
    "#viewer img",
    "div.reader-img-wrap img",
    "div.reader-container img",
    "div#reader img",
}

-- Solo selectores del visor (sin heuristicas).
local function viewerImages(doc)
    for _, sel in ipairs(VIEWER_SELECTORS) do
        local pages, seen = {}, {}
        for _, el in ipairs(html_select(doc, sel)) do
            local u = imgSrc(el)
            if u ~= "" and not isBadImg(u) and not seen[u] then
                seen[u] = true
                table.insert(pages, u)
            end
        end
        if #pages > 0 then return pages end
    end
    return {}
end

local IMG_EXT = { ".webp", ".jpg", ".jpeg", ".png", ".avif" }

local function hasImgExt(u)
    local l = u:lower():gsub("[?#].*$", "")
    for _, e in ipairs(IMG_EXT) do
        if l:sub(-#e) == e then return true end
    end
    return false
end

-- Con heuristicas: <img> por ruta y, como ultimo recurso, URLs sueltas en el HTML.
local function extractImages(doc)
    local pages = viewerImages(doc)
    if #pages > 0 then return pages end

    local seen = {}
    for _, el in ipairs(html_select(doc, "img")) do
        local u = imgSrc(el)
        if u ~= "" and not isBadImg(u) and not seen[u]
            and (u:find("/uploads/", 1, true) or u:find("/storage/", 1, true)
                 or u:find("/mangas/", 1, true) or u:find("/viewer/", 1, true)) then
            seen[u] = true
            table.insert(pages, u)
        end
    end
    if #pages > 0 then return pages end

    local clean = doc:gsub("\\/", "/")
    for u in clean:gmatch([=[https?://[^"'%s<>\]+]=]) do
        if hasImgExt(u) and not isBadImg(u) and not seen[u] then
            seen[u] = true
            table.insert(pages, u)
        end
    end
    return pages
end

-- id del visor -> URL de la vista "cascade" (todas las paginas en un HTML)
local function cascadeUrlFrom(doc, cur)
    cur = cur or ""
    local vid = cur:match("/viewer/([^/%?#]+)/paginated") or cur:match("/viewer/([^/%?#]+)/cascade")
    if not vid then
        vid = doc:match("/viewer/([%w%-_]+)/paginated") or doc:match("/viewer/([%w%-_]+)/cascade")
    end
    if vid then return baseUrl .. "/viewer/" .. vid .. "/cascade" end
    return nil
end

-- Sigue la pagina intermedia de /view_uploads (4 variantes del lector TMO).
-- Devuelve el HTML siguiente o nil si no hay redireccion.
local function followRedirect(doc, pageUrl)
    local opts = { headers = { ["Referer"] = pageUrl } }

    -- 1) <input id="redirect-url" value="...">
    local v = html_attr(doc, "input#redirect-url", "value")
    if v and v ~= "" then
        local r = http_get(absUrl(v), opts)
        if r.success then return r.body end
    end

    -- 2) window.location.replace("...")
    local u = doc:match([=[window%.location%.replace%(%s*["']([^"']+)["']]=])
    -- 3) var redirectUrl = '...'
    if not u then u = doc:match([=[redirectUrl%s*=%s*["']([^"']+)["']]=]) end
    if u then
        u = u:gsub("\\/", "/")
        local r = http_get(absUrl(u), opts)
        if r.success then return r.body end
    end

    -- 4) formulario autoenviado: { uniqid: "...", _token: "..." } + form.action
    if doc:find("uniqid", 1, true) then
        local action = doc:match([=[form%.action%s*=%s*"([^"]*)"]=])
        local obj = doc:match("{(.-)}")
        if action and obj then
            local parts = {}
            for k, val in obj:gmatch([=[([%w_]+)%s*:%s*"([^"]*)"]=]) do
                table.insert(parts, k .. "=" .. url_encode(val))
            end
            if #parts > 0 then
                local r = http_post(absUrl(action), table.concat(parts, "&"), opts)
                if r.success then return r.body end
            end
        end
    end

    return nil
end

-- Lleva el HTML recibido hasta la vista cascade del visor.
local function resolveViewerDoc(html, url)
    local doc, cur = html or "", url or ""

    for _ = 1, 5 do
        local canon = html_attr(doc, "link[rel=canonical]", "href")
        if not canon or canon == "" then
            canon = html_attr(doc, "meta[property='og:url']", "content")
        end
        if canon and canon ~= "" and canon:find("/viewer/", 1, true) then
            cur = absUrl(canon)
        end

        local imgs = viewerImages(doc)
        local onPaginated = cur:find("/paginated", 1, true) ~= nil
        if #imgs > 1 or (#imgs == 1 and not onPaginated) then
            return doc, cur
        end

        -- Visor paginado (o con 1 sola imagen): pasar a cascade
        local cascade = cascadeUrlFrom(doc, cur)
        if cascade and cascade ~= cur then
            local r = http_get(cascade, { headers = { ["Referer"] = cur } })
            if r.success then
                doc, cur = r.body, cascade
            else
                log_error("TMOHentai: cascade HTTP " .. tostring(r.code) .. " " .. cascade)
                return doc, cur
            end
        else
            -- Pagina intermedia con redireccion
            local nextDoc = followRedirect(doc, cur)
            if not nextDoc then return doc, cur end
            doc = nextDoc
        end
    end

    return doc, cur
end

-- =====================================================================
-- PÁGINAS DEL CAPÍTULO
-- =====================================================================

function getPageList(html, url)
    html = html or ""
    url  = url or ""

    local doc, cur = resolveViewerDoc(html, url)
    local pages = extractImages(doc)

    -- La pagina que entrego la app puede venir vacia: pedirla nosotros.
    if #pages == 0 and url ~= "" then
        local r = http_get(url, { headers = { ["Referer"] = baseUrl .. "/" } })
        if r.success then
            doc, cur = resolveViewerDoc(r.body, url)
            pages = extractImages(doc)
        else
            log_error("TMOHentai: getPageList HTTP " .. tostring(r.code) .. " en " .. url)
        end
    end

    -- Ultimo recurso (patron observado en el CDN; sin verificar para todas las obras)
    if #pages == 0 then
        local id = extractId(url) or extractId(cur)
        if id then
            log_error("TMOHentai: sin imagenes en el visor, usando patron del CDN para id " .. id)
            local total = #html_select(doc, "#viewer-pages-select option")
            if total == 0 then total = 60 end
            for i = 1, total do
                table.insert(pages, "https://storage.tmohentai.app/mangas/" .. id .. "/" .. i .. ".webp")
            end
        end
    end

    if #pages == 0 then
        log_error("TMOHentai: no se encontraron paginas para " .. url .. " (visor=" .. cur .. ")")
        return nil
    end

    local seen, unique = {}, {}
    for _, p in ipairs(pages) do
        if not seen[p] then
            seen[p] = true
            table.insert(unique, p)
        end
    end

    log_info("TMOHentai: " .. #unique .. " paginas desde " .. cur)
    return unique
end

-- =====================================================================
-- FILTROS
-- =====================================================================

local STATIC_GENRES = {
    { "doujinshi", "Doujinshi" }, { "manga", "Manga" }, { "hentai", "Hentai" },
    { "netorare", "Netorare" }, { "impregnation", "Impregnación" }, { "harem", "Harem" },
    { "schoolgirl", "Escolar" }, { "group", "Grupo" }, { "creampie", "Creampie" },
    { "orgy", "Orgía" }, { "virgin", "Virgen" }, { "mind-control", "Control Mental" },
    { "big-breasts", "Pechos Grandes" }, { "ahegao", "Ahegao" }, { "incest", "Incesto" },
    { "rape", "Violación" }, { "yuri", "Yuri" }, { "yaoi", "Yaoi" },
    { "futanari", "Futanari" }, { "bondage", "Bondage" }, { "milf", "MILF" }
}

local _genreCache = nil

local function discoverGenres()
    if _genreCache then return _genreCache end

    local found, order = {}, {}

    local function add(slug, label)
        slug = string_trim(slug or ""):lower()
        if slug == "" or found[slug] then return end

        label = string_clean(label or "")
        if label == "" then label = slug end

        found[slug] = label
        table.insert(order, slug)
    end

    local r = http_get(baseUrl .. "/biblioteca")
    if r.success then
        for _, a in ipairs(html_select(r.body, 'a[href*="tag="]')) do
            local tag = a.href:match("[?&]tag=([^&#]+)")
            if tag then
                add(tag, a.text)
            end
        end
    end

    for _, g in ipairs(STATIC_GENRES) do
        add(g[1], g[2])
    end

    local options = {}
    for _, slug in ipairs(order) do
        table.insert(options, { value = slug, label = found[slug] })
    end

    table.sort(options, function(x, y) return x.label:lower() < y.label:lower() end)
    _genreCache = options
    return options
end

function getFilterList()
    return {
        {
            type         = "select",
            key          = "type",
            label        = "Tipo",
            defaultValue = "all",
            options = {
                { value = "all", label = "Todos" },
                { value = "doujinshi", label = "Doujinshi" },
                { value = "manga", label = "Manga" },
                { value = "hentai", label = "Hentai" }
            }
        },
        {
            type         = "select",
            key          = "order",
            label        = "Ordenar por",
            defaultValue = "latest",
            options = {
                { value = "latest", label = "Más recientes" },
                { value = "popular", label = "Más populares" },
                { value = "rated", label = "Mejor valorados" },
                { value = "alphabetical", label = "Alfabético" }
            }
        },
        {
            type    = "checkbox",
            key     = "genre",
            label   = "Géneros",
            options = discoverGenres()
        }
    }
end

function getCatalogFiltered(index, filters)
    if type(filters) ~= "table" then filters = {} end

    local page = index + 1
    local query = "?page=" .. page

    local order = filters["order"]
    if type(order) == "string" and order ~= "" and order ~= "latest" then
        query = query .. "&order=" .. url_encode(order)
    end

    local typeFilter = filters["type"]
    if type(typeFilter) == "string" and typeFilter ~= "" and typeFilter ~= "all" then
        query = query .. "&type=" .. url_encode(typeFilter)
    end

    local genres = filters["genre_included"]
    if type(genres) == "table" then
        for _, g in ipairs(genres) do
            if type(g) == "string" and g ~= "" then
                query = query .. "&tag=" .. url_encode(g:lower())
            end
        end
    end

    local url = baseUrl .. "/biblioteca" .. query
    log_info("TMOHentai: filtered -> " .. url)

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCards(r.body)
    local hasNext = #items > 0
    return { items = items, hasNext = hasNext }
end
