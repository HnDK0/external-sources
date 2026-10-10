-- YummyAnime — видео-плагин NoveLA (content_type = "video")
-- Сайт (baseUrl, веб-страницы книг для WebView): https://ru.yummyani.me
-- Каталог/метаданные: https://api.yani.tv (JSON, заголовок X-Application).
-- Серии: api.yani.tv ?need_videos=true (Kodik/Alloha/Aksor/Sibnet), запасной
-- источник — CVH-playlist plapi.cdnvideohub.com (Referer/Origin ru.yummyani.me).

content_type = "video"
id          = "yummyanime"
name        = "YummyAnime"
version     = "1.1.0"
baseUrl     = "https://ru.yummyani.me"
language    = "ru"
icon        = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/yummyanime.png"

-- ── GUARD: старые сборки приложения без require_lib/либ и base64_decode ──
-- Top-level обязан загрузиться без новых API (иначе плагин молча исчезает
-- из списка источников), поэтому либа грузится через pcall, а ошибка
-- поднимается из публичных функций. show_error в проде асинхронный
-- (возвращает NIL), поэтому сразу после него идёт error(..., 0).
local libErr = nil
local HAS_LIBS = type(require_lib) == "function"

local function tryLib(name)
    if not HAS_LIBS then return nil end
    local ok, res = pcall(require_lib, name)
    if not ok then libErr = tostring(res) return nil end
    return res
end

local TEXT = tryLib("text")
-- Хостер-резолверы вынесены в libs/hosters/ (lane shared-libs): каждая либа
-- грузится тем же pcall-паттерном, ошибка копится в libErr для ensureEngine.
local KODIK  = tryLib("kodik")
local ALLOHA = tryLib("alloha")
local AKSOR  = tryLib("aksor")
local SIBNET = tryLib("sibnet")
local CVH    = tryLib("cvh")

local function ensureEngine()
    local missing = {}
    if not HAS_LIBS then missing[#missing + 1] = "require_lib" end
    if rawget(_G, "base64_decode") == nil then missing[#missing + 1] = "base64_decode" end
    if TEXT == nil then missing[#missing + 1] = "text" end
    if KODIK == nil then missing[#missing + 1] = "kodik" end
    if ALLOHA == nil then missing[#missing + 1] = "alloha" end
    if AKSOR == nil then missing[#missing + 1] = "aksor" end
    if SIBNET == nil then missing[#missing + 1] = "sibnet" end
    if CVH == nil then missing[#missing + 1] = "cvh" end
    if #missing > 0 then
        show_error("Please update NoveLA",
            "This plugin needs new functions or libraries (" .. table.concat(missing, ", ") ..
            "). Please update the application to the latest version." ..
            (libErr and (" " .. libErr) or ""))
        error("A newer version of the application is required: " .. table.concat(missing, ","), 0)
    end
end

local API     = "https://api.yani.tv"
-- Lang — заголовок, которым сайт (ru.yummyani.me) выбирает язык ответа api.yani.tv:
-- без него API локализует title/description/anime_status/genres по Accept-Language
-- устройства и отдаёт английские названия и описания.
local API_APP = { ["X-Application"] = "e_y7qb7p9d_z1mdw", ["Lang"] = "ru" }
local CVH_API  = "https://plapi.cdnvideohub.com/api/v1/player/sv"
local REFERER  = "https://ru.yummyani.me/"
local CVH_HDR  = { ["Referer"] = REFERER, ["Origin"] = REFERER }
local PAGE_SIZE = 24

-- Таймауты http_get_batch (мс): бюджет одной попытки вместо лестницы ретраев
-- клиента (3+3+3+3+15 с) — один мёртвый URL не тормозит весь батч.
local BATCH_TIMEOUT = 8000  -- дефолт батча: iframe kodik/alloha, shell.php sibnet
local AKSOR_TIMEOUT = 6000  -- aksor: маленький JSON-запрос
local CVH_TIMEOUT   = 6000  -- CVH: маленький JSON-запрос

-- Кэш сеанса: detail-ответы api.yani.tv, CVH-плейлисты (по shikimori_id)
-- и списки плееров эпизодов (по slug, ?need_videos=true).
local _detailCache   = {}
local _playlistCache = {}
local _videosCache   = {}

-- Слаг и из веб-роута /catalog/item/<slug>, и из старого API-вида /anime/<slug>.
local function bookSlug(bookUrl)
    return bookUrl:match("/catalog/item/([^/?]+)") or bookUrl:match("/anime/([^/?]+)")
end

local function fetchDetail(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return nil end
    local cached = _detailCache[slug]
    if cached then return cached end
    local r = http_get(API .. "/anime/" .. slug, { headers = API_APP })
    if not r.success then return nil end
    local data = json_parse(r.body)
    local detail = data and data.response
    if type(detail) ~= "table" then return nil end
    _detailCache[slug] = detail
    return detail
end

-- Обложка: API отдаёт протокол-относительные URL вида "//static.yani.tv/...".
local function posterUrl(poster)
    if type(poster) ~= "table" then return nil end
    local src = poster.fullsize
    if type(src) ~= "string" or src == "" then return nil end
    if src:sub(1, 2) == "//" then return "https:" .. src end
    if src:find("^https?://") then return src end
    return nil
end

local function ratingText(rating)
    if type(rating) ~= "table" then return nil end
    local avg = rating.average
    if type(avg) ~= "number" then return nil end
    return "Rating: " .. tostring(avg) .. "/10"
end

local function itemToBook(item)
    if type(item) ~= "table" then return nil end
    local title, slug = item.title, item.anime_url
    if type(title) ~= "string" or title == "" then return nil end
    if type(slug) ~= "string" or slug == "" then return nil end
    local book = {
        title = string_clean(title),
        url   = baseUrl .. "/catalog/item/" .. slug,
        cover = posterUrl(item.poster),
        rating = ratingText(item.rating),
    }
    return book
end

-- Каталог/поиск: { response = [ ... ] }; total нет — hasNext по числу карточек.
local function fetchCatalog(url)
    local r = http_get(url, { headers = API_APP })
    if not r.success then return { items = {}, hasNext = false } end
    local data = json_parse(r.body)
    local arr = data and data.response
    if type(arr) ~= "table" then return { items = {}, hasNext = false } end
    local items = {}
    for _, item in ipairs(arr) do
        local book = itemToBook(item)
        if book then table.insert(items, book) end
    end
    return { items = items, hasNext = #arr >= PAGE_SIZE }
end

function getCatalogList(index)
    ensureEngine()
    local offset = index * PAGE_SIZE
    return fetchCatalog(API .. "/anime?limit=" .. PAGE_SIZE .. "&offset=" .. offset)
end

function getCatalogSearch(index, query)
    ensureEngine()
    if index > 0 then return { items = {}, hasNext = false } end
    return fetchCatalog(
        API .. "/anime?q=" .. url_encode(query) .. "&limit=" .. PAGE_SIZE .. "&offset=0"
    )
end

-- Фильтры: api.yani.tv/anime принимает те же query-параметры, что и
-- фильтр каталога на ru.yummyani.me/catalog. Допустимые значения API
-- проверены фактическими ответами (ошибкой 400 с перечислением enum).
--
-- Сортировка: enum sort = [title, year, rating, rating_counters, views, top,
-- random, id]. sort_forward=true — по возрастанию поля, false — по убыванию;
-- без параметра API сортирует так же, как sort=top (проверено на 3 страницах).
local SORT_ORDER = {
    --            sort_forward: "true"  = возрастание, "false" = убывание
    top             = "true",   -- 1-е место = лучшее (это же порядок по умолчанию)
    title           = "true",   -- А → Я
    random          = "true",   -- направление неважно
    year            = "false",  -- свежие первыми
    rating          = "false",  -- высокий рейтинг первым
    rating_counters = "false",  -- больше голосов первым
    views           = "false",  -- больше просмотров первым
}

local function filterGenreOptions()
    local r = http_get(API .. "/anime/genres", { headers = API_APP })
    if not r.success then return nil end
    local data = json_parse(r.body)
    local list = data and data.response and data.response.genres
    if type(list) ~= "table" then return nil end
    local options = {}
    for _, g in ipairs(list) do
        if type(g) == "table" and type(g.title) == "string"
            and g.title ~= "" and g.value ~= nil then
            table.insert(options, { value = tostring(g.value), label = string_clean(g.title) })
        end
    end
    if #options == 0 then return nil end
    return options
end

function getFilterList()
    ensureEngine()
    local list = {
        {
            type         = "select",
            key          = "status",
            label        = "Статус",
            defaultValue = "",
            options = {
                { value = "",         label = "Любой" },
                { value = "ongoing",  label = "Онгоинг" },
                { value = "released", label = "Вышел" },
                { value = "announce", label = "Анонс" },
            },
        },
        {
            type         = "select",
            key          = "types",
            label        = "Тип",
            defaultValue = "",
            options = {
                { value = "",        label = "Любой" },
                { value = "tv",      label = "Сериал" },
                { value = "movie",   label = "Полнометражный фильм" },
                { value = "ona",     label = "ONA" },
                { value = "ova",     label = "OVA" },
                { value = "special", label = "Спешл" },
            },
        },
        {
            type         = "text",
            key          = "year",
            label        = "Год",
            defaultValue = "",
        },
        {
            type         = "select",
            key          = "sort",
            label        = "Сортировка",
            defaultValue = "top",
            options = {
                { value = "top",             label = "По умолчанию" },
                { value = "title",           label = "По названию" },
                { value = "year",            label = "По году" },
                { value = "rating",          label = "По рейтингу" },
                { value = "rating_counters", label = "По числу голосов" },
                { value = "views",           label = "По просмотрам" },
                { value = "random",          label = "Случайная" },
            },
        },
    }
    local genres = filterGenreOptions()
    if genres then
        table.insert(list, {
            type  = "tristate",
            key   = "genres",
            label = "Жанры",
            options = genres,
        })
    end
    return list
end

-- tristate/checkbox приходят как массивы строк: key_included / key_excluded.
local function csvParam(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, v in ipairs(list) do
        if type(v) == "string" and v ~= "" then table.insert(out, v) end
    end
    if #out == 0 then return nil end
    return table.concat(out, ",")
end

local function filterValue(filters, key)
    local v = filters and filters[key]
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

function getCatalogFiltered(index, filters)
    ensureEngine()
    local parts = { "limit=" .. PAGE_SIZE, "offset=" .. (index * PAGE_SIZE) }
    -- genres = список id через запятую (AND), exclude_genres — исключения.
    local status   = filterValue(filters, "status")
    local types    = filterValue(filters, "types")
    local year     = filterValue(filters, "year")
    local sort     = filterValue(filters, "sort")
    local genres   = csvParam(filters and filters["genres_included"])
    local excluded = csvParam(filters and filters["genres_excluded"])

    if status then table.insert(parts, "status=" .. status) end
    if types then table.insert(parts, "types=" .. types) end
    if sort then
        table.insert(parts, "sort=" .. sort)
        table.insert(parts, "sort_forward=" .. (SORT_ORDER[sort] or "true"))
    end
    if year and year:match("^%d%d%d%d$") then
        table.insert(parts, "from_year=" .. year .. "&to_year=" .. year)
    end
    if genres then table.insert(parts, "genres=" .. genres) end
    if excluded then table.insert(parts, "exclude_genres=" .. excluded) end

    return fetchCatalog(API .. "/anime?" .. table.concat(parts, "&"))
end

function getBookTitle(bookUrl)
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d or type(d.title) ~= "string" or d.title == "" then return nil end
    return string_clean(d.title)
end

function getBookCoverImageUrl(bookUrl)
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    return posterUrl(d.poster)
end

function getBookDescription(bookUrl)
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d or type(d.description) ~= "string" or d.description == "" then return nil end
    return string_trim(d.description)
end

function getBookStatus(bookUrl)
    ensureEngine()
    local d = fetchDetail(bookUrl)
    local status = d and d.anime_status
    if type(status) ~= "table" then return nil end
    if type(status.title) ~= "string" or status.title == "" then return nil end
    return status.title
end

function getBookRating(bookUrl)
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    return ratingText(d.rating)
end

function getBookGenres(bookUrl)
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d or type(d.genres) ~= "table" then return {} end
    local genres = {}
    for _, g in ipairs(d.genres) do
        if type(g) == "table" and type(g.title) == "string" and g.title ~= "" then
            table.insert(genres, g.title)
        end
    end
    return genres
end

local function shikimoriId(detail)
    local ids = detail and detail.remote_ids
    local id = ids and tonumber(ids.shikimori_id)
    if id and id > 0 then return id end
    return nil
end

-- Элементы CVH-плейлиста → { season, episode, vkId, voiceStudio, voiceType }.
-- У фильмов поля episode нет вовсе — тогда все элементы считаются серией 1;
-- в сериалах записи без номера серии пропускаются.
local function normalizeEpisodes(raw)
    local hasEpisode = false
    for _, it in ipairs(raw) do
        local ep = tonumber(it.episode)
        if ep and ep > 0 then hasEpisode = true break end
    end
    local out = {}
    for _, it in ipairs(raw) do
        local episode = tonumber(it.episode)
        if episode and episode <= 0 then episode = nil end
        if episode or not hasEpisode then
            local season = tonumber(it.season)
            if not season or season <= 0 then season = 1 end
            table.insert(out, {
                season      = season,
                episode     = episode or 1,
                vkId        = it.vkId,
                voiceStudio = it.voiceStudio,
                voiceType   = it.voiceType,
            })
        end
    end
    return out
end

local function playlistUrl(id)
    return CVH_API .. "/playlist?pub=745&id=" .. id .. "&aggr=mali"
end

local function fetchPlaylist(shikimoriId)
    local cached = _playlistCache[shikimoriId]
    if cached then return cached end
    local r = http_get(playlistUrl(shikimoriId), { headers = CVH_HDR })
    if not r.success then return nil end
    local data = json_parse(r.body)
    if type(data) ~= "table" or type(data.items) ~= "table" then return nil end
    local episodes = normalizeEpisodes(data.items)
    _playlistCache[shikimoriId] = episodes
    return episodes
end

-- Список плееров серий: GET api.yani.tv/anime/<slug>?need_videos=true →
-- response.videos = { number, iframe_url, data{player, player_id, dubbing} }.
local function videosUrl(slug)
    return API .. "/anime/" .. slug .. "?need_videos=true"
end

local function parseVideos(body)
    local data = json_parse(body)
    local videos = data and data.response and data.response.videos
    if type(videos) ~= "table" then return nil end
    return videos
end

local function fetchVideos(slug)
    local cached = _videosCache[slug]
    if cached then return cached end
    local r = http_get(videosUrl(slug), { headers = API_APP })
    if not r.success then return nil end
    local videos = parseVideos(r.body)
    if not videos then return nil end
    _videosCache[slug] = videos
    return videos
end

-- Уникальные number в порядке появления → сортировка по числовому префиксу
-- ("100-101" → 100) по возрастанию; при равном префиксе — порядок из API;
-- записи без ведущего числа уходят в конец исходным порядком.
local function videoNumbers(videos)
    local seen, list = {}, {}
    for _, rec in ipairs(videos) do
        local number = type(rec) == "table" and rec.number or nil
        if type(number) == "string" and number ~= "" and not seen[number] then
            seen[number] = true
            list[#list + 1] = {
                number = number,
                order  = #list + 1,
                lead   = tonumber(number:match("^%d+")),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.lead and b.lead then
            if a.lead ~= b.lead then return a.lead < b.lead end
            return a.order < b.order
        end
        if a.lead then return true end
        if b.lead then return false end
        return a.order < b.order
    end)
    local out = {}
    for _, it in ipairs(list) do out[#out + 1] = it.number end
    return out
end

-- Серии = главы. url сохраняет вид <bookUrl>/episode/<number>: номер не
-- кодируется (движок кодирует при запросе), поэтому «57-58» доедет до сервера.
function getChapterList(bookUrl)
    ensureEngine()
    local slug = bookSlug(bookUrl)
    if not slug then return {} end
    local videos = fetchVideos(slug)
    if not videos then return {} end
    local chapters = {}
    for _, number in ipairs(videoNumbers(videos)) do
        chapters[#chapters + 1] = {
            title = "Серия " .. number,
            url   = bookUrl .. "/episode/" .. number,
        }
    end
    return chapters
end

-- Сигнатура обновления списка серий: "сколько уникальных number : последний number",
-- например "531:152-153" — меняется при появлении новой серии.
-- Запрос ПРЯМОЙ, мимо _videosCache: иначе хэш всегда был бы одинаковым; свежий
-- ответ тут же кладётся в кэш, чтобы getChapterList его переиспользовал.
-- Ошибка сети или пустой список → nil, движок тогда возьмёт полный getChapterList.
function getChapterListHash(bookUrl)
    ensureEngine()
    local slug = bookSlug(bookUrl)
    if not slug then return nil end
    local r = http_get(videosUrl(slug), { headers = API_APP })
    if not r.success then return nil end
    local videos = parseVideos(r.body)
    if not videos then return nil end
    _videosCache[slug] = videos
    local numbers = videoNumbers(videos)
    if #numbers == 0 then return nil end
    return #numbers .. ":" .. numbers[#numbers]
end

-- AniLiberty (семейный проект) — первым, остальные по алфавиту.
local function compareVoices(a, b)
    local aFirst = a.voiceStudio == "AniLiberty"
    local bFirst = b.voiceStudio == "AniLiberty"
    if aFirst ~= bFirst then return aFirst end
    local as = a.voiceStudio or ""
    local bs = b.voiceStudio or ""
    if as ~= bs then return as < bs end
    local at = a.voiceType or ""
    local bt = b.voiceType or ""
    if at ~= bt then return at < bt end
    return tostring(a.vkId) < tostring(b.vkId)
end

-- ============ Потоки: резолверы плееров сайта ============
-- Один источник — { url, quality, headers? } ровно в том виде, в каком его
-- принимает convertLuaVideoList. Каждая цепочка закрыта в pcall: упал один
-- плеер → log_error и переход к следующему, каталог серий не должен
-- ломаться. Механика плагина — батч GET-запросов, кэши и сборка списка
-- источников; резолверы хостеров (kodik/alloha/aksor/sibnet/cvh) — в
-- libs/hosters/. Диспетчер record (api.yani.tv) остаётся в плагине: kind-ID
-- 4=kodik/2=alloha/1=aksor/7=sibnet специфичны для бэкенда yummyanime.

local function pushSource(list, seen, src)
    if type(src) ~= "table" then return end
    local url = src.url
    if type(url) ~= "string" or url == "" or seen[url] then return end
    seen[url] = true
    list[#list + 1] = src
end

local PLAYER_KINDS = { [4] = "kodik", [2] = "alloha", [1] = "aksor", [7] = "sibnet" }

-- KODIK/ALLOHA/AKSOR/SIBNET = nil, пока require_lib недоступен, а таблица
-- создаётся на top-level: значение берём через and, иначе падение при загрузке
-- молча убрало бы плагин из списка источников (не-nil гарантирует ensureEngine).
local RESOLVERS = {
    kodik  = KODIK and KODIK.resolve,
    alloha = ALLOHA and ALLOHA.resolve,
    aksor  = AKSOR and AKSOR.resolve,
    sibnet = SIBNET and SIBNET.resolve,
}

local function playerKind(rec)
    local data = type(rec.data) == "table" and rec.data or {}
    local pid = tonumber(data.player_id)
    local kind = pid and PLAYER_KINDS[pid] or nil
    if kind then return kind end
    local name = type(data.player) == "string" and data.player:lower() or ""
    if name:find("kodik", 1, true) then return "kodik" end
    if name:find("alloha", 1, true) then return "alloha" end
    if name:find("aksor", 1, true) then return "aksor" end
    if name:find("sibnet", 1, true) then return "sibnet" end
    return nil
end

local function recordDubbing(rec)
    local data = type(rec.data) == "table" and rec.data or {}
    local d = data.dubbing
    if type(d) == "string" and d ~= "" then return d end
    return "Озвучка"
end

-- iframe_url бывает протокол-относительным ("//alloha.yani.tv/...").
local function embedUrl(iframe)
    if iframe:sub(1, 2) == "//" then return "https:" .. iframe end
    return iframe
end

-- pages — ключ → ответ общего http_get_batch (см. batchPlayers): для
-- kodik/alloha/sibnet сам iframe, для aksor iframe → ответ api/video/<md5>.
local function resolveRecord(rec, sources, seen, pages)
    local kind = playerKind(rec)
    local iframe = type(rec.iframe_url) == "string" and rec.iframe_url or nil
    local run = kind and RESOLVERS[kind] or nil
    if not run or not iframe or iframe == "" then return end
    iframe = embedUrl(iframe)
    local ok, result = pcall(run, iframe, recordDubbing(rec), pages[iframe])
    if not ok then
        log_error("YummyAnime: " .. kind .. ": " .. tostring(result))
        return
    end
    if type(result) ~= "table" then return end
    for _, s in ipairs(result) do pushSource(sources, seen, s) end
end

-- CVH-плейлист тайтла по URL серии: detail → shikimori_id → плейлист.
-- Оба ответа кэшируются на сеанс, поэтому серия за серией не ходит в сеть.
local function cvhPlaylist(episodeUrl)
    local id = shikimoriId(fetchDetail(episodeUrl))
    if not id then return nil end
    return fetchPlaylist(id)
end

-- Варианты CVH (запасной источник) этой серии, отсортированные по озвучке.
-- nil — если CVH для серии недоступен.
local function collectCvhItems(episodeUrl, number)
    local items = cvhPlaylist(episodeUrl)
    if not items then return nil end
    -- "57-58"/"119+120" → ведущее число серии
    local ep = tonumber(number) or tonumber(number:match("^%d+"))
    if not ep then return nil end
    local matched = {}
    for _, it in ipairs(items) do
        if it.episode == ep then matched[#matched + 1] = it end
    end
    if #matched == 0 then return nil end
    table.sort(matched, compareVoices)
    return matched
end

-- Варианты CVH — в конец списка, после плееров сайта.
local function appendCvhSources(matched, pages, sources, seen)
    for _, it in ipairs(matched) do
        local ok, src = pcall(CVH.sourceFrom, it, pages[CVH.videoUrl(it.vkId)])
        if ok then
            pushSource(sources, seen, src)
        else
            log_error("YummyAnime: CVH " .. tostring(src))
        end
    end
end

-- ============ Потоки: один http_get_batch на всю серию ============
-- Батч умеет только GET/HEAD, поэтому в него собираем всё, что можно:
-- страницы kodik/alloha, api/video aksor, shell.php sibnet и видео CVH.
-- Остаются последовательными только POST (/ftor, /bnsi) внутри резолверов —
-- их в батч передать нельзя; кэшируемые detail/playlist CVH идут перед батчем.

local AKSOR_OPTS = {
    headers = { ["Accept"] = "application/json" },
    timeout = AKSOR_TIMEOUT,
}
local SIBNET_OPTS = { charset = "windows-1251" }
local CVH_OPTS = { headers = CVH_HDR, timeout = CVH_TIMEOUT }

local function newBatch()
    return { items = {}, byKey = {}, seen = {} }
end

-- url — что реально запросить, key — ключ ответа в pages (для aksor url =
-- api/video/<md5>, а key = iframe, т.к. resolveRecord ищет страницу по iframe).
local function batchAdd(b, url, key, opts)
    if type(url) ~= "string" or url == "" then return end
    b.byKey[key] = url
    if not b.seen[url] then
        b.seen[url] = true
        b.items[#b.items + 1] = { url = url, opts = opts }
    end
end

local function batchRun(b)
    if #b.items == 0 then return {} end
    local reqs = {}
    for i, it in ipairs(b.items) do
        local e = { url = it.url }
        local o = it.opts
        if o then
            e.headers = o.headers
            e.charset = o.charset
            e.timeout = o.timeout
        end
        reqs[i] = e
    end
    local rs = http_get_batch(reqs, { timeout = BATCH_TIMEOUT })
    local pages = {}
    for i, it in ipairs(b.items) do pages[it.url] = rs[i] end
    local out = {}
    for key, url in pairs(b.byKey) do out[key] = pages[url] end
    return out
end

local function batchPlayers(b, recs)
    for _, rec in ipairs(recs) do
        local kind = playerKind(rec)
        local iframe = type(rec.iframe_url) == "string" and rec.iframe_url or nil
        if kind and iframe and iframe ~= "" then
            iframe = embedUrl(iframe)
            if kind == "kodik" or kind == "alloha" then
                batchAdd(b, iframe, iframe, nil)
            elseif kind == "aksor" then
                batchAdd(b, AKSOR.apiUrl(iframe), iframe, AKSOR_OPTS)
            elseif kind == "sibnet" then
                batchAdd(b, iframe, iframe, SIBNET_OPTS)
            end
        end
    end
end

local function batchCvh(b, items)
    for _, it in ipairs(items) do
        local url = CVH.videoUrl(it.vkId)
        batchAdd(b, url, url, CVH_OPTS)
    end
end

-- A) Старый формат URL (.../season/<s>/episode/<e>) — только CVH-плейлист.
local function legacyVideoList(episodeUrl)
    local slug = episodeUrl:match("/catalog/item/([^/?]+)/") or episodeUrl:match("/anime/([^/?]+)/")
    local season = tonumber(episodeUrl:match("/season/(%d+)"))
    local episode = tonumber(episodeUrl:match("/episode/(%d+)"))
    if not slug or not season or not episode then
        error("YummyAnime: не удалось разобрать URL эпизода")
    end

    local items = cvhPlaylist(API .. "/anime/" .. slug)
    if not items then return nil end

    local matched = {}
    for _, it in ipairs(items) do
        if it.season == season and it.episode == episode then
            matched[#matched + 1] = it
        end
    end
    if #matched == 0 then return nil end
    table.sort(matched, compareVoices)

    -- Все видео этой серии — одним батчем вместо последовательных http_get.
    local b = newBatch()
    batchCvh(b, matched)
    local pages = batchRun(b)

    local sources, seen = {}, {}
    appendCvhSources(matched, pages, sources, seen)
    if #sources == 0 then return nil end
    return sources
end

function getVideoList(episodeUrl)
    ensureEngine()
    if episodeUrl:find("/season/", 1, true) then
        return legacyVideoList(episodeUrl)
    end

    -- B) Новый формат: <url-серии>/episode/<number> — плееры сайта
    local prefix, number = episodeUrl:match("^(.-)/episode/([^/?]+)$")
    if not prefix or not number then return nil end
    local slug = bookSlug(prefix)
    if not slug then return nil end
    local videos = _videosCache[slug] or fetchVideos(slug)
    if not videos then return nil end

    local recs = {}
    for _, rec in ipairs(videos) do
        if type(rec) == "table" and rec.number == number then recs[#recs + 1] = rec end
    end

    -- Стандарт getVideoList (см. guide): все GET-запросы этой серии — одним
    -- http_get_batch: страницы kodik/alloha, api/video aksor, shell.php sibnet
    -- и видео CVH. Деталь и плейлист CVH кэшируются на сеанс и идут перед
    -- батчем (URL видео из плейлиста зависит от их ответов). Состав, порядок
    -- и dedup источников не меняются: плееры сайта первыми, CVH — в конец.
    local b = newBatch()
    batchPlayers(b, recs)
    local matched = collectCvhItems(episodeUrl, number)
    if matched then batchCvh(b, matched) end
    local pages = batchRun(b)

    local sources, seen = {}, {}
    for _, rec in ipairs(recs) do
        resolveRecord(rec, sources, seen, pages)
    end
    if matched then appendCvhSources(matched, pages, sources, seen) end
    if #sources == 0 then return nil end
    return sources
end

function getUserAgentPreset()
    ensureEngine()
    return "Chrome Mobile"
end
