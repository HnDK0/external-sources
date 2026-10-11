-- =====================================================================
-- Lib: senk* family — shared engine for the Senkognito / Senkuro
--      GraphQL manga clones (ru/senkognito, ru/senkuro). Both copies were
--      byte-identical except for the GraphQL host and the site metadata,
--      so the plugins keep only metadata + this config.
-- Loaded via require_lib("senklb"). No dependencies on other libs.
--
-- config (first argument of every M.* function):
--   graphqlUrl  string  GraphQL endpoint (required),
--                       e.g. https://api.senkognito.com/graphql
--   baseUrl     string  site origin with a trailing slash (required)
--   name        string  label for log lines (default "senk")
--
-- Cursors and detail/chapter caches are keyed by the site origin: one
-- lib instance may serve several copies of the family at once.
-- =====================================================================
local version = "1.0.0"

local M = {}

local function origin(config)
    return config.baseUrl
end

local function bookSlug(bookUrl)
    if not bookUrl then return nil end
    return string.match(bookUrl, "/manga/([^/?]+)")
end

-- RU title wins, otherwise the first one the API returned.
local function firstTitle(titles)
    if not titles or #titles == 0 then return "" end
    for _, t in ipairs(titles) do
        if t.lang == "RU" and t.content then return t.content end
    end
    return titles[1].content or ""
end

-- ── GraphQL transport ───────────────────────────────────────────────

local function gql(config, query)
    local body = '{"query":"'
        .. query:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
        .. '"}'
    local r = http_post(config.graphqlUrl, body, {
        headers = { ["Content-Type"] = "application/json" },
    })
    if not r.success then return nil end
    local ok, data = pcall(json_parse, r.body)
    if not ok or not data then return nil end
    return data
end

-- Shared selection set of the paginated `mangas` connection.
local MANGAS_NODE = 'slug titles { lang content } cover { original { url } } '
    .. 'score status chapters views'

local function mangasQuery(args)
    return '{ mangas(first: 20' .. args .. ') { edges { node { '
        .. MANGAS_NODE
        .. ' } } pageInfo { hasNextPage endCursor } } }'
end

-- GraphQL node -> catalog item (title/cover/rating/url).
local function nodeToItem(config, node)
    local title = firstTitle(node.titles)
    if title == "" then title = node.slug end

    local cover = ""
    if node.cover and node.cover.original and node.cover.original.url then
        cover = node.cover.original.url
    end

    local item = {
        title = title,
        url   = origin(config) .. "manga/" .. node.slug,
        cover = cover,
    }
    if node.score and node.score > 0 then
        item.rating = tostring(node.score) .. "/10"
    end
    return item
end

local function edgesToList(config, edges)
    local items = {}
    for _, edge in ipairs(edges) do
        table.insert(items, nodeToItem(config, edge.node))
    end
    return items
end

-- ── Catalog / search ────────────────────────────────────────────────

local _catalogCursor = {}

function M.getCatalogList(config, index)
    local key = origin(config)
    local after = ""
    if index > 0 and _catalogCursor[key] then
        after = string.format(', after: "%s"', _catalogCursor[key])
    else
        _catalogCursor[key] = nil
    end

    local d = gql(config, mangasQuery(after))
    if not d or not d.data or not d.data.mangas or not d.data.mangas.edges then
        return { items = {}, hasNext = false }
    end

    local pi = d.data.mangas.pageInfo
    _catalogCursor[key] = pi and pi.hasNextPage and pi.endCursor or nil

    return {
        items  = edgesToList(config, d.data.mangas.edges),
        hasNext = pi and pi.hasNextPage or false,
    }
end

-- No server-side search on this API: one request pulls the whole list
-- (500 nodes) and the filter runs locally. Page > 0 has nothing left.
function M.getCatalogSearch(config, index, query)
    if index > 0 then return { items = {}, hasNext = false } end

    local d = gql(config, '{ mangas(first: 500) { edges { node { '
        .. MANGAS_NODE .. ' } } pageInfo { hasNextPage endCursor } } }')
    if not d or not d.data or not d.data.mangas or not d.data.mangas.edges then
        return { items = {}, hasNext = false }
    end

    local items = {}
    local queryLower = string.lower(query)
    for _, edge in ipairs(d.data.mangas.edges) do
        local node = edge.node
        local title = firstTitle(node.titles)
        if string.find(string.lower(title), queryLower, 1, true) then
            table.insert(items, nodeToItem(config, node))
        end
    end

    return { items = items, hasNext = false }
end

-- ── Filters ─────────────────────────────────────────────────────────

local _FILTER_SORT = {
    { value = "SCORE",      label = "По рейтингу" },
    { value = "VIEWS",      label = "По просмотрам" },
    { value = "CHAPTERS",   label = "По главам" },
    { value = "CREATED_AT", label = "По дате добавления" },
}

local _FILTER_TYPE = {
    { value = "MANGA",     label = "Манга" },
    { value = "MANHWA",    label = "Манхва" },
    { value = "MANHUA",    label = "Маньхуа" },
    { value = "COMICS",    label = "Комиксы" },
    { value = "OEL_MANGA", label = "OEL" },
}

local _FILTER_STATUS = {
    { value = "ONGOING",   label = "Выходит" },
    { value = "FINISHED",  label = "Завершена" },
    { value = "CANCELLED", label = "Прервана" },
}

local _FILTER_RATING = {
    { value = "SENSITIVE",    label = "Чувствительный" },
    { value = "QUESTIONABLE", label = "Спорный" },
    { value = "EXPLICIT",     label = "Откровенный" },
}

local _FILTER_FORMAT = {
    { value = "WEB",      label = "Веб" },
    { value = "WEBTOON",  label = "Вебтун" },
    { value = "SINGLE",   label = "Том" },
    { value = "DIGEST",   label = "Антология" },
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

function M.getFilterList()
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

local function quotedList(values)
    local quoted = {}
    for _, v in ipairs(values) do
        table.insert(quoted, '"' .. v .. '"')
    end
    return table.concat(quoted, ", ")
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
        table.insert(args, 'label: { include: [' .. quotedList(labels) .. '] }')
    end

    local labelsExcluded = filters["label_excluded"]
    if labelsExcluded and #labelsExcluded > 0 then
        table.insert(args, 'label: { exclude: [' .. quotedList(labelsExcluded) .. '] }')
    end

    return table.concat(args, ", ")
end

local _filteredCursor = {}

function M.getCatalogFiltered(config, index, filters)
    local key = origin(config)
    local after = ""
    if index > 0 and _filteredCursor[key] then
        after = string.format(', after: "%s"', _filteredCursor[key])
    else
        _filteredCursor[key] = nil
    end

    local filterArgs = buildFilterArgs(filters)
    local d = gql(config, mangasQuery(after .. ", " .. filterArgs))
    if not d or not d.data or not d.data.mangas or not d.data.mangas.edges then
        return { items = {}, hasNext = false }
    end

    local pi = d.data.mangas.pageInfo
    _filteredCursor[key] = pi and pi.hasNextPage and pi.endCursor or nil

    return {
        items   = edgesToList(config, d.data.mangas.edges),
        hasNext = pi and pi.hasNextPage or false,
    }
end

-- ── Book details (one cached manga(...) query for all of them) ──────

local _detailCache = {}

local function fetchMangaDetail(config, slug)
    local key = origin(config) .. "|" .. slug
    if _detailCache[key] then return _detailCache[key] end

    local q = string.format(
        '{ manga(slug: "%s") { id slug titles { lang content } cover { original { url } } labels { titles { lang content } } status type rating score views chapters branches { id lang } localizations { lang description { __typename ... on TiptapNodeNestedBlock { type content { __typename ... on TiptapNodeText { type text } } } } } updatedAt } }',
        slug)
    local d = gql(config, q)
    if not d or not d.data or not d.data.manga then return nil end

    _detailCache[key] = d.data.manga
    return d.data.manga
end

-- RU branch wins, otherwise the first one — chapters are branch-scoped.
local function findBranch(branches)
    if not branches then return nil end
    for _, b in ipairs(branches) do
        if b.lang == "RU" then return b.id end
    end
    if #branches > 0 then return branches[1].id end
    return nil
end

function M.getBookTitle(config, bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(config, slug)
    if not detail then return "" end
    return firstTitle(detail.titles)
end

function M.getBookCoverImageUrl(config, bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(config, slug)
    if not detail or not detail.cover or not detail.cover.original then return "" end
    return detail.cover.original.url or ""
end

-- Tiptap description blocks -> plain paragraphs (RU localization first).
function M.getBookDescription(config, bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(config, slug)
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

function M.getBookGenres(config, bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return {} end
    local detail = fetchMangaDetail(config, slug)
    if not detail or not detail.labels then return {} end

    local genres, seen = {}, {}
    for _, label in ipairs(detail.labels) do
        local name = firstTitle(label.titles)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(genres, name)
        end
    end
    return genres
end

function M.getBookRating(config, bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(config, slug)
    if not detail or not detail.score or detail.score <= 0 then
        if detail and detail.rating then return detail.rating end
        return ""
    end
    return tostring(detail.score) .. "/10"
end

-- Site status enum -> the app's own wording (guide: status is shown as-is).
function M.getBookStatus(config, bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(config, slug)
    if not detail or not detail.status then return "" end

    local s = detail.status
    if s == "FINISHED" then return "Закончена"
    elseif s == "ONGOING" then return "Выпускается"
    elseif s == "CANCELLED" then return "Прервана"
    elseif s == "HIBERNATING" then return "На паузе"
    elseif s == "DISCONTINUED" then return "Закроется"
    else return s end
end

function M.getBookLastUpdate(config, bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end
    local detail = fetchMangaDetail(config, slug)
    if not detail or not detail.updatedAt then return "" end
    local datePart = string.match(detail.updatedAt, "^(%d%d%d%d%-%d%d%-%d%d)")
    return datePart or detail.updatedAt
end

-- ── Chapters (paged mangaChapters connection, RU branch) ────────────

local _chapterCache = {}

local function fetchChapters(config, slug)
    local key = origin(config) .. "|" .. slug
    if _chapterCache[key] then return _chapterCache[key] end

    local detail = fetchMangaDetail(config, slug)
    if not detail then return {} end

    local branchId = findBranch(detail.branches)
    if not branchId then return {} end

    local allChapters = {}
    local cursor = nil

    while true do
        local after = cursor and string.format(', after: "%s"', cursor) or ""
        local q = string.format(
            '{ mangaChapters(branchId: "%s", orderBy: { field: NUMBER, direction: ASC }, first: 100%s) { edges { node { id number name slug pages { id number image { original { url } } } } } pageInfo { hasNextPage endCursor } } }',
            branchId, after)

        local d = gql(config, q)
        if not d or not d.data or not d.data.mangaChapters or not d.data.mangaChapters.edges then break end

        for _, edge in ipairs(d.data.mangaChapters.edges) do
            table.insert(allChapters, edge.node)
        end

        local pi = d.data.mangaChapters.pageInfo
        if not pi or not pi.hasNextPage or not pi.endCursor then break end
        cursor = pi.endCursor
    end

    _chapterCache[key] = allChapters
    return allChapters
end

function M.getChapterList(config, bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return {} end

    local chapters = fetchChapters(config, slug)
    if #chapters == 0 then return {} end

    local result = {}
    for _, ch in ipairs(chapters) do
        local title = ch.name or ""
        if title == "" then title = "Глава " .. (ch.number or "?") end
        table.insert(result, {
            title = title,
            url = origin(config) .. "manga/" .. slug .. "/chapters/" .. (ch.slug or ch.id),
        })
    end
    return result
end

function M.getChapterListHash(config, bookUrl)
    local slug = bookSlug(bookUrl)
    if not slug then return "" end

    local chapters = fetchChapters(config, slug)
    if #chapters == 0 then return "" end

    local latest = chapters[#chapters]
    return origin(config) .. "manga/" .. slug .. "/chapters/" .. (latest.slug or latest.id)
end

-- ── Reader ──────────────────────────────────────────────────────────

-- The page list lives in the chapters fetched by getChapterList (the
-- reader calls it after the list was loaded): match the chapter slug or
-- id from the URL and return its images.
function M.getPageList(config, html, url)
    local chapterSlug = string.match(url, "/chapter/([^/?]+)")
        or string.match(url, "/chapters/([^/?]+)")
    if not chapterSlug then return {} end

    for _, chapters in pairs(_chapterCache) do
        for _, ch in ipairs(chapters) do
            if (tostring(ch.slug) == chapterSlug or tostring(ch.id) == chapterSlug) and ch.pages then
                local pages = {}
                for _, p in ipairs(ch.pages) do
                    if p.image and p.image.original and p.image.original.url then
                        table.insert(pages, p.image.original.url)
                    end
                end
                -- Kept as-is from the copies: the comparator reads p.number
                -- off a URL string (always nil), so the API order survives.
                table.sort(pages, function(a, b)
                    return (a.number or 0) < (b.number or 0)
                end)
                return pages
            end
        end
    end

    return {}
end

function M.getChapterText(config, html, url)
    local pages = M.getPageList(config, html, url)
    local out = {}
    for _, p in ipairs(pages) do
        table.insert(out, '<img src="' .. p .. '">')
    end
    return table.concat(out, "\n")
end

return M
