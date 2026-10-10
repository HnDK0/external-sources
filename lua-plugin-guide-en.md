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
13. [Video plugins (content_type = "video")](#video-plugins-content_type--video)
14. [Plugin Errors (show_error)](#plugin-errors-show_error)
15. [Catalog Filters](#catalog-filters)
16. [Plugin Settings](#plugin-settings)
17. [Helpers and Utilities](#helpers-and-utilities)
18. [Shared Libraries (require_lib)](#shared-libraries-require_lib)
19. [Heavy Operations (Kotlin API)](#heavy-operations-kotlin-api)
20. [Full API Reference](#full-api-reference)
21. [Full Plugin Template](#full-plugin-template)
22. [Common Mistakes](#common-mistakes)

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
function getBookStatus(bookUrl) ... end       -- book status, see section below
function getBookLastUpdate(bookUrl) ... end   -- last update date, see section below
function getChapterListHash(bookUrl) ... end  -- only needed if there's no parsePage (see below)
function parsePage(bookUrl, page) ... end     -- paginated chapter list; if present, it fully
                                               -- replaces getChapterList and getChapterListHash
function getFilterList() ... end
function getCatalogFiltered(index, filters) ... end
function getSettingsSchema() ... end
function getUserAgentPreset() ... end         -- name of the UA preset, see "Working with HTTP"
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
content_type = "manga"        -- only for manga; omit for novels (default: novel)
content_type = "video"        -- video mode: built-in player, see "Video plugins"
cf_options  = {               -- Cloudflare/WAF bypass settings (optional)
    whitelist = false,         -- true = engine does NOT bypass CF for this host
    ignore_markers = {        -- domains with these markers are skipped
        "cf-wrapper", "cf-error-details"
    },
    trigger_markers = {       -- domains with these markers are sent to bypass
        "/WAF/VERIFY/CAPTCHA", "but-captcha"
    },
}
```

**Important about `id`:** it must match the `.lua` file name without the extension. If `id = "royal_road"`, the file must be named `royal_road.lua`.

**`cf_options`** controls the behavior of the engine's built-in Cloudflare bypass. When a site returns a CF challenge (HTTP 200/403/503/429 with `cf-challenge`, `__cf_chl_`, `cf-browser-verification` in headers or `Server: cloudflare`), the engine automatically solves Turnstile in a hidden WebView and bakes `cf_clearance`. `cf_options` affects this process:

- `whitelist = true` — engine **skips** bypass and returns the response as-is. Use when the site works correctly without bypass (CF is on CDN but content is accessible directly) or when bypass breaks authentication.
- `ignore_markers` — domains whose URL contains one of these markers are **skipped** by bypass (same behavior as `whitelist`).
- `trigger_markers` — domains whose URL contains one of these markers are **always** sent to bypass, even if bypass would not normally trigger.

If `cf_options` is not specified, the engine bypasses CF automatically based on response headers.

**`referer`** — a custom Referer for images (optional). Covers on CDNs with hotlink protection require the original site in the Referer, not the host of the image itself. Declared as a global at the root of the script — before all functions:

```
referer = "https://site.com/"

baseUrl = "https://site.com"
name = "Example Source"

function getCatalogList(index) ... end
```

How it works:

- **Priority:** the plugin's `referer` → the host of the page URL (catalog/book) → the host of the image itself (previous behavior when nothing is set).
- The value is sent to the header as-is (only surrounding whitespace is trimmed) — you can even include a path: `referer = "https://site.com/manga/"`.
- **Where it applies:** covers in the source's catalog, on the book/manga page, offline cover downloads (library/backup), chapter images on EPUB export.
- Does not affect the plugin's own HTTP requests (`http_get`/`http_post`) — those still use their own `config.headers`.

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

- `items` — an array of `{ title, url, cover, rating? }`, where `cover` and `rating` are optional
- `hasNext` — `true` if there is a next page

`rating` is a string (e.g. `"4.6"`) taken from the list card, **without** a separate
request to the book page. If a card has no rating (e.g. in search results), simply
omit the key. Numbers are accepted too and converted to strings.

Rating formats (parsed by the app at display time):

- `"4.3"` — a bare number = rating on a 0-5 scale (default type, backward compatible)
- `"Rating: 4.3"` — a rating explicitly marked with the word `Rating`
- `"Rating: 8.7/10"` — a rating on another scale: the `/N` suffix tells the app to rescale it to 0-5 (shown as `4.4/5`)
- `"Rank: 3"` — a rank: the word `Rank` is required, shown as is

The type is determined by the word: `rank` → rank, `rating` → rating, a bare number → rating.
Garbage is not shown: a number outside 0-5 without an explicit scale, a number above its declared scale, or no number at all.

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

### getBookRating(bookUrl) — optional

Book rating (string, e.g. `"4.8"`) or `nil` if absent. Called when opening a book
and for library backfill, so it must NOT parse the chapter list — only the rating.

```
function getBookRating(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".rating .nub")
    return el and string_clean(el.text) or nil
end
```

Ready-to-use templates:

```
-- 1. Rating: a clean number from a card attribute
rating = html_attr(card.html, ".info-rating", "data-rating")   -- "4.6"

-- 2. Rating: extract the number from dirty text ("Rating: 4.6 of 5" → "4.6")
local n = string.match(string_clean(el.text), "%d+%.?%d*")

-- 3. Rating on a 10-point scale — the app rescales it to 0-5 itself
rating = "Rating: " .. n .. "/10"                              -- "Rating: 8.7/10"

-- 4. Rank (the word Rank is required)
rating = "Rank: " .. n                                         -- "Rank: 3"
```

A comma as the decimal separator is handled too (`4,6` = `4.6`).

### getBookStatus(bookUrl) — optional

Book status: the text as the site provides it ("Ongoing", "Completed", "Анонс", "Завершён", etc.) or `nil` if the site doesn't show a status. No mapping to English values — the app shows the text as-is with a single generic status icon (the same for every status) and a "Status: %s" label.

```
function getBookStatus(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local el = html_select_first(html, ".book-status")
    return el and string_clean(el.text) or nil
end
```

### getBookLastUpdate(bookUrl) — optional

Last chapter update date normalized to `YYYY-MM-DD` (no time — keeps the UI string short), or `nil` if it can't be parsed.

The golden rule — **implement only the format the site actually serves**. First find the date on the book page (or in the JSON API) in the fixture, then write a parser exactly for it. A universal "parse every format" helper is not needed: it bloats the plugin and silently lies (e.g. it treats an hourly relative date as days). Two verified references below — pick the one matching your site.

Where to look:

- the `meta[property='article:modified_time']` tag — almost always an ISO date with time;
- a `<time>` element on the book page or next to the last chapter (its text or `datetime` attribute);
- the book JSON API: `updatedAt`, `lastUpdated`, `last_update` fields. **Cross-check the field against what the page actually shows** — it may go stale (NovelArrow's `updated_date_webnovel` lagged a week behind the UI and can't be used).

**Format 1 — ISO date in a meta tag** (`en/novelarrow.lua`). The site always serves `article:modified_time` as `2026-08-18T23:00:15.751Z` (the same value the book page shows) — just take the first 10 characters, no helper needed:

```
function getBookLastUpdate(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local v = html_attr(html, "meta[property='article:modified_time']", "content")
    local y, m, d = string.match(v, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return y and (y .. "-" .. m .. "-" .. d) or nil
end
```

**Format 2 — relative date** (`en/novelphoenix.lua`). The site only shows strings like `Updated 8 hours ago`, `Updated 3 days ago`, `Updated 2 years ago` (verify the actual units: minutes/hours/days/weeks/months/years, singular and plural). Computed with `os.time()` (seconds) and `os.date()`, which are available in the engine sandbox; months and years are approximate (30/365 days):

```
-- Normalizes a relative site date to YYYY-MM-DD. Unrecognized → nil.
local function normalizeUpdateDate(raw)
    if not raw or raw == "" then return nil end
    local n, unit = string.match(raw, "Updated%s+(%d+)%s+(%w+)%s+ago")
    if not n then return nil end
    local mult = {
        minute = 60, minutes = 60,
        hour = 3600, hours = 3600,
        day = 86400, days = 86400,
        week = 7 * 86400, weeks = 7 * 86400,
        month = 30 * 86400, months = 30 * 86400,
        year = 365 * 86400, years = 365 * 86400,
    }
    local secs = mult[unit]
    if not secs then return nil end
    return os.date("%Y-%m-%d", os.time() - n * secs)
end
```

A page may contain several similar elements (NovelPhoenix has a second `p.update` — "Average score is 4.6" in the reviews block). Iterate all of them and take the first that passes the format — `normalizeUpdateDate` will discard the rest:

```
function getBookLastUpdate(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    for _, el in ipairs(html_select(html, ".update")) do
        local d = normalizeUpdateDate(string_clean(el.text))
        if d then return d end
    end
    return nil
end
```

If the format doesn't match — return `nil`: the app simply won't show the date. Don't invent handling for formats the site doesn't have.

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

### Overriding the User-Agent (getUserAgentPreset)

Some sites serve different layouts depending on the User-Agent (mobile/desktop), and the app's global UA isn't enough. For that, the plugin declares a function:

```lua
function getUserAgentPreset()
  return "Safari Mobile"
end
```

Mechanics (`LuaSourceAdapter.registerUAPreset`):
- Called **once** when the adapter is created, with no arguments.
- The returned preset name is registered against the source **`id`** and the **host from `baseUrl`** — it applies to all requests of the source, including image loads on the same domain.
- An invalid/blank name is ignored (a warning is written to the log).

Valid names (`UAPresets`):

| Preset (full name) | Alias |
|---|---|
| `Chrome 150 (Windows)` | `Chrome Desktop` |
| `Safari 18 (macOS)` | `Safari Desktop` |
| `Firefox 152 (Windows)` | `Firefox Desktop` |
| `Edge 150 (Windows)` | `Edge Desktop` |
| `Chrome 150 (Android)` | `Chrome Mobile` |
| `Safari 18 (iOS)` | `Safari Mobile` |
| `Firefox 152 (Android)` | `Firefox Mobile` |
| `Edge 150 (Android)` | `Edge Mobile` |
| `Samsung Internet 30.0 (Android)` | `Samsung Mobile` |

User-Agent priority for a request: value from the plugin's `config.headers` → preset by source id → preset by host → the app's global UA. In other words, **if the plugin manually sets `User-Agent` in `headers`, the preset won't apply** — use `getUserAgentPreset` instead of hardcoding a UA, so the user's global settings aren't overridden.

Repo example — `en/readfrom.lua` (mobile layout of readfrom.net).

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

-- Binary mode — for images, fonts, and other binary data
local r = http_get("https://example.com/image.png", { binary = true })
if r.success then
    -- r.body = {137, 80, 78, 71, ...} — byte table (1-based Lua table)
    local bytes = r.body
    print("Size: " .. #bytes .. " bytes")
    -- Check PNG header (first 8 bytes: 0x89 0x50 0x4E 0x47)
    if bytes[1] == 0x89 and bytes[2] == 0x50 then
        print("Valid PNG")
    end
end

-- Checking the result
if not r.success then
    log_error("Request failed: code=" .. tostring(r.code))
    return { items = {}, hasNext = false }
end
-- r.body  — response body string (or byte table when binary = true)
-- r.code  — HTTP status code (200, 404, ...)
-- r.headers — response headers table (works the same for both text and binary mode)
```

`config` parameters in addition to `headers` / `charset` / `binary`:

- `timeout` — request budget in **milliseconds** (integer `> 0`). When set, the whole call (DNS, connection, redirects, body read) is bounded by this time and runs as a **single attempt** instead of the client's long retry series (3+3+3+3+15 s). For 5xx responses short retries may happen inside the budget, so the actual time can slightly exceed the stated value. Not set or `<= 0` → previous client behavior. Exists in `http_get` and in `http_get_batch` (there — globally in `config` and per-URL in the element); not in `http_post`.
- `method = "HEAD"` — sends HEAD instead of GET (case does not matter): same headers, empty response body (`r.body == ""`), the `http_get` cache is neither read nor written, and `Cache-Control: no-cache` is added to the request. Serves as a cheap link liveness probe — the server is checked by HTTP code, the body is not downloaded. Any other method value → error `allowed: GET, HEAD`. Exists in `http_get` and in `http_get_batch` (there — globally in `config` and per-URL in the element); not in `http_post`.
- `followRedirects = false` — do not follow 3xx: `r.code` stays `3xx` and `r.headers.location` shows the target (gate/hoster sites where the redirect is the answer). Defaults to `true`.

```
-- link liveness probe: 3 s budget, no body download
local r = http_get(url, { timeout = 3000, method = "HEAD" })
local alive = r.success and r.code >= 200 and r.code < 400
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

### http_get_batch(items [, config])

Parallel loading of multiple URLs in one call. Returns an array of **the same length and in the same order**, each element being a `{ success, body, code, headers }` table.

Each element of `items` is either a **URL string** (settings come from `config`) or a **table** `{ url = ..., headers = {...}, charset = ..., binary = ..., timeout = ..., followRedirects = ..., method = ... }` — then the per-URL keys override the values from `config`. The `url` key is required in a table.

`success` is honest: in text mode it is a successful HTTP response code, with `binary = true` — `code` in the range 200..299. A failure of a single URL (network, SSRF block) yields `{ success = false, code = -1, body = <error text>, headers = {} }` **for that element only** — the neighbouring requests of the batch stay successful.

Requests run in parallel; page cache, `method = "HEAD"`, `timeout`, `followRedirects`, `charset` follow the same rules as `http_get`. Validation errors (an element that is neither a string nor a table, a table without `url`, an unsupported `method`) raise an exception **before** any request goes out to the network.

```
-- Text mode (default)
local urls = {}
for p = 2, maxPage do
    table.insert(urls, baseUrl .. "/chapters?page=" .. p)
end

local results = http_get_batch(urls)
for i, res in ipairs(results) do
    if res.success then
        -- res.body — string
    end
end

-- Binary mode — for batch loading images and other binary data
local cover_urls = {
    "https://example.com/cover1.jpg",
    "https://example.com/cover2.jpg",
    "https://example.com/cover3.jpg"
}

local results = http_get_batch(cover_urls, { binary = true })
for i, res in ipairs(results) do
    if res.success then
        -- res.body — byte table (1-based)
        print("Cover " .. i .. ": " .. #res.body .. " bytes")
    end
end
```

> **Note on `binary = true`:**
> - `resp.body` is returned as a Lua table `{0x89, 0x50, 0x4E, ...}` (1-based) instead of a string
> - Binary responses are **not cached** (TTL cache works only for text)
> - `resp.code`, `resp.headers`, `resp.success` work the same for both modes
> - Use `#resp.body` to get the size in bytes

`config` parameters (defaults for the whole batch) and element keys:

- `headers` — a headers table applied **to every request of the batch**. The engine's default headers (`Referer` from the URL, `Accept-Language`) are added to each request of the batch automatically, then `config.headers` go on top of them, then the element's `headers` on top of those: each next level overrides the previous one. A specific element's `headers` are **merged over** the global ones: listed keys are replaced, the remaining global ones survive.
- `binary = true` — each entry's body as a byte table (see above).
- `charset` — encoding of text responses (default `UTF-8`).
- `timeout` — budget in ms per request (see `http_get`): a single attempt instead of the client's retry series.
- `followRedirects = false` — do not follow 3xx, as in `http_get`.
- `method = "HEAD"` — as in `http_get`: empty body, cache neither read nor written.

Each of these keys can be set both in `config` (for the whole batch) and in the element (for that URL only) — the per-URL value overrides the global one.

```
local results = http_get_batch(urls, {
    headers = { ["Referer"] = "https://ref.example/" },
})
```

Resolving several hosters with a single batch instead of sequential `http_get` calls:

```lua
function getVideoList(episodeUrl)
    local id = episodeUrl:match("([%w%-]+)$")
    local items = {
        { url = "https://hoster-one.example/e/" .. id,   headers = { Referer = episodeUrl }, timeout = 8000 },
        { url = "https://hoster-two.example/e/" .. id,   headers = { Referer = episodeUrl }, followRedirects = false },
        { url = "https://hoster-three.example/e/" .. id, timeout = 5000 },
        "https://hoster-four.example/e/" .. id,          -- string: settings come from config
    }
    local results = http_get_batch(items, { timeout = 8000, headers = { Referer = episodeUrl } })
    for _, res in ipairs(results) do
        if res.success then
            -- parse res.body and extract the stream link
        end
    end
end
```

> **`timeout` is mandatory for potentially dead links.** Without `timeout` every element goes through the client's full retry ladder (3+3+3+3+15 s) and the batch waits for its slowest element — a single "black hole" (TCP comes up, 0 bytes of response) slows down the whole resolve. With `timeout` each request fits into its own budget with one attempt.

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

### Working with localStorage

The engine automatically saves localStorage from the WebView when pages load (in `onPageFinished` and every 3 seconds). Plugins can read this data via `get_localStorage` — for example, to get a Bearer token or other auth key.

```lua
-- Get a value by URL and key
local token = get_localStorage("https://example.com", "auth_token")
if token and token ~= "" then
    -- Use the token in headers
    local r = http_get(apiUrl, {
        headers = {
            ["Authorization"] = "Bearer " .. token,
        }
    })
end
```

Data is cached by host. If the user is already logged in on the site — the token is available immediately. If the key is absent — `nil` is returned.

### Delays (rate limiting)

```
sleep(300)                        -- 300 ms
sleep(math.random(150, 350))      -- random delay of 150-350 ms
```

Use `sleep` between requests in `getChapterList` if the site aggressively blocks scrapers (example: jaomix).

---

## Page Caching (fetchPage)

The engine calls `getBookTitle`, `getBookCoverImageUrl`, `getBookDescription`, `getBookGenres`, `getBookStatus`, `getBookLastUpdate`, `getChapterListHash`, and `getChapterList` **in parallel** — each of them does its own `http_get(bookUrl)` by default. That's 6–8 identical requests to the same page.

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

## Video plugins (content_type = "video")

With `content_type = "video"`, the plugin opens the built-in player (media3) instead of the text reader. Mapping: a series is a regular `Book` from the catalog, episodes are regular chapters from `getChapterList`, a season is the `volume` field.

The only difference from a regular plugin: instead of `getChapterText`, implement `getVideoList(episodeUrl)` — it returns the stream variants for the episode. `episodeUrl` comes from `getChapterList`; the plugin fetches the page itself via `http_get`.

```lua
function getVideoList(episodeUrl)
    local r = http_get(episodeUrl)
    if not r.success then return nil end
    local data = json_parse(r.body)
    return {
        {
            url     = data.stream,   -- m3u8 или прямой mp4
            quality = "1080p",       -- подпись для UI (опционально)
            mime    = "hls",         -- опционально: тип контента, см. ниже
            headers = {              -- опционально
                ["Referer"] = episodeUrl,
            },
            subtitles = {            -- опционально: .srt / .vtt
                { url = "https://.../ru.srt", label = "Русский", lang = "ru" },
            },
        },
    }
end
```

Rules:

- A video plugin doesn't need `getChapterText`: the validator requires `getVideoList` based on `content_type` (a missing one logs a warning).
- `return nil` or `return {}` → the app shows "No sources found" (not an error). `error("text")` → the error text is shown on screen.
- `headers` are applied **identically to every request of the stream**: the playlist, HLS segments, subtitles, and offline download. The usual set is `Referer` (the episode page) and `User-Agent`; the source's cookies come from the app's shared jar. The contract has no separate headers "for the playlist only". The set is defined per stream variant — quality variants may carry their own headers.
- `subtitles`: fields `url` (HTTP), `label` — track caption in the player, `lang` — language code; the mime type is derived from the URL extension (`.srt`, `.vtt`).
- `quality`, `headers`, `subtitles`, `mime` are optional; entries without `url` are skipped — that's not an error.
- `mime` — a content-type hint for the player: `hls`/`m3u8` (→ HLS), `mp4`, `mpd` (→ DASH); a ready-made `application/…`/`video/…` value is also accepted (case does not matter). It is needed **only** for URLs **without a media extension** (e.g. `https://cdn…/?token=…`): without it media3 looks at the last path segment, sees "/", and opens the stream with a progressive source → `UnrecognizedInputFormatException` on HLS. A `.m3u8`/`.mp4` extension in the URL already determines the type — then the field is not required. An unknown value or its absence is ignored and the player falls back to inferring the type from the URL. `mime` also travels into the offline download (media3 picks `HlsDownloader` by it).

### Standard getVideoList: speed and filtering out dead hosts

A pattern for all video plugins (a documented, user-proven solution): a series of dozens of embed hosts must not hang on dead links.

1. **SKIP_HOSTS — before any network request.** Check hosts against a list/regex **before** any HTTP. Even with `timeout` in `http_get`, the only cheapest "hard timeout" is to not go to known-dead / JS-only hosts at all: SKIP_HOSTS saves both time and network. The list must carry a reason (a comment or a `reason` field) — why the host is skipped: measured "0 bytes of response", a redirect loop, "no direct link", and so on. Without a reason the list cannot be reviewed.

2. **One `http_get_batch` instead of sequential `http_get` per embed.** Collect all candidate links → one batch (the engine runs it in parallel via `async(Dispatchers.IO)` in the app) → parse the responses → deduplicate by URL → output.

3. **Why this is critical (the measurements the standard grew from).** Sequential traversal with "black holes" (TCP comes up, 0 bytes → the whole timeout is spent; without `timeout` NetworkClient retries 3+3+3+3+15 s) took **17.9–19.9 s** per series; after the fix — **1.2–2.7 s** with no loss of sources. Probing every link for "liveness" with the old API (without `timeout`/`HEAD`) cost **26–30 s** per series; in the current API it is covered by one line — see item 4.

4. **What the API has now.** `http_get` supports `timeout` (budget in ms, single attempt) and `method = "HEAD"` (empty body, cache untouched) — together a cheap liveness probe: `http_get(url, { timeout = 3000, method = "HEAD" })`, check the HTTP code (see "Working with HTTP" → `http_get`). `http_get_batch` takes the same keys — `headers`, `charset`, `binary`, `timeout`, `followRedirects`, `method` — globally in `config` for the whole batch and per-URL in the element table (the element itself can also be a URL string). Per-URL `headers` are merged over the global ones; Range is not supported in the batch; requests also carry the engine's default `Accept-Language` and `Referer` computed from the URL itself (`HttpGetBatchFunction` in `LuaSourceLoader.kt`). Details — "Working with HTTP" → `http_get_batch`.

5. **New video plugin checklist:** a skip list with reasons → one batch for all embeds → dedupe → `Referer` from the source link in `headers` of every variant (required for mp4upload and the like) → output.

---

## Plugin Errors (show_error)

### show_error(title, message)

A plugin can show an error dialog to the user by calling `show_error(title, message)`.

| Parameter | Type   | Description                    |
|-----------|--------|--------------------------------|
| `title`   | string | Dialog title                   |
| `message` | string | Error message (dialog body)    |

### When to use

- Paid content / subscription required
- Site requires login
- Page not found / chapter deleted
- Source temporarily unavailable

### Examples

#### Paid chapter

```lua
function getChapterText(doc)
    if doc:selectFirst(".paid-chapter") then
        show_error("Paid Content", "This chapter is only available with a subscription.")
        return nil
    end
    -- ...parse text...
end
```

#### Login required

```lua
function getChapterPages(doc)
    if doc:selectFirst(".login-required") then
        show_error("Login Required", "Please log in to the site to read this chapter.")
        return nil
    end
    -- ...fetch pages...
end
```

#### Combining with other checks

```lua
function getChapterText(doc)
    local errorDiv = doc:selectFirst(".error-message")
    if errorDiv then
        show_error("Source Error", errorDiv:text())
        return nil
    end

    local content = doc:selectFirst(".chapter-content")
    if not content then
        show_error("Chapter Not Found", "Could not extract chapter text.")
        return nil
    end

    return content:text()
end
```

### Behavior

- `show_error()` **stops chapter loading** — the function must return `nil` after calling it
- The user sees a dialog with the specified title and message
- When the dialog is closed, the reader closes (returns to chapter list)
- **No retries are performed** — a plugin error is not a network issue
- Existing plugins without `show_error()` continue to work unchanged

### Important

- `show_error()` is called **inside** `getChapterText()` or `getChapterPages()`
- After calling it, return `nil` — otherwise behavior is undefined
- Do not use `show_error()` for normal situations (chapter simply doesn't exist) — only for real errors that require user attention

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

        -- Tag input with autocomplete (text field + chips)
        {
            type        = "tag_input",
            key         = "tags",
            label       = "Tags",
            allowCustom = true,
            options = {
                { value = "harem",    label = "Harem"    },
                { value = "op_mc",    label = "OP MC"    },
                { value = "strong_mc", label = "Strong MC" },
                { value = "isekai",   label = "Isekai"   },
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
| `tag_input` | `filters["key_included"]`   | array table of strings        |

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

    -- Tags from tag_input
    local tags_inc = filters["tags_included"] or {}
    for _, v in ipairs(tags_inc) do url = url .. "&tag[]=" .. v end

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

### pow_solve(challenge, difficulty)

Kotlin Proof-of-Work solver (global, new NoveLA builds only): nonce search for byse/filemoon PoW (memory-hard function gr), batches of 1024, 15-second budget. Returns the nonce as a string, or `nil` on timeout/error.

```lua
local nonce = pow_solve(challenge, 12)
if not nonce then
    log_error("my_source: pow_solve timeout")
    return nil
end
```

---

## Shared Libraries (require_lib)

`require_lib(id)` — a Lua global (new NoveLA builds only): reads a shared library and returns its table.

```lua
local urls = require_lib("urls")
local host = urls.hostOf(pageUrl)
```

Search paths for `<id>.lua`:

| Environment | Search paths |
|---|---|
| On device | `lua_extensions/lib/<id>.lua` |
| Repo tester | `<scriptDir>/lib/<id>.lua`, then `<scriptDir>/../libs/<id>.lua` and `<scriptDir>/../libs/*/<id>.lua` |

**Errors** are LuaError (not `nil`): invalid id (not `[a-z0-9_]+`), file missing, library did not return a table.

Inside a library `require_lib` is available (metatable `__index` → globals) — libraries can reference each other; cycles between libraries are forbidden. Already-loaded libraries are cached (invalidated by file mtime/size).

### libs/ structure

`libs/` lives in the repo root, shared by all languages: one file per extractor/decoder. Subfolders are repo layout only: **a library id is the file basename and does not depend on the subfolder** — `require_lib` takes only the id.

| File | Contents |
|---|---|
| `libs/helpers/urls.lua` | `origin`, `hostOf`, `unescapeSlashes`, `resolve`, `driveDirectUrl` |
| `libs/helpers/hls.lua` | `pickStream`, `hasMediaExt` |
| `libs/helpers/text.lua` | `rot13`, `rot18` |
| `libs/hosters/aksor.lua` | `apiUrl`, `resolve` — Aksor JSON API by iframe |
| `libs/hosters/alloha.lua` | `resolve` — borth permutations, POST /bnsi → HLS |
| `libs/hosters/cvh.lua` | `videoUrl`, `sourceFrom` — CDN VideoHub player API |
| `libs/hosters/dailymotion.lua` | `parseMetadata`, `resolveDailymotion` — metadata → HLS master |
| `libs/hosters/dood.lua` | `resolveDood` — DOOD/dsvplay extractor |
| `libs/hosters/dotplay.lua` | `resolve` — embed → api.php → base64 video_url |
| `libs/hosters/dropbox.lua` | `resolve` — shared link → direct CDN URL |
| `libs/hosters/dtube.lua` | `resolve` — api.d.tube JSON → master.m3u8 |
| `libs/hosters/embeds.lua` | `extractFromEmbed` dispatcher (routes per hoster) |
| `libs/hosters/gdriveplayer.lua` | `decode` — atob+XOR script → HLS playlist |
| `libs/hosters/hgcloud.lua` | `mirrors`, `mediaUrls`, `resolve` — packed config from mirror |
| `libs/hosters/kodik.lua` | `resolve` — urlParams/d_sign → POST /ftor |
| `libs/hosters/mailru.lua` | `parseMeta`, `resolve` — metadataUrl → mp4 |
| `libs/hosters/mirrors.lua` | `mirrorOptions` — embed mirror option list |
| `libs/hosters/mixdrop.lua` | `extractMixdrop` — MDCore.wurl → mp4 |
| `libs/hosters/mp4upload.lua` | `extractMp4upload` — player.src → mp4 |
| `libs/hosters/okru.lua` | `resolveOkRu` — data-options → flashvars.metadata |
| `libs/hosters/otaku.lua` | `resolve` — window.__P (base64∘xor) → m3u8 + subtitles |
| `libs/hosters/pixeldrain.lua` | `resolve` — embed /u/ → /api/file/ mp4 |
| `libs/hosters/rumble.lua` | `resolve` — jwplayer config → mp4/HLS |
| `libs/hosters/seekplayer.lua` | `decode` — API hex blob → AES-128-CBC JSON |
| `libs/hosters/share4max.lua` | `version`, `resolve` — Inertia XHR → props.streams |
| `libs/hosters/shared.lua` | `extract` — 4shared embed → first `<source>` |
| `libs/hosters/sibnet.lua` | `resolve` — shell.php → single mp4 |
| `libs/hosters/soraplay.lua` | `parsePlayers`, `parseSources` — sources and player list |
| `libs/hosters/uqload.lua` | `packedMediaUrls`, `resolve` — packed-JS → jwplayer sources |
| `libs/hosters/vidbom.lua` | `isLink`, `parseSources` — vidbom/vadbom/… family → sources |
| `libs/hosters/videa.lua` | `request`, `parse` — _xt token → XML (RC4 + base64) |
| `libs/hosters/videas.lua` | `parse` — videas.fr embed → direct HLS/MP4 |
| `libs/hosters/vidmoly.lua` | `resolve` — redirect → player → packed media URLs |
| `libs/hosters/vidyard.lua` | `origin`, `resolve` — player/<id>.json → hls[] profiles |
| `libs/hosters/vk.lua` | `videoExtUrl`, `resolve` — video_ext.php → mp4_144…1080 |
| `libs/hosters/voe.lua` | `extractVoe`, `extractSources` — obfuscated JSON (1.3.0) |

**What belongs in `libs/hosters/`**: generic hoster resolvers that any site can embed. A site-specific dispatcher/gate (backend kind-ID, Livewire gates, the site's own CDN) stays in the plugin — examples: `record`/yummyanime, `yonaplay`/witanime, `gateUrl`/witanime.

The historical `libs/common.lua` and `libs/decode.lua` are **gone**: URL helpers moved to `urls`, `pickStream` to `hls`, and `base64Decode`/`unpackAll` were replaced by the engine API `base64_decode_bytes`/`unpack_packed` (see "Heavy Operations (Kotlin API)"). There are no Lua decryptor files in `libs/` — all crypto (AES-GCM/RC4/base64/hash) lives in the Kotlin engine API. Do not use the old names — `require_lib("common")` on the new repo throws a LuaError.

File format: header comment, local helpers, `return M`. Libraries have NO `version` field.

### Library sync (by sha256)

The library catalog is the `libraries` section in the root `index.yaml` (not the per-language ones):

```yaml
libraries:
  - id: "urls"
    url: "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/libs/helpers/urls.lua"
    sha256: "<hex>"
```

`sha256` is computed by `scripts/sync_index.py` automatically from the contents of `libs/**/*.lua` (recursive walk, the URL carries the subfolder) — regeneration updates the hashes itself. The app downloads a library into flat `lua_extensions/lib/<id>.lua` when the local file's sha256 differs from the catalog's — the subfolder in the URL does not affect that. Versions are not involved. `libs/` is in the sync SKIP_DIRS (subfolders included) — it is not a language folder.

After any edit to `libs/**/*.lua`, always run `GITHUB_REF_NAME=main python3 scripts/sync_index.py` — otherwise the catalog sha256 goes stale and the app re-downloads the library on every pull. **`GITHUB_REF_NAME=main` is mandatory**: without it the sync on a feature branch rewrites every URL in index.yaml to that branch and breaks the release.

### Fallback for old builds

`require_lib` exists only in new app versions. **Do not throw `error` at top level** — the plugin will silently disappear from the source list. Pattern: a check at the start of every public function; the canonical form is `show_error(...)` + `error(..., 0)` (in production `show_error` is asynchronous and returns `nil`, so without `error` the function would keep running without the libraries):

```lua
function getChapterText(html, url)
    if type(require_lib) ~= "function" then
        show_error("NoveLA update required", "This plugin needs shared libraries")
        error("NoveLA update required (require_lib)", 0)
    end
    local embeds = require_lib("embeds")
    -- ...
end
```

---

## Heavy Operations (Kotlin API)

Hashes, ciphers, binary base64 and P.A.C.K.E.R unpacking run engine-side (Kotlin) — Lua only calls them. These globals exist **only in new NoveLA builds** (see "Guard pattern" below).

| API | Signature | Return / contract |
|---|---|---|
| `sha256(data)` | `(data: str) -> str` | **Raw bytes** (binary-str, 32 of them), NOT hex; the caller hex-encodes if needed. Invalid type → LuaError |
| `md5(data)` | `(data: str) -> str` | **Raw bytes** (16 of them), NOT hex. Invalid type → LuaError |
| `sha1(data [, "hex"\|"raw"])` | `(data: str, mode?: "hex"\|"raw") -> str` | **Raw bytes** (20 of them) with no mode and with `"raw"` (mirrors `sha256`); `"hex"` → 40-char hex. Unknown mode/invalid type → LuaError |
| `crc32(data)` | `(data: str) -> number` | CRC-32 → a Lua **number** holding the unsigned value `0..2^32-1` exactly (fits a double). `crc32("123456789")` = 3421780262 (0xCBF43926), `crc32("")` = 0. Invalid type → LuaError |
| `hmac_sha256(key, data)` | `(key: str, data: str) -> str` | **Raw bytes** (32 of them), NOT hex; run `hexEncode(...)` on the caller's side when hex is required. Invalid type → LuaError |
| `pbkdf2(password, salt, iterations, dkLen [, hash])` | `(str, str, int, int, "sha1"\|"sha256"\|"sha512"?) -> str` | PBKDF2-HMAC → **raw bytes** of length `dkLen`; `hash` defaults to `sha256`. The password is read as UTF-8 text, the salt as raw bytes. Invalid `hash`/type, `iterations < 1`, `dkLen < 1` → LuaError |
| `aes_gcm_decrypt(key, iv, ct, tag)` | 4 args, all **raw bytes** (binary-str) | AES-GCM decryption; the tag is a separate argument. **`nil` on any error** (bad tag, wrong key) — Lua does the nil-fallback. Unpacking bundled forms (`iv‖tag‖ct`, `arr:<b64 iv>:<b64 tag>:<b64 ct>`) happens on the caller's side. Invalid type → LuaError |
| `rc4(key, data)` | `(key: str, data: str) -> str` | RC4, raw bytes in and out; empty key → LuaError |
| `aes_ctr(data, key, iv)` | `(data, key, iv: str) -> str` | AES/CTR/NoPadding → **raw bytes**; the mode is symmetric (the same call encrypts and decrypts). key 16/24/32, iv strictly 16 bytes (contract = AES block; an 8-byte nonce is rejected). Wrong key/iv length → LuaError. New builds only |
| `rsa_decrypt(data, privateKey)` | `(data, privateKey: str) -> str` | RSA/ECB/PKCS1Padding → **raw bytes**; `privateKey` is standard base64 DER PKCS#8 (the same base64 `base64_decode` takes). Broken base64/key/padding → LuaError (English message). New builds only |
| `aes_decrypt(data, key, iv)` | `(data, key, iv: str) -> str \| nil` | AES/CBC/PKCS5; key/iv are raw bytes. **`nil` on error** |
| `base64_encode(s)` | `(s: str) -> str` | Base64 (Java String — not suitable for binary data) |
| `base64_decode(s)` | `(s: str) -> str \| nil` | Base64 → string (UTF-8); `nil` on invalid base64 |
| `base64_decode_bytes(s)` | `(s: str) -> str \| nil` | Base64 → **raw bytes** (binary-str with `\0` etc.); lenient: whitespace, url-safe `-_/`, auto-padding. `nil` on invalid base64, invalid type → LuaError |
| `unpack_packed(script)` | `(script: str) -> str` | Unpacks `eval(function(p,a,c,k,e,d)...)` → original src; **first match** in the text; **`""` when there is no packer** (not `nil` — callers check `un ~= ""`). Invalid type → LuaError |
| `json_encode(value)` | `(value: bool\|num\|str\|table) -> str` | Compact JSON (no spaces), object keys are sorted → deterministic output. A table → **array** on contiguous integer keys `1..n`, otherwise an **object** (empty table → `[]`, holes → `{"1":..,"3":..}`). Top-level `nil`, mixed/unsupported keys, cycles, functions, non-finite numbers → LuaError. **The canonical encoder**; `json_stringify` is legacy (see "JSON") |
| `inflate(data [, mode])` | `(data: str, mode?: "zlib"\|"gzip") -> str \| nil` | Decompression → **raw bytes**; `mode` defaults to `"zlib"`. Corrupt/truncated data and an unknown `mode` → `nil` (data handling, not a call error); invalid type → LuaError. HTTP Content-Encoding (gzip/deflate/br) is decoded by the engine itself — `inflate` is only for compressed blobs **inside** the data |
| `pow_solve(challenge, difficulty)` | `(str, int) -> str \| nil` | Nonce for byse/filemoon PoW; `nil` on timeout/error |
| `require_lib(id)` | `(id: str) -> table` | Shared library from `libs/`; errors are LuaError (see "Shared Libraries (require_lib)") |

The **raw bytes** contract matters: keys, IVs, ciphertext and digests are binary, and `checkjstring()`/`tojstring()` (UTF-8 round-trip) corrupt them. That is why `sha256(...)` returns a binary-str: `string.byte(sha256(x))` gives bytes, and `hexEncode` is done by the caller when hex is wanted.

### When to move it to Kotlin

**Marker:** a byte loop, bit twiddling, crypto or decoders written in pure Lua — a candidate for the engine API: character-by-character work over a binary blob is far too slow in Lua, and the sandbox ships no libraries of its own. Stays in Lua: `fetch`/HTTP, JSON field extraction and URL building — tables and strings, Lua handles those fine.

New API lands through TDD: golden snapshots → unit tests (`HeavyOpsTest`) → parity with the tester (`plugin-tester-jvm`), and only after that a line in this guide.

Roadmap: `json_encode` / `inflate` / `pbkdf2` / `sha1` / `crc32` / `aes_ctr` / `rsa_decrypt` — added (all listed in the tables above). New candidates appear as their callsites do.

### Guard pattern

The globals above only exist in new builds. A plugin that uses them must check them **inside the first public function** and call that check **from every public function** (the `ensureEngine` canon; `es/latanime.lua` has a single combined `ensureLibs` that checks `require_lib` and the engine API alike). Check **only the APIs actually used**:

```lua
local function ensureEngine()
    local missing = {}
    if rawget(_G, "sha256") == nil then missing[#missing + 1] = "sha256" end
    if rawget(_G, "unpack_packed") == nil then missing[#missing + 1] = "unpack_packed" end
    if #missing > 0 then
        show_error("Please update NoveLA",
            "This plugin needs new functions (" .. table.concat(missing, ", ") ..
            "). Please update the application to the latest version.")
        error("A newer version of the application is required: " .. table.concat(missing, ","), 0)
    end
end
```

`rawget(_G, "<api>")` instead of a direct read — old builds have no such global, a direct read would silently give `nil`, while the comparison against `nil` catches the absence itself.

For `require_lib` — a separate **top-level** layer (otherwise on old builds a top-level `require_lib(...)` is a nil-call and the plugin silently vanishes from the source list): per-name loading via `pcall` with the error kept in `libErr` + `ensureLibs()` in the public functions (the latanime:40-65 canon). Message text is in the plugin's language (es → Spanish, the rest → English).

---

## Full API Reference

### Plugin functions (called by the engine)

| Function                            | Description                                                                           |
| ------------------------------------- | --------------------------------------------------------------------------------------- |
| `getUserAgentPreset()`              | Name of the UA preset (e.g. `"Safari Mobile"`) — applies to all source requests and its domain. See "Working with HTTP" |
| `getBookStatus(bookUrl)`            | Book status — the text as on the site, or `nil`. See "getBookStatus" |
| `getBookLastUpdate(bookUrl)`        | Last chapter update date `YYYY-MM-DD` or `nil`. See "getBookLastUpdate" |

### HTTP

| Function                           | Description                                          |
| ------------------------------------ | ------------------------------------------------------ |
| `http_get(url [, config])`         | GET/HEAD request → `{success, body, code}` (body is a string or byte table with `binary = true`). config: `headers`, `charset`, `binary`, `followRedirects`, `timeout` (ms), `method` (`"GET"`/`"HEAD"`) |
| `http_post(url, body [, config])`  | POST request → `{success, body, code}`; config: `headers`, `charset` |
| `http_get_batch(items [, config])` | Parallel GET → array of the same length, element `{success, body, code, headers}`; element is a URL string or a table `{url, headers, charset, binary, timeout, followRedirects, method}`; config: `headers`, `charset`, `binary`, `followRedirects`, `timeout`, `method` (defaults, per-URL overrides). Failure of a single URL → `{success=false, code=-1}` for it only |
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
| `json_stringify(v)`   | Lua table → JSON string. **Legacy**: `nil` on error, key order not guaranteed. `json_encode` is canonical (see "Crypto / Encoding") |

### Crypto / Encoding

| Function                        | Description                    |
| ---------------------------------- | ---------------------------------- |
| `base64_encode(s)`               | Base64 encode                  |
| `base64_decode(s)`               | Base64 decode → string; `nil` on invalid base64 |
| `base64_decode_bytes(s)`         | Base64 decode → **raw bytes** (lenient: whitespace, url-safe, auto-padding); `nil` on invalid base64. New builds only |
| `aes_decrypt(data, key, iv)`     | AES/CBC/PKCS5 decryption → string or `nil` on error |
| `aes_gcm_decrypt(key, iv, ct, tag)` | AES-GCM decryption, args are raw bytes → string or `nil` on error. New builds only |
| `rc4(key, data)`                 | RC4 → raw bytes. New builds only |
| `aes_ctr(data, key, iv)`         | AES/CTR → raw bytes, symmetric; key 16/24/32, iv strictly 16; wrong length → LuaError. New builds only |
| `rsa_decrypt(data, privateKey)`  | RSA/ECB/PKCS1Padding → raw bytes; `privateKey` = standard base64 DER PKCS#8; errors → LuaError. New builds only |
| `sha256(data)`                   | SHA-256 → **raw bytes** (not hex). New builds only |
| `md5(data)`                      | MD5 → **raw bytes** (not hex). New builds only |
| `sha1(data [, "hex"\|"raw"])`    | SHA-1 → **raw bytes** (20 of them), `"hex"` → hex. New builds only |
| `crc32(data)`                    | CRC-32 → Lua number `0..2^32-1`. New builds only |
| `hmac_sha256(key, data)`         | HMAC-SHA256 → **raw bytes** (not hex). New builds only |
| `pbkdf2(password, salt, iterations, dkLen [, hash])` | PBKDF2-HMAC → **raw bytes** of length `dkLen`; `hash` = `sha1`/`sha256`/`sha512`, default `sha256`; password as UTF-8 text, salt as raw bytes; invalid `hash`, `iterations < 1`, `dkLen < 1` → LuaError. New builds only |
| `unpack_packed(script)`          | Unpack P.A.C.K.E.R → src; `""` when there is no packer. New builds only |
| `json_encode(v)`                 | Compact JSON → string; array on contiguous keys `1..n`, otherwise object (keys sorted), empty table → `[]`; `nil`/mixed keys/cycles/functions → LuaError. **Canonical** encoder (see `json_stringify` under "JSON"). New builds only |
| `inflate(data [, mode])`         | Decompress zlib (default) or gzip → **raw bytes**; corrupt data/unknown `mode` → `nil`. The engine decodes HTTP Content-Encoding itself — for compressed blobs inside the data only. New builds only |
| `pow_solve(challenge, difficulty)` | Nonce search for byse/filemoon PoW (memory-hard function gr), batches of 1024, 15 s budget → nonce as a string or `nil` on timeout/error. New builds only |

### Storage

| Function                        | Description                                      |
| ---------------------------------- | ----------------------------------------------------- |
| `get_preference(key)`            | Read from SharedPreferences "lua_preferences"    |
| `set_preference(key, value)`     | Write to SharedPreferences "lua_preferences"     |
| `get_localStorage(url, key)`     | Read a value from WebView localStorage by URL and key (returns `nil` if key not found) |

### Utilities

| Function                     | Description                                    |
| -------------------------------- | ------------------------------------------------- |
| `sleep(ms)`                     | Delay in milliseconds                          |
| `detect_pagination(html)`       | Detect hasNext → `{hasNext, next_url}`         |
| `log_info(msg)`                 | INFO log (Timber)                              |
| `log_error(msg)`                | ERROR log (Timber)                             |
| `show_error(title, message)`    | Show error dialog to user. Stops chapter loading, return `nil` after calling |
| `os_time()`                     | Unix timestamp in milliseconds                 |
| `require_lib(id)`               | Shared library from `libs/` → table; errors are LuaError (invalid id `[a-z0-9_]+`, file missing, library returned no table). Paths: `lua_extensions/lib/<id>.lua` on device, `<scriptDir>/lib/` → `<scriptDir>/../libs/` → `<scriptDir>/../libs/*/` in the tester. Cached by mtime/size. New builds only |

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

-- Status and last update date (optional): contract — the "getBookStatus" and
-- "getBookLastUpdate" sections in this guide. The app shows them in the library.
function getBookStatus(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".book-status")
    return el and string_clean(el.text) or nil
end

-- The site serves an ISO date with time in the meta article:modified_time —
-- keep only YYYY-MM-DD (for relative dates like "Updated 3 days ago" see
-- Format 2 in the "getBookLastUpdate" section).
function getBookLastUpdate(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local v = html_attr(r.body, "meta[property='article:modified_time']", "content")
    local y, m, d = string.match(v, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return y and (y .. "-" .. m .. "-" .. d) or nil
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

**If a site needs a specific User-Agent (mobile/desktop layout) — don't hardcode it in `headers`.** Declare `getUserAgentPreset()` and the engine will apply the preset to all source requests without breaking global settings:

```lua
-- ✅ Built-in mechanism: the preset applies to all source requests and its domain
function getUserAgentPreset()
    return "Safari Mobile"
end
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
