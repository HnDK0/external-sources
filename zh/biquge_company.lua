-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "biquge_company"
name     = "BiqugeCompany"
version  = "1.0.3"
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
-- title/cover/description/status/chapter-list functions in one adapter run.
-- getChapterListHash stays on a direct http_get — the hash must see a fresh
-- page.
local function fetchPage(url)
  return LIB("fetch").page(url)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

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
-- Shared lib covers the domain lines, the leading chapter title (the
-- duplicated "第N章：第N章" prefix collapses into the same strip) and the
-- translator/editor attribution lines. The trailing "tip" text biquge leaves
-- at the end is site-specific and stays here.
local function applyStandardContentTransforms(text)
  text = LIB("content").standardTransforms(text, { domain = baseUrl, lang = "zh" })
  if text == "" then return "" end

  -- "温馨提示：按 回车[Enter]键 返回书目..."
  text = regex_replace(text,
    "(?im)温馨提示[:：].*$", "")
  text = regex_replace(text,
    "(?im)\\n\\s*上一章\\s*章节目录\\s*下一章\\s*$", "")

  return string_trim(text)
end

-- ── Catalog ─────────────────────────────────────────────────────────────────
-- /sort/0/{page}.html — "书库" (full library). catId=0 means all categories.

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
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
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1.booktitle, h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local src = html_attr(body, ".bookinfo img, #fmimg img, .cover img, img", "src")
  if src ~= "" then return absUrl(src) end
  return nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".bookintro, #intro, .intro")
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
  local body = fetchPage(bookUrl)
  if not body then return {} end

  local nodes = html_select(body, "#list-chapterAll a[href]")
  if #nodes == 0 then
    -- запасной вариант: весь <dl>, но только реальные ссылки на главы
    nodes = html_select(body, "dl dd a[href]")
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
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".booktag span.red")
  if el then return string_clean(el.text) end
  return nil
end

function getBookLastUpdate(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  -- Извлекаем дату YYYY-MM-DD из текста страницы (shared meta lib).
  return LIB("meta").normalizeDate(body)
end
