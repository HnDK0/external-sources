id       = "desu"
name     = "Desu"
version  = "1.1.3"
baseUrl  = "https://desu.uno/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/desu.png"
content_type = "manga"

-- Источник манги/манхвы на русском (JSON API /api/manga/). Главы — это
-- изображения: getPageList возвращает упорядоченные URL страниц главы,
-- getChapterText остаётся legacy-фолбэком для сборок приложения без
-- поддержки page-list (склеивает те же URL в <img src="...">).
--
-- Проверено живьём (2026-08-18): старые домены desu.me/desu.win/desu.city
-- мертвы, работает только desu.uno. Параметры order_by/kinds/genres/status
-- у /api/manga/catalog/ игнорируются API, поэтому фильтры идут через
-- HTML-каталог /manga/?kinds=&status=&genres=&order_by= (getCatalogFiltered),
-- а обычный каталог — через JSON API. В HTML главы нет <img> со страницами —
-- только window.MangaReader с id манги и главы; сами страницы отдаёт
-- /api/manga/<mid>/chapters/<cid>.

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function fetch(url)
    local r = http_get(url)
    if not r.success then return nil end
    return r.body
end

-- id манги из URL книги вида .../slug.<id>[/]
local function mangaId(bookUrl)
    return string.match(bookUrl, "%.(%d+)/?$")
end

-- ── API: детали книги (кэш на сессию) ──
-- Все пять функций деталей движок вызывает параллельно с одним URL —
-- кэшируем распарсенный JSON, чтобы не дублировать запросы.
local _mangaCache = {}

local function fetchApiManga(bookUrl)
    local id = mangaId(bookUrl)
    if not id then return nil end
    if _mangaCache[id] then return _mangaCache[id] end
    local body = fetch(baseUrl .. "api/manga/" .. id .. "/")
    if not body then return nil end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.manga then return nil end
    _mangaCache[id] = data.manga
    return data.manga
end

-- ── Каталог ──

function getCatalogList(index)
    local page = index + 1
    local body = fetch(baseUrl .. "api/manga/catalog/?page=" .. page .. "&limit=20")
    if not body then return { items = {}, hasNext = false } end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.mangas then
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, m in ipairs(data.mangas) do
        local title = m.russian
        if title == nil or title == "" then title = m.name end
        local item = {
            title = title,
            url = absUrl(m.view_url),
            cover = (m.cover and m.cover.preview) or "",
        }
        -- Рейтинг со шкалой 10 ("7.62/10") — рейтинговый парсер приложения
        -- нормализует его в 5-балльный; голое число >5 он бы отклонил.
        if m.score and m.score.value and m.score.value > 0 then
            item.rating = tostring(m.score.value) .. "/10"
        end
        table.insert(items, item)
    end
    local pag = data.pagination
    local hasNext = pag ~= nil and pag.last_page and pag.last_page > pag.current_page
    return { items = items, hasNext = hasNext or false }
end

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    -- Поиск работает только через HTML-POST /manga/search/ (проверено:
    -- ?search= на каталоге игнорируется, а JSON-поиска нет).
    local r = http_post(baseUrl .. "manga/search/",
        "q=" .. url_encode(query) .. "&type=manga")
    if not r.success then return { items = {}, hasNext = false } end
    local items = {}
    for _, card in ipairs(html_select(r.body, ".AniMangaSearchCard")) do
        local a = html_select_first(card.html, ".AniMangaSearchCard__link")
        local img = html_select_first(card.html, ".AniMangaSearchCard__cover")
        local title = html_select_first(card.html, ".AniMangaSearchCard__title")
        if a and title then
            local url = absUrl(a.href)
            if url ~= "" then
                local item = {
                    title = string_clean(title.text),
                    url = url,
                    cover = "",
                }
                -- В поиске обложки отдаются в уменьшенном виде /covers/x120/ —
                -- заменяем на /covers/preview/ (как в каталоге и деталях).
                if img and img.src then
                    item.cover = absUrl(string.gsub(img.src, "/covers/x120/", "/covers/preview/"))
                end
                -- Рейтинг: <span class="is-score">8,8</span> — запятая как
                -- десятичный разделитель, приводим к формату "8.8/10".
                -- Скобки обязательны: string.gsub возвращает два значения,
                -- иначе второй (счётчик замен) попадёт в tonumber как base.
                local score = html_select_first(card.html, ".AniMangaSearchCard__facts .is-score")
                if score and score.text then
                    local v = tonumber((string.gsub(string_trim(score.text), ",", ".")))
                    if v and v > 0 then item.rating = tostring(v) .. "/10" end
                end
                table.insert(items, item)
            end
        end
    end
    return { items = items, hasNext = false }
end

-- ── Фильтры (HTML-каталог /manga/) ──
-- JSON API фильтры игнорирует, поэтому getCatalogFiltered ходит на HTML:
-- параметры kinds/status/genres (запятыми), order_by, "!" перед жанром =
-- исключение. Список жанров взят с самой страницы каталога (чекбоксы
-- catalog-genres: data-genre-id, data-genre-slug, data-genre-name).

local _GENRES = {
    {"46-Mystery", "Детектив"},
    {"47-Shounen", "Сёнен"},
    {"48-Supernatural", "Сверхъестественное"},
    {"49-Comedy", "Комедия"},
    {"50-Drama", "Драма"},
    {"51-Ecchi", "Этти"},
    {"52-Seinen", "Сейнен"},
    {"53-Fiction", "Фантастика"},
    {"54-Slice of Life", "Повседневность"},
    {"56-Action", "Экшен"},
    {"57-Fantasy", "Фэнтези"},
    {"58-Magic", "Магия"},
    {"59-Hentai", "Хентай"},
    {"60-School", "Школа"},
    {"61-Mystic", "Мистика"},
    {"62-Romance", "Романтика"},
    {"63-Shoujo", "Сёдзе"},
    {"64-Vampire", "Вампиры"},
    {"66-Martial Arts", "Боевые искусства"},
    {"67-Psychological", "Психологическое"},
    {"68-Adventure", "Приключения"},
    {"69-Historical", "Исторический"},
    {"70-Color", "В цвете"},
    {"71-Harem", "Гарем"},
    {"72-Demons", "Демоны"},
    {"76-Sports", "Спорт"},
    {"77-LitRPG", "ЛитRPG"},
    {"78-Music", "Музыка"},
    {"79-Game", "Игры"},
    {"80-Horror", "Ужасы"},
    {"81-Thriller", "Триллер"},
    {"82-Super Power", "Супер сила"},
    {"83-Mecha", "Меха"},
    {"84-Web", "Веб"},
    {"85-Space", "Космос"},
    {"86-Parody", "Пародия"},
    {"87-Josei", "Дзёсей"},
    {"88-Samurai", "Самураи"},
    {"89-Isekai", "Исекай"},
    {"90-Dementia", "Безумие"},
    {"91-Tragedy", "Трагедия"},
    {"92-Heroic Fantasy", "Героическое фэнтези"},
    {"93-Post Apocalyptic", "Постапокалиптика"},
    {"95-Yonkoma", "Ёнкома"},
    {"96-Sci-Fi", "Научная фантастика"},
    {"142-Gambling", "Азартные игры"},
    {"143-Alchemy", "Алхимия"},
    {"145-Angels", "Ангелы"},
    {"146-Anti-hero", "Антигерой"},
    {"147-Dystopia", "Антиутопия"},
    {"148-Apocalypse", "Апокалипсис"},
    {"149-Army", "Армия"},
    {"150-Artifacts", "Артефакты"},
    {"151-Gods", "Боги"},
    {"152-Sword Fighting", "Бои на мечах"},
    {"153-Power Struggle", "Борьба за власть"},
    {"154-Brother and Sister", "Брат и сестра"},
    {"155-Future", "Будущее"},
    {"156-Witch", "Ведьма"},
    {"157-Western", "Вестерн"},
    {"158-Video Games", "Видеоигры"},
    {"159-Virtual Reality", "Виртуальная реальность"},
    {"160-Demon Lord", "Владыка демонов"},
    {"161-Military", "Военные"},
    {"162-War", "Война"},
    {"163-Wizards / Mages", "Волшебники / маги"},
    {"164-Magical Creatures", "Волшебные существа"},
    {"165-Memories from Another World", "Воспоминания из другого мира"},
    {"166-Survival", "Выживание"},
    {"167-Female MC", "ГГ женщина"},
    {"168-IMBA MC", "ГГ имба"},
    {"169-Male MC", "ГГ мужчина"},
    {"170-Gamers", "Геймеры"},
    {"171-Guilds", "Гильдии"},
    {"172-Stupid MC", "Глупый ГГ"},
    {"173-Goblins", "Гоблины"},
    {"174-Maids", "Горничные"},
    {"176-Gyaru", "Гяру"},
    {"177-Dragons", "Драконы"},
    {"178-Friendship", "Дружба"},
    {"179-Cruel World", "Жестокий мир"},
    {"180-Animal Companions", "Животные компаньоны"},
    {"181-World Conquest", "Завоевание мира"},
    {"182-Beastmen", "Зверолюди"},
    {"183-Evil Spirits", "Злые духи"},
    {"184-Zombies", "Зомби"},
    {"185-Gaming elements", "Игровые элементы"},
    {"186-Empires", "Империи"},
    {"188-Quests", "Квесты"},
    {"189-Cooking", "Кулинария"},
    {"190-Cultivation", "Культивирование"},
    {"191-Legendary weapons", "Легендарное оружие"},
    {"192-Moli", "Моли"},
    {"193-Magic academy", "Магическая академия"},
    {"194-Mafia", "Мафия"},
    {"195-Medicine", "Медицина"},
    {"196-Revenge", "Месть"},
    {"197-Monster girls", "Монстродевушки"},
    {"198-Monsters", "Монстры"},
    {"199-Murim", "Мурим"},
    {"200-Skills / abilities", "Навыки / способности"},
    {"201-Mercenaries", "Наёмники"},
    {"202-Violence / cruelty", "Насилие / жестокость"},
    {"203-Undead", "Нежить"},
    {"204-Ninja", "Ниндзя"},
    {"205-Body swap", "Обмен телами"},
    {"206-Reverse Harem", "Обратный Гарем"},
    {"207-Firearms", "Огнестрельное оружие"},
    {"208-Office workers", "Офисные Работники"},
    {"209-Pirates", "Пираты"},
    {"210-Dungeons", "Подземелья"},
    {"211-Politics", "Политика"},
    {"212-Police", "Полиция"},
    {"214-Full color", "Полноцветный"},
    {"217-Time travel", "Путешествие во времени"},
    {"218-Slaves", "Рабы"},
    {"219-Sentient races", "Разумные расы"},
    {"220-Power ranks", "Ранги силы"},
    {"221-Reincarnation", "Реинкарнация"},
    {"222-Robots", "Роботы"},
    {"223-Knights", "Рыцари"},
    {"225-System", "Система"},
    {"226-Identity hiding", "Скрытие личности"},
    {"227-Saving the world", "Спасение мира"},
    {"228-Sports body", "Спортивное тело"},
    {"229-Middle Ages", "Средневековье"},
    {"230-Steampunk", "Стимпанк"},
    {"231-Superheroes", "Супергерои"},
    {"232-Traditional games", "Традиционные игры"},
    {"233-Smart GG", "Умный ГГ"},
    {"234-Teacher", "Учитель"},
    {"235-Philosophy", "Философия"},
    {"236-Hikikomori", "Хикикомори"},
    {"237-Cold weapons", "Холодное оружие"},
    {"238-Blackmail", "Шантаж"},
    {"239-Elves", "Эльфы"},
    {"240-Yakuza", "Якудза"},
    {"241-Yandere", "Яндере"},
    {"242-Japan", "Япония"},
    {"243-Aristocracy", "Аристократия"},
}

function getFilterList()
    local kinds = {}
    for _, g in ipairs({ "manga", "manhwa", "manhua", "one_shot", "comics" }) do
        table.insert(kinds, { value = g, label = g })
    end
    local statuses = {}
    for _, s in ipairs({ "ongoing", "released", "continued", "completed" }) do
        table.insert(statuses, { value = s, label = s })
    end
    local genres = {}
    for _, g in ipairs(_GENRES) do
        table.insert(genres, { value = g[1], label = g[2] })
    end
    return {
        {
            type = "select",
            key = "sort",
            label = "Сортировка",
            defaultValue = "updated",
            options = {
                { value = "popular", label = "По популярности" },
                { value = "updated", label = "По обновлению" },
                { value = "id", label = "По дате добавления" },
                { value = "name", label = "По названию" },
            },
        },
        {
            type = "checkbox",
            key = "kinds",
            label = "Тип",
            multiselect = true,
            options = kinds,
        },
        {
            type = "checkbox",
            key = "status",
            label = "Статус",
            multiselect = true,
            options = statuses,
        },
        {
            type = "checkbox",
            key = "genres",
            label = "Жанры",
            multiselect = true,
            options = genres,
        },
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local sort = filters["sort"] or "updated"
    local kinds = filters["kinds_included"] or {}
    local statuses = filters["status_included"] or {}
    local genres = filters["genres_included"] or {}

    local url = baseUrl .. "manga/?page=" .. page
    if sort ~= "updated" then url = url .. "&order_by=" .. sort end
    if #kinds > 0 then url = url .. "&kinds=" .. table.concat(kinds, ",") end
    if #statuses > 0 then url = url .. "&status=" .. table.concat(statuses, ",") end
    if #genres > 0 then
        -- Каждое значение кодируем отдельно: в slug'ах есть пробелы,
        -- а запятые-разделители должны остаться разделителями.
        local enc = {}
        for _, g in ipairs(genres) do table.insert(enc, url_encode(g)) end
        url = url .. "&genres=" .. table.concat(enc, ",")
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, li in ipairs(html_select(r.body, "ol.section.memberList > li.primaryContent")) do
        local a = html_select_first(li.html, "a.avatar")
        local title = html_select_first(li.html, 'span[itemprop="title"]')
        if not title then title = html_select_first(li.html, "a.animeTitle") end
        if a and title then
            local bookUrl = absUrl(a.href)
            if bookUrl ~= "" then
                local item = { title = string_clean(title.text), url = bookUrl, cover = "" }
                -- Обложка лежит в style="background-image: url('...')" —
                -- селектором из style не достать, только regex.
                local cover = string.match(li.html, "background%-image: url%('([^']+)'%)")
                if cover then item.cover = absUrl(cover) end
                -- Рейтинг: второй dl.pairsInline ("Рейтинг: <dd>9.75</dd>").
                local rating = html_select_first(li.html,
                    "div.animeInfo dl.pairsInline:nth-child(2) dd")
                if rating and rating.text ~= "" then
                    local v = tonumber(string_trim(rating.text))
                    if v and v > 0 then item.rating = tostring(v) .. "/10" end
                end
                table.insert(items, item)
            end
        end
    end
    -- hasNext: в PageNav data-last = число страниц; при одной странице
    -- PageNav не рендерится вовсе.
    local last = tonumber(html_attr(r.body, "div.PageNav", "data-last")) or 0
    local cur = tonumber(html_attr(r.body, "div.PageNav", "data-page")) or 1
    return { items = items, hasNext = last > cur }
end

-- ── Детали книги ──

function getBookTitle(bookUrl)
    local m = fetchApiManga(bookUrl)
    if not m then return nil end
    if m.russian and m.russian ~= "" then return string_clean(m.russian) end
    return m.name and string_clean(m.name) or nil
end

function getBookCoverImageUrl(bookUrl)
    local m = fetchApiManga(bookUrl)
    if not m or not m.cover or not m.cover.preview then return nil end
    return absUrl(m.cover.preview)
end

function getBookDescription(bookUrl)
    local m = fetchApiManga(bookUrl)
    if not m or not m.description then return nil end
    local text = string_trim(m.description)
    if text == "" then return nil end
    return text
end

function getBookGenres(bookUrl)
    local m = fetchApiManga(bookUrl)
    if not m or not m.genres then return {} end
    local genres = {}
    for _, g in ipairs(m.genres) do
        if g.name and g.name ~= "" then table.insert(genres, g.name) end
    end
    return genres
end

function getBookRating(bookUrl)
    local m = fetchApiManga(bookUrl)
    if not m or not m.score or not m.score.value or m.score.value <= 0 then
        return nil
    end
    -- Шкала 10, как на сайте (score.value). Формат "7.62/10".
    return tostring(m.score.value) .. "/10"
end

-- ── Статус и дата обновления ──

function getBookStatus(bookUrl)
    local m = fetchApiManga(bookUrl)
    if not m or not m.status or m.status == "" then return nil end
    -- Статус из JSON API (ongoing/released/continued/completed) — как на сайте,
    -- без маппинга в русский (контракт движка: строка как есть).
    return string_clean(m.status)
end

function getBookLastUpdate(bookUrl)
    local m = fetchApiManga(bookUrl)
    -- updated_date — Unix-время (секунды) из JSON API; nil/0 = нет данных.
    if not m or not m.updated_date or m.updated_date <= 0 then return nil end
    return os.date("%Y-%m-%d", m.updated_date)
end

-- ── Список глав ──

function getChapterList(bookUrl)
    local id = mangaId(bookUrl)
    if not id then return {} end
    local body = fetch(baseUrl .. "api/manga/" .. id .. "/chapters")
    if not body then return {} end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.chapters then return {} end
    local chapters = {}
    for _, ch in ipairs(data.chapters) do
        local num = tonumber(ch.number) or 0
        local vol = tonumber(ch.volume) or 0
        local title = "Глава " .. ch.number
        if vol > 0 then title = "Том " .. ch.volume .. " " .. title end
        if ch.title and ch.title ~= "" then title = title .. " — " .. ch.title end
        local entry = {
            title = string_clean(title),
            url = absUrl(ch.view_url),
        }
        if ch.publish_date and ch.publish_date > 0 then
            entry.uploaded = ch.publish_date
        end
        table.insert(chapters, entry)
    end
    -- API отдаёт новые сверху — сортируем хронологически по (том, номер).
    table.sort(chapters, function(a, b)
        local av, an = string.match(a.url, "/vol(%d+)/ch(%d+)")
        local bv, bn = string.match(b.url, "/vol(%d+)/ch(%d+)")
        av, an = tonumber(av) or 0, tonumber(an) or 0
        bv, bn = tonumber(bv) or 0, tonumber(bn) or 0
        if av ~= bv then return av < bv end
        return an < bn
    end)
    return chapters
end

function getChapterListHash(bookUrl)
    local id = mangaId(bookUrl)
    if not id then return "" end
    local body = fetch(baseUrl .. "api/manga/" .. id .. "/chapters")
    if not body then return "" end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.chapters or #data.chapters == 0 then
        return ""
    end
    -- Новейшая глава в API всегда первая.
    return data.chapters[1].view_url or ""
end

-- ── Текст главы (страницы изображений) ──

-- id манги и главы из window.MangaReader на HTML-странице главы
-- (JSON заканчивается на "};" — первого вхождения достаточно, внутри JSON
-- символа ';' нет).
local function parseReaderIds(body)
    if not body or body == "" then return nil end
    local s = string.find(body, "window.MangaReader", 1, true)
    if not s then return nil end
    local start = string.find(body, "{", s)
    if not start then return nil end
    local e = string.find(body, "};", start)
    if not e then return nil end
    local ok, data = pcall(json_parse, string.sub(body, start, e))
    if not ok or not data or not data.manga or not data.chapter then
        return nil
    end
    return data.manga.id, data.chapter.id
end

-- Страницы главы с API: /api/manga/<mid>/chapters/<cid> → pages[].url.
local function fetchChapterPages(html, url)
    local body = html
    if not body or body == "" then
        local r = http_get(url)
        if not r.success then return {} end
        body = r.body
    end
    local mid, cid = parseReaderIds(body)
    if not mid or not cid then return {} end
    local j = fetch(baseUrl .. "api/manga/" .. mid .. "/chapters/" .. cid)
    if not j then return {} end
    local ok, data = pcall(json_parse, j)
    if not ok or not data or not data.chapter or not data.chapter.pages then
        return {}
    end
    local pages = {}
    for _, p in ipairs(data.chapter.pages) do
        if p.url and p.url ~= "" then table.insert(pages, p.url) end
    end
    return pages
end

function getPageList(html, url)
    -- Движок передаёт HTML страницы главы (jsoup round-trip переживает
    -- window.MangaReader как есть); fallback — загрузить URL главы самим.
    return fetchChapterPages(html, url)
end

function getChapterText(html, url)
    local pages = fetchChapterPages(html, url)
    local out = {}
    for _, p in ipairs(pages) do
        table.insert(out, '<img src="' .. p .. '">')
    end
    return table.concat(out, "\n")
end