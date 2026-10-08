-- AniLiberty — видео-плагин NoveLA (content_type = "video")
-- API: https://aniliberty.top/api/v1 (JSON), сайт: https://aniliberty.top
-- Референс: miru-project/repo/repo/aniliberty.js

content_type = "video"
id          = "aniliberty"
name        = "AniLiberty"
version     = "1.0.0"
baseUrl     = "https://aniliberty.top"
language    = "ru"
icon        = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr/icons/aniliberty.png"

local API = baseUrl .. "/api/v1"
-- Максимум, который принимает каталог (100 → HTTP 422)
local CATALOG_LIMIT = 50

-- Кэш detail-ответов (паттерн fetchPage, живёт в рамках сеанса плагина)
local _detailCache = {}

local function fetchDetail(bookUrl)
    local alias = bookUrl:match("/release/([^/]+)/")
    if not alias then return nil end
    local cached = _detailCache[alias]
    if cached then return cached end
    local r = http_get(API .. "/anime/releases/" .. alias)
    if not r.success then return nil end
    local data = json_parse(r.body)
    if type(data) ~= "table" then return nil end
    _detailCache[alias] = data
    return data
end

-- Название, усечённое сайтом (многоточие в конце ответа API).
local function isCutTitle(s)
    s = string_trim(s)
    return string_ends_with(s, "…") or string_ends_with(s, "...")
end

-- Полное название из объекта name. Часть записей в базе сайта хранится уже
-- усечённой («…» в конце), тогда полное название лежит в соседнем поле
-- name.english — проверено на ответах catalog/search/detail и на HTML
-- страницы релиза: fantasy-bishoujo-juniku-ojisan-to →
--   main:    "Фантастический мир с обращённым в красавицу мужчиной и…"
--   english: "Fantasy Bishoujo Juniku Ojisan to"
-- nil возвращает, только если названия нет вовсе.
local function pickTitle(name)
    if type(name) ~= "table" then return nil end
    local main, eng = name.main, name.english
    if type(main) == "string" and main ~= "" and not isCutTitle(main) then
        return main
    end
    if type(eng) == "string" and eng ~= "" and not isCutTitle(eng) then
        return eng
    end
    -- оба поля усечены или english отсутствует — отдаём как есть
    if type(main) == "string" and main ~= "" then return main end
    if type(eng) == "string" and eng ~= "" then return eng end
    return nil
end

local function itemToBook(item)
    if type(item) ~= "table" or not item.alias then return nil end
    local title = pickTitle(item.name)
    if not title then return nil end
    local cover = ""
    if item.poster and item.poster.src then cover = baseUrl .. item.poster.src end
    local book = {
        title = string_clean(title),
        url   = baseUrl .. "/anime/releases/release/" .. item.alias .. "/episodes",
        cover = cover,
    }
    local avg = item.rating and item.rating.average
    if type(avg) == "number" then
        book.rating = "Rating: " .. tostring(avg) .. "/10"
    end
    return book
end

local function itemsToResult(arr)
    local items = {}
    if type(arr) == "table" then
        for _, item in ipairs(arr) do
            local book = itemToBook(item)
            if book then table.insert(items, book) end
        end
    end
    return { items = items, hasNext = false }
end

-- Каталог: { data = { ... }, meta.pagination = { total, current_page, total_pages, ... } }
local function fetchCatalog(url)
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local body = json_parse(r.body)
    if type(body) ~= "table" or type(body.data) ~= "table" then
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, item in ipairs(body.data) do
        local book = itemToBook(item)
        if book then table.insert(items, book) end
    end
    local pag = body.meta and body.meta.pagination
    local hasNext = false
    if type(pag) == "table" then
        hasNext = (tonumber(pag.current_page) or 0) < (tonumber(pag.total_pages) or 0)
    end
    return { items = items, hasNext = hasNext }
end

local function catalogUrl(page, query)
    local url = API .. "/anime/catalog/releases?page=" .. page .. "&limit=" .. CATALOG_LIMIT
    if query and query ~= "" then url = url .. "&" .. query end
    return url
end

function getCatalogList(index)
    return fetchCatalog(catalogUrl(index + 1))
end

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local r = http_get(API .. "/app/search/releases?query=" .. url_encode(query))
    if not r.success then return { items = {}, hasNext = false } end
    return itemsToResult(json_parse(r.body))
end

function getBookTitle(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local t = pickTitle(d.name)
    return t and string_clean(t) or nil
end

function getBookCoverImageUrl(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d or type(d.poster) ~= "table" then return nil end
    local src = d.poster.src
    if not src or src == "" then return nil end
    if src:find("^https?://") then return src end
    return baseUrl .. src
end

function getBookDescription(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d or not d.description or d.description == "" then return nil end
    return string_trim(d.description)
end

function getBookStatus(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d or type(d.is_ongoing) ~= "boolean" then return nil end
    return d.is_ongoing and "Онгоинг" or "Завершён"
end

function getBookRating(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d or type(d.rating) ~= "table" then return nil end
    local avg = d.rating.average
    if type(avg) ~= "number" then return nil end
    return "Rating: " .. tostring(avg) .. "/10"
end

function getBookGenres(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d or type(d.genres) ~= "table" then return {} end
    local genres = {}
    for _, g in ipairs(d.genres) do
        if g.name and g.name ~= "" then table.insert(genres, g.name) end
    end
    return genres
end

-- Эпизоды = главы, сезон у релиза один — volume не используем.
function getChapterList(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d or type(d.episodes) ~= "table" then return {} end
    local episodes = {}
    for _, ep in ipairs(d.episodes) do table.insert(episodes, ep) end
    table.sort(episodes, function(a, b)
        return (tonumber(a.ordinal) or 0) < (tonumber(b.ordinal) or 0)
    end)
    local chapters = {}
    for _, ep in ipairs(episodes) do
        local ordinal = tonumber(ep.ordinal)
        if ordinal then
            -- Номер серии — обязательный префикс: без него UI показывает
            -- только название, и серии не различаются (пункт "нет номера серии").
            local base = ep.name or ep.name_english
            local title = base and (tostring(ordinal) .. ". " .. base)
                or ("Серия " .. tostring(ordinal))
            table.insert(chapters, {
                title = string_clean(title),
                url   = bookUrl .. "/" .. tostring(ordinal),
            })
        end
    end
    return chapters
end

-- Хэш списка серий для быстрого скипа автообновления: "количество:номер последней".
-- Тот же endpoint, что у getChapterList (detail API), но запрос всегда свежий,
-- без кэша fetchDetail — иначе хэш замёрзнет на время сеанса и движок перестанет
-- замечать новые серии. Ошибка сети или пустой список → nil (полный парс глав).
function getChapterListHash(bookUrl)
    local alias = bookUrl:match("/release/([^/]+)/")
    if not alias then return nil end
    local r = http_get(API .. "/anime/releases/" .. alias)
    if not r.success then return nil end
    local data = json_parse(r.body)
    if type(data) ~= "table" or type(data.episodes) ~= "table" then return nil end
    local count, last = 0, 0
    for _, ep in ipairs(data.episodes) do
        local ordinal = tonumber(ep.ordinal)
        if ordinal then
            count = count + 1
            if ordinal > last then last = ordinal end
        end
    end
    if count == 0 then return nil end
    return count .. ":" .. last
end

-- Потоки эпизода: hls_1080 → hls_720 → hls_480, null-качества пропускаются.
function getVideoList(episodeUrl)
    local alias = episodeUrl:match("/release/([^/]+)/")
    local ordinal = tonumber(episodeUrl:match("/episodes/(%d+)"))
    if not alias or not ordinal then
        error("AniLiberty: не удалось разобрать URL эпизода")
    end
    local r = http_get(API .. "/anime/releases/" .. alias)
    if not r.success then
        error("AniLiberty: API недоступен (HTTP " .. tostring(r.code) .. ")")
    end
    local data = json_parse(r.body)
    if type(data) ~= "table" or type(data.episodes) ~= "table" then
        error("AniLiberty: некорректный ответ API")
    end
    local episode = nil
    for _, ep in ipairs(data.episodes) do
        if tonumber(ep.ordinal) == ordinal then
            episode = ep
            break
        end
    end
    if not episode then return nil end
    local variants = {
        { url = episode.hls_1080, quality = "1080p" },
        { url = episode.hls_720,  quality = "720p" },
        { url = episode.hls_480,  quality = "480p" },
    }
    local sources = {}
    for _, v in ipairs(variants) do
        if type(v.url) == "string" and v.url ~= "" then
            table.insert(sources, { url = v.url, quality = v.quality })
        end
    end
    if #sources == 0 then return nil end
    return sources
end

------------------------------------------------------------------------------
-- Фильтры каталога
-- Значения опций — из GET /api/v1/anime/catalog/references/*
------------------------------------------------------------------------------

-- Параметры query: скобки закодированы, значения кодируются через url_encode
local FILTER_PARAM = {
    sorting           = "f%5Bsorting%5D",
    types             = "f%5Btypes%5D",
    genres            = "f%5Bgenres%5D",
    seasons           = "f%5Bseasons%5D",
    age_ratings       = "f%5Bage_ratings%5D",
    publish_statuses  = "f%5Bpublish_statuses%5D",
    production_statuses = "f%5Bproduction_statuses%5D",
}
local CHECKBOX_KEYS = {
    "types", "genres", "seasons", "age_ratings",
    "publish_statuses", "production_statuses",
}

local SORTING_OPTIONS = {
    { value = "FRESH_AT_DESC", label = "Обновлены недавно" },
    { value = "FRESH_AT_ASC",  label = "Обновлены давно" },
    { value = "RATING_DESC",   label = "Самый высокий рейтинг" },
    { value = "RATING_ASC",    label = "Самый низкий рейтинг" },
    { value = "YEAR_DESC",     label = "Самые новые" },
    { value = "YEAR_ASC",      label = "Самые старые" },
}

local TYPE_OPTIONS = {
    { value = "TV",      label = "ТВ" },
    { value = "ONA",     label = "ONA" },
    { value = "WEB",     label = "WEB" },
    { value = "OVA",     label = "OVA" },
    { value = "OAD",     label = "OAD" },
    { value = "MOVIE",   label = "Фильм" },
    { value = "DORAMA",  label = "Дорама" },
    { value = "SPECIAL", label = "Спешл" },
}

-- value — числовой id жанра, а не название
local GENRE_OPTIONS = {
    { value = "1",  label = "Комедия" },
    { value = "2",  label = "Меха" },
    { value = "3",  label = "Психологическое" },
    { value = "4",  label = "Сёнен" },
    { value = "5",  label = "Сейнен" },
    { value = "6",  label = "Триллер" },
    { value = "7",  label = "Школа" },
    { value = "8",  label = "Драма" },
    { value = "9",  label = "Мистика" },
    { value = "10", label = "Повседневность" },
    { value = "11", label = "Романтика" },
    { value = "12", label = "Спорт" },
    { value = "13", label = "Ужасы" },
    { value = "14", label = "Экшен" },
    { value = "15", label = "Боевые искусства" },
    { value = "16", label = "Демоны" },
    { value = "17", label = "Игры" },
    { value = "18", label = "Магия" },
    { value = "19", label = "Музыка" },
    { value = "20", label = "Сёдзе" },
    { value = "21", label = "Супер сила" },
    { value = "22", label = "Фантастика" },
    { value = "23", label = "Этти" },
    { value = "24", label = "Вампиры" },
    { value = "25", label = "Детектив" },
    { value = "26", label = "Исторический" },
    { value = "27", label = "Приключения" },
    { value = "28", label = "Сверхъестественное" },
    { value = "29", label = "Фэнтези" },
    { value = "30", label = "Киберпанк" },
    { value = "31", label = "Сёдзе-ай" },
    { value = "32", label = "Гарем" },
    { value = "33", label = "Дзёсей" },
    { value = "34", label = "Исекай" },
    { value = "36", label = "Пародия" },
}

local SEASON_OPTIONS = {
    { value = "winter", label = "Зима" },
    { value = "spring", label = "Весна" },
    { value = "summer", label = "Лето" },
    { value = "autumn", label = "Осень" },
}

local AGE_RATING_OPTIONS = {
    { value = "R0_PLUS",  label = "0+" },
    { value = "R6_PLUS",  label = "6+" },
    { value = "R12_PLUS", label = "12+" },
    { value = "R16_PLUS", label = "16+" },
    { value = "R18_PLUS", label = "18+" },
}

local PUBLISH_STATUS_OPTIONS = {
    { value = "IS_ONGOING",      label = "Онгоинг" },
    { value = "IS_NOT_ONGOING",  label = "Неонгоинг" },
}

local PRODUCTION_STATUS_OPTIONS = {
    { value = "IS_IN_PRODUCTION",     label = "Сейчас в озвучке" },
    { value = "IS_NOT_IN_PRODUCTION", label = "Озвучка завершена" },
}

function getFilterList()
    return {
        {
            type         = "select",
            key          = "sorting",
            label        = "Сортировка",
            defaultValue = "FRESH_AT_DESC",
            options      = SORTING_OPTIONS,
        },
        { type = "checkbox", key = "types",             label = "Тип",             options = TYPE_OPTIONS },
        { type = "checkbox", key = "genres",            label = "Жанры",           options = GENRE_OPTIONS },
        { type = "checkbox", key = "seasons",           label = "Сезон",           options = SEASON_OPTIONS },
        { type = "checkbox", key = "age_ratings",       label = "Возраст",         options = AGE_RATING_OPTIONS },
        { type = "checkbox", key = "publish_statuses",  label = "Статус выхода",   options = PUBLISH_STATUS_OPTIONS },
        { type = "checkbox", key = "production_statuses", label = "Озвучка",        options = PRODUCTION_STATUS_OPTIONS },
        { type = "text", key = "year_from", label = "Год с", defaultValue = "" },
        { type = "text", key = "year_to",   label = "Год по", defaultValue = "" },
    }
end

-- Собирает строку query из применённых фильтров; пустые значения пропускаются.
local function buildFilterQuery(filters)
    if type(filters) ~= "table" then return "" end
    local parts = {}

    local sorting = filters["sorting"]
    if type(sorting) == "string" and sorting ~= "" then
        table.insert(parts, FILTER_PARAM.sorting .. "=" .. url_encode(sorting))
    end

    -- checkbox: значения приходят массивом в "<key>_included", склеиваем запятой
    for _, key in ipairs(CHECKBOX_KEYS) do
        local values = filters[key .. "_included"]
        if type(values) == "table" and #values > 0 then
            local encoded = {}
            for _, v in ipairs(values) do
                if type(v) == "string" and v ~= "" then
                    table.insert(encoded, url_encode(v))
                end
            end
            if #encoded > 0 then
                table.insert(parts, FILTER_PARAM[key] .. "=" .. table.concat(encoded, ","))
            end
        end
    end

    local yearFrom = filters["year_from"]
    if type(yearFrom) == "string" and yearFrom ~= "" then
        table.insert(parts, "f%5Byears%5D%5Bfrom_year%5D=" .. url_encode(yearFrom))
    end
    local yearTo = filters["year_to"]
    if type(yearTo) == "string" and yearTo ~= "" then
        table.insert(parts, "f%5Byears%5D%5Bto_year%5D=" .. url_encode(yearTo))
    end

    return table.concat(parts, "&")
end

function getCatalogFiltered(index, filters)
    return fetchCatalog(catalogUrl(index + 1, buildFilterQuery(filters)))
end
