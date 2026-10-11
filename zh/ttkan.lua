-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "ttkan"
name     = "TTKan"
version  = "1.1.2"
baseUrl  = "https://www.ttkan.co/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ttkan.png"

-- ── Changelog (1.0.0 → 1.1.0) ───────────────────────────────────────────────
-- FIX: Catalog pagination infinite loop. The site ignores `?page=N` and
--      returns the same 100 books every page, so `hasNext` must always be
--      false after index=0. Previously `hasNext = #items > 0` caused the
--      engine to keep fetching the same page forever.
-- FIX: Search pagination — same root cause, same fix.
-- ADD: Category filters (`getFilterList` + `getCatalogFiltered`) using the
--      /novel/rank/{category} pages discovered on the rank home.
-- IMP: Content transforms now strip ad placeholders, social-share buttons,
--      "chapter report" feedback widgets, and the trailing nav bar that
--      ttkan injects inside `.content`. Pattern lifted from the
--      novel_extractor.py audit work (collapse duplicated chapter-title
--      prefix, drop "chapter report / share with friends" UI tail).
-- ────────────────────────────────────────────────────────────────────────────

-- ── Helpers ─────────────────────────────────────────────────────────────────

-- Old builds ship no require_lib: keep the plugin loadable (a top-level error
-- would drop it from the source list) and fail with a visible message on the
-- first call instead. Shared libs load lazily and are cached per session.
local _libs
local function LIB(id)
  if type(require_lib) ~= "function" then
    show_error("Requires NoveLA update", "This plugin needs the shared libraries")
    error("Requires NoveLA update (require_lib)", 0)
  end
  if not _libs then _libs = {} end
  if not _libs[id] then _libs[id] = require_lib(id) end
  return _libs[id]
end

local function absUrl(href)
  return LIB("urls").absUrl(baseUrl, href)
end

-- Session-cached book page (shared fetch lib): the book page is read by the
-- title/description/status functions in one adapter run.
-- getChapterListHash stays on a direct http_get — the hash must see a fresh
-- page.
local function fetchPage(url)
  return LIB("fetch").page(url)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- Apply standard content transforms.
-- Shared lib covers the domain lines, the leading chapter title (the
-- duplicated "第N章：第N章" prefix collapses into the same strip) and the
-- translator/editor attribution lines. The trailing "chapter report / share
-- with friends" UI tail that ttkan leaves inside .content is site-specific
-- and stays here.
local function applyStandardContentTransforms(text)
  text = LIB("content").standardTransforms(text, { domain = baseUrl, lang = "zh" })
  if text == "" then return "" end

  -- "章節報錯" (chapter report) and "分享給朋友：" (share with friends).
  text = regex_replace(text, "(?im)\\n\\s*章節報錯\\s*$", "")
  text = regex_replace(text, "(?im)\\n\\s*分享給朋友[：:].*$", "")
  text = regex_replace(text, "(?im)\\n\\s*上一頁.*下一頁\\s*$", "")

  return string_trim(text)
end

-- Extract the novel_id (slug) from a book URL like
-- /novel/chapters/qingshan-huishuohuadezhouzi
local function extractNovelId(bookUrl)
  return string.match(bookUrl, "/novel/chapters/([^/?#]+)")
end

-- Build a cover URL from the book slug.
-- bookUrl = ".../novel/chapters/qingshan-huishuohuadezhouzi"
-- → https://static.ttkan.co/cover/qingshan-huishuohuadezhouzi.jpg?w=250&h=300&q=100
local function buildCoverUrl(bookUrl)
  local slug = string.match(bookUrl, "/([^/?#]+)/?$")
  if not slug or slug == "" then return "" end
  return "https://static.ttkan.co/cover/" .. slug .. ".jpg?w=250&h=300&q=100"
end

-- ── Catalog ─────────────────────────────────────────────────────────────────
-- The site has NO real pagination: ?page=N is silently ignored and the same
-- 100-book list is returned for every page. We expose only the first page
-- and return hasNext=false so the engine stops after one fetch.

function getCatalogList(index)
  if index > 0 then return { items = {}, hasNext = false } end

  local url = "https://www.ttkan.co/novel/rank"
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".rank_list > div")) do
    local titleEl = html_select_first(card.html, "h2")
    local aEl     = html_select_first(card.html, "a[href*='/novel/chapters/']")
    if titleEl and aEl then
      local bookUrl = absUrl(aEl.href)
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = buildCoverUrl(bookUrl)
        })
      end
    end
  end

  -- hasNext is always false — the site ignores ?page=N.
  return { items = items, hasNext = false }
end

-- ── Search ──────────────────────────────────────────────────────────────────
-- The site returns ALL matches on a single page; ?page=N is ignored.

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end

  local encoded = url_encode(query)
  local url = "https://www.ttkan.co/novel/search?q=" .. encoded
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".novel_cell")) do
    local titleEl = html_select_first(card.html, "h3")
    local aEl     = html_select_first(card.html, "a[href*='/novel/chapters/']")
    if titleEl and aEl then
      local bookUrl = absUrl(aEl.href)
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = buildCoverUrl(bookUrl)
        })
      end
    end
  end

  return { items = items, hasNext = false }
end

-- ── Filters (NEW in 1.1.0) ──────────────────────────────────────────────────
-- Expose ttkan's per-category rank pages as catalog filters.

function getFilterList()
  return {
    {
      type         = "select",
      key          = "category",
      label        = "分類",
      defaultValue = "rank",
      options = {
        { value = "rank",             label = "熱門總榜" },
        { value = "rank/xuanhuan",     label = "玄幻排行" },
        { value = "rank/gudaiyanqing", label = "言情排行" },
        { value = "rank/chuanyuechongsheng", label = "穿越排行" },
        { value = "rank/dushi",        label = "都市排行" },
        { value = "rank/kehuan",       label = "科幻排行" },
        { value = "rank/xianxia",      label = "仙俠排行" },
        { value = "rank/yanqing",      label = "現言排行" },
        { value = "rank/lishi",        label = "歷史排行" },
        { value = "rank/lingyi",       label = "靈異排行" },
        { value = "rank/xuanyi",       label = "懸疑排行" },
        { value = "rank/youxi",        label = "遊戲排行" },
        { value = "rank/qita",         label = "其他排行" },
      }
    }
  }
end

function getCatalogFiltered(index, filters)
  if index > 0 then return { items = {}, hasNext = false } end

  local cat = filters["category"] or "rank"
  local url = "https://www.ttkan.co/novel/" .. cat
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".rank_list > div")) do
    local titleEl = html_select_first(card.html, "h2")
    local aEl     = html_select_first(card.html, "a[href*='/novel/chapters/']")
    if titleEl and aEl then
      local bookUrl = absUrl(aEl.href)
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = buildCoverUrl(bookUrl)
        })
      end
    end
  end

  return { items = items, hasNext = false }
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  -- Cover is constructed from the URL slug — no extra HTTP request needed.
  local cover = buildCoverUrl(bookUrl)
  if cover ~= "" then return cover end
  return nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".description")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Chapter list (JSON API) ────────────────────────────────────────────────

function getChapterList(bookUrl)
  local novelId = extractNovelId(bookUrl)
  if not novelId or novelId == "" then
    log_error("ttkan: cannot extract novelId from " .. bookUrl)
    return {}
  end

  local apiUrl = "https://www.ttkan.co/api/nq/amp_novel_chapters?language=tw&novel_id=" .. novelId

  local r = http_get(apiUrl)
  if not r.success then
    log_error("ttkan: API failed " .. tostring(r.code) .. " " .. apiUrl)
    return {}
  end

  -- Parse JSON response: {"items":[{"chapter_name":"...","chapter_id":N}, ...]}
  local data = json_parse(r.body)
  if not data or not data.items then
    log_error("ttkan: API returned no items for " .. novelId)
    return {}
  end

  local chapters = {}
  for _, item in ipairs(data.items) do
    local chapterName = item.chapter_name or item["chapter_name"] or ""
    local chapterId = item.chapter_id or item["chapter_id"] or 0
    if chapterName ~= "" then
      chapterName = unescape_unicode(chapterName)
      local chUrl = "https://www.ttkan.co/novel/pagea/" .. novelId .. "_" .. tostring(chapterId) .. ".html"
      table.insert(chapters, { title = chapterName, url = chUrl })
    end
  end

  return chapters
end

-- ── Hash for updates ───────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  -- IMPORTANT: direct http_get, NOT fetchPage. The hash must reflect the
  -- live state of the book page so the engine detects new chapters.
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "button.btn_show_all_chapters")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Chapter text ────────────────────────────────────────────────────────────
-- The chapter page has structure:
--   <div class="content">
--     <a class="anchor_bookmark"></a>
--     <p>...</p> <p>...</p> ...
--     <center></center>  (ad placeholder, sometimes empty)
--     <p>...</p> ...
--     <div id="div_content_end"></div>  (end marker)
--     <div class="div_feedback">章節報錯</div>
--     <div class="social_share_frame">分享給朋友：</div>
--     <amp-social-share>...</amp-social-share>
--     ...
--   </div>
-- We strip everything that isn't a <p> with prose, then apply standard
-- content transforms.

function getChapterText(html, url)
  local cleaned = html_remove(html,
    "script", "style",
    ".ads_auto_place", ".mobadsq",        -- ad placeholders
    "amp-img", "img", "svg",              -- visual noise
    "center",                             -- ad center blocks
    "#div_content_end",                   -- end-of-content marker
    ".div_adhost",                        -- ad host containers
    ".trc_related_container",             -- "related chapters" widget
    ".div_feedback",                      -- "chapter report" widget
    ".social_share_frame",                -- "share with friends" widget
    "amp-social-share",                   -- AMP share buttons
    "button",                             -- any stray buttons
    ".icon", ".decoration",               -- icon / decoration spans
    ".next_page_links",                   -- prev/next chapter links
    ".more_recommend",                    -- "more recommendations" widget
    "a"                                   -- any anchor (chapter nav)
  )
  local el = html_select_first(cleaned, ".content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Статус и дата обновления ──────────────────────────────────────────────

-- Статус книги — мета-тег og:novel:status (напр. «完結»).
function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local s = html_attr(body, "meta[name='og:novel:status']", "content")
  if s and s ~= "" then return s end
  return nil
end

-- На странице книги нет даты обновления (проверено на живом сайте) — nil.
function getBookLastUpdate(bookUrl)
  return nil
end
