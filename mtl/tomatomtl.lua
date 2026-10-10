-- ═══════════════════════════════════════════════════════════════════════════
-- TomatoMTL plugin for NoveLA
-- Китайские новеллы с MTL-переводом (tomatomtl.com). Главы зашифрованы
-- AES-128-CBC — ключ/iv/шифртекст в base64 прямо в HTML страницы главы.
-- ── Metadata ───────────────────────────────────────────────────────────────
id = "tomatomtl"
name = "TomatoMTL"
version = "1.1.0"
baseUrl = "https://tomatomtl.com"
language = "MTL"
icon = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/tomatomtl.png"

-- GUARD: old app builds without the engine APIs (base64_decode_bytes/aes_decrypt).
-- Called from every public function; show_error is async in prod, hence the
-- error(..., 0) after it (the adapter surfaces pending-show-error first).
local function ensureEngine()
    local missing = {}
    if rawget(_G, "base64_decode_bytes") == nil then missing[#missing + 1] = "base64_decode_bytes" end
    if rawget(_G, "aes_decrypt") == nil then missing[#missing + 1] = "aes_decrypt" end
    if #missing > 0 then
        show_error("Update NoveLA required",
            "This plugin needs new functions (" .. table.concat(missing, ", ") ..
            "). Please update the app to the latest version.")
        error("A newer version of the app is required: " .. table.concat(missing, ","), 0)
    end
end

-- ── Settings keys ──────────────────────────────────────────────────────────
local PREF_MODE = "tomatomtl_mode" -- "raw" | "google" | "cina"

-- ── Helpers ────────────────────────────────────────────────────────────────

local _pageCache = {} -- кэш HTML страниц книг

local function fetchPage(url)
    if _pageCache[url] then
        return _pageCache[url]
    end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- Упрощённый стандартный прогон контента: нормализация → вырезание строк
-- с доменом сайта (водяные знаки/реклама) → trim.
local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "(?im)^[^\\n\\r]*tomatomtl\\.com[^\\n\\r]*\\n?", "")
    return string_trim(text)
end

-- ── Перевод названий ─────────────────────────────────────────────────────────
-- Режим перевода: raw = всё китайское; google/cina = всё на английском.

local function getMode()
    local mode = get_preference(PREF_MODE)
    if mode == "" then mode = "google" end
    return mode
end

-- Потолок пачки — по РАЗМЕРУ закодированного URL: сайт/движок тянет до 8к
-- символов, режем на 7000 с запасом. Число строк в пачке плавающее.
local NAMES_CHUNK_CHARS = 7000

-- Google Translate (публичный ключ/URL с сайта tomatomtl.com)
local function translateGoogleUrl(chunk)
    return "https://translate-pa.googleapis.com/v1/translate?params.client=gtx" ..
        "&query.source_language=zh-CN&query.target_language=en&query.display_language=en-US" ..
        "&data_types=TRANSLATION&key=AIzaSyDLEeFI5OtFBwYBIoK_jj5m32rZK5CkCXA&query.text=" ..
        url_encode(chunk)
end

local function translateGoogle(chunk)
    local r = http_get(translateGoogleUrl(chunk))
    if not r.success then
        return nil
    end
    local data = json_parse(r.body)
    if not data or type(data.translation) ~= "string" or data.translation == "" then
        return nil
    end
    return data.translation
end

-- Разбор маркеров [i] по ВСЕМУ ответу, а не построчно: google склеивает
-- строки (в одну запись попадала смесь глав), меняет переводы строк и
-- теряет маркеры. Берём текст между соседними маркерами; повторный
-- маркер с тем же номером не перетирает первый. Внутренние переводы
-- строк схлопываем в пробел — заголовок не должен быть многострочным.
local function parseMarkers(translated, n)
    local marks = {}
    for s, idx, e in translated:gmatch("()%[%s*(%d+)%s*%]()") do
        local i = tonumber(idx)
        if i >= 0 and i < n then
            marks[#marks + 1] = { s = s, e = e, i = i }
        end
    end
    local map = {}
    for k, m in ipairs(marks) do
        if map[m.i] == nil then
            local stop = marks[k + 1] and (marks[k + 1].s - 1) or #translated
            local text = translated:sub(m.e + 1, stop)
            text = text:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" then
                map[m.i] = text
            end
        end
    end
    return map
end

-- Один проход перевода по списку индексов lines: нарезка пачек по бюджету
-- URL → маркируем → один http_get_batch → разбор по маркерам.
-- Возвращает got[i]=перевод и failed — индексы без перевода.
local function translatePass(lines, idxs)
    local chunks, cur, curSize = {}, {}, 0
    for _, i in ipairs(idxs) do
        -- маркер "[i] " + сама строка; +16 — запас на percent-кодировку
        local enc = #url_encode(lines[i]) + 16
        if #cur > 0 and curSize + enc > NAMES_CHUNK_CHARS then
            chunks[#chunks + 1] = cur
            cur, curSize = {}, 0
        end
        cur[#cur + 1] = i
        curSize = curSize + enc
    end
    if #cur > 0 then chunks[#chunks + 1] = cur end

    local urls = {}
    for ci, ch in ipairs(chunks) do
        local marked = {}
        for k, i in ipairs(ch) do
            marked[k] = "[" .. tostring(k - 1) .. "] " .. lines[i]
        end
        urls[ci] = translateGoogleUrl(table.concat(marked, "\n"))
    end
    local results = http_get_batch(urls)

    local got, failed = {}, {}
    for ci, ch in ipairs(chunks) do
        local translated = nil
        local res = results[ci]
        if res and res.success then
            local data = json_parse(res.body)
            if data and type(data.translation) == "string" and data.translation ~= "" then
                translated = data.translation
            end
        end
        local map = translated and parseMarkers(translated, #ch) or nil
        for k, i in ipairs(ch) do
            local t = map and map[k - 1]
            if t then
                got[i] = t
            else
                failed[#failed + 1] = i
            end
        end
    end
    return got, failed
end

-- Переводит массив названий батчем, как сайт: join('\n') → запрос →
-- разбор по маркерам. Пачки режутся по РАЗМЕРУ закодированного URL
-- (NAMES_CHUNK_CHARS), а не по числу строк, и шлются все разом через
-- http_get_batch (параллельная загрузка движка, как в en/novelfull.lua).
-- Непереведённые после первого прохода (сбой пачки/потерянные маркеры)
-- повторяются ОДИН раз — только они, не весь список. Остаток → оригинал.
local function translateNamesBatch(lines)
    if #lines == 0 then return {} end
    local all = {}
    for i = 1, #lines do all[i] = i end

    local got, failed = translatePass(lines, all)
    if #failed > 0 then
        local got2, failed2 = translatePass(lines, failed)
        for i, t in pairs(got2) do got[i] = t end
        failed = failed2
    end
    if #failed > 0 then
        log_error("tomatomtl: " .. #failed .. " названий не перевелись, возвращаю оригиналы")
    end

    local out = {}
    for i, line in ipairs(lines) do
        out[i] = got[i] or line
    end
    return out
end

-- Переводит названия в списке записей (каталог/поиск/главы), если режим
-- не raw. Названия ВСЕГДА google-батчем (на сайте названия google-ом;
-- cina медленный). Мутирует item.title на месте, остальное не трогает.
local function applyTitleTranslation(items)
    local mode = getMode()
    if mode == "raw" or #items == 0 then
        return items
    end
    local titles = {}
    for _, item in ipairs(items) do
        titles[#titles + 1] = item.title
    end
    local translated = translateNamesBatch(titles)
    for i, item in ipairs(items) do
        item.title = translated[i] or item.title
    end
    return items
end

-- ── Settings schema ──────────────────────────────────────────────────────────

function getSettingsSchema()
    ensureEngine()
    return {{
        key = PREF_MODE,
        type = "select",
        label = "Translation mode",
        current = "google",
        options = {{
            value = "raw",
            label = "Raw (Chinese)"
        }, {
            value = "google",
            label = "Google Translate (fast)"
        }, {
            value = "cina",
            label = "CinaNMT"
        }}
    }}
end

-- ── Каталог ─────────────────────────────────────────────────────────────────

-- Подписи x-signature у обложек fanqie-explorer живут считанные минуты, а
-- ответ сервера бывает отдан с уже протухшим x-expires — тогда CDN отдаёт 403.
-- Сайт в этом случае грузит картинку через wsrv.nl (tomato.js, link_cover):
-- срезаем query и "~..."-суффикс, хост меняем на p6-novel.byteimg.com/origin.
local function cover_via_proxy(cover)
    local u = cover:gsub("^https://", ""):gsub("^http://", "")
    local parts = {}
    for seg in u:gmatch("[^/]+") do
        local part = seg
        if part:find("[?~]") then
            part = part:match("^[^~]*")
        end
        parts[#parts + 1] = part
    end
    -- как в link_cover: первый сегмент (хост) заменяется на origin-заглушку
    parts[1] = "https://wsrv.nl/?url=https://p6-novel.byteimg.com/origin"
    return table.concat(parts, "/") .. "&w=225&h=300&fit=cover&output=webp"
end

local function buildCatalogItem(book)
    local cover = book.thumb_url or ""
    if cover ~= "" then
        cover = cover:gsub("/origin/origin/", "/origin/")
        -- поисковый API отдаёт обложки по http — CDN отвечает 301 text/html
        cover = cover:gsub("^http://", "https://")
        -- 10с запас на сетевую латентность; при протухшей подписи — wsrv
        local exp = cover:match("x%-expires=(%d+)")
        if exp and tonumber(exp) <= os.time() + 10 then
            cover = cover_via_proxy(cover)
        end
    end
    local item = {
        title = string_clean(book.book_name or ""),
        url = baseUrl .. "/book/" .. tostring(book.book_id)
    }
    if cover ~= "" then
        item.cover = cover
    end
    local score = book.score or ""
    if score ~= "" then
        item.rating = "Rating: " .. score .. "/10"
    end
    return item
end

-- ── Фильтры (эндпоинт /fanqie-explorer, параметры как у сайта) ──────────────

function getFilterList()
    ensureEngine()
    return {
        {
            type = "select",
            key = "gender",
            label = "Gender",
            defaultValue = "-1",
            options = {
                { value = "-1", label = "All" },
                { value = "1", label = "Male" },
                { value = "0", label = "Female" },
            }
        },
        {
            type = "select",
            key = "category",
            label = "Category",
            defaultValue = "-1",
            options = {
                { value = "-1", label = "All" },
            { value = "1317", label = "Theme: Historical Romance & Political Intrigue" },
            { value = "1169", label = "Theme: Suspense Romance" },
            { value = "1012", label = "Theme: Pure Love" },
            { value = "1079", label = "Theme: Derivative / Fanfiction" },
            { value = "558", label = "Theme: Political Journey" },
            { value = "1058", label = "Theme: Comprehensive Film And TV Works" },
            { value = "658", label = "Theme: Natural Disaster" },
            { value = "871", label = "Theme: First-person Perspective" },
            { value = "873", label = "Theme: Cyberpunk" },
            { value = "855", label = "Theme: The Fourth Calamity" },
            { value = "851", label = "Theme: Rule-based Horror Stories" },
            { value = "758", label = "Theme: Ancient Times" },
            { value = "10", label = "Theme: Suspense" },
            { value = "705", label = "Theme: Cthulhu" },
            { value = "516", label = "Theme: Urban Superpowers" },
            { value = "515", label = "Theme: Post-Apocalyptic Survival" },
            { value = "514", label = "Theme: Spiritual Recovery" },
            { value = "513", label = "Theme: High-level Martial Arts World" },
            { value = "512", label = "Theme: Otherworldly Continent" },
            { value = "511", label = "Theme: Eastern Fantasy" },
            { value = "507", label = "Theme: Spy Warfare" },
            { value = "503", label = "Theme: Qing Dynasty" },
            { value = "501", label = "Theme: Song Dynasty" },
            { value = "500", label = "Theme: Breaking The Mold" },
            { value = "497", label = "Theme: Military General" },
            { value = "496", label = "Theme: National Destiny" },
            { value = "485", label = "Theme: Workplace And Business Battles" },
            { value = "481", label = "Theme: Angsty Deep Love" },
            { value = "474", label = "Theme: Love Over Time" },
            { value = "473", label = "Theme: Prestigious Families" },
            { value = "465", label = "Theme: Comprehensive Manga" },
            { value = "464", label = "Theme: Otherworldly Transmigration" },
            { value = "460", label = "Theme: Exclusive Doting" },
            { value = "453", label = "Theme: Starting Plot" },
            { value = "452", label = "Theme: Alternate History/Fictional Setting" },
            { value = "259", label = "Theme: Fantasy Xianxia" },
            { value = "1", label = "Theme: Metropolis" },
            { value = "3", label = "Theme: Modern Romance" },
            { value = "5", label = "Theme: Ancient Romance" },
            { value = "7", label = "Theme: Fantasy" },
            { value = "12", label = "Theme: History" },
            { value = "15", label = "Theme: Sports" },
            { value = "16", label = "Theme: Martial arts/Wuxia" },
            { value = "32", label = "Theme: Fantasy Romance" },
            { value = "29", label = "Roles: CEO" },
            { value = "91", label = "Roles: Multiple Female Heroine" },
            { value = "25", label = "Roles: Live-in Son-in-law" },
            { value = "865", label = "Roles: Loyal And Devoted Partner" },
            { value = "856", label = "Roles: Almighty" },
            { value = "853", label = "Roles: White On The Outside, Black On The Inside" },
            { value = "849", label = "Roles: Two Grade-A-student" },
            { value = "1456", label = "Roles: High Status, Great Power" },
            { value = "521", label = "Roles: Drama Queen" },
            { value = "520", label = "Roles: Big Boss (Influential Figure)" },
            { value = "519", label = "Roles: Young Lady" },
            { value = "518", label = "Roles: Agent" },
            { value = "509", label = "Roles: Gaming Streamer" },
            { value = "506", label = "Roles: Detective" },
            { value = "502", label = "Roles: Royalty And Nobility" },
            { value = "498", label = "Roles: Emperor" },
            { value = "492", label = "Roles: General (Military)" },
            { value = "491", label = "Roles: Poisonous Doctor" },
            { value = "490", label = "Roles: Female Chefs" },
            { value = "488", label = "Roles: Lawyer" },
            { value = "487", label = "Roles: Doctor" },
            { value = "486", label = "Roles: Celebrity" },
            { value = "470", label = "Roles: Stand-In" },
            { value = "469", label = "Roles: Dual Personality" },
            { value = "468", label = "Roles: Iceberg" },
            { value = "459", label = "Roles: Quirky And Witty" },
            { value = "455", label = "Roles: Match Made In Heaven" },
            { value = "454", label = "Roles: Both Cool And Sweet" },
            { value = "392", label = "Roles: No Romantic Pairings" },
            { value = "389", label = "Roles: Single Female Heroine" },
            { value = "385", label = "Roles: Campus Belle" },
            { value = "391", label = "Roles: No Female Heroine" },
            { value = "380", label = "Roles: Yandere" },
            { value = "378", label = "Roles: Empress (Female Emperor)" },
            { value = "375", label = "Roles: Special Forces" },
            { value = "369", label = "Roles: Villain" },
            { value = "28", label = "Roles: Adorable Baby" },
            { value = "26", label = "Roles: Divine Doctor" },
            { value = "30", label = "Roles: Spoiling The Wife" },
            { value = "42", label = "Roles: Stay-at-Home Dad" },
            { value = "82", label = "Roles: Academic Genius" },
            { value = "83", label = "Roles: Princess" },
            { value = "84", label = "Roles: Empress" },
            { value = "85", label = "Roles: Princess Consort" },
            { value = "86", label = "Roles: Strong Female Lead" },
            { value = "87", label = "Roles: Imperial Uncle" },
            { value = "88", label = "Roles: Legitimate Daughter" },
            { value = "89", label = "Roles: Pokemon" },
            { value = "90", label = "Roles: Genius" },
            { value = "92", label = "Roles: Cunning And Manipulative" },
            { value = "93", label = "Roles: Playing Dumb To Outsmart Others" },
            { value = "94", label = "Roles: Group Favorite" },
            { value = "747", label = "Plot: Female-Targeted Mystery" },
            { value = "1141", label = "Plot: Western Fantasy" },
            { value = "1140", label = "Plot: Eastern Xianxia" },
            { value = "1139", label = "Plot: Ancient-Style Social Realism" },
            { value = "8", label = "Plot: Post-apocalyptic Sci-Fi" },
            { value = "1016", label = "Plot: Male-oriented Derivative Works" },
            { value = "1015", label = "Plot: Female-Oriented Derivatives" },
            { value = "1017", label = "Plot: Romance In The Republic Of China Era" },
            { value = "1014", label = "Plot: Urban High-level Martial Arts" },
            { value = "751", label = "Plot: Suspense And Supernatural" },
            { value = "539", label = "Plot: Creative Suspense" },
            { value = "504", label = "Plot: Resistance And Espionage During War" },
            { value = "749", label = "Plot: Youthful Sweet Romance" },
            { value = "275", label = "Plot: Two Male Leads" },
            { value = "253", label = "Plot: Creative Ancient Romance" },
            { value = "273", label = "Plot: Ancient History" },
            { value = "272", label = "Plot: Creative Take On History" },
            { value = "267", label = "Plot: Modern Brainstorming" },
            { value = "263", label = "Plot: Urban Farming" },
            { value = "262", label = "Plot: Urban Brainstorming" },
            { value = "261", label = "Plot: Urban Daily Life" },
            { value = "257", label = "Plot: Fantasy Brainstorming" },
            { value = "248", label = "Plot: Fantasy Romance" },
            { value = "246", label = "Plot: Palace Intrigue And Family Struggles" },
            { value = "748", label = "Plot: Elite CEO" },
            { value = "27", label = "Plot: Warlord As A Live-In Son-in-Law" },
            { value = "718", label = "Plot: Anime Derivatives" },
            { value = "745", label = "Plot: Glittering Stardom" },
            { value = "746", label = "Plot: Gaming And Sports" },
            { value = "750", label = "Plot: Workplace Romance" },
            { value = "704", label = "Plot: Two Female Leads" },
            { value = "258", label = "Plot: Traditional Fantasy" },
            { value = "124", label = "Plot: Urban Cultivation" },
            { value = "79", label = "Plot: Era-Based" },
            { value = "23", label = "Plot: Farm" },
            { value = "24", label = "Plot: Quick Transmigration" },
            { value = "1458", label = "Plot: Substitute Marriage" },
            { value = "1459", label = "Plot: Romancing the Villain" },
            { value = "1455", label = "Plot: Feng Shui Secret Arts" },
            { value = "1062", label = "Plot: God Slayer Derivatives" },
            { value = "1060", label = "Plot: Ten Days Derivative" },
            { value = "373", label = "Plot: Journey To The West Derivative Works" },
            { value = "1037", label = "Plot: Derivatives Of Public Domain Works" },
            { value = "1036", label = "Plot: Dream Of The Red Chamber Derivative Works" },
            { value = "1035", label = "Plot: Zhen Huan Derivative Works" },
            { value = "1034", label = "Plot: Ruyi's Royal Love In The Palace Derivatives" },
            { value = "1460", label = "Plot: Urban Jianghu" },
            { value = "1457", label = "Plot: Second Male Lead Becomes the ML" },
            { value = "537", label = "Plot: Thriller Games" },
            { value = "872", label = "Plot: Pursuing A Husband" },
            { value = "874", label = "Plot: Card Games" },
            { value = "875", label = "Plot: Classic Of Mountains And Seas" },
            { value = "876", label = "Plot: Transmigration Before Birth" },
            { value = "867", label = "Plot: Ghost Hunting" },
            { value = "868", label = "Plot: Sword Cultivation" },
            { value = "869", label = "Plot: Post-Apocalyptic" },
            { value = "860", label = "Plot: Mutual Redemption" },
            { value = "861", label = "Plot: Spoiling The Husband" },
            { value = "864", label = "Plot: Instances Dungeons" },
            { value = "854", label = "Plot: Black Technology" },
            { value = "850", label = "Plot: Pure Enjoyment Without Depth" },
            { value = "852", label = "Plot: Soul Transmigration" },
            { value = "845", label = "Plot: Master Descends The Mountain" },
            { value = "846", label = "Plot: Dark Transformation" },
            { value = "847", label = "Plot: Raising Children" },
            { value = "848", label = "Plot: Age Gap" },
            { value = "843", label = "Plot: Self-delusion Comedy" },
            { value = "844", label = "Plot: Real And Fake Heiresses" },
            { value = "839", label = "Plot: Reunion After A Long Separation" },
            { value = "840", label = "Plot: Rags To Riches" },
            { value = "838", label = "Plot: No Harem" },
            { value = "835", label = "Plot: Upbringing" },
            { value = "836", label = "Plot: Mutual Pampering" },
            { value = "837", label = "Plot: Struggle For Supremacy" },
            { value = "834", label = "Plot: 1v1" },
            { value = "830", label = "Plot: Level-Up Style" },
            { value = "831", label = "Plot: Soul Swap" },
            { value = "832", label = "Plot: Imperial Examinations" },
            { value = "829", label = "Plot: Younger Partner" },
            { value = "34", label = "Plot: Marriage And Romance" },
            { value = "731", label = "Plot: Investiture Of The Gods" },
            { value = "495", label = "Plot: Courtyard Dwellings (Hutongs)" },
            { value = "508", label = "Plot: Esports" },
            { value = "524", label = "Plot: Double Reincarnation" },
            { value = "523", label = "Plot: Past And Present Lives" },
            { value = "702", label = "Plot: Mutual Purity" },
            { value = "616", label = "Plot: Regretful ML" },
            { value = "11", label = "Plot: Countryside" },
            { value = "557", label = "Plot: Escaping Famine" },
            { value = "538", label = "Plot: Doujin" },
            { value = "522", label = "Plot: Face-Slapping" },
            { value = "505", label = "Plot: Solving Cases" },
            { value = "494", label = "Plot: Stockpiling Supplies" },
            { value = "493", label = "Plot: Fishing" },
            { value = "484", label = "Plot: Happy Ending" },
            { value = "483", label = "Plot: Enemies to Lovers" },
            { value = "482", label = "Plot: Secret Crush" },
            { value = "480", label = "Plot: Runaway Marriage" },
            { value = "479", label = "Plot: Pregnant And Running Away" },
            { value = "478", label = "Plot: Strong Vs. Strong" },
            { value = "477", label = "Plot: Love At First Sight" },
            { value = "476", label = "Plot: Mutual Effort In Love" },
            { value = "475", label = "Plot: Reuniting After Separation" },
            { value = "471", label = "Plot: Arranged Marriage" },
            { value = "467", label = "Plot: Hidden Marriage" },
            { value = "466", label = "Plot: Flash Marriage" },
            { value = "463", label = "Plot: Modern To Ancient Time-Travel" },
            { value = "462", label = "Plot: Ancient-to-Modern Time Travel" },
            { value = "461", label = "Plot: Group Transmigration" },
            { value = "458", label = "Plot: Protective Of Loved Ones" },
            { value = "457", label = "Plot: Tormenting Scumbags" },
            { value = "456", label = "Plot: Exclusive Love" },
            { value = "266", label = "Plot: Alternate Identity" },
            { value = "265", label = "Plot: Married First, Love Later" },
            { value = "247", label = "Plot: Medical Skills" },
            { value = "372", label = "Plot: Online Game" },
            { value = "367", label = "Plot: Ultraman Doujin" },
            { value = "379", label = "Plot: Survival" },
            { value = "388", label = "Plot: Woman Disguised As A Man" },
            { value = "387", label = "Plot: Childhood Sweethearts" },
            { value = "384", label = "Plot: Invincible" },
            { value = "390", label = "Plot: Republic Of China Era" },
            { value = "383", label = "Plot: Uncle Nine" },
            { value = "382", label = "Plot: Transmigration Into A Book" },
            { value = "381", label = "Plot: Chat Group" },
            { value = "377", label = "Plot: Qin Dynasty" },
            { value = "376", label = "Plot: Dragon Ball" },
            { value = "374", label = "Plot: Marvel" },
            { value = "371", label = "Plot: Pokémon" },
            { value = "370", label = "Plot: Pirates/One Piece" },
            { value = "368", label = "Plot: Naruto" },
            { value = "127", label = "Plot: Workplace" },
            { value = "126", label = "Plot: Ming Dynasty" },
            { value = "125", label = "Plot: Family" },
            { value = "67", label = "Plot: Three Kingdoms" },
            { value = "68", label = "Plot: Eschatology" },
            { value = "69", label = "Plot: Livestreaming" },
            { value = "70", label = "Plot: Infinite Flow" },
            { value = "71", label = "Plot: Myriad Worlds And Realms" },
            { value = "72", label = "Plot: Beast World" },
            { value = "73", label = "Plot: Tang Dynasty" },
            { value = "74", label = "Plot: Pets" },
            { value = "75", label = "Plot: Food Delivery" },
            { value = "76", label = "Plot: Qing Dynasty Transmigration" },
            { value = "77", label = "Plot: Interstellar" },
            { value = "78", label = "Plot: Cuisine" },
            { value = "80", label = "Plot: Way Of The Sword" },
            { value = "81", label = "Plot: Tomb Raiding" },
            { value = "95", label = "Plot: Angsty Stories" },
            { value = "96", label = "Plot: Sweet Pet" },
            { value = "100", label = "Plot: Supernatural" },
            { value = "4", label = "Plot: School Life" },
            { value = "17", label = "Plot: Antique Appraisal" },
            { value = "19", label = "Plot: System" },
            { value = "20", label = "Plot: Divine Tycoon" },
            { value = "36", label = "Plot: Rebirth" },
            { value = "37", label = "Plot: Transmigration" },
            { value = "39", label = "Plot: Anime/2D Culture" },
            { value = "40", label = "Plot: Islands" },
            { value = "43", label = "Plot: Entertainment Industry" },
            { value = "44", label = "Plot: Space/Dimension" },
            { value = "61", label = "Plot: Mystery And Deduction" },
            { value = "66", label = "Plot: Ancient World" },
            }
        },
        {
            type = "select",
            key = "creation_status",
            label = "Status",
            defaultValue = "-1",
            options = {
                { value = "-1", label = "All" },
                { value = "0", label = "Completed" },
                { value = "1", label = "Ongoing" },
            }
        },
        {
            type = "select",
            key = "word_count",
            label = "Word Count",
            defaultValue = "-1",
            options = {
                { value = "-1", label = "All" },
                { value = "0", label = "Below 300k" },
                { value = "1", label = "300k-500k" },
                { value = "2", label = "500k-1M" },
                { value = "3", label = "1M-2M" },
                { value = "4", label = "Above 2M" },
            }
        },
        {
            type = "select",
            key = "sort",
            label = "Sort By",
            defaultValue = "0",
            options = {
                { value = "0", label = "Most Popular" },
                { value = "1", label = "Latest" },
                { value = "2", label = "Word Count" },
            }
        },
    }
end

-- Общий запрос к ajax-эндпоинту fanqie-explorer (page_index с 0, как в JS сайта)
local function fetchExplorer(index, params)
    local url = baseUrl .. "/fanqie-explorer?ajax=1&page_index=" .. tostring(index) ..
        "&page_count=18" ..
        "&gender=" .. (params and params.gender or "-1") ..
        "&creation_status=" .. (params and params.creation_status or "-1") ..
        "&word_count=" .. (params and params.word_count or "-1") ..
        "&sort=" .. (params and params.sort or "0") ..
        "&category_id=" .. (params and params.category_id or "-1")
    local r = http_get(url)
    if not r.success then
        log_error("tomatomtl: fanqie-explorer failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end
    local data = json_parse(r.body)
    if not data or not data.books then
        log_error("tomatomtl: cannot parse fanqie-explorer JSON")
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, book in ipairs(data.books) do
        table.insert(items, buildCatalogItem(book))
    end
    return { items = applyTitleTranslation(items), hasNext = (data.has_more == true) }
end

function getCatalogList(index)
    ensureEngine()
    return fetchExplorer(index, nil)
end

function getCatalogFiltered(index, filters)
    ensureEngine()
    return fetchExplorer(index, {
        gender = filters["gender"],
        category_id = filters["category"],
        creation_status = filters["creation_status"],
        word_count = filters["word_count"],
        sort = filters["sort"],
    })
end

-- ── Поиск ───────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    ensureEngine()
    if index > 0 then
        return { items = {}, hasNext = false }
    end
    local r = http_post(baseUrl .. "/api/search-proxy.php", json_stringify({
        query = query,
        page_index = index,
        page_count = 10,
        query_type = 0
    }), {
        headers = {
            ["Referer"] = baseUrl .. "/search?q=" .. url_encode(query)
        }
    })
    if not r.success then
        log_error("tomatomtl: getCatalogSearch failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end
    local data = json_parse(r.body)
    if not data or not data.search_tabs or not data.search_tabs[1] then
        log_error("tomatomtl: cannot parse search JSON")
        return { items = {}, hasNext = false }
    end
    local items = {}
    local tab = data.search_tabs[1]
    for _, entry in ipairs(tab.data or {}) do
        for _, book in ipairs(entry.book_data or {}) do
            table.insert(items, buildCatalogItem(book))
        end
    end
    return { items = applyTitleTranslation(items), hasNext = (#items >= 10) }
end

-- ── Детали книги ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- og:title серверный и надёжный; h1.book-title в raw-curl пуст (заполняется JS)
    local title = html_attr(body, "meta[property='og:title']", "content")
    if title == "" then
        local el = html_select_first(body, "h1.book-title")
        if el then
            title = string_clean(el.text)
        end
    end
    if title == "" then return nil end
    if getMode() == "raw" then
        return title
    end
    local translated = translateGoogle(title)
    if translated then
        return translated
    end
    log_error("tomatomtl: перевод названия книги не удался, возвращаю оригинал")
    return title
end

function getBookCoverImageUrl(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "img.book-cover", "src")
    if cover == "" then
        cover = html_attr(body, "img.book-cover", "data-src")
    end
    return cover ~= "" and cover or nil
end

function getBookDescription(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local desc = html_attr(body, "meta[name=description]", "content")
    return desc ~= "" and desc or nil
end

function getBookGenres(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local genres = {}
    for _, el in ipairs(html_select(body, "a[href*='categories']")) do
        local g = string_clean(el.text)
        if g ~= "" then
            table.insert(genres, g)
        end
    end
    return genres
end

function getBookStatus(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, el in ipairs(html_select(body, ".book-meta-item")) do
        local status = el.text and el.text:match("Status:%s*([^|]+)")
        if status then
            local s = string_clean(status)
            if s ~= "" then
                return s
            end
        end
    end
    return nil
end

function getBookRating(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, el in ipairs(html_select(body, ".book-meta-item")) do
        local score = el.text and el.text:match("Score:%s*([%d%.]+)")
        if score then
            return "Rating: " .. score .. "/10"
        end
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, el in ipairs(html_select(body, ".book-meta-item")) do
        local iso = el.text and el.text:match("Last Updated:%s*([%d%-]+T[%d:]+)")
        if iso then
            return string.sub(iso, 1, 10)
        end
    end
    return nil
end

-- ── Список глав ─────────────────────────────────────────────────────────────

local _chapterTitlesCache = {} -- кэш переведённого списка глав по bookUrl

function getChapterList(bookUrl)
    ensureEngine()
    if getMode() ~= "raw" and _chapterTitlesCache[bookUrl] then
        return _chapterTitlesCache[bookUrl]
    end
    local bookId = string.match(bookUrl, "/book/(%d+)")
    if not bookId then
        log_error("tomatomtl: cannot extract book id from " .. tostring(bookUrl))
        return {}
    end
    local r = http_get(baseUrl .. "/catalog/" .. bookId)
    if not r.success then
        log_error("tomatomtl: chapters API failed code=" .. tostring(r.code))
        return {}
    end
    local data = json_parse(r.body)
    if type(data) ~= "table" then
        log_error("tomatomtl: cannot parse chapters JSON")
        return {}
    end
    local chapters = {}
    for _, ch in ipairs(data) do
        local title = string_clean(ch.title or "")
        if title ~= "" and ch.id then
            table.insert(chapters, {
                title = title,
                url = baseUrl .. "/book/" .. bookId .. "/" .. tostring(ch.id) .. "/"
            })
        end
    end
    -- Пост-фильтр: главы с пустым/пробельным названием (google может потерять
    -- маркер/строку, в сырых данных тоже встречаются пустые) и дубликаты по url
    local filtered = {}
    local seen = {}
    for _, ch in ipairs(chapters) do
        local title = ch.title or ""
        if title ~= "" and not string.match(title, "^%s*$") and not seen[ch.url] then
            seen[ch.url] = true
            filtered[#filtered + 1] = ch
        end
    end
    chapters = filtered
    -- Перевод названий глав (google-батч) вне raw-режима
    if getMode() ~= "raw" and #chapters > 0 then
        chapters = applyTitleTranslation(chapters)
        _chapterTitlesCache[bookUrl] = chapters
    end
    return chapters
end

-- NOTE: намеренно НЕ через fetchPage — хэш должен отражать свежее состояние
function getChapterListHash(bookUrl)
    ensureEngine()
    local bookId = string.match(bookUrl, "/book/(%d+)")
    if not bookId then
        return nil
    end
    local r = http_get(baseUrl .. "/catalog/" .. bookId)
    if not r.success then
        return nil
    end
    local data = json_parse(r.body)
    if type(data) ~= "table" then
        return nil
    end
    return tostring(#data)
end

-- ── Текст главы ─────────────────────────────────────────────────────────────

local TRANSLATE_CHUNK_SIZE = 4500

local function translateCina(chunk)
    local r = http_post("https://cina.tomatomtl.com/translate?token=tomatomtl",
        json_stringify({
            text = chunk,
            target_lang = "EN",
            source_lang = "ZH"
        }), {
        headers = {
            ["Authorization"] = "Bearer tomatomtl"
        }
    })
    if not r.success then
        return nil
    end
    local data = json_parse(r.body)
    if not data or data.code ~= 200 or not data.data or data.data == "" then
        return nil
    end
    return data.data
end

function getChapterText(html, url)
    ensureEngine()
    local uc = html:match('unlock_code%s*=%s*"([^"]+)"')
    if not uc then
        show_error("Chapter load error", "Unable to find the decryption key on the page.")
        return nil
    end

    -- encryptedData есть только у залогиненного; у анонима — заглушка Login Required.
    -- Через json_parse, а не регэксп: сайт сериализует JSON с экранированием «\/»,
    -- и сырой захват оставляет бэкслэш внутри base64 → декодер падает.
    local blk = html:match('encryptedData%s*=%s*(%b{})')
    local obj = blk and json_parse(blk)
    local iv = obj and obj.iv
    local enc = obj and obj.enc
    if not blk or not iv or not enc then
        show_error("Login required",
            "Chapter content requires a tomatomtl.com account. Tap \"Open in browser\" to log in, then retry.",
            baseUrl .. "/user/login")
        return nil
    end

    -- key/iv декодируются движковым base64_decode_bytes (сырые байты: в
    -- base64 встречаются ≥0x80, Java-строка их портит). Ключ сайта — первые
    -- 16 байт unlock_code (AES-128); сам шифротекст движку отдаётся как есть:
    -- aes_decrypt(b64, key, iv) декодирует base64 внутри (фикс B4: key/iv —
    -- бинарные поля LuaString, не UTF-8 round-trip).
    local keyFull = base64_decode_bytes(uc)
    local ivRaw = base64_decode_bytes(iv)
    if not keyFull or #keyFull < 16 or not ivRaw or #ivRaw < 1 or not enc or #enc == 0 then
        local kst = keyFull and tostring(#keyFull) or "nil"
        local cst = enc and tostring(#enc) or "nil"
        local ist = ivRaw and tostring(#ivRaw) or "nil"
        show_error("Chapter decrypt error", "Unable to decrypt chapter content.\n\nDIAG key#" .. kst
            .. " ct#" .. cst .. " iv#" .. ist
            .. "\nuc# " .. #uc .. " uc=" .. uc
            .. "\niv=" .. (iv or "nil")
            .. "\nenc# " .. (enc and #enc or -1) .. " head=" .. (enc and enc:sub(1, 24) or "nil"))
        return nil
    end

    -- Ошибки шифра (битый padding, неверный ключ) → nil, не LuaError.
    local text = aes_decrypt(enc, keyFull:sub(1, 16), ivRaw)

    -- Честные причины отказа вместо общего «corrupted»:
    -- крошечный текст = глава-заголовок/разделитель без содержания,
    -- отсутствие китайского = расшифровка дала мусор.
    if not text or #text < 40 then
        local n = text and #text or 0
        show_error("Chapter has no content",
            "Decrypted only " .. n .. " characters — this looks like a title/divider page with no readable text.")
        return nil
    end
    local hasCJK = false
    for i = 1, #text do
        local b = string.byte(text, i)
        if b >= 228 and b <= 233 then
            hasCJK = true
            break
        end
    end
    if not hasCJK then
        show_error("Chapter decrypt failed",
            "Decrypted text contains no Chinese characters — the result is garbage, not a valid chapter.")
        return nil
    end

    text = applyStandardContentTransforms(text)

    local mode = getMode()
    if mode == "raw" then
        return text
    end

    local translate = (mode == "cina") and translateCina or translateGoogle

    -- Чанкинг по ~4500 байт, но НЕ разрезая UTF-8 символы (китайский = 3 байта):
    -- если байт сразу за границей — продолжение символа (0x80..0xBF), откатываемся.
    local chunks = {}
    local pos = 1
    while pos <= #text do
        local last = math.min(pos + TRANSLATE_CHUNK_SIZE - 1, #text)
        while last > pos and last < #text and string.byte(text, last + 1) >= 128 and string.byte(text, last + 1) <= 191 do
            last = last - 1
        end
        chunks[#chunks + 1] = text:sub(pos, last)
        pos = last + 1
    end

    local results = {}
    for _, chunk in ipairs(chunks) do
        local translated = translate(chunk)
        if translated then
            results[#results + 1] = translated
        else
            -- Не маскируем сбой: пользователь выбрал перевод и ждёт результат
            show_error("Translation failed",
                "Translation failed. Switch to Raw mode or use the built-in translator.")
            return nil
        end
    end
    return table.concat(results, "\n")
end