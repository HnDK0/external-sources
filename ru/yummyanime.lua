-- YummyAnime — видео-плагин NoveLA (content_type = "video")
-- Сайт (baseUrl, веб-страницы книг для WebView): https://ru.yummyani.me
-- Каталог/метаданные: https://api.yani.tv (JSON, заголовок X-Application).
-- Серии: api.yani.tv ?need_videos=true (Kodik/Alloha/Aksor/Sibnet), запасной
-- источник — CVH-playlist plapi.cdnvideohub.com (Referer/Origin ru.yummyani.me).

content_type = "video"
id          = "yummyanime"
name        = "YummyAnime"
version     = "1.0.1"
baseUrl     = "https://ru.yummyani.me"
language    = "ru"
icon        = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/yummyanime.png"

local API     = "https://api.yani.tv"
-- Lang — заголовок, которым сайт (ru.yummyani.me) выбирает язык ответа api.yani.tv:
-- без него API локализует title/description/anime_status/genres по Accept-Language
-- устройства и отдаёт английские названия и описания.
local API_APP = { ["X-Application"] = "e_y7qb7p9d_z1mdw", ["Lang"] = "ru" }
local CVH_API  = "https://plapi.cdnvideohub.com/api/v1/player/sv"
local REFERER  = "https://ru.yummyani.me/"
local CVH_HDR  = { ["Referer"] = REFERER, ["Origin"] = REFERER }
local PAGE_SIZE = 24

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
    local offset = index * PAGE_SIZE
    return fetchCatalog(API .. "/anime?limit=" .. PAGE_SIZE .. "&offset=" .. offset)
end

function getCatalogSearch(index, query)
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
    local d = fetchDetail(bookUrl)
    if not d or type(d.title) ~= "string" or d.title == "" then return nil end
    return string_clean(d.title)
end

function getBookCoverImageUrl(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    return posterUrl(d.poster)
end

function getBookDescription(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d or type(d.description) ~= "string" or d.description == "" then return nil end
    return string_trim(d.description)
end

function getBookStatus(bookUrl)
    local d = fetchDetail(bookUrl)
    local status = d and d.anime_status
    if type(status) ~= "table" then return nil end
    if type(status.title) ~= "string" or status.title == "" then return nil end
    return status.title
end

function getBookRating(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    return ratingText(d.rating)
end

function getBookGenres(bookUrl)
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

-- Подпись озвучки — это ещё и ключ запоминания выбора в плеере, нужен различимым.
local function voiceLabel(item)
    local studio = type(item.voiceStudio) == "string" and item.voiceStudio or ""
    local vtype  = type(item.voiceType) == "string" and item.voiceType or ""
    local label
    if studio ~= "" and vtype ~= "" then
        label = studio .. " (" .. vtype .. ")"
    elseif studio ~= "" then
        label = studio
    elseif vtype ~= "" then
        label = vtype
    else
        label = "vk" .. tostring(item.vkId)
    end
    return string_clean(label)
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
-- плеер → log_error и переход к следующему, каталог серий не должен ломаться.

local function pushSource(list, seen, src)
    if type(src) ~= "table" then return end
    local url = src.url
    if type(url) ~= "string" or url == "" or seen[url] then return end
    seen[url] = true
    list[#list + 1] = src
end

-- Base64 на чистом Lua: в движке есть base64_decode, но по условию задачи
-- реализация своя (только stdlib, без внешних библиотек).
local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUES = nil

local function base64DecodePure(s)
    if not B64_VALUES then
        B64_VALUES = {}
        for i = 1, #B64_ALPHABET do
            B64_VALUES[B64_ALPHABET:sub(i, i)] = i - 1
        end
    end
    local out, buf, bits = {}, 0, 0
    for i = 1, #s do
        local v = B64_VALUES[s:sub(i, i)]
        if v ~= nil then
            buf = buf * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local div = 2 ^ bits
                out[#out + 1] = string.char(math.floor(buf / div) % 256)
                buf = buf % div
            end
        end
    end
    return table.concat(out)
end

-- Kodik: src в ответе /ftor либо абсолютный, либо ROT-18 по буквам + base64.
local function kodikDecode(src)
    if src:find("//", 1, true) then return src end
    local t = {}
    for i = 1, #src do
        local b = src:byte(i)
        if b >= 65 and b <= 90 then
            b = b + 18
            if b > 90 then b = b - 26 end
        elseif b >= 97 and b <= 122 then
            b = b + 18
            if b > 122 then b = b - 26 end
        end
        t[#t + 1] = string.char(b)
    end
    local url = base64DecodePure(table.concat(t))
    if url == "" then return nil end
    if url:sub(1, 2) == "//" then return "https:" .. url end
    return url
end

-- page — ответ общего http_get_batch по этому iframe (см. getVideoList):
-- эмбеды Kodik/Alloha грузятся одним батчем, без своих заголовков.
local function resolveKodik(iframeUrl, dubbing, page)
    if type(page) ~= "table" or not page.success then
        log_error("YummyAnime: Kodik iframe " .. tostring(page and page.code))
        return nil
    end
    local url = iframeUrl
    if url:sub(1, 2) == "//" then url = "https:" .. url end
    local html = page.body
    -- urlParams — JSON с подписями d_sign/pd_sign/ref_sign, без них /ftor отдаёт 500
    local raw = html:match("urlParams%s*=%s*'([^']+)'")
        or html:match('urlParams%s*=%s*"([^"]+)"')
    local params = raw and json_parse(raw) or nil
    if type(params) ~= "table" or type(params.d_sign) ~= "string" or params.d_sign == "" then
        log_error("YummyAnime: Kodik — не найдены urlParams")
        return nil
    end
    local vtype = html:match("vInfo%.type%s*=%s*'([^']+)'")
        or html:match('var%s+type%s*=%s*"([^"]+)"')
    local vhash = html:match("vInfo%.hash%s*=%s*'([^']+)'")
    local vid   = html:match('videoId%s*=%s*"([^"]+)"')
        or html:match("vInfo%.id%s*=%s*'([^']+)'")
    if not vtype or not vhash or not vid then
        -- запасной путь: сегменты пути iframe — host/type/id/hash
        local seg = {}
        for part in url:gsub("[?#].*$", ""):gmatch("[^/]+") do seg[#seg + 1] = part end
        vtype = vtype or seg[2]
        vid   = vid   or seg[3]
        vhash = vhash or seg[4]
    end
    if not vtype or not vid or not vhash then
        log_error("YummyAnime: Kodik — не удалось получить type/id/hash")
        return nil
    end
    local function field(v)
        return url_encode(type(v) == "string" and v or "")
    end
    -- ponytail: ref/ref_sign не отправляем — сервер подписывает их под Referer
    -- запроса iframe, а движок всегда шлёт свой Referer, из-за чего подпись
    -- не сходится и /ftor отдаёт 500; без этих полей 200 в обоих случаях
    local body = table.concat({
        "d=",        field(params.d),
        "&d_sign=",  field(params.d_sign),
        "&pd=",      field(params.pd),
        "&pd_sign=", field(params.pd_sign),
        "&type=",    url_encode(vtype),
        "&id=",      url_encode(vid),
        "&hash=",    url_encode(vhash),
        "&bad_user=false&cdn_is_working=true",
    })
    local pr = http_post("https://kodikplayer.com/ftor", body)
    if not pr.success then
        log_error("YummyAnime: Kodik /ftor " .. tostring(pr.code))
        return nil
    end
    local data = json_parse(pr.body)
    local links = data and data.links
    if type(links) ~= "table" then return nil end
    -- ключи links — качества в строковом виде ("240".."720"), от большего к меньшему
    local qs = {}
    for k in pairs(links) do
        if type(k) == "string" and k:match("^%d+$") then qs[#qs + 1] = k end
    end
    table.sort(qs, function(a, b) return tonumber(a) > tonumber(b) end)
    local out = {}
    for _, q in ipairs(qs) do
        local items = links[q]
        if type(items) == "table" then
            for _, it in ipairs(items) do
                local src = type(it) == "table" and it.src or nil
                local hls = type(src) == "string" and kodikDecode(src) or nil
                if hls then
                    -- m3u8 Kodik отдаётся и без Referer/Origin (проверено: 200)
                    out[#out + 1] = {
                        url     = hls,
                        quality = "Kodik · " .. dubbing .. " · " .. q .. "p",
                    }
                end
            end
        end
    end
    return out
end

-- Borth (Alloha): перестановки ZU/Zx/ZQ из dec_app — порт borth_core.js.
-- Порты сверены с эталоном node: 170 входов (1..513 символов, реальный
-- viewporti) побайтово совпадают. Zf в эталоне всегда false, поэтому
-- финальные повороты строк — мёртвый код и здесь их нет.
local function borthBits(len)
    local bits = 0
    while 2 ^ bits < len do bits = bits + 1 end
    return bits
end

local function borthGroupU(v)
    local n = 0
    while v > 0 do
        n = n + 1
        v = math.floor(v / 2)
    end
    return n
end

local function borthGroupX(v, bits)
    if v == 0 then return bits end
    local n = 0
    while v % 2 == 0 do
        n = n + 1
        v = math.floor(v / 2)
    end
    return n
end

local function borthU(s)
    local len = #s
    if len <= 1 then return s end
    local bits = borthBits(len)
    local counts = {}
    for g = 0, bits do counts[g] = 0 end
    for i = 0, len - 1 do
        local g = borthGroupU(i)
        counts[g] = counts[g] + 1
    end
    local chunks, pos = {}, 0
    for g = bits, 0, -1 do              -- нарезка входа по группам сверху вниз
        local n = counts[g]
        chunks[g] = s:sub(pos + 1, pos + n)
        pos = pos + n
    end
    local used = {}
    for g = 0, bits do used[g] = 0 end
    local out = {}
    for i = 0, len - 1 do
        local g = borthGroupU(i)
        local o = used[g]
        used[g] = o + 1
        out[i + 1] = chunks[g]:sub(o + 1, o + 1)
    end
    return table.concat(out)
end

local function borthX(s)
    local len = #s
    if len <= 1 then return s end
    local bits = borthBits(len)
    local counts = {}
    for g = 0, bits do counts[g] = 0 end
    for i = 0, len - 1 do
        local g = borthGroupX(i, bits)
        counts[g] = counts[g] + 1
    end
    local chunks, pos = {}, 0
    for g = 0, bits do                  -- нарезка входа по группам снизу вверх
        local n = counts[g]
        chunks[g] = s:sub(pos + 1, pos + n)
        pos = pos + n
    end
    local used = {}
    for g = 0, bits do used[g] = 0 end
    local out = {}
    for i = 0, len - 1 do
        local g = borthGroupX(i, bits)
        local o = used[g]
        used[g] = o + 1
        out[i + 1] = chunks[g]:sub(o + 1, o + 1)
    end
    return table.concat(out)
end

local function isPrime(n)
    if n < 2 then return false end
    if n % 2 == 0 then return n == 2 end
    local d = 3
    while d * d <= n do
        if n % d == 0 then return false end
        d = d + 2
    end
    return true
end

local function borthQ(s)
    local len = #s
    if len <= 1 then return s end
    local p = len + 1
    while not isPrime(p) do p = p + 1 end
    local taken, order, cur = {}, {}, 0
    while #order < len do
        cur = (cur + 2) % p
        if cur < len and not taken[cur + 1] then
            taken[cur + 1] = true
            order[#order + 1] = cur
        end
    end
    local out = {}
    for m = 0, len - 1 do
        out[order[m + 1] + 1] = s:sub(m + 1, m + 1)
    end
    return table.concat(out)
end

local function borthPayload(viewporti)
    return borthQ(borthX(borthU(viewporti)))
end

-- Качества в порядке убывания: ключи JSON приходят в произвольном порядке.
local function sortedQualityKeys(quals)
    local keys = {}
    for k in pairs(quals) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb and na ~= nb then return na > nb end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local ALLOHA_ORIGIN = "https://alloha.yani.tv"

-- page — ответ общего http_get_batch по этому iframe (см. getVideoList).
local function resolveAlloha(iframeUrl, dubbing, page)
    if type(page) ~= "table" or not page.success then
        log_error("YummyAnime: Alloha iframe " .. tostring(page and page.code))
        return nil
    end
    local html = page.body
    local viewporti = html:match('<meta name="viewporti" content="([^"]+)"')
    local token     = html:match("token:%s*'([0-9a-f]+)'")
    local activeId  = html:match('"active"%s*:%s*{%s*"id"%s*:%s*(%d+)')
    if not viewporti or not token or not activeId then
        log_error("YummyAnime: Alloha — не удалось разобрать страницу плеера")
        return nil
    end
    -- fp (sha256-отпечаток) сервер не сверяет: на живом нули и настоящий sha256
    -- дают одинаковый 200, а хеш-функции в песочнице движка нет.
    local borth = string.rep("0", 64) .. "|" .. borthPayload(viewporti)
    local body = "token=" .. token .. "&av1=true&autoplay=0&audio=&subtitle="
    local pr = http_post(ALLOHA_ORIGIN .. "/bnsi/movies/" .. activeId, body, {
        headers = {
            ["Referer"]          = iframeUrl,
            ["Origin"]           = ALLOHA_ORIGIN,
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Borth"]            = borth,
        },
    })
    if not pr.success then
        log_error("YummyAnime: Alloha /bnsi " .. tostring(pr.code))
        return nil
    end
    local data = json_parse(pr.body)
    local tracks = data and data.hlsSource
    if type(tracks) ~= "table" then return nil end
    -- CDN vkvideo отвечает 403 без Origin → заголовки источника обязательны
    local headers = { ["Referer"] = iframeUrl, ["Origin"] = ALLOHA_ORIGIN }
    local out = {}
    for _, track in ipairs(tracks) do
        local quals = type(track) == "table" and track.quality or nil
        if type(quals) == "table" then
            for _, k in ipairs(sortedQualityKeys(quals)) do
                local u = quals[k]
                if type(u) == "string" and u ~= "" then
                    out[#out + 1] = {
                        url     = u,
                        quality = "Alloha · " .. dubbing .. " · " .. tostring(k) .. "p",
                        headers = headers,
                    }
                end
            end
        end
    end
    return out
end

-- Aksor: один запрос к api/video/<md5 из iframe_url>; страница заполняет
-- только q1080, остальные качества приходят null.
local AKSOR_QUALITIES = {
    { key = "q1080", label = "1080" },
    { key = "q720",  label = "720" },
    { key = "q480",  label = "480" },
}

local function resolveAksor(iframeUrl, dubbing)
    local md5 = iframeUrl:gsub("[?#].*$", ""):match("([^/]+)$")
    if not md5 or md5 == "" then return nil end
    local r = http_get("https://player.aksor.tv/api/video/" .. md5, {
        headers = { ["Accept"] = "application/json" },
    })
    if not r.success then
        log_error("YummyAnime: Aksor api " .. tostring(r.code))
        return nil
    end
    local data = json_parse(r.body)
    local quals = type(data) == "table" and data.qualities or nil
    if type(quals) ~= "table" then return nil end
    local out = {}
    for _, q in ipairs(AKSOR_QUALITIES) do
        local u = quals[q.key]
        if type(u) == "string" and u ~= "" then
            -- в путях Aksor встречается пробел («SHIZA Project»): без %20 URL
            -- не проходит, а .mpd движок проигрывает и без заголовков
            local enc = (u:gsub(" ", "%%20"))
            out[#out + 1] = {
                url     = enc,
                quality = "Aksor · " .. dubbing .. " · " .. q.label .. "p",
            }
        end
    end
    return out
end

local function resolveSibnet(iframeUrl, dubbing)
    -- shell.php отдаёт windows-1251; шаблон режет ~35-45 запросов за 2-3 минуты
    -- (403 rate-limit) — тогда этот плеер просто пропускаем
    local r = http_get(iframeUrl, { charset = "windows-1251" })
    if not r.success then
        log_error("YummyAnime: Sibnet " .. tostring(r.code))
        return nil
    end
    local src = r.body:match('player%.src%(%[%s*{%s*src:%s*"([^"]+)"')
        or r.body:match('src:%s*"(/v/[^"]+)"')
    if not src then return nil end
    if src:sub(1, 1) == "/" then src = "https://video.sibnet.ru" .. src end
    return {
        {
            url     = src,
            quality = "Sibnet · " .. dubbing,
            -- /v/ отвечает 302 на подписанный mp4: редирект раскрутит плеер
            -- (OkHttp), заголовки источника применятся ко всему потоку.
            -- Без Referer video.sibnet.ru отдаёт 403 — проверено.
            headers = { ["Referer"] = "https://video.sibnet.ru/" },
        },
    }
end

local PLAYER_KINDS = { [4] = "kodik", [2] = "alloha", [1] = "aksor", [7] = "sibnet" }

local RESOLVERS = {
    kodik  = resolveKodik,
    alloha = resolveAlloha,
    aksor  = resolveAksor,
    sibnet = resolveSibnet,
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

-- pages — iframe → ответ общего http_get_batch (для aksor/sibnet там nil:
-- у них свои настройки http_get, в batch их передать нельзя).
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

local function cvhSource(item)
    local r = http_get(CVH_API .. "/video/" .. item.vkId, { headers = CVH_HDR })
    if not r.success then return nil end
    local data = json_parse(r.body)
    local hls = data and data.sources and data.sources.hlsUrl
    if type(hls) ~= "string" or hls == "" then return nil end
    -- Заголовки потока НЕ задаём: подписанные сегменты okcdn (путь .../sig/<подпись>/...)
    -- отвечают 400, если в запросе есть Referer или Origin. Проверено: без них
    -- сегмент 200, с ними 400 при любом User-Agent. Referer/Origin нужны только
    -- для API-запросов плагина, см. CVH_HDR выше.
    return { url = hls, quality = voiceLabel(item) }
end

-- Варианты CVH (запасной источник) — в конец списка, после плееров сайта.
local function appendCvhSources(episodeUrl, number, sources, seen)
    local id = shikimoriId(fetchDetail(episodeUrl))
    if not id then return end
    local items = fetchPlaylist(id)
    if not items then return end
    -- "57-58"/"119+120" → ведущее число серии
    local ep = tonumber(number) or tonumber(number:match("^%d+"))
    if not ep then return end
    local matched = {}
    for _, it in ipairs(items) do
        if it.episode == ep then matched[#matched + 1] = it end
    end
    if #matched == 0 then return end
    table.sort(matched, compareVoices)
    for _, it in ipairs(matched) do
        local ok, src = pcall(cvhSource, it)
        if ok then
            pushSource(sources, seen, src)
        else
            log_error("YummyAnime: CVH " .. tostring(src))
        end
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

    local id = shikimoriId(fetchDetail(API .. "/anime/" .. slug))
    if not id then return nil end
    local items = fetchPlaylist(id)
    if not items then return nil end

    local matched = {}
    for _, it in ipairs(items) do
        if it.season == season and it.episode == episode then
            matched[#matched + 1] = it
        end
    end
    if #matched == 0 then return nil end
    table.sort(matched, compareVoices)

    local sources, seen = {}, {}
    for _, it in ipairs(matched) do
        local ok, src = pcall(cvhSource, it)
        if ok then
            pushSource(sources, seen, src)
        else
            log_error("YummyAnime: CVH " .. tostring(src))
        end
    end
    if #sources == 0 then return nil end
    return sources
end

function getVideoList(episodeUrl)
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

    local sources, seen = {}, {}
    -- Стандарт getVideoList (см. guide): iframe'ы этой серии грузим одним
    -- http_get_batch. В batch идут только kodik/alloha (им нужен page);
    -- aksor/sibnet ходят своим http_get — у них свои настройки, которых
    -- в batch передать нельзя, им page не нужен (3-й аргумент игнорируют).
    local recs, urls, urlSeen = {}, {}, {}
    for _, rec in ipairs(videos) do
        if type(rec) == "table" and rec.number == number then
            recs[#recs + 1] = rec
            local kind = playerKind(rec)
            local iframe = type(rec.iframe_url) == "string" and rec.iframe_url or nil
            if iframe and iframe ~= "" and (kind == "kodik" or kind == "alloha") then
                local u = embedUrl(iframe)
                if not urlSeen[u] then
                    urlSeen[u] = true
                    urls[#urls + 1] = u
                end
            end
        end
    end
    local pages = {}
    if #urls > 0 then
        local rs = http_get_batch(urls, {})
        for i, u in ipairs(urls) do pages[u] = rs[i] end
    end
    for _, rec in ipairs(recs) do
        resolveRecord(rec, sources, seen, pages)
    end
    appendCvhSources(episodeUrl, number, sources, seen)
    if #sources == 0 then return nil end
    return sources
end

function getUserAgentPreset()
    return "Chrome Mobile"
end
