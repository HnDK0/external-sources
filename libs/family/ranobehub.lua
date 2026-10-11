-- =====================================================================
-- Lib: ranobehub family — shared engine for the ranobehub.org /
--      ranobe.space clones (ru/ranobehub, ru/ranobespace). Both copies
--      were byte-identical except for the site origin and metadata, so
--      the plugins keep only metadata + this config.
-- Loaded via require_lib("ranobehub"); uses require_lib("urls").
--
-- config (first argument of every M.* function):
--   baseUrl  string  site origin with a trailing slash (required)
--   name     string  label for log lines (default "ranobehub")
--
-- Status is NOT mapped anywhere: the app shows the site's own string
-- (guide «getBookStatus») — "В процессе", "Завершено" and so on.
-- =====================================================================
local version = "1.0.0"

local urls = require_lib("urls")

local M = {}

local function origin(config)
    return config.baseUrl
end

local function absUrl(config, href)
    return urls.absUrl(origin(config), href)
end

local function applyStandardContentTransforms(config, text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = origin(config):gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = string_trim(text)
    return text
end

-- Book id out of URLs like https://ranobe.space/ranobe/1246-jobless-... -> "1246"
local function getBookId(bookUrl)
    return bookUrl:match("/ranobe/(%d+)")
end

-- hasNext: the "Дальше" button is present and NOT disabled (on the last
-- page the button carries the disabled attribute — assumed from the
-- markup, not verified).
local function hasNextPage(html)
    return html_select_first(html, "button:contains(Дальше):not([disabled])") ~= nil
end

-- Parses a catalog/search card: a[data-book-transition-id] > h3 title,
-- img.book-cover-image, rating from span.rating (text like "9.8").
-- The title comes from h3[data-book-transition-title="true"], not from
-- strong — strong lives in the hidden .book-cover-copy overlay (shown on
-- hover) and may be missing/duplicated (checked on catalog and search
-- fixtures).
-- IMPORTANT: the href is taken from the card's own el.href field, not
-- from html_attr(el.html, "a", "href") — el.html is the card's innerHTML,
-- there is no nested <a> tag there, so such a request always returns an
-- empty string (catalog and search returned 0 items — bug v1.1.0).
-- IMPORTANT: the site rating scale is 1-10, so we send "Rating: N/10"
-- (as in getBookRating) — a bare "9.8" is read by the app as a 0-5 scale
-- and shows 0 (the rating format is described in lua-plugin-guide.md).
local function parseCards(config, html)
    local items = {}
    local cards = html_select(html, "a[data-book-transition-id]")
    for _, el in ipairs(cards) do
        local titleEl  = html_select_first(el.html, 'h3[data-book-transition-title="true"]')
        local href     = el.href or ""
        local cover    = html_attr(el.html, "img.book-cover-image", "src")
        local ratingEl = html_select_first(el.html, "span.rating")
        local rating   = ratingEl and string_clean(ratingEl.text) or ""
        local title    = titleEl and titleEl.text or ""
        if title ~= "" and href ~= "" then
            local item = {
                title = string_clean(title),
                url   = absUrl(config, href),
                cover = absUrl(config, cover),
            }
            if rating ~= "" then item.rating = "Rating: " .. rating .. "/10" end
            table.insert(items, item)
        end
    end
    return items
end

-- ── Catalog / search (HTML pages /ranobe[?q=...]) ───────────────────

function M.getCatalogList(config, index)
    local page = index + 1
    local url = origin(config) .. "ranobe"
    if page > 1 then url = url .. "?page=" .. tostring(page) end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    return {
        items   = parseCards(config, r.body),
        hasNext = hasNextPage(r.body),
    }
end

function M.getCatalogSearch(config, index, query)
    local page = index + 1
    local url = origin(config) .. "ranobe?q=" .. url_encode(query)
    if page > 1 then url = url .. "&page=" .. tostring(page) end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    return {
        items   = parseCards(config, r.body),
        hasNext = hasNextPage(r.body),
    }
end

-- ── Book details (book page) ────────────────────────────────────────

function M.getBookTitle(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "h1")
    return el and string_clean(el.text) or nil
end

function M.getBookCoverImageUrl(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local src = html_attr(r.body, ".book-cover img", "src")
    if src == "" then return nil end
    return absUrl(config, src)
end

function M.getBookDescription(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".book-description-copy")
    if not el then el = html_select_first(r.body, ".book-hero-summary") end
    if not el then return nil end
    return string_trim(html_text(el.html))
end

-- First span.rating on the book page (hero block) — the 1-10 reader
-- score (text like "9.8"). Verified on the live site.
function M.getBookRating(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "span.rating")
    if not el then return nil end
    local score = string.match(string_clean(el.text), "%d+%.?%d*")
    if not score then return nil end
    return "Rating: " .. score .. "/10"
end

-- ── Status and last update ──────────────────────────────────────────

-- Months (English abbreviations, as on the site: "Aug 10, 2026")
local MONTHS = {
    Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

-- Absolute date from the text: "Aug 10, 2026", "Aug 11" (current year),
-- "Apr 21, 2022· изменён" (the extra suffix is ignored) -> YYYY-MM-DD
local function parseAbsoluteDate(txt)
    local mon, d, y = string.match(txt, "(%u%a%a)%s+(%d+)%D*(%d*)")
    if not mon then return nil end
    local m = MONTHS[mon]
    if not m then return nil end
    y = (y ~= "" and y) or os.date("%Y", os.time())
    return y .. "-" .. string.format("%02d", m) .. "-" .. string.format("%02d", tonumber(d))
end

-- Relative date (RU): "сегодня", "вчера", "N часов назад" and so on
-- -> YYYY-MM-DD relative to now.
local function parseRelativeDate(txt)
    if string.find(txt, "сегодня", 1, true) then
        return os.date("%Y-%m-%d", os.time())
    end
    if string.find(txt, "вчера", 1, true) then
        return os.date("%Y-%m-%d", os.time() - 86400)
    end
    local n = tonumber(string.match(txt, "(%d+)"))
    if not n then return nil end
    local secs = 0
    if string.find(txt, "минут", 1, true) then secs = 60
    elseif string.find(txt, "час", 1, true) then secs = 3600
    elseif string.find(txt, "день", 1, true) or string.find(txt, "дня", 1, true) or string.find(txt, "дней", 1, true) then secs = 86400
    elseif string.find(txt, "недел", 1, true) then secs = 604800
    elseif string.find(txt, "месяц", 1, true) then secs = 2592000
    elseif string.find(txt, "год", 1, true) or string.find(txt, "лет", 1, true) then secs = 31536000
    end
    if secs == 0 then return nil end
    return os.date("%Y-%m-%d", os.time() - n * secs)
end

-- Text date: absolute first, relative second.
local function parseBookDateText(txt)
    return parseAbsoluteDate(txt) or parseRelativeDate(txt)
end

function M.getBookStatus(config, bookUrl)
    -- Status — the text of the .book-kicker-status link (e.g. "В процессе",
    -- "Завершено"). Verified on the live site.
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".book-kicker-status")
    if not el then return nil end
    local s = string_clean(el.text)
    if s == "" then return nil end
    return s
end

function M.getBookLastUpdate(config, bookUrl)
    -- The datetime attribute of the <time> tag inside .book-kicker-updated
    -- (ISO 8601, e.g. 2026-08-22T19:12:14.000Z). The tag text is rendered
    -- by JS, hence the attribute. Fallback: parse the text itself.
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local dt = html_attr(r.body, ".book-kicker-updated time", "datetime")
    if dt ~= "" then
        local y, m, d = string.match(dt, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
        if y and m and d then return y .. "-" .. m .. "-" .. d end
    end
    local timeEl = html_select_first(r.body, ".book-kicker-updated time")
    if not timeEl then return nil end
    return parseBookDateText(string_clean(timeEl.text))
end

-- ── Chapter list (JSON API, paged through parsePage) ────────────────

-- The /api/books/{id}/chapters API returns at most 100 chapters per
-- request (limit=101+ -> HTTP 400), pagination is via offset. Response:
-- { items, total, offset, nextOffset }. For 408 chapters totalPages =
-- ceil(408/100) = 5. The engine fetches the pages itself and re-reads
-- only the last one on refresh — getChapterList/getChapterListHash are
-- not needed.
function M.parsePage(config, bookUrl, page)
    local bookId = getBookId(bookUrl)
    if not bookId then return { chapters = {}, totalPages = 1 } end

    local offset = (page - 1) * 100
    local apiUrl = origin(config) .. "api/books/" .. bookId ..
                   "/chapters?sort=asc&offset=" .. tostring(offset) .. "&limit=100"
    local r = http_get(apiUrl)
    if not r.success then return { chapters = {}, totalPages = 1 } end

    local parsed = json_parse(r.body)
    if not parsed or not parsed.items then return { chapters = {}, totalPages = 1 } end

    -- sort=asc -> old chapters first inside a page, as the engine expects
    local chapters = {}
    for _, ch in ipairs(parsed.items) do
        table.insert(chapters, {
            title  = string_clean(ch.title or ""),
            url    = bookUrl .. "/chapter/" .. tostring(ch.id),
            volume = "Том " .. tostring(ch.volume or ""),
        })
    end

    local total = tonumber(parsed.total or #parsed.items) or #parsed.items
    local totalPages = math.max(1, math.ceil(total / 100))
    return { chapters = chapters, totalPages = totalPages }
end

-- ── Chapter text ────────────────────────────────────────────────────

function M.getChapterText(config, html, url)
    local el = html_select_first(html, "div.reader-content")
    if not el then return "" end
    return applyStandardContentTransforms(config, html_text(el.html))
end

-- ── Filters ─────────────────────────────────────────────────────────

-- Filter values verified on the live site (catalog payload and the
-- actual requests): sort ∈ updated/popular/rating/new/chapters;
-- status 1-4; country 1-4 (Japan/China/Korea/USA); tag=N — include a
-- genre, several = AND. Tag exclusion (tag=-N) is NOT supported by the
-- site, so the genres are checkbox-only, no tristate. Genre ids match
-- ranobehub.org.
function M.getFilterList()
    return {

        -- Sorting
        {
            type             = "sort",
            key              = "sort",
            label            = "Сортировка",
            defaultValue     = "updated",
            defaultAscending = false,
            options = {
                { value = "updated",  label = "По обновлению"  },
                { value = "popular",  label = "По популярности" },
                { value = "rating",   label = "По рейтингу"     },
                { value = "new",      label = "Сначала новые"   },
                { value = "chapters", label = "По главам"       },
            }
        },

        -- Status
        {
            type  = "select",
            key   = "status",
            label = "Статус",
            options = {
                { value = "1", label = "В процессе" },
                { value = "2", label = "Завершено"  },
                { value = "3", label = "Заморожено" },
                { value = "4", label = "Неизвестно" },
            }
        },

        -- Country
        {
            type  = "checkbox",
            key   = "country",
            label = "Страна",
            options = {
                { value = "1", label = "Япония" },
                { value = "2", label = "Китай"  },
                { value = "3", label = "Корея"  },
                { value = "4", label = "США"    },
            }
        },

        -- Genres
        {
            type         = "checkbox",
            key          = "tags",
            label        = "Жанры",
            multiselect  = true,
            options = {
                { value = "22",  label = "Боевые искусства"   },
                { value = "114", label = "Гарем"              },
                { value = "246", label = "Гендер бендер"      },
                { value = "216", label = "Дзёсэй"             },
                { value = "115", label = "Для взрослых"       },
                { value = "7",   label = "Драма"              },
                { value = "101", label = "Исторический"       },
                { value = "17",  label = "Комедия"            },
                { value = "638", label = "Лоликон"            },
                { value = "922", label = "Магический реализм" },
                { value = "24",  label = "Меха"               },
                { value = "12",  label = "Милитари"           },
                { value = "2",   label = "Мистика"            },
                { value = "13",  label = "Научная фантастика" },
                { value = "747", label = "Непристойность"     },
                { value = "93",  label = "Повседневность"     },
                { value = "11",  label = "Приключение"        },
                { value = "18",  label = "Психология"         },
                { value = "9",   label = "Романтика"          },
                { value = "20",  label = "Сверхъестественное" },
                { value = "15",  label = "Сёдзё"              },
                { value = "23",  label = "Сёдзё-ай"           },
                { value = "189", label = "Сёнэн"              },
                { value = "680", label = "Сёнэн-ай"           },
                { value = "420", label = "Спорт"              },
                { value = "5",   label = "Сэйнэн"             },
                { value = "242", label = "Сюаньхуа"           },
                { value = "364", label = "Сянься"             },
                { value = "19",  label = "Трагедия"           },
                { value = "3",   label = "Триллер"            },
                { value = "1",   label = "Ужасы"              },
                { value = "720", label = "Уся"                },
                { value = "8",   label = "Фэнтези"            },
                { value = "21",  label = "Школьная жизнь"     },
                { value = "14",  label = "Экшн"               },
                { value = "327", label = "Эччи"               },
                { value = "691", label = "Юри"                },
                { value = "682", label = "Яой"                },
                { value = "907", label = "Eastern fantasy"    },
                { value = "999", label = "Isekai"             },
                { value = "993", label = "Video games"        },
            }
        },
    }
end

-- ── Filtered catalog ────────────────────────────────────────────────

function M.getCatalogFiltered(config, index, filters)
    local page = index + 1

    local qs = "sort=" .. url_encode(filters["sort"] or "updated")

    local status = filters["status"]
    if status and status ~= "" then
        qs = qs .. "&status=" .. url_encode(status)
    end

    -- Several countries go through a comma: country=1,2 (verified live)
    local country_inc = filters["country_included"] or {}
    if #country_inc > 0 then
        qs = qs .. "&country=" .. table.concat(country_inc, ",")
    end

    -- Genres: tag=N per selected one (AND), negatives are not supported
    local tags_inc = filters["tags_included"] or {}
    for _, t in ipairs(tags_inc) do
        qs = qs .. "&tag=" .. t
    end

    local url = origin(config) .. "ranobe?" .. qs
    if page > 1 then url = url .. "&page=" .. tostring(page) end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    return {
        items   = parseCards(config, r.body),
        hasNext = hasNextPage(r.body),
    }
end

return M
