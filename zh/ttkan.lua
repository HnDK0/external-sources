-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "ttkan"
name     = "TTKan"
version  = "1.1.1"
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

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Apply standard content transforms.
-- Lifted from the novel_extractor.py audit: strip site domain refs, collapse
-- a duplicated chapter-title prefix that some sites accidentally inject
-- (e.g. "Chapter 1: Chapter 1: ..."), drop translator/editor notes, and
-- strip the trailing "chapter report / share with friends" UI tail that
-- ttkan leaves inside .content.
local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)

  -- Strip site domain references ("www.ttkan.co ..." etc.)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")

  -- Collapse a duplicated chapter-title prefix at the start of the text.
  -- Pattern: "第N章[:：. -— ]第N章[:：. -— ]rest" → "第N章[:：. -— ]rest"
  -- Also handles "Chapter N: Chapter N: ..." (English) and the case where
  -- the separator is just whitespace.
  text = regex_replace(text,
    "(?i)\\A[\\s\\p{Z}\\uFEFF]*" ..
    "((?:第[\\d〇零一二三四五六七八九十百千两\\d]+[章节卷回部集篇]|Chapter\\s+\\d+|Глава\\s+\\d+)" ..
    "(?:\\s*[:：.\\-—]\\s*|\\s+))" ..
    "\\1" ..
    "(?:[\\s\\p{Z}\\uFEFF]*[\\n\\r]+|[\\s\\p{Z}\\uFEFF]+)",
    "")

  -- Strip a single leading chapter title (it duplicates the chapter title
  -- field that the engine already displays above the body).
  text = regex_replace(text,
    "(?i)\\A[\\s\\p{Z}\\uFEFF]*" ..
    "(?:(?:第[\\d一二三四五六七八九十百]+[章节]|Chapter\\s+\\d+|Глава\\s+\\d+)" ..
    "[^\\n\\r]*[\\n\\r\\s]*)+", "")

  -- Strip translator / editor / proofreader attribution lines.
  text = regex_replace(text,
    "(?im)^\\s*(翻译|譯者|译者|編輯|编辑|校對|校对|更新|閱讀|阅读|最新閱讀|最新阅读)" ..
    "[:\\s：][^\\n\\r]{0,70}(\\r?\\n|$)", "")

  -- Strip the trailing UI tail that ttkan leaves inside .content:
  -- "章節報錯" (chapter report) and "分享給朋友：" (share with friends).
  -- These appear after the chapter body and are not prose.
  text = regex_replace(text, "(?im)\\n\\s*章節報錯\\s*$", "")
  text = regex_replace(text, "(?im)\\n\\s*分享給朋友[：:].*$", "")
  text = regex_replace(text, "(?im)\\n\\s*上一頁.*下一頁\\s*$", "")

  text = string_trim(text)
  return text
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
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1")
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
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".description")
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
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local s = html_attr(r.body, "meta[name='og:novel:status']", "content")
  if s and s ~= "" then return s end
  return nil
end

-- На странице книги нет даты обновления (проверено на живом сайте) — nil.
function getBookLastUpdate(bookUrl)
  return nil
end
