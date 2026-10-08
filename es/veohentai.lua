-- Veohentai — видео-плагин NoveLA (content_type = "video")
-- Сайт: https://veohentai.com (Next.js, хенгай с испанскими субтитрами).
-- Каталог сериалов: /directorio-hentai/?view=grid&pagina=N (12 карточек, 88 страниц).
-- Поиск: /buscar/?q=… — отдаёт карточки ЭПИЗОДОВ, приводим их к /serie/<slug>/.
-- Страница сериала: h1 = название, обложка — <img alt="<название>">, жанры — /genero/*.
--   Синопсиса на ней нет: он лежит в JSON-LD VideoObject первой страницы эпизода.
-- Поток (HentaiPlayer / NHPlayer):
--   Формат A (vid=, r2.1hanime.com) — 5 шагов:
--   1. /ver/<slug>-episodio-N/ → <iframe src="https://<host>/v/<code>/">
--   2. /v/<code>/            → <li data-id="/player.php?vid=..&s=..&i=..&type=">
--   3. /player.php?<…>       → <script src="player-core-v2.php?t=…">
--   4. /player-core-v2.php   → var _a='hex.hex' (sc), var _b='16 hex' (rid)
--   5. /get-video-url-v2.php?vid=..&p1..p4=8hex&t=<unix>&sc=..&rid=..&fp=<b64>&df=&pow=
--      (заголовок X-Requested-With обязателен, без него 403) → {"url":"…mp4?verify=…"}
--   Формат B (u=, cdn.hentaiplayer.com) — прямой base64-URL, челлендж не нужен:
--   /v/<code>/ → <li data-id="/player.php?u=<b64 mp4>&i=..&type=">; декодируем u=.
--   Параметр s — base64 со ссылкой на испанский .srt (отдаётся без Referer).
--   ВАЖНО (проверено живьём 2026-10-08): mp4 формата A живёт на
--   r2.1hanime.com под Cloudflare-защитой по TLS-фингерпринту

id           = "veohentai"
name         = "Veohentai"
version      = "1.0.1"
baseUrl      = "https://veohentai.com"
language     = "es"
content_type = "video"
icon         = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr/icons/veohentai.png"

local SERIE_SEL = 'a[href*="/serie/"]'
local EP_SEL    = 'a[href*="/ver/"]'

-- Бюджеты запросов (мс): одна попытка вместо лестницы ретраев клиента
-- (3+3+3+3+15 с) — иначе один мёртвый хост в цепочке плеера тянет полминуты.
local PAGE_TIMEOUT   = 15000
local PLAYER_TIMEOUT = 12000

local _pageCache = {}

local function absUrl(href)
    if type(href) ~= "string" or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Страница сериала: тайтл, обложка, жанры, описание и список эпизодов — всё
-- в одном HTML, поэтому кэшируем его на сеанс.
local function fetchPage(url)
    local cached = _pageCache[url]
    if cached ~= nil then return cached end
    local r = http_get(url, { timeout = PAGE_TIMEOUT })
    if not r.success then
        log_error("Veohentai: page request failed (HTTP " .. tostring(r.code) .. "): " .. url)
        return nil
    end
    _pageCache[url] = r.body
    return r.body
end

-- Постер карточки — первый <img> с непустым alt: у баннера каталога alt="".
local function cardCover(scope)
    for _, img in ipairs(html_select(scope, "img")) do
        if string_trim(img:attr("alt") or "") ~= "" then
            local src = absUrl(img:attr("src") or "")
            if src ~= "" then return src end
        end
    end
    return ""
end

-- Поиск отдаёт /ver/<slug>-episodio-N/, а каталог — /serie/<slug>/; приводим
-- карточку к каноничному URL сериала, чтобы одна серия не двоилась.
local function serieUrlFromEpisode(href)
    local tail = href:match("/ver/(.+)$")
    if type(tail) ~= "string" or tail == "" then return nil end
    -- Отрезаем последний «-episodio-<N>»: в слагах сериалов дефис встречается
    -- часто, поэтому нужен именно последний хвост, а не первый.
    local parts = string_split(tail, "-episodio-")
    if #parts < 2 then return nil end
    if not parts[#parts]:match("^%d+/*$") then return nil end
    local slug = table.concat(parts, "-episodio-", 1, #parts - 1)
    if slug == "" then return nil end
    return baseUrl .. "/serie/" .. slug .. "/"
end

-- "Kokuhaku… Episodio 4" → "Kokuhaku…"; без номера в хвосте не трогаем.
local function stripEpisodeSuffix(title)
    local pos, cut = 1, nil
    while true do
        local i = title:find(" Episodio ", pos, true)
        if not i then break end
        cut, pos = i, i + 1
    end
    if not cut then return title end
    local rest = string_trim(title:sub(cut + 10))
    if not rest:match("^%d+$") then return title end
    return string_trim(title:sub(1, cut - 1))
end

-- Карточки эпизодов (/ver/…) → каноничные карточки сериалов: поиск, жанр и
-- сортировка /explorar/ все отдают эпизодные ссылки с «Episodio N» в заголовке.
local function episodeCards(body)
    local items, seen = {}, {}
    for _, a in ipairs(html_select(body, EP_SEL)) do
        local bookUrl = serieUrlFromEpisode(a:attr("href") or "")
        if bookUrl and not seen[bookUrl] then
            seen[bookUrl] = true
            local h3 = html_select_first(a.html, "h3")
            local title = ""
            if h3 then title = string_trim(h3.text) end
            if title == "" then
                local slug = bookUrl:match("/serie/([^/]+)/$")
                if slug then title = slug end
            end
            title = stripEpisodeSuffix(title)
            if title ~= "" then
                local cover = cardCover(a.html)
                items[#items + 1] = {
                    title = string_clean(title),
                    url   = bookUrl,
                    cover = cover ~= "" and cover or nil,
                }
            end
        end
    end
    return items
end

function getCatalogList(index)
    local url = baseUrl .. "/directorio-hentai/?view=grid&pagina=" .. tostring(index + 1)
    local body = fetchPage(url)
    if not body then return { items = {}, hasNext = false } end
    local items, seen = {}, {}
    for _, a in ipairs(html_select(body, SERIE_SEL)) do
        local bookUrl = absUrl(a:attr("href") or "")
        if bookUrl ~= "" and not seen[bookUrl] then
            seen[bookUrl] = true
            local h3 = html_select_first(a.html, "h3")
            local title = ""
            if h3 then title = string_trim(h3.text) end
            if title ~= "" then
                local cover = cardCover(a.html)
                items[#items + 1] = {
                    title = string_clean(title),
                    url   = bookUrl,
                    cover = cover ~= "" and cover or nil,
                }
            end
        end
    end    -- pagina=89 уже пуст — каталог сам отдаёт признак конца.
    return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
    -- Поиск не пагинируется: страница одна, всего ~30 результатов.
    if index > 0 or type(query) ~= "string" or query == "" then
        return { items = {}, hasNext = false }
    end
    local body = fetchPage(baseUrl .. "/buscar/?q=" .. url_encode(query))
    if not body then return { items = {}, hasNext = false } end
    return { items = episodeCards(body), hasNext = false }
end

-- Замерено: фильтры живут на одном /explorar/ — принимает несколько жанров
-- сразу (?genero=tetonas,virgenes,ecchi), сортировку (orden=vistas|…) и
-- HTTP-пагинацию (pagina=N сохраняет фильтры; конец — страница без карточек).
-- Карточки там эпизодные (/ver/…), разбираются episodeCards().
local GENRE_OPTIONS = {
    { value = "ahegao",        label = "Ahegao" },
    { value = "anal",          label = "Anal" },
    { value = "bondage",       label = "Bondage" },
    { value = "casadas",       label = "Casadas" },
    { value = "censurado",     label = "Censurado" },
    { value = "chikan",        label = "Chikan" },
    { value = "corridas",      label = "Corridas" },
    { value = "ecchi",         label = "Ecchi" },
    { value = "enfermeras",    label = "Enfermeras" },
    { value = "fantasia",      label = "Fantasía" },
    { value = "futanari",      label = "Futanari" },
    { value = "gore",          label = "Gore" },
    { value = "hardcore",      label = "Hardcore" },
    { value = "harem",         label = "Harem" },
    { value = "hentai-escolares",    label = "Hentai escolares" },
    { value = "hentai-sin-censura",  label = "Hentai sin censura" },
    { value = "incesto",       label = "Incesto" },
    { value = "josei",         label = "Josei" },
    { value = "juegos-sexuales",     label = "Juegos sexuales" },
    { value = "lesbiana",      label = "Lesbiana" },
    { value = "lolicon",       label = "Lolicon" },
    { value = "maids",         label = "Maids" },
    { value = "manga",         label = "Manga" },
    { value = "masturbacion",  label = "Masturbación" },
    { value = "milfs",         label = "MILFs" },
    { value = "netorare",      label = "Netorare" },
    { value = "ninfomania",    label = "Ninfomanía" },
    { value = "ninjas",        label = "Ninjas" },
    { value = "oral",          label = "Oral" },
    { value = "orgias",        label = "Orgías" },
    { value = "romance",       label = "Romance" },
    { value = "shota",         label = "Shota" },
    { value = "softcore",      label = "Softcore" },
    { value = "succubus",      label = "Succubus" },
    { value = "teacher",       label = "Profesores" },
    { value = "tentaculos",    label = "Tentáculos" },
    { value = "tetonas",       label = "Tetonas" },
    { value = "vanilla",       label = "Vanilla" },
    { value = "violacion",     label = "Violación" },
    { value = "virgenes",      label = "Vírgenes" },
    { value = "yaoi",          label = "Yaoi" },
    { value = "yuri",          label = "Yuri" },
}

local ORDEN_OPTIONS = {
    { value = "",               label = "Por defecto" },
    { value = "vistas",         label = "Más vistos" },
    { value = "vistas-semana",  label = "Más vistos esta semana" },
    { value = "likes",          label = "Más gustados" },
    { value = "antiguos",       label = "Más antiguos" },
    { value = "za",             label = "A-Z" },
}

function getFilterList()
    return {
        {
            type         = "select",
            key          = "orden",
            label        = "Ordenar por",
            defaultValue = "",
            options      = ORDEN_OPTIONS,
        },
        {
            type         = "checkbox",
            key          = "genre",
            label        = "Género",
            options      = GENRE_OPTIONS,
        },
    }
end

function getCatalogFiltered(index, filters)
    if type(filters) ~= "table" then filters = {} end
    index = tonumber(index) or 0
    local page = index + 1

    local params = { "pagina=" .. page }
    local genres = filters["genre_included"]
    if type(genres) == "table" and #genres > 0 then
        local joined = {}
        for _, v in ipairs(genres) do
            if type(v) == "string" and v ~= "" then
                joined[#joined + 1] = v
            end
        end
        if #joined > 0 then
            params[#params + 1] = "genero=" .. url_encode(table.concat(joined, ","))
        end
    end
    local orden = filters["orden"]
    if type(orden) == "string" and orden ~= "" then
        params[#params + 1] = "orden=" .. url_encode(orden)
    end

    local url = baseUrl .. "/explorar/?" .. table.concat(params, "&")
    local body = fetchPage(url)
    if not body then return { items = {}, hasNext = false } end
    local items = episodeCards(body)
    return { items = items, hasNext = #items > 0 }
end

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local h1 = html_select_first(body, "h1")
    if not h1 then return nil end
    local title = string_clean(h1.text)
    return title ~= "" and title or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local h1 = html_select_first(body, "h1")
    if not h1 then return nil end
    local title = string_trim(h1.text)
    if title == "" then return nil end
    -- В шапке два логотипа с alt="VeoHentai — …", у баннера alt="": постер
    -- единственный img, у которого alt совпадает с заголовком сериала.
    for _, img in ipairs(html_select(body, "img")) do
        if string_trim(img:attr("alt") or "") == title then
            local src = absUrl(img:attr("src") or "")
            if src ~= "" then return src end
        end
    end
    local og = html_attr(body, 'meta[property="og:image"]', "content")
    if type(og) == "string" and og ~= "" then return absUrl(og) end
    return nil
end

-- Синопсис есть только в JSON-LD VideoObject на странице эпизода.
local function jsonLdDescription(body)
    for _, sc in ipairs(html_select(body, 'script[type="application/ld+json"]')) do
        local data = json_parse(sc.html or "")
        if type(data) == "table"
            and data["@type"] == "VideoObject"
            and type(data.description) == "string"
            and data.description ~= "" then
            return string_trim(data.description)
        end
    end
    return nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local a = html_select_first(body, EP_SEL)
    if a then
        local epUrl = absUrl(a:attr("href") or "")
        if epUrl ~= "" then
            local r = http_get(epUrl, { timeout = PAGE_TIMEOUT })
            if r.success then
                local text = jsonLdDescription(r.body)
                if text then return text end
            else
                log_error("Veohentai: episode request failed (HTTP " .. tostring(r.code) .. "): " .. epUrl)
            end
        end
    end
    -- Запасной вариант — meta description самого сериала.
    local meta = html_attr(body, 'meta[name="description"]', "content")
    if type(meta) == "string" then
        meta = string_trim(meta)
        if meta ~= "" then return meta end
    end
    return nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres, seen = {}, {}
    for _, a in ipairs(html_select(body, 'a[href*="/genero/"]')) do
        local slug = (a:attr("href") or ""):match("/genero/([^/]+)")
        if slug and not seen[slug] then
            seen[slug] = true
            -- В бейдже рядом с жанром стоит счётчик: "Corridas 4" → "Corridas".
            local name = string_trim((string_trim(a.text):gsub("%d+$", "")))
            if name ~= "" then genres[#genres + 1] = name end
        end
    end
    return genres
end

function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local raw = {}
    for _, a in ipairs(html_select(body, EP_SEL)) do
        local url = absUrl(a:attr("href") or "")
        if url ~= "" then
            local num = tonumber(url:match("%-episodio%-(%d+)"))
            local h3 = html_select_first(a.html, "h3")
            local title = ""
            if h3 then title = string_trim(h3.text) end
            -- Номер эпизода берём из URL: подпись "Episodio N" совпадает с
            -- бейджем "Ep. N" сайта и не дублирует название сериала.
            if num then title = "Episodio " .. tostring(num) end
            if title == "" then title = "Episodio" end
            raw[#raw + 1] = { url = url, num = num, title = string_clean(title) }
        end
    end
    -- Старые → новые; карточки без номера в URL уходят в конец.
    table.sort(raw, function(x, y)
        local a, b = x.num or math.huge, y.num or math.huge
        if a ~= b then return a < b end
        return x.url < y.url
    end)
    local chapters, seen = {}, {}
    for _, ep in ipairs(raw) do
        if not seen[ep.url] then
            seen[ep.url] = true
            chapters[#chapters + 1] = { title = ep.title, url = ep.url }
        end
    end
    return chapters
end

function getChapterListHash(bookUrl)
    -- Прямой запрос без кэша: через fetchPage хэш не заметил бы новый эпизод.
    local r = http_get(bookUrl, { timeout = PAGE_TIMEOUT })
    if not r.success then return nil end
    for _, el in ipairs(html_select(r.body, ".pill-count")) do
        local txt = string_clean(el.text)
        if txt:find("episodio", 1, true) then return txt end
    end
    return nil
end

------------------------------------------------------------------------------
-- Плеер HentaiPlayer / NHPlayer
------------------------------------------------------------------------------

local XHR_HEADERS = { ["X-Requested-With"] = "XMLHttpRequest" }

-- player.php под нагрузкой отдаёт 500, поэтому одна повторная попытка.
local function httpGet(url, tries)
    local r
    for _ = 1, (tries or 1) do
        r = http_get(url, { timeout = PLAYER_TIMEOUT })
        if r and r.success then return r end
    end
    return r
end

-- Значение параметра из data-id вида "/player.php?vid=…&s=…&i=…&type=".
local function queryParam(query, key)
    return query:match("[?&]" .. key .. "=([^&]*)")
end

-- Имена переменных в player-core-v2.js обфусцированы и меняются, но формат
-- значений стабилен: sc = "hex.hex", rid = 16 hex.
-- regex_match отдаёт таблицу ПОЛНЫХ совпадений (без групп), поэтому значение
-- в кавычках достаётся Lua-паттерном из m[1]; полное совпадение содержит
-- пробелы и кавычки и ломает SSRF-проверку URL (java.net.URI).
local function playerChallenge(js)
    local m = regex_match(js, "var\\s+[\\w$]+='([0-9a-f]+\\.[0-9a-f]+)'")
    local sc = type(m) == "table" and type(m[1]) == "string"
        and m[1]:match("'([0-9a-f]+%.[0-9a-f]+)'") or nil
    m = regex_match(js, "var\\s+[\\w$]+='([0-9a-f]{16})'")
    local rid = type(m) == "table" and type(m[1]) == "string"
        and m[1]:match("'([0-9a-f]+)'") or nil
    if type(sc) ~= "string" or type(rid) ~= "string" then return nil, nil end
    return sc, rid
end

-- Части вызова из player.php: скрытых блока два — настоящий и приманка
-- (фиксированные id tpl/tss/ch3, data-v/data-ts/data-challenge). Настоящий
-- определяется по ts == префикс _pV.pid, id и имена data-* рандомизированы.
-- Возвращает p1..p4 и ts (t в запросе обязан быть ts, иначе "Invalid proof").
local function playerParts(ph)
    local ts = ph:match('_pV=%{vid:".-",ct:".-",pid:"(%d+)_')
    if not ts then return nil end
    local anchor = '="' .. ts .. '"'
    local i = ph:find(anchor, 1, true)
    if not i then return nil end
    -- Начало контейнера — последний <div style="display:none до ts.
    local start, pos = nil, 1
    while true do
        local p = ph:find('<div style="display:none', pos, true)
        if not p or p > i then break end
        start, pos = p, p + 1
    end
    if not start then return nil end
    local block = ph:sub(start, i + 64)
    local p1 = block:match('<span[^>]*data%-[0-9a-f]+="([0-9a-f]+)"')
    local p2 = block:match('<input type="hidden"[^>]*value="([0-9a-f]+)"')
    local p3 = block:match('<div[^>]*data%-[0-9a-f]+="([0-9a-f]+)"')
    local p4 = block:match('<template[^>]*><p>([0-9a-f]+)</p></template>')
    if not (p1 and p2 and p3 and p4) then return nil end
    return p1, p2, p3, p4, ts
end

-- data-id → ссылка на mp4. Возвращает url, субтитры и флаг http11 (формат A
-- живёт на r2.1hanime.com под CF по TLS-фингерпринту — плееру нужен h1).
local function resolveServer(host, dataId, label)
    -- Параметр s (оба формата) — base64 со ссылкой на испанский .srt.
    local subtitle
    local raw = queryParam(dataId, "s")
    if type(raw) == "string" and raw ~= "" then
        local srt = base64_decode(raw)
        if type(srt) == "string" and srt ~= "" then
            subtitle = { url = srt, label = "Español", lang = "es" }
        end
    end

    -- Формат B: параметр u= несёт прямой base64-URL на cdn.hentaiplayer.com,
    -- челлендж не нужен (проверено живьём 2026-10-08: 206/200 без заголовков).
    raw = queryParam(dataId, "u")
    if type(raw) == "string" and raw ~= "" then
        local direct = base64_decode(raw)
        if type(direct) ~= "string" or direct == "" then
            log_error("Veohentai: bad u= param in data-id")
            return nil, nil
        end
        return direct, subtitle, false
    end

    local r = httpGet(host .. dataId, 2)
    if not r then
        log_error("Veohentai: player.php unreachable: " .. tostring(dataId))
        return nil, nil
    end
    local core = html_attr(r.body, 'script[src*="player-core-v2"]', "src")
    if type(core) ~= "string" or core == "" then
        log_error("Veohentai: no player-core-v2.php on " .. tostring(host))
        return nil, nil
    end
    local rc = httpGet(url_resolve(host .. "/", core), 2)
    if not rc then
        log_error("Veohentai: player-core-v2.php unreachable: " .. tostring(host))
        return nil, nil
    end
    local sc, rid = playerChallenge(rc.body)
    if not sc then
        log_error("Veohentai: no challenge token in player-core-v2.php: " .. tostring(host))
        return nil, nil
    end

    -- Части челленджа из player.php: p1..p4 и t (== префикс _pV.pid) обязаны
    -- совпасть с блоком-приманкой, иначе сервер отвечает "Invalid challenge".
    local p1, p2, p3, p4, ts = playerParts(r.body)
    if not p1 then
        log_error("Veohentai: no challenge parts in player.php")
        return nil, nil
    end

    -- Отпечаток: сервер проверяет только t >= 2000, детали устройства не важны.
    local fp = base64_encode('{"t":5000,"b":{"sw":1440,"sh":900}}')
    local url = host .. "/get-video-url-v2.php"
        .. "?vid=" .. url_encode(queryParam(dataId, "vid") or "")
        .. "&p1=" .. p1 .. "&p2=" .. p2 .. "&p3=" .. p3 .. "&p4=" .. p4
        .. "&t=" .. ts
        .. "&sc=" .. sc .. "&rid=" .. rid
        .. "&fp=" .. url_encode(fp)
        .. "&df=&pow="
    local rr = http_get(url, { timeout = PLAYER_TIMEOUT, headers = XHR_HEADERS })
    if not rr.success then
        log_error("Veohentai: get-video-url-v2.php failed (HTTP " .. tostring(rr.code) .. ")")
        return nil, nil
    end
    local data = json_parse(rr.body)
    if type(data) ~= "table" or type(data.url) ~= "string" or data.url == "" then
        log_error("Veohentai: no stream url in get-video-url-v2.php response")
        return nil, nil
    end

    -- Параметр s — base64 со ссылкой на .srt с испанскими субтитрами.
    if label == nil or label == "" then label = host end
    return data.url, subtitle, true
end

function getVideoList(episodeUrl)
    local r = http_get(episodeUrl, { timeout = PAGE_TIMEOUT })
    if not r.success then
        log_error("Veohentai: episode page failed (HTTP " .. tostring(r.code) .. "): " .. tostring(episodeUrl))
        return {}
    end

    local sources, seen, seenSub = {}, {}, {}
    for _, frame in ipairs(html_select(r.body, "iframe[src]")) do
        local embed = absUrl(frame:attr("src") or "")
        local host = embed:match("^(https?://[^/?#]+)")
        if host then
            local er = httpGet(embed, 2)
            if not er then
                log_error("Veohentai: embed page unreachable: " .. embed)
            else
                for _, li in ipairs(html_select(er.body, "li[data-id]")) do
                    local dataId = li:attr("data-id") or ""
                    if dataId:find("/player.php", 1, true) == 1 then
                        local label = string_trim(li.text)
                        local url, subtitle, http11 = resolveServer(host, dataId, label)
                        if url and not seen[url] then
                            seen[url] = true
                            local source = {
                                url = url,
                                quality = label ~= "" and label or host,
                                headers = {
                                    ["Referer"] = host .. "/",
                                },
                            }
                            -- Формат A (r2.1hanime.com): CF режет h2-предложение по
                            -- TLS-фингерпринту → плеер ходит туда только h1.
                            if http11 then source.http11 = true end
                            if subtitle and not seenSub[subtitle.url] then
                                seenSub[subtitle.url] = true
                                source.subtitles = { subtitle }
                            end
                            sources[#sources + 1] = source
                        end
                    end
                end
            end
        end
    end
    if #sources == 0 then
        log_error("Veohentai: no sources for " .. tostring(episodeUrl))
    end
    -- Формат A: mp4 живёт на r2.1hanime.com под CF-защитой по TLS-фингерпринту
    -- (см. шапку). Приложение (OkHttp) получает 403, браузер — 206/200. Это
    -- ограничение сайта, не плагина: заголовки UA/Referer/куки не влияют.
    return sources
end
