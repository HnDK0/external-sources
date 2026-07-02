# Lua Plugin Writing Guide

> Based on analysis of real code: `LuaSourceAdapter.kt`, `LuaSourceLoader.kt`, `LuaFilterSupport.kt`, `LuaSettingsSupport.kt`, and 27 existing plugins.

---

## Table of Contents

1. [Plugin Structure](#plugin-structure)
2. [Metadata](#metadata)
3. [Required Functions](#required-functions)
4. [Working with HTTP](#working-with-http)
5. [Page Caching (fetchPage)](#page-caching-fetchpage)
6. [Working with HTML and CSS Selectors](#working-with-html-and-css-selectors)
7. [Text Cleanup](#text-cleanup)
8. [Working with the JSON API](#working-with-the-json-api)
9. [Catalog and Pagination](#catalog-and-pagination)
10. [Chapter List](#chapter-list)
11. [Paginated Chapter List (parsePage)](#paginated-chapter-list-parsepage)
12. [Chapter Text](#chapter-text)
13. [Catalog Filters](#catalog-filters)
14. [Plugin Settings](#plugin-settings)
15. [Helpers and Utilities](#helpers-and-utilities)
16. [Full API Reference](#full-api-reference)
17. [Full Plugin Template](#full-plugin-template)
18. [Common Mistakes](#common-mistakes)

---

## Plugin Structure

A plugin is a single `.lua` file. The engine (`LuaEngine`) loads it via `JsePlatform.standardGlobals()`, executes it, and passes `globals` to `LuaSourceAdapter`. All functions and variables declared in the global scope are available to the adapter.

Minimal file structure:

```
-- 1. METADATA (global variables)
id       = "my_source"
name     = "My Source"
version  = "1.0.0"
baseUrl  = "https://example.com"
language = "en"

-- 2. LOCAL HELPERS
local function absUrl(href) ... end

-- 3. REQUIRED FUNCTIONS
function getCatalogList(index) ... end
function getCatalogSearch(index, query) ... end
function getBookTitle(bookUrl) ... end
function getBookCoverImageUrl(bookUrl) ... end
function getBookDescription(bookUrl) ... end
function getChapterList(bookUrl) ... end      -- only needed if there's no parsePage (see below)
function getChapterText(html, url) ... end

-- 4. OPTIONAL FUNCTIONS
function getBookGenres(bookUrl) ... end
function getChapterListHash(bookUrl) ... end  -- only needed if there's no parsePage (see below)
function parsePage(bookUrl, page) ... end     -- paginated chapter list; if present, it fully
                                               -- replaces getChapterList and getChapterListHash
function getFilterList() ... end
function getCatalogFiltered(index, filters) ... end
function getSettingsSchema() ... end
```

The adapter automatically determines the subclass based on which functions are present:

| Functions present     | Adapter subclass               |
| ---------------------- | ------------------------------ |
| Only the basics        | `LuaSourceAdapter`             |
| + `getSettingsSchema`  | `LuaSourceAdapterConfigurable` |
| + `getFilterList`      | `LuaSourceAdapterFilterable`   |
| + both                 | `LuaSourceAdapterFull`         |

---

## Metadata

All fields are global Lua variables.

```
id       = "source_id"        -- unique ID, used as the file name: source_id.lua
name     = "Source Name"      -- display name
version  = "1.0.0"            -- version
baseUrl  = "https://..."      -- base URL (required)
language = "en"               -- ISO 639-1: "en", "ru", "ja", "zh", "id"
                              -- or "MTL" for machine translation
icon     = "https://..."      -- icon URL (optional)
charset  = "UTF-8"            -- response encoding (optional, default UTF-8)
```

**Important about `id`:** it must match the `.lua` file name without the extension. If `id = "royal_road"`, the file must be named `royal_road.lua`.

---

## Required Functions

### getCatalogList(index)

Paginated catalog. `index` starts at 0.

```
function getCatalogList(index)
    local page = index + 1  -- most sites number pages starting at 1
    local r = http_get(baseUrl .. "/novels?page=" .. page)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".novel-item")) do
        local titleEl = html_select_first(card.html, "h3 a")
        if titleEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(html_attr(card.html, "img", "src"))
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end
```

Return table:

- `items` — an array of `{ title, url, cover }`, where `cover` is optional
- `hasNext` — `true` if there is a next page

### getCatalogSearch(index, query)

Search. If the site returns everything on a single page, return `hasNext = false` when `index > 0`.

```
function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local url = baseUrl .. "/search?q=" .. url_encode(query)
    -- ... similar to getCatalogList
end
```

### getBookTitle(bookUrl)

```
function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "h1.title")
    return el and string_clean(el.text) or nil
end
```

### getBookCoverImageUrl(bookUrl)

```
function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cover = html_attr(r.body, ".cover img", "src")
    return cover ~= "" and absUrl(cover) or nil
end
```

### getBookDescription(bookUrl)

```
function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".description")
    return el and string_trim(el.text) or nil
end
```

### getChapterList(bookUrl)

Returns an array of `{ title, url, volume? }` in chronological order (from first to last).

```
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local chapters = {}
    for _, a in ipairs(html_select(r.body, ".chapter-list a[href]")) do
        table.insert(chapters, {
            title = string_clean(a.text),
            url   = absUrl(a.href)
        })
    end
    return chapters
end
```

### getChapterText(html, url)

Receives the full HTML of the chapter page and its URL. Must return a string with the chapter text.

```
function getChapterText(html, url)
    local cleaned = html_remove(html, "script", "style", ".ads", ".nav-links")
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end
```

---

## Working with HTTP

### Default headers

The engine automatically adds these to **every** call to `http_get`, `http_post`, and `http_get_batch`:

| Header             | Value                                                                |
| ------------------- | --------------------------------------------------------------------- |
| `User-Agent`        | The app's global UA (configurable by the user in settings)            |
| `Referer`           | `scheme://host/` derived from the request URL                         |
| `Accept-Language`   | The device locale (e.g. `ru-RU,ru;q=0.9,en-US;q=0.8`)                 |

A plugin can **override** any of these via `config.headers` — values from the plugin take priority over the defaults. Only do this when you need a specific value different from the default (for example, a `Referer` pointing to the book page instead of the domain root).

```
-- Override only what's needed — the remaining defaults are preserved
local r = http_post(ajaxUrl, body, {
    headers = {
        ["Referer"]          = bookUrl,        -- override: need the book page, not the root
        ["X-Requested-With"] = "XMLHttpRequest", -- add: no default exists
        ["Accept"]           = "text/html, */*; q=0.01",
    }
})
```

### http_get(url [, config])

```
-- Simple GET — User-Agent, Referer, Accept-Language are added automatically
local r = http_get("https://example.com/page")

-- With headers (only request-specific ones — no need to duplicate defaults)
local r = http_get(url, {
    headers = {
        ["X-Requested-With"] = "XMLHttpRequest",
        ["Accept"]           = "application/json",
    },
    charset = "UTF-8"  -- response encoding (default UTF-8)
})

-- Checking the result
if not r.success then
    log_error("Request failed: code=" .. tostring(r.code))
    return { items = {}, hasNext = false }
end
-- r.body  — response body string
-- r.code  — HTTP status code (200, 404, ...)
```

### http_post(url, body [, config])

```
-- Form-encoded POST — Content-Type is determined automatically from the body
local r = http_post(
    baseUrl .. "/ajax",
    "action=loadChapters&id=" .. novelId,
    {
        headers = {
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Referer"]          = bookUrl  -- override if you need the book page, not the root
        }
    }
)

-- JSON POST — Content-Type = application/json is determined automatically
local r = http_post(
    baseUrl .. "/api/reader",
    json_stringify({ novel_id = 123, chapter = 1 }),
    {
        headers = {
            ["Origin"] = baseUrl
        }
    }
)
```

### http_get_batch(urls_table)

Parallel loading of multiple URLs. The response order matches the request order.

```
local urls = {}
for p = 2, maxPage do
    table.insert(urls, baseUrl .. "/chapters?page=" .. p)
end

local results = http_get_batch(urls)
for i, res in ipairs(results) do
    if res.success then
        -- process res.body
    end
end
```

### Working with cookies

```
-- Get cookies for a domain
local cookies = get_cookies("https://example.com")
local token = cookies["session_token"]

-- Set cookies
set_cookies("https://example.com", {
    ["session_id"] = "abc123",
    ["token"]      = "xyz"
})
```

### Delays (rate limiting)

```
sleep(300)                        -- 300 ms
sleep(math.random(150, 350))      -- random delay of 150-350 ms
```

Use `sleep` between requests in `getChapterList` if the site aggressively blocks scrapers (example: jaomix).

---

## Page Caching (fetchPage)

The engine calls `getBookTitle`, `getBookCoverImageUrl`, `getBookDescription`, `getBookGenres`, `getChapterListHash`, and `getChapterList` **in parallel** — each of them does its own `http_get(bookUrl)` by default. That's 5–6 identical requests to the same page.

The solution is a local cache via `fetchPage`. Add it to every plugin where several functions read the same book page.

```
-- Declare at the top of the file, after the metadata
local _pageCache = {}

local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end
```

Then, in all the book-details functions, replace `http_get(bookUrl)` with `fetchPage(bookUrl)`:

```
-- ❌ Each function makes a separate HTTP request
function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    -- ...
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl)  -- second request to the same page
    if not r.success then return nil end
    -- ...
end

-- ✅ All functions use a single cached request
function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- ...
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)  -- comes from cache, no HTTP request
    if not body then return nil end
    -- ...
end
```

If `getChapterList` also loads the book page (for example, to extract `novelId` from `og:url`), hook it up too:

```
function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)  -- free if already cached
    if not body then return {} end

    local ogUrl = html_attr(body, "meta[property='og:url']", "content")
    -- ... then an AJAX request for the chapters
end
```

**Bottom line:** instead of 5–6 requests to the book page — **1 request + N AJAX calls**.

> **Note:** the cache lives only for the duration of a single plugin run. It's reset between different engine calls — there are no memory leaks.

> **⚠️ Important regarding `getChapterListHash` and `getChapterList`:**
>
> - `getChapterListHash` **must NOT** use `fetchPage`. Its job is to detect whether the chapter list has changed (new chapters, updates). If it reads the page from cache, the hash will always be stale and the update trigger won't fire. Always use a direct `http_get(bookUrl)`.
> - `getChapterList` **may** use `fetchPage`, but only to extract stable metadata (e.g. `novelId` from `og:url`), while fetching the actual chapter list via a separate, uncached request (AJAX, JSON API). If `getChapterList` parses chapters directly from the book page's HTML, it must also use a direct `http_get`, not `fetchPage`.

---

## Working with HTML and CSS Selectors

### Core functions

```
-- Parses HTML, returns { text, html, title, body }
local doc = html_parse(htmlString)

-- Returns an array of elements
local cards = html_select(htmlString, ".novel-card")

-- Returns the first element or nil
local el = html_select_first(htmlString, "h1.title")

-- Quickly get an attribute from the first match
local src = html_attr(htmlString, ".cover img", "src")

-- Extract text while preserving line breaks (<p>, <br>)
local text = html_text(innerHtml)

-- Remove elements from HTML
local cleanHtml = html_remove(html, "script", "style", ".ads", "#popup")
```

### Element object

`html_select` and `html_select_first` return tables with the following fields:

```
el.text   -- text content (analogous to element.innerText)
el.html   -- innerHTML
el.href   -- href attribute (already absolute if abs:href is available)
el.src    -- src attribute
el.title  -- title attribute
el.class  -- class attribute
el.id     -- id attribute

-- Methods:
el:attr("data-id")        -- any attribute
el:select(".child")       -- find child elements
el:get_text()             -- same as el.text
el:get_html()             -- same as el.html
el:remove()               -- remove the element from the DOM
```

### Typical selector patterns

```
-- Iterating over catalog cards
for _, card in ipairs(html_select(r.body, ".book-item")) do
    local titleEl = html_select_first(card.html, "h3 a")
    local cover   = html_attr(card.html, "img", "src")
    -- ...
end

-- Getting an href with a check
local a = html_select_first(r.body, ".read-btn a")
if a and a.href ~= "" then
    chapterUrl = absUrl(a.href)
end

-- Getting a data attribute
local postId = html_attr(r.body, "#novel-report", "data-post-id")
-- or via select:
local el = html_select_first(r.body, "#novel-report")
if el then
    local postId = el:attr("data-post-id")
end

-- Removing junk before parsing text
local cleaned = html_remove(html,
    "script", "style",
    ".advertisement", ".popup",
    ".chapter-nav", "#comments"
)
```

### Working with nested structures

```
-- Multi-level search
for _, row in ipairs(html_select(r.body, "table tr")) do
    local cells = html_select(row.html, "td")
    if #cells >= 2 then
        local label = string_trim(cells[1].text)
        local value = string_trim(cells[2].text)
        if label == "Genre" then
            -- process value
        end
    end
end
```

---

## Text Cleanup

### Standard content-cleanup function

Use this in every plugin — it's a template taken from real plugins:

```
local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end

    -- 1. Unicode normalization (NFKC)
    text = string_normalize(text)

    -- 2. Remove references to the source site
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")

    -- 3. Remove the chapter heading at the start (it's duplicated in the title)
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")

    -- 4. Remove translator/editor lines
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")

    -- 5. Trim whitespace
    text = string_trim(text)
    return text
end
```

For Russian-language sites, add a line covering Cyrillic:

```
text = regex_replace(text, "(?im)^\\s*(Перевод|Переводчик|Редакция|Редактор|Аннотация|Сайт|Источник)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
```

### string_clean vs string_trim

```
-- string_clean: normalize Unicode + collapse whitespace + trim
-- Use for: title, author, genre — any short field
string_clean("  Chapter  Title  ") --> "Chapter Title"

-- string_trim: trims whitespace only
-- Use for: description, where line breaks matter
string_trim("  text  ") --> "text"
```

**Rule:** `string_clean` for short metadata (title, genre, chapter), `string_trim` for longer description text.

### html_text — correctly extracting text

`html_text` uses `TextExtractor`, which understands HTML structure:

- `<p>` → paragraph + double line break
- `<br>` → single line break
- `<hr>` → double line break

```
-- CORRECT: preserves paragraph structure
local text = html_text(el.html)

-- WRONG for chapter text: loses line breaks
local text = el.text
```

### Regular expressions

The engine uses Java regex with support for:

- `(?i)` — case-insensitive
- `(?m)` — multiline (`^` and `$` at each line)
- `\\p{Z}` — Unicode whitespace
- `\\uFEFF` — BOM character
- `\\A` — absolute start of string

```
-- Strip HTML tags
text = regex_replace(text, "<[^>]*>", "")

-- Find a numeric ID
local id = regex_match(url, "/novel/(\\d+)/")[1]

-- Collapse repeated whitespace
text = regex_replace(text, "\\s+", " ")
```

---

## Working with the JSON API

```
function getCatalogList(index)
    local r = http_get(apiBase .. "novels?page=" .. (index + 1))
    if not r.success then return { items = {}, hasNext = false } end

    -- Parse JSON
    local data = json_parse(r.body)
    if not data then
        log_error("json_parse failed for getCatalogList")
        return { items = {}, hasNext = false }
    end

    local items = {}
    -- data may be an array, or an object with a data/items/results field
    local novelList = data.data or data.items or data.results or data
    if type(novelList) ~= "table" then return { items = {}, hasNext = false } end

    for _, novel in ipairs(novelList) do
        local title = novel.title or novel.name or ""
        local id    = tostring(novel.id or "")
        if title ~= "" and id ~= "" then
            table.insert(items, {
                title = string_clean(title),
                url   = baseUrl .. "/novel/" .. id,
                cover = absUrl(novel.cover or novel.image or "")
            })
        end
    end

    -- Determining hasNext
    local hasNext = data.hasNext                       -- boolean field
        or (data.pagination and data.pagination.hasMore)
        or (#items > 0 and data.total and data.total > (index + 1) * 40)
        or (#items >= 20)  -- heuristic: if 20+ were returned, there's probably more

    return { items = items, hasNext = hasNext == true or hasNext ~= false and #items > 0 }
end
```

### Deep field access

```
-- Safe access to nested fields
local cover = (novel.poster and novel.poster.medium) or ""
local title = (novel.names and (novel.names.rus or novel.names.eng)) or novel.name or ""

-- Serializing back to JSON (for use in a POST)
local body = json_stringify({
    page = 1,
    filters = { status = "ongoing" }
})
```

---

## Catalog and Pagination

### Standard pagination schemes

**Scheme 1: `?page=N` parameter**

```
function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/catalog?page=" .. page
    -- ...
    return { items = items, hasNext = #items > 0 }
end
```

**Scheme 2: Cursor / offset**

```
local ITEMS_PER_PAGE = 20
function getCatalogList(index)
    local offset = index * ITEMS_PER_PAGE
    local url = apiBase .. "novels?offset=" .. offset .. "&limit=" .. ITEMS_PER_PAGE
    -- ...
end
```

**Scheme 3: A single page (the whole list at once)**

```
function getCatalogList(index)
    if index > 0 then return { items = {}, hasNext = false } end
    -- load everything
end
```

**Scheme 4: Auto-detection via detect_pagination**

```
local pagination = detect_pagination(r.body)
return { items = items, hasNext = pagination.hasNext }
```

### URL filter-building pattern

```
local url = baseUrl .. "/search?page=" .. page

-- Simple parameters
if sort ~= "" then url = url .. "&sort=" .. url_encode(sort) end
if status ~= "all" then url = url .. "&status=" .. status end

-- Arrays (several identical parameters)
for _, v in ipairs(genres_included) do
    url = url .. "&genre[]=" .. url_encode(v)
end

-- Comma-separated arrays
if #tags_included > 0 then
    url = url .. "&tags=" .. table.concat(tags_included, ",")
end
```

---

## Chapter List

### Pattern 1: All chapters on a single page

```
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local chapters = {}
    for _, a in ipairs(html_select(r.body, ".chapters-list a[href]")) do
        local title = string_trim(a.title)
        if title == "" then title = string_trim(a.text) end
        table.insert(chapters, {
            title = string_clean(title),
            url   = absUrl(a.href)
        })
    end
    return chapters
end
```

### Pattern 2: Paginated AJAX (like jaomix)

```
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    -- Determine the number of pages
    local pages = html_select(r.body, ".pagination a[href]")
    local maxPage = 1
    for _, a in ipairs(pages) do
        local p = tonumber(a.text)
        if p and p > maxPage then maxPage = p end
    end

    local allChapters = {}
    for page = 1, maxPage do
        local pr = http_post(baseUrl .. "/ajax", "action=chapters&page=" .. page, {
            headers = { ["X-Requested-With"] = "XMLHttpRequest" }
        })
        if not pr.success then break end

        for _, a in ipairs(html_select(pr.body, "a[href]")) do
            table.insert(allChapters, {
                title = string_clean(a.text),
                url   = absUrl(a.href)
            })
        end

        sleep(200)
    end

    return allChapters
end
```

### Pattern 3: JSON API with volumes

```
function getChapterList(bookUrl)
    local novelId = bookUrl:match("/novel/(%d+)")
    if not novelId then return {} end

    local r = http_get(apiBase .. "novels/" .. novelId .. "/chapters")
    if not r.success then return {} end

    local data = json_parse(r.body)
    if not data or not data.volumes then return {} end

    local chapters = {}
    for _, volume in ipairs(data.volumes) do
        local volTitle = "Volume " .. tostring(volume.num or "")
        for _, ch in ipairs(volume.chapters or {}) do
            table.insert(chapters, {
                title  = string_clean(ch.title or "Chapter " .. tostring(ch.num)),
                url    = baseUrl .. "/read/" .. novelId .. "/" .. ch.id,
                volume = volTitle
            })
        end
    end
    return chapters
end
```

### Parallel loading via http_get_batch

```
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    -- Collect the URLs of all pages
    local slug = bookUrl:match("/([^/]+)$")
    local maxPage = 1
    for _, a in ipairs(html_select(r.body, ".pagination a")) do
        local p = tonumber(a.text)
        if p and p > maxPage then maxPage = p end
    end

    -- Load all pages in parallel
    local urls = {}
    for p = 2, maxPage do
        table.insert(urls, baseUrl .. "/novel/" .. slug .. "/chapters?page=" .. p)
    end

    local firstPageChapters = parseChaptersFromHtml(r.body)
    local allChapters = firstPageChapters

    if #urls > 0 then
        local results = http_get_batch(urls)
        for _, res in ipairs(results) do
            if res.success then
                for _, ch in ipairs(parseChaptersFromHtml(res.body)) do
                    table.insert(allChapters, ch)
                end
            end
        end
    end

    return allChapters
end
```

### getChapterListHash

An optional function. If it returns a string, it's used to determine whether the chapter list has changed (so the whole list doesn't need to be reloaded).

```
function getChapterListHash(bookUrl)
    -- IMPORTANT: always a direct http_get, NOT fetchPage!
    -- The cache would make the hash stale, and chapter updates wouldn't be detected.
    local r = http_get(bookUrl)
    if not r.success then return nil end
    -- Return something that uniquely identifies the current state:
    -- URL of the last chapter, chapter count, last-update date
    local lastChapter = html_select_first(r.body, ".chapter-list a:last-child")
    return lastChapter and lastChapter.href or nil
end
```

---

## Paginated Chapter List (parsePage)

> Use this only if the site splits the chapter list across multiple pages via AJAX or pagination.
> Most plugins don't need this — `getChapterList` is enough.
> If `parsePage` is implemented, you don't need to write `getChapterList` or `getChapterListHash` for this plugin — the engine won't call them.

### Why

`getChapterList` reloads every page each time the library is updated.
If there are 10 pages, that's 10 requests every time. `parsePage` solves this: on update,
the engine re-reads only the last page and fetches new ones if they've appeared.

### What you need to implement

A single function, `parsePage(bookUrl, page)`, that returns the chapters of one page:

```
function parsePage(bookUrl, page)
    -- page — the page number; the engine passes 1, 2, 3... N
    -- return this page's chapters + the total number of pages
    return {
        chapters   = { { title = "...", url = "..." }, ... },
        totalPages = 10,
    }
end
```

Rules:

- Chapters within a page are in chronological order (oldest at the top, newest at the bottom)
- `totalPages` — the same number on every call, regardless of `page`
- The engine requests pages 1, 2, 3... where **1 = the oldest chapters**, N = the newest

### What the engine does

**The first time (the first library update after adding a book):**

1. Calls `parsePage(url, 1)` → gets the chapters + `totalPages = 10`
2. Calls `parsePage(url, 2)`, ..., `parsePage(url, 10)`
3. Saves all the chapters and remembers that the last page = 10

**On update:**

1. Re-reads only page 10 (the last one)
2. If `totalPages` has grown to 11, fetches only page 11
3. Adds only the new chapters — instead of 10 requests it makes 1–2

### About page order on the site

Different sites use different orders:

**The site serves old chapters on page 1** (direct order, as the engine expects):

```
function parsePage(bookUrl, page)
    local r = http_get(bookUrl .. "/chapters?page=" .. page)
    if not r.success then return { chapters = {}, totalPages = 1 } end

    local totalPages = 1
    for _, a in ipairs(html_select(r.body, ".pagination a[href]")) do
        local p = tonumber(a.href:match("page=(%d+)"))
        if p and p > totalPages then totalPages = p end
    end

    local chapters = {}
    for _, a in ipairs(html_select(r.body, ".chapter-list a[href]")) do
        table.insert(chapters, { title = string_clean(a.text), url = absUrl(a.href) })
    end

    return { chapters = chapters, totalPages = totalPages }
end
```

A real example — `syosetu.lua` uses the same logic inside `getChapterList`:
it loads page 1 first, determines `totalPages` via `.c-pager__item--last`,
then pages 2..N.

---

**The site serves new chapters on page 1** (reverse order, as with jaomix):

You need to invert it: the engine asks for page 1 (old) → we take the site's last page.

```
local function getTotalPages(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return 1 end
    local opts = html_select(r.body, "select.sel-toc option")
    return #opts > 0 and #opts or 1
end

local function fetchAjaxPage(bookUrl, sitePage)
    local pr = http_post(
        baseUrl .. "wp-admin/admin-ajax.php",
        "action=loadpagenavchapstt&page=" .. tostring(sitePage),
        { headers = { ["X-Requested-With"] = "XMLHttpRequest", ["Referer"] = bookUrl } }
    )
    if not pr.success then return {} end

    local chapters = {}
    for _, a in ipairs(html_select(pr.body, "div.title a[href]")) do
        local h2 = html_select_first(a.html, "h2")
        table.insert(chapters, {
            title = h2 and string_clean(h2.text) or string_clean(a.text),
            url   = absUrl(a.href)
        })
    end
    return chapters
end

function parsePage(bookUrl, page)
    local totalPages = getTotalPages(bookUrl)

    -- Invert: engine page=1 → site's last page (old chapters)
    --         engine page=N → site's page 1 (new chapters)
    local sitePage = totalPages - page + 1

    local raw = fetchAjaxPage(bookUrl, sitePage)

    -- Within a page the site also puts newest first — reverse it
    local chapters = {}
    for i = #raw, 1, -1 do
        table.insert(chapters, raw[i])
    end

    sleep(math.random(150, 300))
    return { chapters = chapters, totalPages = totalPages }
end
```

### getChapterList — not needed if parsePage exists

The engine determines what to use on its own: if a plugin declares `parsePage`,
the engine **always** calls it (both for the initial load and for updates); `getChapterList` is never called at all. There's no need to declare `getChapterList` "just in case" — it would be dead code that never runs
as long as `parsePage` is present in the file.

`getChapterList` is only needed for plugins **without** `parsePage` — i.e. ones
where the chapter list is served in a single request or the site doesn't support
paginated loading.

### getChapterListHash — also not needed with parsePage

`getChapterListHash` is the update-detection mechanism for plugins **without** `parsePage`. If `parsePage` is implemented, the engine tracks
updates on its own through it: it re-reads the last known page
and compares `totalPages`/chapters directly — it doesn't need a separate hash,
and you don't need to write `getChapterListHash` for such a plugin.

The example below is only relevant for plugins without `parsePage`:

```
-- Option 1: URL of the last chapter via a quick request (jaomix)
function getChapterListHash(bookUrl)
    local pr = http_post(
        baseUrl .. "wp-admin/admin-ajax.php",
        "action=loadpagenavchapstt&page=1",   -- site page 1 = the newest
        { headers = { ["X-Requested-With"] = "XMLHttpRequest", ["Referer"] = bookUrl } }
    )
    if not pr.success then return nil end
    local el = html_select_first(pr.body, "div.title a[href]")
    return el and el.href or nil
end

-- Option 2: chapter counter from the API (novelbuddy, ranobehub)
function getChapterListHash(bookUrl)
    local manga = fetchMangaNextData(bookUrl)
    if not manga then return nil end
    local count = manga.stats and manga.stats.chapters_count
    return count and tostring(count) or manga.updated_at
end
```

---

## Chapter Text

`getChapterText(html, url)` receives the full HTML of the page and its URL. The engine loads the page itself — the plugin only parses it.

### Standard pattern

```
function getChapterText(html, url)
    -- Step 1: Remove unwanted elements
    local cleaned = html_remove(html,
        "script", "style",              -- always
        ".ads", ".advertisement",       -- ads
        ".chapter-nav", ".nav-links",   -- navigation
        "#comments", ".disqus"          -- comments
    )

    -- Step 2: Find the container with the text
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then
        -- Fallback options
        el = html_select_first(cleaned, "#content, .entry-content, .text-content")
    end
    if not el then return "" end

    -- Step 3: Extract text while preserving paragraph structure
    local text = html_text(el.html)

    -- Step 4: Standard transformations
    return applyStandardContentTransforms(text)
end
```

### Common CSS selectors for chapter text

```
-- General
".chapter-content"
"#chapter-content"
".entry-content"
"#content"
".text-content"
".chapter-text"
".content-area"

-- Site-specific
"div.ui.text.container[data-container]"  -- RanobeHub
".chapter-content"                        -- NovelFire, RoyalRoad
".entry-content"                          -- Jaomix, WordPress
```

### When the site encrypts content / uses an API

```
function getChapterText(html, chapterUrl)
    -- Extract parameters from the URL
    local novelId  = chapterUrl:match("/novel/(%d+)/")
    local chapterNo = tonumber(chapterUrl:match("/chapter%-(%d+)"))
    if not novelId or not chapterNo then return "" end

    -- Request via the API
    local r = http_post(
        baseUrl .. "/api/reader/get",
        json_stringify({ novel_id = novelId, chapter = chapterNo }),
        { headers = { ["Content-Type"] = "application/json" } }
    )
    if not r.success then return "" end

    local data = json_parse(r.body)
    if not data or not data.content then return "" end

    -- Assemble paragraphs
    local paragraphs = {}
    if type(data.content) == "table" then
        for _, para in ipairs(data.content) do
            local text = string_trim(tostring(para))
            if text ~= "" then table.insert(paragraphs, text) end
        end
    else
        table.insert(paragraphs, string_normalize(tostring(data.content)))
    end

    return applyStandardContentTransforms(table.concat(paragraphs, "\n\n"))
end
```

---

## Catalog Filters

For a plugin to support filters, it needs to declare two functions: `getFilterList()` and `getCatalogFiltered(index, filters)`.

### getFilterList()

Returns an array of filter descriptions. The list always originates from Lua — there's no hardcoding in Kotlin.

```
function getFilterList()
    return {
        -- Choose a single value from a list
        {
            type         = "select",
            key          = "sort",
            label        = "Sort By",
            defaultValue = "latest",
            options = {
                { value = "latest",  label = "Latest Update" },
                { value = "popular", label = "Most Popular"  },
                { value = "rating",  label = "Top Rated"     },
            }
        },

        -- Multiple selection (include)
        {
            type  = "checkbox",
            key   = "language",
            label = "Language",
            options = {
                { value = "1", label = "Chinese"  },
                { value = "2", label = "Korean"   },
                { value = "3", label = "Japanese" },
            }
        },

        -- Tri-state (include / exclude / ignore)
        {
            type  = "tristate",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "action",  label = "Action"  },
                { value = "fantasy", label = "Fantasy" },
                { value = "romance", label = "Romance" },
            }
        },

        -- Toggle switch
        {
            type         = "switch",
            key          = "completed_only",
            label        = "Completed Only",
            defaultValue = false
        },

        -- Text input
        {
            type         = "text",
            key          = "author",
            label        = "Author Name",
            defaultValue = ""
        },

        -- Sorting with direction
        {
            type             = "sort",
            key              = "order",
            label            = "Order By",
            defaultValue     = "rating",
            defaultAscending = false,
            options = {
                { value = "rating",  label = "Rating"       },
                { value = "views",   label = "Views"        },
                { value = "updated", label = "Last Updated" },
            }
        },
    }
end
```

### getCatalogFiltered(index, filters)

How Kotlin passes filters into `filters` (a LuaTable):

| Filter type | Key in filters             | Value                        |
| ----------- | --------------------------- | ----------------------------- |
| `select`    | `filters["key"]`            | string                        |
| `checkbox`  | `filters["key_included"]`   | array table of strings        |
| `tristate`  | `filters["key_included"]`   | array table of strings        |
| `tristate`  | `filters["key_excluded"]`   | array table of strings        |
| `switch`    | `filters["key"]`            | `"true"` or `"false"`         |
| `text`      | `filters["key"]`            | string                        |
| `sort`      | `filters["key"]`            | string (the selected value)   |
| `sort`      | `filters["key_ascending"]`  | `"true"` or `"false"`         |

```
function getCatalogFiltered(index, filters)
    local page = index + 1

    -- Read values with defaults
    local sort        = filters["sort"]           or "latest"
    local genres_inc  = filters["genres_included"] or {}
    local genres_exc  = filters["genres_excluded"] or {}
    local lang_inc    = filters["language_included"] or {}
    local completed   = filters["completed_only"] or "false"
    local author      = filters["author"] or ""

    -- Sorting with direction
    local order_val = filters["order"]           or "rating"
    local order_asc = filters["order_ascending"] or "false"

    -- Build the URL
    local url = baseUrl .. "/search?page=" .. page
        .. "&sort=" .. url_encode(sort)

    if completed == "true" then url = url .. "&status=completed" end
    if author ~= "" then url = url .. "&author=" .. url_encode(author) end

    -- Arrays
    for _, v in ipairs(genres_inc) do url = url .. "&genre[]=" .. v end
    for _, v in ipairs(genres_exc) do url = url .. "&genre_ex[]=" .. v end
    for _, v in ipairs(lang_inc)   do url = url .. "&lang[]=" .. v    end

    url = url .. "&orderBy=" .. order_val
             .. "&asc=" .. (order_asc == "true" and "1" or "0")

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    -- Parsing is analogous to getCatalogList
    local items = {}
    for _, card in ipairs(html_select(r.body, ".novel-item")) do
        local titleEl = html_select_first(card.html, "h3 a")
        if titleEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(html_attr(card.html, "img", "src"))
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end
```

---

## Plugin Settings

For persistent settings saved across sessions.

```
-- Constant — the settings key
local PREF_LANG = "my_source_language"

local function getLang()
    local v = get_preference(PREF_LANG)
    return (v ~= "" and v) or "en"  -- default "en"
end

function getSettingsSchema()
    return {
        {
            key     = PREF_LANG,
            type    = "select",
            label   = "Language",
            current = getLang(),       -- current value for the UI
            options = {
                { value = "en", label = "English" },
                { value = "ru", label = "Russian" },
            }
        }
    }
end

-- Usage inside functions
function getCatalogList(index)
    local lang = getLang()
    local url = baseUrl .. "/" .. lang .. "/novels?page=" .. (index + 1)
    -- ...
end
```

**Key-naming rules:** use a prefix with the plugin ID to avoid conflicts: `"my_source_language"`, `"my_source_mode"`.

---

## Helpers and Utilities

### The mandatory absUrl

Always define this function — it's needed to correctly handle relative URLs:

```
local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end
```

### Extracting an ID from a URL

```
-- Simple pattern
local novelId = bookUrl:match("/novel/(%d+)")

-- Segment after the last slash
local slug = bookUrl:match("/([^/]+)$")

-- Regex via regex_match
local ids = regex_match(bookUrl, "/novel/(\\d+)-(.*?)(?:/|$)")
local id   = ids[1]
local slug = ids[2]
```

### Cache (lives for the session)

```
-- Local module variable — lives until the app is closed
local _bookDataCache = {}

local function fetchBookData(bookUrl)
    if _bookDataCache[bookUrl] then return _bookDataCache[bookUrl] end
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local data = json_parse(r.body)
    if data then _bookDataCache[bookUrl] = data end
    return data
end

-- Used across several functions — one HTTP request instead of three
function getBookTitle(bookUrl)
    local data = fetchBookData(bookUrl)
    return data and string_clean(data.title) or nil
end

function getBookCoverImageUrl(bookUrl)
    local data = fetchBookData(bookUrl)
    return data and absUrl(data.cover) or nil
end
```

**Important:** the cache resets when the app is closed/restarted. Don't use it for data that must be up to date on every run.

---

## Full API Reference

### HTTP

| Function                           | Description                                          |
| ------------------------------------ | ------------------------------------------------------ |
| `http_get(url [, config])`         | GET request → `{success, body, code}`                |
| `http_post(url, body [, config])`  | POST request → `{success, body, code}`               |
| `http_get_batch(urls)`             | Parallel GET → array of `{success, body, code}`      |
| `get_cookies(url)`                 | Get cookies for a domain → table                     |
| `set_cookies(url, table)`          | Set cookies                                           |

### HTML / DOM

| Function                               | Description                              |
| ----------------------------------------- | ------------------------------------------ |
| `html_parse(html)`                     | Parse → `{text, html, title, body}`      |
| `html_select(html, selector)`          | All matches → array of elements          |
| `html_select_first(html, selector)`    | First match → element or nil             |
| `html_attr(html, selector, attr)`      | Attribute of the first match → string    |
| `html_text(html)`                      | Text preserving paragraph structure      |
| `html_remove(html, sel1, sel2, ...)`   | Remove elements → HTML string            |

### Strings

| Function                                  | Description                                    |
| -------------------------------------------- | -------------------------------------------------- |
| `string_clean(s)`                          | normalize + collapse whitespace + trim         |
| `string_trim(s)`                           | trim whitespace                                |
| `string_normalize(s)`                      | Unicode NFKC normalization                     |
| `string_split(s, sep)`                     | Split a string → array                         |
| `string_starts_with(s, prefix)`            | boolean                                        |
| `string_ends_with(s, suffix)`              | boolean                                        |
| `regex_replace(s, pattern, replacement)`   | Replace via regex                              |
| `regex_match(s, pattern)`                  | Find all matches → array                       |
| `unescape_unicode(s)`                      | Unescape `\uXXXX` sequences                    |

### URL

| Function                          | Description                                   |
| ------------------------------------ | ------------------------------------------------ |
| `url_encode(s)`                    | URL-encode as UTF-8                           |
| `url_encode_charset(s, charset)`   | URL-encode in a given charset (for GBK)       |
| `url_resolve(base, href)`          | Resolve a relative URL                        |

### JSON

| Function              | Description                    |
| ----------------------- | --------------------------------- |
| `json_parse(s)`       | String → Lua table/value        |
| `json_stringify(v)`   | Lua table → JSON string          |

### Crypto / Encoding

| Function                        | Description                    |
| ---------------------------------- | ---------------------------------- |
| `base64_encode(s)`               | Base64 encode                  |
| `base64_decode(s)`               | Base64 decode                  |
| `aes_decrypt(data, key, iv)`     | AES/CBC/PKCS5 decryption        |

### Storage

| Function                        | Description                                      |
| ---------------------------------- | ----------------------------------------------------- |
| `get_preference(key)`            | Read from SharedPreferences "lua_preferences"    |
| `set_preference(key, value)`     | Write to SharedPreferences "lua_preferences"     |

### Utilities

| Function                     | Description                                    |
| -------------------------------- | ------------------------------------------------- |
| `sleep(ms)`                     | Delay in milliseconds                          |
| `detect_pagination(html)`       | Detect hasNext → `{hasNext, next_url}`         |
| `log_info(msg)`                 | INFO log (Timber)                              |
| `log_error(msg)`                | ERROR log (Timber)                             |
| `os_time()`                     | Unix timestamp in milliseconds                 |

---

## Full Plugin Template

A minimal working template with comments:

```
-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "my_source"
name     = "My Source"
version  = "1.0.0"
baseUrl  = "https://example.com"
language = "en"
icon     = "https://raw.githubusercontent.com/user/repo/main/icons/my_source.png"

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

-- ── Catalog ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local r = http_get(baseUrl .. "/novels?page=" .. page)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".novel-item")) do
        local titleEl = html_select_first(card.html, "h3 a")
        if titleEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(html_attr(card.html, "img", "src"))
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end

-- ── Search ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "/search?q=" .. url_encode(query) .. "&page=" .. page
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".novel-item")) do
        local titleEl = html_select_first(card.html, "h3 a")
        if titleEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(html_attr(card.html, "img", "src"))
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end

-- ── Book details ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "h1.novel-title")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cover = html_attr(r.body, ".cover-image img", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".novel-description")
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local genres = {}
    for _, a in ipairs(html_select(r.body, ".genres-list a")) do
        local label = string_trim(a.text)
        if label ~= "" then table.insert(genres, label) end
    end
    return genres
end

-- ── Chapter list ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then
        log_error("my_source: getChapterList failed for " .. bookUrl)
        return {}
    end

    local chapters = {}
    for _, a in ipairs(html_select(r.body, ".chapter-list a[href]")) do
        local chUrl = absUrl(a.href)
        if chUrl ~= "" then
            table.insert(chapters, {
                title = string_clean(a.text),
                url   = chUrl
            })
        end
    end

    return chapters
end

function getChapterListHash(bookUrl)
    -- IMPORTANT: a direct http_get, not fetchPage — needs an up-to-date response
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".chapter-list a:last-child")
    return el and el.href or nil
end

-- ── Chapter text ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
    local cleaned = html_remove(html, "script", "style", ".ads", ".chapter-nav")
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end

-- ── Filters (optional) ─────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            type         = "select",
            key          = "sort",
            label        = "Sort By",
            defaultValue = "latest",
            options = {
                { value = "latest",  label = "Latest Update" },
                { value = "popular", label = "Most Popular"  },
            }
        },
        {
            type  = "tristate",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "action",  label = "Action"  },
                { value = "fantasy", label = "Fantasy" },
            }
        },
    }
end

function getCatalogFiltered(index, filters)
    local page       = index + 1
    local sort       = filters["sort"] or "latest"
    local genres_inc = filters["genres_included"] or {}
    local genres_exc = filters["genres_excluded"] or {}

    local url = baseUrl .. "/search?sort=" .. sort .. "&page=" .. page
    for _, v in ipairs(genres_inc) do url = url .. "&genre[]=" .. v    end
    for _, v in ipairs(genres_exc) do url = url .. "&genre_ex[]=" .. v end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".novel-item")) do
        local titleEl = html_select_first(card.html, "h3 a")
        if titleEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(html_attr(card.html, "img", "src"))
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end
```

---

## Common Mistakes

### 1. Incorrect nil handling

```
-- ❌ Crashes if r.body is empty or html_select returned nil
local title = html_select_first(r.body, "h1").text

-- ✅ Check for nil
local el = html_select_first(r.body, "h1")
local title = el and string_clean(el.text) or nil
```

### 2. Using el.text instead of html_text for chapter text

```
-- ❌ Loses line breaks between paragraphs
local text = el.text

-- ✅ Preserves <p>, <br> structure
local text = html_text(el.html)
```

### 3. Ignoring encoding

```
-- ❌ Cyrillic breaks on GBK/Big5 sites
local r = http_get(url)

-- ✅ Specify the encoding
charset = "GBK"  -- in the plugin metadata
-- or for a specific request:
local r = http_get(url, { charset = "GBK" })
-- and correspondingly for search:
url = baseUrl .. "/search?q=" .. url_encode_charset(query, "GBK")
```

### 4. Relative URLs without absUrl

```
-- ❌ May return "/novel/123" instead of "https://example.com/novel/123"
url = a.href

-- ✅
url = absUrl(a.href)
```

### 5. Wrong chapter order

```
-- Most sites show the newest chapters first in the HTML.
-- getChapterList should return them in chronological order (oldest → newest).
-- If the site serves them in reverse order:

-- Option 1: reverse the result
local reversed = {}
for i = #chapters, 1, -1 do
    table.insert(reversed, chapters[i])
end
return reversed

-- Option 2: load pages from the end (like jaomix)
for page = maxPage, 1, -1 do
    -- ...
end
```

### 6. Forgetting to check r.success

```
-- ❌ If the request fails, json_parse gets called on the error string
local data = json_parse(http_get(url).body)

-- ✅
local r = http_get(url)
if not r.success then return { items = {}, hasNext = false } end
local data = json_parse(r.body)
if not data then return { items = {}, hasNext = false } end
```

### 7. Wrong filter key in getCatalogFiltered

```
-- If getFilterList declares key = "genres" with type "tristate",
-- the filters table will contain the keys "genres_included" and "genres_excluded" — NOT "genres"

-- ❌
local genres = filters["genres"]

-- ✅
local genres_inc = filters["genres_included"] or {}
local genres_exc = filters["genres_excluded"] or {}
```

### 9. Repeated http_get calls to the same page

```
-- ❌ The engine calls the functions in parallel — each one makes its own request
function getBookTitle(bookUrl)
    local r = http_get(bookUrl)   -- request 1
    ...
end
function getBookDescription(bookUrl)
    local r = http_get(bookUrl)   -- request 2 to the same page
    ...
end

-- ✅ Use fetchPage — see the "Page Caching" section
local _pageCache = {}
local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then _pageCache[url] = r.body end
    return r.success and r.body or nil
end
```

**Important:** `getChapterListHash` should **NOT** be switched to `fetchPage` — it must always get a fresh response via a direct `http_get`, or new chapters will stop being detected.

### 10. Hardcoding headers that are already added automatically

`User-Agent`, `Referer`, and `Accept-Language` are added by the engine to every request automatically. There's no need to duplicate them in the plugin — it clutters the code and breaks the global settings (for example, the user's custom UA from the app settings stops working).

```
-- ❌ Duplicating what the engine already does — the app-settings UA is ignored
local r = http_get(url, {
    headers = {
        ["User-Agent"]       = "Mozilla/5.0 ...",
        ["Accept-Language"]  = "ru-RU,ru;q=0.9",
        ["Referer"]          = baseUrl,
        ["X-Requested-With"] = "XMLHttpRequest",
    }
})

-- ✅ Only specify what the engine doesn't add on its own
local r = http_get(url, {
    headers = {
        ["X-Requested-With"] = "XMLHttpRequest",
    }
})

-- ✅ Override a default only when a specific value is needed
local r = http_post(ajaxUrl, body, {
    headers = {
        ["Referer"]          = bookUrl,  -- need the book page, not the domain root
        ["X-Requested-With"] = "XMLHttpRequest",
    }
})
```

### 8. Missing log_error while debugging

```
-- Add logs in critical spots — they're visible via Timber/Logcat
function getChapterList(bookUrl)
    local id = bookUrl:match("/novel/(%d+)")
    if not id then
        log_error("my_source: cannot extract novelId from " .. bookUrl)
        return {}
    end
    local r = http_get(apiBase .. id .. "/chapters")
    if not r.success then
        log_error("my_source: chapters API failed code=" .. tostring(r.code))
        return {}
    end
    -- ...
end
```
