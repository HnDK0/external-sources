-- Kakuyomu (カクヨム) source plugin for NoveLA
-- Version 1.3.1
--
-- Uses Kakuyomu's normal /search endpoint for both keyword search and
-- advanced filtering. Common tags are search terms, not a separate API:
-- e.g. "game ハーレム 男主人公" is sent as one q= query.

id       = "kakuyomu"
name     = "カクヨム (Kakuyomu)"
version  = "1.0.0"
baseUrl  = "https://kakuyomu.jp/"
language = "ja"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr/icons/kakuyomu.png"

local SITE = "https://kakuyomu.jp"
local PAGE_SIZE = 20

local GENRES = {
    { value = "fantasy",     label = "Isekai Fantasy (異世界ファンタジー)" },
    { value = "action",      label = "Modern Fantasy / Action (現代ファンタジー)" },
    { value = "sf",          label = "Sci-Fi (SF)" },
    { value = "love_story",  label = "Love Story (恋愛)" },
    { value = "romance",     label = "Romantic Comedy (ラブコメ)" },
    { value = "drama",       label = "Contemporary Drama (現代ドラマ)" },
    { value = "horror",      label = "Horror (ホラー)" },
    { value = "mystery",     label = "Mystery (ミステリー)" },
    { value = "nonfiction",  label = "Essay / Nonfiction (エッセイ・ノンフィクション)" },
    { value = "history",     label = "Historical / Period (歴史・時代・伝奇)" },
    { value = "criticism",   label = "Writing / Criticism (創作論・評論)" },
    { value = "others",      label = "Poetry / Other (詩・童話・その他)" },
    { value = "maho",        label = "Maho-i-land (魔法のiらんど)" },
    { value = "fan_fiction", label = "Fan Fiction (二次創作)" }
}

-- These are convenience terms. Their value is exactly what Kakuyomu's
-- /tags/<tag> page uses, and the same Japanese value can be put into q=.
local TAGS = {
    { value = "ダンジョン", label = "Dungeon (ダンジョン)" },
    { value = "勘違い", label = "Misunderstanding (勘違い)" },
    { value = "異世界", label = "Isekai (異世界)" },
    { value = "ブラコン", label = "Brother Complex (ブラコン)" },
    { value = "シスコン", label = "Sister Complex (シスコン)" },
    { value = "ざまぁ", label = "Revenge (ざまぁ)" },
    { value = "剣と魔法", label = "Sword and Magic (剣と魔法)" },
    { value = "幼馴染", label = "Childhood Friend (幼馴染)" },
    { value = "ヤンデレ", label = "Yandere (ヤンデレ)" },
    { value = "転生", label = "Reincarnation (転生)" },
    { value = "悪役転生", label = "Villain Reincarnation (悪役転生)" },
    { value = "悪役", label = "Villain (悪役)" },
    { value = "男主人公", label = "Male Protagonist (男主人公)" },
    { value = "魔法", label = "Magic (魔法)" },
    { value = "ハーレム", label = "Harem (ハーレム)" },
    { value = "学園", label = "School (学園)" },
    { value = "コメディ", label = "Comedy (コメディ)" },
    { value = "ラブコメ", label = "Romantic Comedy (ラブコメ)" },
    { value = "ゲーム", label = "Game (ゲーム)" },
    { value = "ゲーム転生", label = "Game Reincarnation (ゲーム転生)" },
    { value = "NTR", label = "NTR" },
    { value = "エロゲ", label = "Eroge (エロゲ)" },
    { value = "BSS", label = "BSS" },
    { value = "主人公最強", label = "Strongest Protagonist (主人公最強)" },
    { value = "乙女ゲーム", label = "Otome Game (乙女ゲーム)" },
    { value = "セックス", label = "Sex (セックス)" },
    { value = "義妹", label = "Stepsister (義妹)" },
    { value = "巨乳", label = "Big Breasts (巨乳)" },
    { value = "ts", label = "TS / Gender Bender (ts)" }
}

local CONTENT_FLAGS = {
    { value = "cruel",           label = "Graphic / Cruel depictions (残酷描写)" },
    { value = "violent",         label = "Violent depictions (暴力描写)" },
    { value = "sexual",          label = "Sexual depictions (性描写)" },
    { value = "has_publication", label = "Adapted to other media (書籍化・メディア化)" }
}

local SERIAL_STATUS = {
    RUNNING   = "連載中",
    COMPLETED = "完結",
    PAUSED    = "休載中"
}

-- One local page cache is useful because NoveLA may call several book-detail
-- functions for the same URL during one adapter run.
local _pageCache = {}

local function fetchPage(url)
    if _pageCache[url] then
        return _pageCache[url]
    end

    local r = http_get(url)
    if not r or not r.success then
        return nil
    end

    _pageCache[url] = r.body
    return r.body
end

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    if string_starts_with(href, "/") then return SITE .. href end
    return href
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((第\\s*\\d+話|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = string_trim(text)
    return text
end

local function metaContent(html, name)
    return string.match(html, 'property="' .. name .. '"%s+content="([^"]*)"')
        or string.match(html, 'name="' .. name .. '"%s+content="([^"]*)"')
end

local function getWorkId(url)
    return string.match(url or "", "/works/(%d+)")
end

-- Kakuyomu embeds a normalized Apollo cache in __NEXT_DATA__.
local _apolloCache = {}

local function getApolloState(html)
    if _apolloCache[html] ~= nil then
        return _apolloCache[html] or nil
    end

    local jsonText = string.match(
        html,
        '<script id="__NEXT_DATA__" type="application/json">(.-)</script>'
    )

    local state = nil
    if jsonText then
        local ok, data = pcall(json_parse, jsonText)
        if ok and data and data.props and data.props.pageProps then
            state = data.props.pageProps.__APOLLO_STATE__
        end
    end

    _apolloCache[html] = state or false
    return state
end

local function getWork(url)
    local body = fetchPage(url)
    if not body then return nil, nil, nil end

    local id = getWorkId(url)
    if not id then return nil, body, nil end

    local state = getApolloState(body)
    return state and state["Work:" .. id] or nil, body, state
end

local function parseListPage(r)
    if not r or not r.success then
        return { items = {}, hasNext = false }
    end

    local items = {}
    local seen = {}

    for _, a in ipairs(html_select(r.body, "a[href*='/works/']")) do
        local href = a.href or ""
        local id = string.match(href, "/works/(%d+)$")

        -- Kakuyomu list pages repeat the same work through several links.
        -- The link with title= contains the clean work title.
        if id and not seen[id] and a.title and a.title ~= "" then
            seen[id] = true
            items[#items + 1] = {
                title = string_clean(a.title),
                url   = absUrl(href),
                cover = ""
            }
        end
    end

    return {
        items = items,
        hasNext = #items >= PAGE_SIZE
    }
end

function getCatalogList(index)
    local page = index + 1
    return parseListPage(
        http_get(SITE .. "/search?page=" .. page)
    )
end

function getCatalogSearch(index, query)
    local page = index + 1
    local q = query or ""

    if q == "" then
        return getCatalogList(index)
    end

    local url = SITE .. "/search?order=weekly_ranking&q=" .. url_encode(q)
        .. "&page=" .. page

    return parseListPage(http_get(url))
end

function getFilterList()
    local genres = {
        { value = "all", label = "All genres (総合)" }
    }

    for _, g in ipairs(GENRES) do
        genres[#genres + 1] = g
    end

    return {
        {
            type = "sort",
            key = "order",
            label = "Sort by",
            defaultValue = "weekly_ranking",
            defaultAscending = false,
            options = {
                { value = "weekly_ranking", label = "Weekly ranking (週間ランキング順)" },
                { value = "published_at",   label = "Newest first (新着順)" },
                { value = "popular",         label = "Most popular (人気順)" }
            }
        },

        {
            type = "select",
            key = "genre",
            label = "Genre",
            defaultValue = "all",
            options = genres
        },

        -- A tag_input is used deliberately: Kakuyomu treats tags as search
        -- words in q, so multiple selected/custom terms become one q string.
        {
            type = "tag_input",
            key = "query_terms",
            label = "Search terms / Tags",
            allowCustom = true,
            options = TAGS
        },

        {
            type = "select",
            key = "serial_status",
            label = "Novel status",
            defaultValue = "all",
            options = {
                { value = "all",       label = "Any (すべて)" },
                { value = "running",   label = "Ongoing (連載中)" },
                { value = "completed", label = "Completed (完結済)" }
            }
        },

        {
            type = "select",
            key = "length",
            label = "Novel length",
            defaultValue = "any",
            options = {
                { value = "any",           label = "Any (指定なし)" },
                { value = "20000-100000",  label = "Short: 20k–100k characters" },
                { value = "100000-",        label = "Medium+: 100k+ characters" },
                { value = "500000-",        label = "Long: 500k+ characters" }
            }
        },

        {
            type = "tristate",
            key = "content",
            label = "Content conditions",
            options = CONTENT_FLAGS
        }
    }
end

local function joinValues(values)
    if type(values) ~= "table" then
        return ""
    end

    local out = {}
    for _, value in ipairs(values) do
        if value and tostring(value) ~= "" then
            out[#out + 1] = tostring(value)
        end
    end
    return table.concat(out, " ")
end

function getCatalogFiltered(index, filters)
    filters = filters or {}

    local page = index + 1
    local params = {}

    local order = filters["order"] or "weekly_ranking"
    local genre = filters["genre"] or "all"
    local status = filters["serial_status"] or "all"
    local length = filters["length"] or "any"

    params[#params + 1] = "page=" .. page
    params[#params + 1] = "order=" .. url_encode(order)

    if genre ~= "" and genre ~= "all" then
        params[#params + 1] = "genre_name=" .. url_encode(genre)
    end

    -- Search terms/tags are all part of one q parameter, separated by spaces.
    local terms = joinValues(filters["query_terms_included"] or {})
    if terms == "" then
        -- Accept a plain text value too, in case a compatible NoveLA build
        -- supplies tag_input data in a scalar form.
        terms = filters["query_terms"] or ""
    end
    if terms ~= "" then
        params[#params + 1] = "q=" .. url_encode(terms)
    end

    if status ~= "" and status ~= "all" then
        params[#params + 1] = "serial_status=" .. url_encode(status)
    end

    if length ~= "" and length ~= "any" then
        params[#params + 1] = "total_character_count_range=" .. url_encode(length)
    end

    local included = filters["content_included"] or {}
    local excluded = filters["content_excluded"] or {}

    if #included > 0 then
        params[#params + 1] =
            "inclusion_conditions=" ..
            url_encode(table.concat(included, ","))
    end

    if #excluded > 0 then
        params[#params + 1] =
            "exclusion_conditions=" ..
            url_encode(table.concat(excluded, ","))
    end

    local url = SITE .. "/search?" .. table.concat(params, "&")
    return parseListPage(http_get(url))
end

function getBookTitle(bookUrl)
    local w, body = getWork(bookUrl)

    if w and w.title and w.title ~= "" then
        return string_clean(w.title)
    end

    if not body then return nil end

    local title = metaContent(body, "og:title")
    if title then
        title = string.gsub(title, "%s*%-%s*カクヨム%s*$", "")
        return string_clean(title)
    end

    local el = html_select_first(body, "h1 a")
        or html_select_first(body, "h1")

    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local w, body = getWork(bookUrl)

    if w and w.ogImageUrl and w.ogImageUrl ~= "" then
        return absUrl(w.ogImageUrl)
    end

    return body and absUrl(metaContent(body, "og:image")) or nil
end

function getBookDescription(bookUrl)
    local w, body = getWork(bookUrl)

    if w and w.introduction and w.introduction ~= "" then
        return string_trim(w.introduction)
    end

    if not body then return nil end
    local desc = metaContent(body, "og:description")
    return desc and string_trim(desc) or nil
end

function getBookGenres(bookUrl)
    local w, body = getWork(bookUrl)
    local out = {}

    -- Один жанр (enum) + все теги отдельными элементами: на сайте они
    -- показаны двумя секциями (ジャンル / タグ), Apollo отдаёт tagLabels массивом.
    if w and w.genre and w.genre ~= "" then
        local code, label = string.lower(w.genre), w.genre
        for _, g in ipairs(GENRES) do
            if g.value == code then
                label = string.match(g.label, "%(([^%)]+)%)") or g.label
                break
            end
        end
        out[#out + 1] = label
    end

    if w and type(w.tagLabels) == "table" then
        for _, t in ipairs(w.tagLabels) do
            if t and t ~= "" then out[#out + 1] = t end
        end
    end

    -- Фолбэк без Apollo: первая жанровая ссылка (SSR секции 詳細 нет в HTML).
    if #out == 0 and body then
        local el = html_select_first(body, "a[href*='/genres/']")
        if el then out[1] = string_clean(el.text) end
    end

    return out
end

function getBookStatus(bookUrl)
    local w, body = getWork(bookUrl)

    if w and w.serialStatus then
        return SERIAL_STATUS[w.serialStatus] or w.serialStatus
    end

    if body then
        local text = html_text(body)
        local completed = string.match(text, "完結[^%s、。]*")
        if completed then return completed end

        local running = string.match(text, "連載中[^%s、。]*")
        if running then return running end
    end

    return nil
end

function getBookLastUpdate(bookUrl)
    local w, body = getWork(bookUrl)

    if w and w.lastEpisodePublishedAt and w.lastEpisodePublishedAt ~= "" then
        local y, m, d = string.match(
            w.lastEpisodePublishedAt,
            "(%d%d%d%d)%-(%d%d)%-(%d%d)"
        )
        if y then
            return y .. "-" .. m .. "-" .. d
        end
    end

    if body then
        local value = metaContent(body, "article:modified_time")
        if value then
            local y, m, d = string.match(value, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
            if y then return y .. "-" .. m .. "-" .. d end
        end
    end

    return nil
end

function getChapterList(bookUrl)
    -- Direct request is intentional here: unlike the detail helpers, chapter
    -- lists must not come from a stale page cache.
    local r = http_get(bookUrl)
    if not r or not r.success then return {} end

    local workId = getWorkId(bookUrl)
    if not workId then return {} end

    local state = getApolloState(r.body)
    local work = state and state["Work:" .. workId] or nil
    local chapters = {}

    if work and type(work.tableOfContentsV2) == "table" then
        for _, tocRef in ipairs(work.tableOfContentsV2) do
            local toc = tocRef.__ref and state[tocRef.__ref]
            if toc and type(toc.episodeUnions) == "table" then
                for _, epRef in ipairs(toc.episodeUnions) do
                    local ep = epRef.__ref and state[epRef.__ref]
                    if ep and ep.id and ep.title then
                        chapters[#chapters + 1] = {
                            title = string_clean(ep.title),
                            url = SITE .. "/works/" .. workId .. "/episodes/" .. ep.id
                        }
                    end
                end
            end
        end
    end

    -- Fallback for a page/template without usable Apollo data.
    if #chapters == 0 then
        local seen = {}
        for _, a in ipairs(html_select(r.body, "a[href*='/episodes/']")) do
            local href = a.href or ""
            local id = string.match(href, "/episodes/(%d+)$")
            local title = string_clean(a.text or "")

            if id and not seen[id] and title ~= "" and title ~= "1話目から読む" then
                seen[id] = true
                title = string.gsub(title, "%d%d%d%d年%d+月%d+日公開$", "")
                title = string_clean(title)

                chapters[#chapters + 1] = {
                    title = title ~= "" and title or ("Episode " .. id),
                    url = absUrl(href)
                }
            end
        end
    end

    return chapters
end

function getChapterListHash(bookUrl)
    -- Must be uncached so a new episode can trigger an update.
    local r = http_get(bookUrl)
    if not r or not r.success then return nil end

    local workId = getWorkId(bookUrl)
    if not workId then return nil end

    local state = getApolloState(r.body)
    local work = state and state["Work:" .. workId] or nil
    if not work then return nil end

    local count = 0
    if type(work.tableOfContentsV2) == "table" then
        for _, tocRef in ipairs(work.tableOfContentsV2) do
            local toc = tocRef.__ref and state[tocRef.__ref]
            if toc and type(toc.episodeUnions) == "table" then
                count = count + #toc.episodeUnions
            end
        end
    end

    local updated = work.lastEpisodePublishedAt or ""
    return tostring(count) .. "|" .. updated
end

function getChapterText(html, url)
    local cleaned = html_remove(
        html,
        "script",
        "style",
        ".ads",
        ".advertisement",
        ".chapter-nav",
        ".nav-links",
        "#comments"
    )

    local el = html_select_first(cleaned, "div.widget-episodeBody")
    if not el then
        el = html_select_first(cleaned, "#episodeContent")
    end
    if not el then
        el = html_select_first(cleaned, "article")
    end
    if not el then
        return ""
    end

    return applyStandardContentTransforms(html_text(el.html))
end
