-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "biquge_company"
name     = "BiqugeCompany"
version  = "1.0.2"
baseUrl  = "https://www.biquge.company/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/biquge_company.png"

-- ── Site notes ──────────────────────────────────────────────────────────────
-- biquge.company (笔趣阁) is a Simplified-Chinese biquge-family novel site.
--
-- URL patterns:
--   Book page:  /book/{bookId}.html                e.g. /book/29901.html
--   Chapter:    /read/{bookId}/{chId}.html         e.g. /read/29901/30753082.html
--   Catalog:    /sort/{catId}/{page}.html          e.g. /sort/0/1.html (书库)
--   Top:        /top.html
--   Completed:  /quanben/{page}.html               e.g. /quanben/1.html
--   Search:     POST /modules/article/search.php
--                body: searchkey={query}&action=login&searchtype=
--
-- Chapter content:
--   The chapter body lives in <div class="readcontent"> inside
--   .content > .book.read. Content uses <br> separators (biquge family).
--   The chapter title is in <h1 class="pt10">.
--   Noise elements:
--     .booktag           (vote / bookmark / feedback links)
--     .text-center       (prev / chapter list / next nav)
--     .pt10              (tip text "按回车返回书目...")
--     .book.mt10.pt10.tuijian  (recommendations)
--     script             (jQuery, ad scripts)
--
-- Biquge family conventions:
--   - Chapter list is in <dl><dd><a>...</a></dd></dl> on the book page,
--     listed in reverse chronological order (newest first). We reverse it
--     before returning so the engine gets oldest-first.
--   - Search is a POST form (not GET).
-- ────────────────────────────────────────────────────────────────────────────

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Extract bookId from a book URL like /book/29901.html
local function extractBookId(bookUrl)
  return string.match(bookUrl, "/book/(%d+)%.html")
end

-- Обложка книги на biquge.company лежит по детерминированному пути,
-- производному от bookId: /files/article/image/{первые2цифры}/{bookId}/{bookId}s.jpg
-- (проверено на реальных страницах — отдаёт 200 image/jpeg). Это позволяет
-- подставить обложку в каталог/поиск без дополнительного запроса к странице книги.
local function coverForBookUrl(bookUrl)
  local bid = extractBookId(bookUrl)
  if not bid or bid == "" then return "" end
  local first2 = string.sub(bid, 1, 2)
  return baseUrl .. "files/article/image/" .. first2 .. "/" .. bid .. "/" .. bid .. "s.jpg"
end

-- Apply standard content transforms.
-- Pattern lifted from the novel_extractor.py audit work: collapse duplicated
-- chapter-title prefix, strip the leading chapter title, drop translator
-- notes, and strip the trailing "tip" text biquge leaves at the end.
local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)

  -- Strip site domain references.
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")

  -- Collapse a duplicated chapter-title prefix at the start.
  text = regex_replace(text,
    "(?i)\\A[\\s\\p{Z}\\uFEFF]*" ..
    "((?:第[\\d〇零一二三四五六七八九十百千两\\d]+[章节卷回部集篇]|Chapter\\s+\\d+)" ..
    "(?:\\s*[:：.\\-—]\\s*|\\s+))" ..
    "\\1" ..
    "(?:[\\s\\p{Z}\\uFEFF]*[\\n\\r]+|[\\s\\p{Z}\\uFEFF]+)",
    "")

  -- Strip a single leading chapter title.
  text = regex_replace(text,
    "(?i)\\A[\\s\\p{Z}\\uFEFF]*" ..
    "(?:(?:第[\\d一二三四五六七八九十百]+[章节]|Chapter\\s+\\d+)" ..
    "[^\\n\\r]*[\\n\\r\\s]*)+", "")

  -- Strip translator / editor attribution lines.
  text = regex_replace(text,
    "(?im)^\\s*(翻译|譯者|译者|編輯|编辑|校對|校对|更新|閱讀|阅读|最新閱讀|最新阅读)" ..
    "[:\\s：][^\\n\\r]{0,70}(\\r?\\n|$)", "")

  -- Strip the trailing "tip" text biquge leaves at the end:
  -- "温馨提示：按 回车[Enter]键 返回书目..."
  text = regex_replace(text,
    "(?im)温馨提示[:：].*$", "")
  text = regex_replace(text,
    "(?im)\\n\\s*上一章\\s*章节目录\\s*下一章\\s*$", "")

  text = string_trim(text)
  return text
end

-- ── Catalog ─────────────────────────────────────────────────────────────────
-- /sort/0/{page}.html — "书库" (full library). catId=0 means all categories.

function getCatalogList(index)
  local page = index + 1
  local url = baseUrl .. "sort/0/" .. tostring(page) .. ".html"
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  -- Books are in .bookbox > .bookinfo
  for _, box in ipairs(html_select(r.body, ".bookbox")) do
    local titleEl = html_select_first(box.html, ".bookname a, h4 a, h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" and string.find(bookUrl, "/book/%d+") then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = coverForBookUrl(bookUrl)
        })
      end
    end
  end

  -- hasNext: look for a "下一页" link.
  local hasNext = false
  for _, a in ipairs(html_select(r.body, ".page a, a[href*='sort']")) do
    local txt = string_clean(a.text)
    if txt == "下一页" or txt == "下页" or txt == "»" or txt == "Next" then
      hasNext = true
      break
    end
  end
  if #items >= 10 then hasNext = true end

  return { items = items, hasNext = hasNext }
end

-- ── Search (POST form) ──────────────────────────────────────────────────────
-- POST /modules/article/search.php with body:
--   searchkey={query}&action=login&searchtype=

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end

  local payload = "searchkey=" .. url_encode(query) .. "&action=login&searchtype="
  local r = http_post(baseUrl .. "modules/article/search.php", payload, {
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
  })
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, box in ipairs(html_select(r.body, ".bookbox")) do
    local titleEl = html_select_first(box.html, ".bookname a, h4 a, h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" and string.find(bookUrl, "/book/%d+") then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = coverForBookUrl(bookUrl)
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
  local el = html_select_first(r.body, "h1.booktitle, h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local src = html_attr(r.body, ".bookinfo img, #fmimg img, .cover img, img", "src")
  if src ~= "" then return absUrl(src) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".bookintro, #intro, .intro")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Chapter list ────────────────────────────────────────────────────────────
-- На странице книги <dl> содержит сразу три блока:
--   1) превью «последние главы» (новые сверху, убывающе),
--   2) служебную ссылку href="javascript:;" (кнопка «查看全部章节»),
--   3) полный список глав внутри <div id="list-chapterAll"> — уже по возрастанию
--      (第1章 → последняя глава).
-- Старый код брал весь <dl> целиком и переворачивал его, из-за чего превью и
-- полный список смешивались (дубликаты + неверный порядок). Берём только
-- #list-chapterAll — он уже отсортирован по возрастанию, переворачивать не надо.

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local nodes = html_select(r.body, "#list-chapterAll a[href]")
  if #nodes == 0 then
    -- запасной вариант: весь <dl>, но только реальные ссылки на главы
    nodes = html_select(r.body, "dl dd a[href]")
  end

  local chapters = {}
  for _, a in ipairs(nodes) do
    local href = a.href or ""
    -- пропускаем служебные ссылки вроде javascript:
    if string.find(href, "/read/") then
      local chUrl = absUrl(href)
      local t = string_clean(a.text)
      if chUrl ~= "" and t ~= "" then
        table.insert(chapters, { title = t, url = chUrl })
      end
    end
  end

  -- #list-chapterAll уже идёт по возрастанию (第1章 → последняя), не переворачиваем.
  return chapters
end

-- ── Hash for updates ───────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  -- Biquge sorts chapters newest-first, so the first <dd><a> is the latest.
  local el = html_select_first(r.body, "dl dd a[href]")
  if el then return el.href end
  return nil
end

-- ── Chapter text ────────────────────────────────────────────────────────────
-- .content > .book.read > .readcontent. Content uses <br> separators.
-- Strip .booktag (vote/bookmark), .text-center (chapter nav), .pt10 (tip),
-- and .book.mt10.pt10.tuijian (recommendations).

function getChapterText(html, url)
  local cleaned = html_remove(html,
    "script", "style",
    ".booktag",                       -- vote / bookmark / feedback
    ".text-center",                   -- prev / chapter list / next nav
    ".pt10",                          -- tip text
    ".book.mt10.pt10.tuijian",        -- "大家还在看" recommendations
    "ins", "iframe",                  -- ad slots
    ".adsbygoogle"
  )

  local el = html_select_first(cleaned, ".readcontent")
  if not el then
    -- Fallbacks for biquge family variants.
    el = html_select_first(cleaned, "#chaptercontent")
    if not el then
      el = html_select_first(cleaned, "#content")
      if not el then
        el = html_select_first(cleaned, ".book.read")
        if not el then return "" end
      end
    end
  end

  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Book status / last update ────────────────────────────────────────────────
-- Статус книги: <span class="red"> внутри <p class="booktag"> (значения:
-- "连载" — продолжается, "全本" — завершена).
-- Дата последнего обновления: <p class="booktime">, формат
-- "更新时间：YYYY-MM-DD HH:MM". Извлекаем только дату YYYY-MM-DD.

function getBookStatus(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".booktag span.red")
  if el then return string_clean(el.text) end
  return nil
end

function getBookLastUpdate(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  -- Извлекаем дату YYYY-MM-DD из текста страницы.
  return string.match(r.body, "%d%d%d%d%-%d%d%-%d%d")
end
