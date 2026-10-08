-- ── Metadatos ─────────────────────────────────────────────────────────────────
-- Ranovel (ranovel.com) — novelas coreanas MTL. Tema WordPress Madara estándar.
--   Catálogo : home "LATEST NOVEL RELEASE" — 20 tarjetas (.page-item-detail), 91 páginas (/page/N/)
--   Búsqueda : /?s=…&post_type=wp-manga — 10 tarjetas (.c-tabs-item__content), /page/N/?s=…
--   Ficha    : /novel/<slug>/ — la lista de capítulos NO viene en el HTML: se carga por AJAX
--              (#manga-chapters-holder) → POST <ficha>/ajax/chapters/ (igual que Sonic MTL)
--   Capítulo : /novel/<slug>/chapter-N/ → texto en .reading-content .text-left
--   Basura   : bloques .code-block (publicidad + marcas de agua "Ran(o)vel dot com") dentro
--              de la descripción y del texto de cada capítulo
id       = "ranovel"
name     = "Ranovel"
version  = "1.0.0"
baseUrl  = "https://ranovel.com"
language = "Mtl"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr/icons/ranovel.png"

-- ── Hélpers ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Caché de la ficha (título/portada/descripción/géneros/estado). NUNCA para la lista de
-- capítulos ni para el hash: esas van siempre en vivo.
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

-- URL de la ficha sin query, sin fragmento y sin "/" final
local function cleanBookUrl(u)
    u = tostring(u or "")
    u = regex_replace(u, "[?#].*$", "")
    u = regex_replace(u, "/+$", "")
    return u
end

-- Portada de una imagen con lazy-load: el sitio deja en src un placeholder (dflazy.jpg)
-- y pone la real en data-src.
local function coverOf(html, selector)
    for _, attr in ipairs({ "data-src", "data-lazy-src", "data-original", "src" }) do
        local v = html_attr(html, selector, attr)
        if v and v ~= "" and not v:find("dflazy", 1, true) and not string_starts_with(v, "data:") then
            return absUrl(v)
        end
    end
    return ""
end

-- ── Limpieza de texto ─────────────────────────────────────────────────────────
-- Marcas de agua del sitio, con muchas variantes ofuscadas ("Only Ran(o)vel dot com",
-- "Read Novel Ra/n(o)ve/l com", "Read Novel 𝒓𝒂𝒏𝒐𝒗𝒆𝒍 com"…). Viven dentro de .code-block y
-- se eliminan con el bloque; esta regex es una red por si alguna queda suelta. Borra la
-- LÍNEA ENTERA y debe ir ANTES de la regla genérica del dominio (que solo cortaría desde
-- "ranovel com" y dejaría "Read Novel" colgando). Va sobre texto ya normalizado (NFKC).
local RANOVEL_MARK = "(?im)^[^\\n]*r[\\W_]{0,2}a[\\W_]{0,2}n[\\W_]{0,2}o[\\W_]{0,2}v[\\W_]{0,2}e[\\W_]{0,2}l[\\W_]{0,2}\\s*(?:dot\\s*)?com[^\\n]*(?:\\n|$)"

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "\\r\\n?", "\n")
    text = regex_replace(text, RANOVEL_MARK, "")
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    -- primera línea "Episode 01": marca del original coreano que repite el título del capítulo
    -- (solo si la línea ENTERA es esa marca)
    text = regex_replace(text, "(?i)\\A\\s*(?:Episode|Ep\\.?)\\s*\\d+[ \\t]*(?:\\n|$)", "")
    -- Líneas de crédito ("Translator: X"). Exige los dos puntos: sin ellos se borraría prosa
    -- legítima que empiece por "Editor …". Se quitó además la regla genérica "Read at/on/latest"
    -- de la plantilla: las marcas de este sitio no la usan y borraba líneas como "Read on the balcony…".
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader)\\s*:[^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = regex_replace(text, "\\n{3,}", "\n\n")
    text = string_trim(text)
    return text
end

-- Descripción: solo normalizar y quitar marcas de agua sueltas (las reglas de capítulo —
-- "Chapter N", "Episode N"— no aplican a una sinopsis).
local function cleanDescription(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "\\r\\n?", "\n")
    text = regex_replace(text, RANOVEL_MARK, "")
    text = regex_replace(text, "\\n{3,}", "\n\n")
    return string_trim(text)
end

-- ── Tarjetas de catálogo ──────────────────────────────────────────────────────
-- Dos plantillas del mismo tema: la home usa .page-item-detail; la búsqueda usa
-- .c-tabs-item__content. En ambas el título está en .post-title a.

local function parseCards(body)
    local cards = html_select(body, ".c-tabs-item__content")
    if #cards == 0 then cards = html_select(body, ".page-item-detail") end

    local items, seen = {}, {}
    for _, card in ipairs(cards) do
        local a = html_select_first(card.html, ".post-title a[href]")
            or html_select_first(card.html, "h3 a[href]")
        if a then
            local url = absUrl(a.href)
            -- solo fichas de novela (/novel/<slug>/), nunca capítulos ni taxonomías
            if url:match("/novel/[^/]+/?$") and not seen[url] then
                local title = string_clean(a.text)
                if title == "" and a.title then title = string_clean(a.title) end
                if title ~= "" then
                    seen[url] = true
                    local item = { title = title, url = url }
                    local cover = coverOf(card.html, "img")
                    if cover ~= "" then item.cover = cover end
                    local sc = html_select_first(card.html, ".post-total-rating .score")
                    local rating = sc and string_clean(sc.text) or ""
                    if rating ~= "" and rating ~= "0" then item.rating = rating end
                    table.insert(items, item)
                end
            end
        end
    end
    return items
end

-- Barra de paginación de WordPress (wp-pagenavi): "Page 1 of 91" + enlace "Next".
local function hasNextPage(body, count)
    if html_select_first(body, "a.nextpostslink") then return true end
    if html_select_first(body, ".wp-pagenavi") then return false end
    return count >= 10   -- sin barra reconocible: heurística
end

local function fetchCards(url)
    local r = http_get(url)
    if not r.success then
        -- WordPress responde 404 al pedir una página más allá de la última: es el fin, no un error
        if r.code ~= 404 then
            log_error("ranovel: HTTP " .. tostring(r.code) .. " en " .. url)
        end
        return { items = {}, hasNext = false }
    end
    local items = parseCards(r.body)
    if #items == 0 then
        log_info("ranovel: 0 tarjetas en " .. url .. " (body=" .. #r.body .. " bytes)")
    end
    return { items = items, hasNext = hasNextPage(r.body, #items) }
end

-- Búsqueda estándar de Madara. Páginas > 1 → /page/N/?s=…
local function searchUrl(page, query, extra)
    local path = "/"
    if page > 1 then path = "/page/" .. page .. "/" end
    return baseUrl .. path .. "?s=" .. url_encode(query or "") .. "&post_type=wp-manga" .. (extra or "")
end

-- ── Catálogo ──────────────────────────────────────────────────────────────────
-- Home = "LATEST NOVEL RELEASE": 20 novelas por página, 91 páginas, orden de última
-- actualización. Si la home no da tarjetas (cambio de plantilla) se usa la búsqueda
-- ordenada por Latest, que es la misma lista con 10 por página.

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/"
    if page > 1 then url = baseUrl .. "/page/" .. page .. "/" end

    local res = fetchCards(url)
    if #res.items > 0 or page > 1 then return res end

    log_info("ranovel: la home no dio tarjetas; se usa la búsqueda ordenada por Latest")
    return fetchCards(searchUrl(1, "", "&m_orderby=latest"))
end

function getCatalogSearch(index, query)
    return fetchCards(searchUrl(index + 1, query, ""))
end

-- ── Detalles del libro ────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local h1 = html_select_first(body, ".post-title h1")
    if h1 then
        local t = string_clean(html_text(html_remove(h1.html, ".manga-title-badges")))
        if t ~= "" then return t end
    end

    local og = html_attr(body, "meta[property='og:title']", "content")
    if og and og ~= "" then
        og = regex_replace(og, "\\s+Ranovel\\s*$", "")
        return string_clean(og)
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local cover = coverOf(body, ".summary_image img")
    if cover == "" then
        cover = html_attr(body, "meta[property='og:image']", "content") or ""
        if cover ~= "" then cover = absUrl(cover) end
    end
    return cover ~= "" and cover or nil
end

-- La sinopsis viene mezclada con bloques .code-block (botón de Ko-fi, texto oculto con
-- "Only Ran(o)vel dot com", líneas de asteriscos…): se quitan antes de sacar el texto.
function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local el = html_select_first(body, ".description-summary .summary__content")
    if not el then return nil end

    local cleaned = html_remove(el.html, ".code-block", "script", "style", "ins", "iframe")
    local text = cleanDescription(html_text(cleaned))
    return text ~= "" and text or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local genres = {}
    for _, a in ipairs(html_select(body, ".genres-content a")) do
        local g = string_clean(a.text)
        if g ~= "" then table.insert(genres, g) end
    end
    return genres
end

function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "#averagerate") or html_select_first(body, ".post-total-rating .score")
    if not el then return nil end
    local rating = string_clean(el.text)
    if rating == "" or rating == "0" then return nil end
    return rating
end

-- Estado: fila "Status" de la ficha (OnGoing / Completed / …)
function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, item in ipairs(html_select(body, ".post-content_item")) do
        local heading = html_select_first(item.html, ".summary-heading h5")
        if heading and string_clean(heading.text) == "Status" then
            local content = html_select_first(item.html, ".summary-content")
            if content then
                local s = string_clean(content.text)
                return s ~= "" and s or nil
            end
        end
    end
    return nil
end

-- ── Lista de capítulos ────────────────────────────────────────────────────────
-- La ficha solo trae <div id="manga-chapters-holder" data-id="…"> con un spinner: la lista
-- se pide por AJAX. Se prueban, en orden, los endpoints de Madara y se recuerda cuál
-- funcionó para no repetir los que fallan:
--   1) POST <ficha>/ajax/chapters/?t=1   (el que usa Sonic MTL en este mismo motor)
--   2) POST <ficha>/ajax/chapters/
--   3) POST /wp-admin/admin-ajax.php  action=manga_get_chapters&manga=<id>   (Madara antiguo)
--   4) POST /wp-admin/admin-ajax.php  action=wp-manga-get-chapters&post_id=<id>
-- El id del libro sale de la ficha (#manga-chapters-holder[data-id], 451447 en el ejemplo).

local _chapterMode = nil

local function ajaxConfig(bookUrl)
    return {
        headers = {
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Referer"]          = bookUrl,
        },
        charset = "UTF-8",
    }
end

-- Filas { title, url, date } tal como las entrega el sitio (Madara: la más nueva primero).
-- Los capítulos son li.wp-manga-chapter, con o sin volúmenes; los bloqueados/de pago
-- llevan href="#" y se omiten.
local function parseChapterRows(body)
    local lis = html_select(body, "li.wp-manga-chapter")
    if #lis == 0 then lis = html_select(body, ".wp-manga-chapter") end

    local rows, seen = {}, {}
    for _, li in ipairs(lis) do
        local a = html_select_first(li.html, "a[href]")
        if a and a.href and a.href ~= "" and a.href ~= "#" then
            local url = absUrl(a.href)
            if url ~= "" and not seen[url] then
                seen[url] = true
                local title = string_clean(a.text)
                if title == "" then title = url:match("/([^/]+)/?$") or url end
                local d = html_select_first(li.html, ".chapter-release-date")
                table.insert(rows, { title = title, url = url, date = d and string_clean(d.text) or "" })
            end
        end
    end
    return rows
end

local function findPostId(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local id = html_attr(body, "#manga-chapters-holder", "data-id")
    if not id or id == "" then id = html_attr(body, ".rating-post-id", "value") end
    if not id or id == "" then
        local m = regex_match(body, "\"manga_id\":\"(\\d+)\"")
        if m and m[1] then id = m[1] end
    end
    if id and id ~= "" then return id end
    return nil
end

local function fetchChapterRows(bookUrl)
    local base     = cleanBookUrl(bookUrl)
    local cfg      = ajaxConfig(bookUrl)
    local adminUrl = baseUrl .. "/wp-admin/admin-ajax.php"

    -- Una petición: devuelve las filas si hubo lista, o nil (error HTTP / respuesta sin capítulos)
    local function try(mode, url, body)
        local r = http_post(url, body, cfg)
        if not r.success then
            log_info("ranovel: '" .. mode .. "' HTTP " .. tostring(r.code))
            return nil
        end
        local rows = parseChapterRows(r.body)
        if #rows == 0 then return nil end
        if _chapterMode ~= mode then
            _chapterMode = mode
            log_info("ranovel: lista de capítulos por '" .. mode .. "' (" .. #rows .. " capítulos)")
        end
        return rows
    end

    -- el endpoint que ya funcionó en esta sesión va primero
    local modes = { "ajax_t", "ajax", "admin1", "admin2" }
    if _chapterMode then
        local ordered = { _chapterMode }
        for _, m in ipairs(modes) do
            if m ~= _chapterMode then table.insert(ordered, m) end
        end
        modes = ordered
    end

    local id, idLooked = nil, false
    for _, mode in ipairs(modes) do
        local rows = nil
        if mode == "ajax_t" then
            rows = try(mode, base .. "/ajax/chapters/?t=1", "")
        elseif mode == "ajax" then
            rows = try(mode, base .. "/ajax/chapters/", "")
        else
            -- los de admin-ajax necesitan el id numérico del libro (se busca una sola vez)
            if not idLooked then
                idLooked = true
                id = findPostId(bookUrl)
                if not id then log_error("ranovel: no encontré el id del libro en " .. bookUrl) end
            end
            if id and mode == "admin1" then
                rows = try(mode, adminUrl, "action=manga_get_chapters&manga=" .. id)
            elseif id and mode == "admin2" then
                rows = try(mode, adminUrl, "action=wp-manga-get-chapters&post_id=" .. id)
            end
        end
        if rows then return rows end
    end

    log_error("ranovel: sin capítulos para " .. bookUrl .. " (ningún endpoint AJAX devolvió una lista)")
    return {}
end

local function chapterNumber(url)
    local seg = tostring(url or ""):match("/([^/]+)/?$") or ""
    local n = seg:match("^chapter%-(%d+)") or seg:match("(%d+)")
    return n and tonumber(n) or nil
end

-- El motor quiere orden cronológico (del más viejo al más nuevo). Madara entrega lo
-- contrario; si por alguna razón viniera ya ascendente (número del primero < número del
-- último) se respeta.
local function toChronological(rows)
    if #rows < 2 then return rows end
    local a, b = chapterNumber(rows[1].url), chapterNumber(rows[#rows].url)
    if a and b and a < b then return rows end
    local rev = {}
    for i = #rows, 1, -1 do table.insert(rev, rows[i]) end
    return rev
end

function getChapterList(bookUrl)
    local rows = toChronological(fetchChapterRows(bookUrl))
    local chapters = {}
    for _, row in ipairs(rows) do
        table.insert(chapters, { title = row.title, url = row.url })
    end
    return chapters
end

-- Huella = cantidad de capítulos + URL del más nuevo. Siempre en vivo (nunca fetchPage).
function getChapterListHash(bookUrl)
    local rows = toChronological(fetchChapterRows(bookUrl))
    if #rows == 0 then return nil end
    return tostring(#rows) .. "|" .. rows[#rows].url
end

-- ── Fecha de la última actualización ──────────────────────────────────────────

local MONTHS = {
    January = 1, February = 2, March = 3, April = 4, May = 5, June = 6,
    July = 7, August = 8, September = 9, October = 10, November = 11, December = 12
}

-- A YYYY-MM-DD. Acepta "N minutes/hours/days ago", "March 30, 2026" y "2026-03-30".
local function normalizeUpdateDate(raw)
    if not raw or raw == "" then return nil end

    local n, unit = string.match(raw, "(%d+)%s+(%a+)%s+ago")
    if n and unit then
        n = tonumber(n)
        local secs = 0
        if unit:find("^second") then secs = n
        elseif unit:find("^minute") then secs = n * 60
        elseif unit:find("^hour") then secs = n * 3600
        elseif unit:find("^day") then secs = n * 86400
        elseif unit:find("^week") then secs = n * 604800
        elseif unit:find("^month") then secs = n * 2592000
        elseif unit:find("^year") then secs = n * 31536000
        end
        if secs > 0 then return os.date("%Y-%m-%d", os.time() - secs) end
    end

    local mon, d, y = string.match(raw, "(%a+)%s+(%d+),?%s+(%d%d%d%d)")
    if mon and MONTHS[mon] and d and y then
        return string.format("%04d-%02d-%02d", tonumber(y), MONTHS[mon], tonumber(d))
    end

    local yy, mm, dd = string.match(raw, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if yy then return yy .. "-" .. mm .. "-" .. dd end
    return nil
end

function getBookLastUpdate(bookUrl)
    local rows = toChronological(fetchChapterRows(bookUrl))
    if #rows == 0 then return nil end
    return normalizeUpdateDate(rows[#rows].date)
end

-- ── Texto del capítulo ────────────────────────────────────────────────────────
-- Estructura verificada: .reading-content > .text-left con solo <p> (y <br>), más bloques
-- .code-block al inicio y al final (publicidad + marca de agua) que se eliminan enteros.

function getChapterText(html, url)
    if not html or html == "" then return "" end

    local cleaned = html_remove(html,
        "script", "style", "ins", "iframe",
        ".code-block", ".ads", ".advertisement",
        "#text-chapter-toolbar", ".wp-manga-nav", "#comments"
    )

    local el = html_select_first(cleaned, ".reading-content .text-left")
    if not el then el = html_select_first(cleaned, ".reading-content") end
    if not el then el = html_select_first(cleaned, ".entry-content") end
    if not el then
        log_error("ranovel: sin .reading-content en " .. tostring(url))
        return ""
    end

    return applyStandardContentTransforms(html_text(el.html))
end

-- ── Filtros ───────────────────────────────────────────────────────────────────
-- Los del formulario de búsqueda avanzada del sitio (verificados en su HTML):
-- genre[] (29), status[] (5), op (OR/AND), adult, author, artist, release, y el orden
-- m_orderby de los enlaces de la propia página de resultados.

function getFilterList()
    return {
        {
            type         = "select",
            key          = "m_orderby",
            label        = "Order By",
            defaultValue = "latest",
            options = {
                { value = "latest",    label = "Latest"     },
                { value = "new-manga", label = "New"        },
                { value = "rating",    label = "Rating"     },
                { value = "trending",  label = "Trending"   },
                { value = "views",     label = "Most Views" },
                { value = "alphabet",  label = "A-Z"        },
                { value = "",          label = "Relevance"  },
            }
        },
        {
            type  = "checkbox",
            key   = "genre",
            label = "Genres",
            options = {
                { value = "action",        label = "Action"        },
                { value = "adventure",     label = "Adventure"     },
                { value = "comedy",        label = "Comedy"        },
                { value = "drama",         label = "Drama"         },
                { value = "ecchi",         label = "Ecchi"         },
                { value = "fantasy",       label = "Fantasy"       },
                { value = "gender-bender", label = "Gender Bender" },
                { value = "harem",         label = "Harem"         },
                { value = "historical",    label = "Historical"    },
                { value = "horror",        label = "Horror"        },
                { value = "josei",         label = "Josei"         },
                { value = "martial-arts",  label = "Martial Arts"  },
                { value = "mature",        label = "Mature"        },
                { value = "mystery",       label = "Mystery"       },
                { value = "psychological", label = "Psychological" },
                { value = "romance",       label = "Romance"       },
                { value = "school-life",   label = "School Life"   },
                { value = "sci-fi",        label = "Sci-fi"        },
                { value = "seinen",        label = "Seinen"        },
                { value = "shoujo",        label = "Shoujo"        },
                { value = "shounen",       label = "Shounen"       },
                { value = "slice-of-life", label = "Slice of Life" },
                { value = "sports",        label = "Sports"        },
                { value = "supernatural",  label = "Supernatural"  },
                { value = "tragedy",       label = "Tragedy"       },
                { value = "updating",      label = "Updating"      },
                { value = "wuxia",         label = "Wuxia"         },
                { value = "xuanhuan",      label = "Xuanhuan"      },
                { value = "yuri",          label = "Yuri"          },
            }
        },
        {
            type         = "select",
            key          = "op",
            label        = "Genres Condition",
            defaultValue = "",
            options = {
                { value = "",  label = "OR (having one of selected genres)" },
                { value = "1", label = "AND (having all selected genres)"   },
            }
        },
        {
            type  = "checkbox",
            key   = "status",
            label = "Status",
            options = {
                { value = "on-going", label = "OnGoing"   },
                { value = "end",      label = "Completed" },
                { value = "canceled", label = "Canceled"  },
                { value = "on-hold",  label = "On Hold"   },
                { value = "upcoming", label = "Upcoming"  },
            }
        },
        {
            type         = "select",
            key          = "adult",
            label        = "Adult Content",
            defaultValue = "",
            options = {
                { value = "",  label = "All"                },
                { value = "0", label = "None adult content" },
                { value = "1", label = "Only adult content" },
            }
        },
        { type = "text", key = "author",  label = "Author",           defaultValue = "" },
        { type = "text", key = "artist",  label = "Artist",           defaultValue = "" },
        { type = "text", key = "release", label = "Year of Released", defaultValue = "" },
    }
end

function getCatalogFiltered(index, filters)
    local orderby  = filters["m_orderby"] or "latest"
    local op       = filters["op"] or ""
    local adult    = filters["adult"] or ""
    local author   = filters["author"] or ""
    local artist   = filters["artist"] or ""
    local release  = filters["release"] or ""
    local genres   = filters["genre_included"] or {}
    local statuses = filters["status_included"] or {}

    local extra = "&m_orderby=" .. url_encode(orderby)
               .. "&op=" .. url_encode(op)
               .. "&adult=" .. url_encode(adult)
    if author  ~= "" then extra = extra .. "&author="  .. url_encode(author)  end
    if artist  ~= "" then extra = extra .. "&artist="  .. url_encode(artist)  end
    if release ~= "" then extra = extra .. "&release=" .. url_encode(release) end
    for _, v in ipairs(genres)   do extra = extra .. "&genre[]="  .. url_encode(v) end
    for _, v in ipairs(statuses) do extra = extra .. "&status[]=" .. url_encode(v) end

    return fetchCards(searchUrl(index + 1, "", extra))
end
