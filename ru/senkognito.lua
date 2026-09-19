id       = "senkognito"
name     = "Senkognito"
version  = "1.0.3"
baseUrl  = "https://senkognito.com/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/senkognito.png"
content_type = "manga"

local GRAPHQL = "https://api.senkognito.com/graphql"

local function bookSlug(bookUrl)
    if not bookUrl then return nil end
    return string.match(bookUrl, "/manga/([^/?]+)")
end

local function firstTitle(titles)
    if not titles or #titles == 0 then return "" end
    for _, t in ipairs(titles) do
        if t.lang == "RU" and t.content then return t.content end
    end
    return titles[1].content or ""
end

local function gql(query)
    local body = '{"query":"' .. query:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"}'
    local r = http_post(GRAPHQL, body, {
        headers = { ["Content-Type"] = "application/json" },
    })
    if not r.success then return nil end
    local ok, data = pcall(json_parse, r.body)
    if not ok or not data then return nil end
    return data
end

local _catalogCursor = nil

function getCatalogList(index)
    local q
    if index > 0 and _catalogCursor then
        q = string.format(
            '{ mangas(first: 20, after: "%s") { edges { node { slug titles { lang content } cover { original { url } } score status chapters views } } pageInfo { hasNextPage endCursor } } }',
            _catalogCursor)
    else
        _catalogCursor = nil
        q = '{ mangas(first: 20) { edges { node { slug titles { lang content } cover { original { url } } score status chapters views } } pageInfo { hasNextPage endCursor } } }'
    end

    local d = gql(q)
    if not d or not d.data or not d.data.mangas or not d.data.mangas.edges then
        return { items = {}, hasNext = false }
    end

    local items = {}
    for _, edge in ipairs(d.data.mangas.edges) do
        local node = edge.node
        local title = firstTitle(node.titles)
        if title == "" then title = node.slug end

        local cover = ""
        if node.cover and node.cover.original and node.cover.original.url then
            cover = node.cover.original.url
        end

        local item = {
            title = title,
            url = baseUrl .. "manga/" .. node.slug,
            cover = cover,
        }
        if node.score and node.score > 0 then
            item.rating = tostring(node.score) .. "/10"
        end
        table.insert(items, item)
    end

    local pi = d.data.mangas.pageInfo
    _catalogCursor = pi and pi.hasNextPage and pi.endCursor or nil

    return {
        items = items,
        hasNext = pi and pi.hasNextPage or false,
    }
end

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end

    local q = '{ mangas(first: 500) { edges { node { slug titles { lang content } cover { original { url } } score status chapters views } } pageInfo { hasNextPage endCursor } } }'
    local d = gql(q)
    if not d or not d.data or not d.data.mangas or not d.data.mangas.edges then
        return { items = {}, hasNext = false }
    end

    local items = {}
    local queryLower = string.lower(query)

    for _, edge in ipairs(d.data.mangas.edges) do
        local node = edge.node
        local title = firstTitle(node.titles)

        if string.find(string.lower(title), queryLower, 1, true) then
            local cover = ""
            if node.cover and node.cover.original and node.cover.original.url then
                cover = node.cover.original.url
            end
            local item = {
                title = title,
                url = baseUrl .. "manga/" .. node.slug,
                cover = cover,
            }
            if node.score and node.score > 0 then
                item.rating = tostring(node.score) .. "/10"
            end
            table.insert(items, item)
        end
    end

    return { items = items, hasNext = false }
end

-- ── Фильтры ──

local _FILTER_SORT = {
    { value = "SCORE",    label = "По рейтингу" },
    { value = "VIEWS",    label = "По просмотрам" },
    { value = "CHAPTERS", label = "По главам" },
    { value = "CREATED_AT", label = "По дате добавления" },
}

local _FILTER_TYPE = {
    { value = "MANGA",    label = "Манга" },
    { value = "MANHWA",   label = "Манхва" },
    { value = "MANHUA",   label = "Маньхуа" },
    { value = "COMICS",   label = "Комиксы" },
    { value = "OEL_MANGA", label = "OEL" },
}

local _FILTER_STATUS = {
    { value = "ONGOING",   label = "Выходит" },
    { value = "FINISHED",  label = "Завершена" },
    { value = "CANCELLED", label = "Прервана" },
}

local _FILTER_RATING = {
    { value = "SENSITIVE",   label = "Чувствительный" },
    { value = "QUESTIONABLE", label = "Спорный" },
    { value = "EXPLICIT",    label = "Откровенный" },
}

local _FILTER_FORMAT = {
    { value = "WEB",     label = "Веб" },
    { value = "WEBTOON", label = "Вебтун" },
    { value = "SINGLE",  label = "Том" },
    { value = "DIGEST",  label = "Антология" },
    { value = "IN_COLOR", label = "В цвете" },
}

local _FILTER_SOURCE = {
    { value = "ORIGINAL",    label = "Оригинал" },
    { value = "MANGA",       label = "Манга" },
    { value = "LIGHT_NOVEL", label = "Лайт-новелла" },
    { value = "VISUAL_NOVEL", label = "Визуальная новелла" },
    { value = "WEB_NOVEL",   label = "Веб-новелла" },
    { value = "OTHER",       label = "Другое" },
}

local _FILTER_LABELS = {
    { value = "shounen", label = "Сёнен" },
    { value = "seinen", label = "Сэйнэн" },
    { value = "shoujo", label = "Сёдзе" },
    { value = "josei", label = "Дзёсей" },
    { value = "action", label = "Экшен" },
    { value = "adventure", label = "Приключения" },
    { value = "comedy", label = "Комедия" },
    { value = "drama", label = "Драма" },
    { value = "fantasy", label = "Фэнтези" },
    { value = "horror", label = "Ужасы" },
    { value = "mystery", label = "Мистика" },
    { value = "psychological", label = "Психологическое" },
    { value = "romance", label = "Романтика" },
    { value = "sci_fi", label = "Фантастика" },
    { value = "slice_of_life", label = "Повседневность" },
    { value = "supernatural", label = "Сверхъестественное" },
    { value = "thriller", label = "Триллер" },
    { value = "tragedy", label = "Трагедия" },
    { value = "historical", label = "Исторический" },
    { value = "military", label = "Военное" },
    { value = "police", label = "Полиция" },
    { value = "crime", label = "Преступления" },
    { value = "mafia", label = "Мафия" },
    { value = "detective", label = "Детектив" },
    { value = "politics", label = "Политика" },
    { value = "isekai", label = "Исекай" },
    { value = "cultivation", label = "Культивация" },
    { value = "murim", label = "Мурим" },
    { value = "dungeon", label = "Подземелье" },
    { value = "post_apocalyptic", label = "Постапокалиптический" },
    { value = "cyberpunk", label = "Киберпанк" },
    { value = "steampunk", label = "Стимпанк" },
    { value = "space", label = "Космос" },
    { value = "urban", label = "В городе" },
    { value = "middle_ages", label = "Средневековье" },
    { value = "school", label = "Школа" },
    { value = "office", label = "Офис" },
    { value = "overpowered_protagonist", label = "ГГ имба" },
    { value = "female_protagonist", label = "ГГ женщина" },
    { value = "male_protagonist", label = "ГГ мужчина" },
    { value = "villainess", label = "Злодейка" },
    { value = "reincarnation", label = "Реинкарнация" },
    { value = "antihero", label = "Антигерой" },
    { value = "demon", label = "Демон" },
    { value = "dragon", label = "Драконы" },
    { value = "elf", label = "Эльф" },
    { value = "vampire", label = "Вампир" },
    { value = "undead", label = "Нежить" },
    { value = "orc", label = "Орк" },
    { value = "monster", label = "Монстр" },
    { value = "monster_girl", label = "Монстродевушка" },
    { value = "kemonomimi", label = "Ушастые" },
    { value = "angel", label = "Ангел" },
    { value = "witch", label = "Ведьма" },
    { value = "wizard", label = "Волшебник / Маг" },
    { value = "martial_arts", label = "Боевые искусства" },
    { value = "swordplay", label = "Бои на мечах" },
    { value = "skills", label = "Навыки / Способности" },
    { value = "superpower", label = "Супер сила" },
    { value = "mecha", label = "Меха" },
    { value = "ninja", label = "Ниндзя" },
    { value = "samurai", label = "Самурай" },
    { value = "knight", label = "Рыцарь" },
    { value = "firearms", label = "Огнестрельное оружие" },
    { value = "steel_arms", label = "Холодное оружие" },
    { value = "female_harem", label = "Женский гарем" },
    { value = "male_harem", label = "Мужской гарем" },
    { value = "ecchi", label = "Этти" },
    { value = "erotica", label = "Эротика" },
    { value = "hentai", label = "Хентай" },
    { value = "yuri", label = "Юри" },
    { value = "yaoi", label = "Яой" },
    { value = "love_polygon", label = "Любовный многоугольник" },
    { value = "music", label = "Музыка" },
    { value = "sport", label = "Спорт" },
    { value = "gourmet", label = "Гурман" },
    { value = "philosophy", label = "Философия" },
    { value = "religion", label = "Религия" },
    { value = "mythology", label = "Мифология" },
    { value = "survival", label = "Выживание" },
    { value = "revenge", label = "Месть" },
    { value = "friendship", label = "Дружба" },
    { value = "system", label = "Система" },
    { value = "quests", label = "Квесты" },
    { value = "guilds", label = "Гильдии" },
    { value = "gag_humor", label = "Гэг-юмор" },
    { value = "parody", label = "Пародия" },
    { value = "cute_girls_doing_cute_things", label = "Милые девушки" },
    { value = "iyashikei", label = "Иясикэй" },
    { value = "dark_world", label = "Мрачный мир" },
    { value = "cruel_world", label = "Жестокий мир" },
    { value = "shoujo_ai", label = "Сёдзе-ай" },
    { value = "shounen_ai", label = "Сёнен-ай" },
}

function getFilterList()
    return {
        {
            type = "sort",
            key = "sort",
            label = "Сортировка",
            defaultValue = "SCORE",
            defaultAscending = false,
            options = _FILTER_SORT,
        },
        {
            type = "checkbox",
            key = "type",
            label = "Тип",
            multiselect = true,
            options = _FILTER_TYPE,
        },
        {
            type = "checkbox",
            key = "status",
            label = "Статус",
            multiselect = true,
            options = _FILTER_STATUS,
        },
        {
            type = "checkbox",
            key = "rating",
            label = "Рейтинг",
            multiselect = true,
            options = _FILTER_RATING,
        },
        {
            type = "checkbox",
            key = "format",
            label = "Формат",
            multiselect = true,
            options = _FILTER_FORMAT,
        },
        {
            type = "checkbox",
            key = "source",
            label = "Источник",
            multiselect = true,
            options = _FILTER_SOURCE,
        },
        {
            type = "tristate",
            key = "label",
            label = "Жанры",
            options = _FILTER_LABELS,
        },
    }
end

local function buildFilterArgs(filters)
    local args = {}

    local sort = filters["sort"]
    local asc = filters["sort_ascending"] == "true"
    if sort and sort ~= "" then
        table.insert(args, string.format(
            'orderBy: { field: %s, direction: %s }',
            sort, asc and "ASC" or "DESC"))
    end

    local checkboxFilters = { "type", "status", "rating", "format", "source" }
    for _, key in ipairs(checkboxFilters) do
        local included = filters[key .. "_included"]
        if included and #included > 0 then
            table.insert(args, string.format(
                '%s: { include: [%s] }',
                key, table.concat(included, ", ")))
        end
    end

    local labels = filters["label_included"]
    if labels and #labels > 0 then
        local quoted = {}
        for _, l in ipairs(labels) do
            table.insert(quoted, '"' .. l .. '"')
        end
        table.insert(args, string.format(
            'label: { include: [%s] }',
            table.concat(quoted, ", ")))
    end

    local labelsExcluded = filters["label_excluded"]
    if labelsExcluded and #labelsExcluded > 0 then
        local quoted = {}
        for _, l in ipairs(labelsExcluded) do
            table.insert(quoted, '"' .. l .. '"')
        end
        table.insert(args, string.format(
            'label: { exclude: [%s] }',
            table.concat(quoted, ", ")))
    end

    return table.concat(args, ", ")
end

local _filteredCursor = nil

function getCatalogFiltered(index, filters)
    local filterArgs = buildFilterArgs(filters)
    local q

    if index > 0 and _filteredCursor then
        q = string.format(
            '{ mangas(first: 20, after: "%s", %s) { edges { node { slug titles { lang content } cover { original { url } } score status chapters views } } pageInfo { hasNextPage endCursor } } }',
            _filteredCursor, filterArgs)
    else
        _filteredCursor = nil
        q = string.format(
            '{ mangas(first: 20, %s) { edges { node { slug titles { lang content } cover { original { url } } score status chapters views } } pageInfo { hasNextPage endCursor } } }',
            filterArgs)
    end

    local d = gql(q)
    if not d or not d.data or not d.data.mangas or not d.data.mangas.edges then
        return { items = {}, hasNext = false }
    end

    local items = {}
    for _, edge in ipairs(d.data.mangas.edges) do
        local node = edge.node
        local title = firstTitle(node.titles)
        if title == "" then title = node.slug end

        local cover = ""
        if node.cover and node.cover.original and node.cover.original.url then
            cover = node.cover.original.url
        end

        local item = {
            title = title,
            url = baseUrl .. "manga/" .. node.slug,
            cover = cover,
        }
        if node.score and node.score > 0 then
            item.rating = tostring(node.score) .. "/10"
        end
        table.insert(items, item)
    end

    local pi = d.data.mangas.pageInfo
    _filteredCursor = pi and pi.hasNextPage and pi.endCursor or nil

    return {
        items = items,
        hasNext = pi and pi.hasNextPage or false,
    }
end

local _mangaDetailCache = {}

local function fetchMangaDetail(slug)
    if _mangaDetailCache[slug] then return _mangaDetailCache[slug] end

    local q = string.format(
        '{ manga(slug: "%s") { id slug titles { lang content } cover { original { url } } labels { titles { lang content } } status type rating score views chapters branches { id lang } localizations { lang description { __typename ... on TiptapNodeNestedBlock { type content { __typename ... on TiptapNodeText { type text } } } } } updatedAt } }',
        slug)
    local d = gql(q)
    if not d or not d.data or not d.data.manga then return nil end

    _mangaDetailCache[slug] = d.data.manga
    return d.data.manga
end

local function findRUBranch(branches)
    if not branches then return nil end
    for _, b in ipairs(branches) do
        if b.lang == "RU" then return b.id end
    end
    if #branches > 0 then return branches[1].id end
    return nil
end

function getBookTitle(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(slug)
    if not detail then return "" end
    return firstTitle(detail.titles)
end

function getBookCoverImageUrl(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(slug)
    if not detail or not detail.cover or not detail.cover.original then return "" end
    return detail.cover.original.url or ""
end

function getBookDescription(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(slug)
    if not detail or not detail.localizations then return "" end

    local loc
    for _, l in ipairs(detail.localizations) do
        if l.lang == "RU" and l.description then loc = l break end
    end
    if not loc then
        for _, l in ipairs(detail.localizations) do
            if l.description then loc = l break end
        end
    end
    if not loc then return "" end

    local parts = {}
    for _, block in ipairs(loc.description) do
        if block.type == "paragraph" and block.content then
            local line = {}
            for _, node in ipairs(block.content) do
                if node.type == "text" and node.text then
                    table.insert(line, node.text)
                end
            end
            if #line > 0 then table.insert(parts, table.concat(line)) end
        end
    end
    return table.concat(parts, "\n")
end

function getBookGenres(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return {} end
    local detail = fetchMangaDetail(slug)
    if not detail or not detail.labels then return {} end

    local genres = {}
    local seen = {}
    for _, label in ipairs(detail.labels) do
        local name = firstTitle(label.titles)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(genres, name)
        end
    end
    return genres
end

function getBookRating(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(slug)
    if not detail or not detail.score or detail.score <= 0 then
        if detail and detail.rating then return detail.rating end
        return ""
    end
    return tostring(detail.score) .. "/10"
end

function getBookStatus(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(slug)
    if not detail or not detail.status then return "" end

    local s = detail.status
    if s == "FINISHED" then return "Закончена"
    elseif s == "ONGOING" then return "Выпускается"
    elseif s == "CANCELLED" then return "Прервана"
    elseif s == "HIBERNATING" then return "На паузе"
    elseif s == "DISCONTINUED" then return "Закроется"
    else return s end
end

function getBookLastUpdate(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(slug)
    if not detail or not detail.updatedAt then return "" end
    local datePart = string.match(detail.updatedAt, "^(%d%d%d%d%-%d%d%-%d%d)")
    return datePart or detail.updatedAt
end

local _chaptersCache = {}

local function fetchChapters(slug)
    if _chaptersCache[slug] then return _chaptersCache[slug] end

    local detail = fetchMangaDetail(slug)
    if not detail then return {} end

    local branchId = findRUBranch(detail.branches)
    if not branchId then return {} end

    local allChapters = {}
    local cursor = nil

    while true do
        local q
        if cursor then
            q = string.format(
                '{ mangaChapters(branchId: "%s", orderBy: { field: NUMBER, direction: ASC }, first: 100, after: "%s") { edges { node { id number name slug pages { id number image { original { url } } } } } pageInfo { hasNextPage endCursor } } }',
                branchId, cursor)
        else
            q = string.format(
                '{ mangaChapters(branchId: "%s", orderBy: { field: NUMBER, direction: ASC }, first: 100) { edges { node { id number name slug pages { id number image { original { url } } } } } pageInfo { hasNextPage endCursor } } }',
                branchId)
        end

        local d = gql(q)
        if not d or not d.data or not d.data.mangaChapters or not d.data.mangaChapters.edges then break end

        for _, edge in ipairs(d.data.mangaChapters.edges) do
            table.insert(allChapters, edge.node)
        end

        local pi = d.data.mangaChapters.pageInfo
        if not pi or not pi.hasNextPage or not pi.endCursor then break end
        cursor = pi.endCursor
    end

    _chaptersCache[slug] = allChapters
    return allChapters
end

function getChapterList(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return {} end

    local chapters = fetchChapters(slug)
    if #chapters == 0 then return {} end

    local result = {}
    for _, ch in ipairs(chapters) do
        local title = ch.name or ""
        if title == "" then title = "Глава " .. (ch.number or "?") end
        table.insert(result, {
            title = title,
            url = baseUrl .. "manga/" .. slug .. "/chapters/" .. (ch.slug or ch.id),
        })
    end
    return result
end

function getChapterListHash(bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end

    local chapters = fetchChapters(slug)
    if #chapters == 0 then return "" end

    local latest = chapters[#chapters]
    return baseUrl .. "manga/" .. slug .. "/chapters/" .. (latest.slug or latest.id)
end

local _chapterPagesCache = {}

function getPageList(html, url)
    -- Поддерживаем оба формата URL: /chapter/SLUG и /manga/SLUG/chapters/SLUG
    local chapterSlug = string.match(url, "/chapter/([^/?]+)") or string.match(url, "/chapters/([^/?]+)")
    if not chapterSlug then return {} end

    for slug, chapters in pairs(_chaptersCache) do
        for _, ch in ipairs(chapters) do
            if (tostring(ch.slug) == chapterSlug or tostring(ch.id) == chapterSlug) and ch.pages then
                local pages = {}
                for _, p in ipairs(ch.pages) do
                    if p.image and p.image.original and p.image.original.url then
                        table.insert(pages, p.image.original.url)
                    end
                end
                table.sort(pages, function(a, b)
                    return (a.number or 0) < (b.number or 0)
                end)
                return pages
            end
        end
    end

    return {}
end

function getChapterText(html, url)
    local pages = getPageList(html, url)
    local out = {}
    for _, p in ipairs(pages) do
        table.insert(out, '<img src="' .. p .. '">')
    end
    return table.concat(out, "\n")
end
