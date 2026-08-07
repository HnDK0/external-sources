-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "faqwiki"
name     = "FAQ Wiki"
version  = "1.6.4"
baseUrl  = "https://faqwiki.us/novel"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/faqwiki.png"

-- ── Helpers ───────────────────────────────────────────────────────────────────

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

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function textAfterLabel(text, label)
  local _, e = string.find(text, label, 1, true)
  if not e then return "" end
  return string_trim(text:sub(e + 1))
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = regex_replace(text, "(?i)faqwiki\\.(xyz|us).*?\\n", "")
  text = string_trim(text)
  return text
end

-- ── Catalog ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  if index > 0 then return { items = {}, hasNext = false } end

  local r = http_get(baseUrl .. "/")
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, "div.plt-page-item") or {}) do
    local titleEl = html_select_first(card.html, "h3.plt-title a")
    if not titleEl then
      titleEl = html_select_first(card.html, "a[href]")
    end
    if titleEl and titleEl.href and titleEl.href ~= "" then
      local title = string_clean(titleEl.text)
      title = regex_replace(title, "(?i)\\s*Novel\\s*[-–—]?\\s*All\\s*Chapters\\s*$", "")
      title = regex_replace(title, "(?i)\\s*[-–—]\\s*All\\s*Chapters\\s*$", "")
      local cover = html_attr(card.html, "div.plt-thumbnail img", "src")
      if not cover or cover == "" then
        cover = html_attr(card.html, "div.plt-thumbnail img", "data-src")
      end
      if not cover or cover == "" then
        cover = html_attr(card.html, "img", "src")
      end
      table.insert(items, {
        title = string_clean(title),
        url   = absUrl(titleEl.href),
        cover = cover ~= "" and absUrl(cover) or nil,
      })
    end
  end

  return { items = items, hasNext = false }
end

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end

  local r = http_get(baseUrl .. "/?s=" .. url_encode(query))
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, article in ipairs(html_select(r.body, "article.hitmag-post, article.post") or {}) do
    local titleEl = html_select_first(article.html, "h3.entry-title a, h2.entry-title a, h1.entry-title a")
    if not titleEl then
      titleEl = html_select_first(article.html, "a[rel='bookmark']")
    end
    if titleEl and titleEl.href and titleEl.href ~= "" then
      local title = string_clean(titleEl.text)
      title = regex_replace(title, "(?i)\\s*Novel\\s*[-–—]?\\s*All\\s*Chapters\\s*$", "")
      title = regex_replace(title, "(?i)\\s*[-–—]\\s*All\\s*Chapters\\s*$", "")
      local cover = html_attr(article.html, "img", "src")
      table.insert(items, {
        title = title,
        url   = absUrl(titleEl.href),
        cover = cover ~= "" and absUrl(cover) or nil,
      })
    end
  end

  if #items == 0 then
    for _, result in ipairs(html_select(r.body, "div.search-result, div.post-item, div.entry") or {}) do
      local titleEl = html_select_first(result.html, "a[href]")
      if titleEl and titleEl.href and titleEl.href ~= "" then
        local title = string_clean(titleEl.text)
        if title ~= "" then
          local cover = html_attr(result.html, "img", "src")
          table.insert(items, {
            title = title,
            url   = absUrl(titleEl.href),
            cover = cover ~= "" and absUrl(cover) or nil,
          })
        end
      end
    end
  end

  return { items = items, hasNext = false }
end

-- ── Book details ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1.entry-title")
  if not el then
    el = html_select_first(body, "h1")
  end
  if not el then return nil end
  local title = string_clean(el.text)
  -- сначала целиком "Novel - All Chapters", потом одиночный "- All Chapters"
  title = regex_replace(title, "(?i)\\s*Novel\\s*[-–—]?\\s*All\\s*Chapters\\s*$", "")
  title = regex_replace(title, "(?i)\\s*[-–—]\\s*All\\s*Chapters\\s*$", "")
  return string_clean(title)
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end

  local src = html_attr(body, "meta[property='og:image']", "content")
  if src and src ~= "" then return absUrl(src) end

  src = html_attr(body, "meta[name='twitter:image']", "content")
  if src and src ~= "" then return absUrl(src) end

  -- JSON-LD thumbnailUrl — надёжнее, чем img в entry-content (там первым идёт
  -- gtranslate-флаг, а не обложка)
  local script = html_select_first(body, "script[type='application/ld+json']")
  if script then
    local thumb = regex_match(script.text, '"thumbnailUrl"\\s*:\\s*"([^"]+)"')
    if thumb and #thumb > 0 and thumb[1] ~= "" then
      return absUrl(thumb[1])
    end
  end

  local img = html_select_first(body, "div.entry-content div.wp-block-image figure img, div.entry-content img.wp-image-\\d+, div.entry-content img, img.wp-image-\\d+")
  if img and img.src and img.src ~= "" then return absUrl(img.src) end

  return nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return "" end
  local el = html_select_first(body, "div.entry-content")
  if not el then return "" end

  local parts = {}
  local collecting = false
  local label = nil
  for _, p in ipairs(html_select(el.html, "p") or {}) do
    local strong = html_select_first(p.html, "strong")
    if strong then
      local lbl = string_trim(strong.text)
      if collecting then
        if string_ends_with(lbl, ":") then break end
      elseif string_starts_with(lbl, "Description") then
        collecting = true
        label = lbl
      end
    end
    if collecting then
      local t = p.text
      if label and string_starts_with(string_trim(t), label) then
        t = textAfterLabel(t, label)
        label = nil
      end
      table.insert(parts, string_trim(t))
    end
  end
  return string_trim(table.concat(parts, "\n\n"))
end

-- ── Genres ────────────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  local el = html_select_first(body, "div.entry-content")
  if not el then return {} end
  for _, p in ipairs(html_select(el.html, "p") or {}) do
    local strong = html_select_first(p.html, "strong")
    if strong then
      local label = string_trim(strong.text)
      if string_starts_with(label, "Genre") then
        local text = textAfterLabel(p.text, label)
        if text ~= "" then
          return string_split(text, " ")
        end
      end
    end
  end
  return {}
end

-- ── Chapter text ──────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local function extractText(body)
    local cleaned = html_remove(body,
      "script", "style",
      "div.code-block",
      "div.sharethis-inline-share-buttons",
      "div.wpavfrsz",
      "div.wpavefrsz-shortcode",
      "div.gtranslate_wrapper",
      "div#wpdiscuz",
      "div#comments",
      "div.wpd-comment",
      "div.wpd-thread",
      "div.nav-links",
      "div[class*='post-navigation']",
      "nav",
      "header",
      "footer",
      "aside",
      "form"
    )

    local el = html_select_first(cleaned, "div.entry-content")
    if not el then
      el = html_select_first(cleaned, "div#content")
    end
    if not el then return nil end

    local inner = el.html

    inner = regex_replace(inner, "(?s)<div[^>]*class=\"code-block[^\"]*\"[^>]*>.*?</div>", "")
    inner = regex_replace(inner, "(?s)<div[^>]*class=\"wpavefrsz[^\"]*\"[^>]*>.*?</div>", "")
    inner = regex_replace(inner, "(?s)<center[^>]*>.*?</center>", "")
    inner = regex_replace(inner, "(?s)<div[^>]*class=\"sharethis-inline-share-buttons\"[^>]*>.*?</div>", "")
    inner = regex_replace(inner, "(?s)<div[^>]*class=\"gtranslate_wrapper\"[^>]*>.*?</div>", "")
    inner = regex_replace(inner, "(?s)<img[^>]*>", "")
    inner = regex_replace(inner, "(?s)<p[^>]*>\\s*<strong>NOTICE:[^<]*</strong>\\s*</p>", "")
    inner = regex_replace(inner, "(?s)<p[^>]*>\\s*NOTICE:[^<]*</p>", "")
    inner = regex_replace(inner, "(?s)<p[^>]*>\\s*Want to have an ad-free experience[^<]*</p>", "")
    inner = regex_replace(inner, "(?s)<a[^>]*>\\s*(Next|Previous)\\s+Chapter\\s*</a>", "")
    inner = regex_replace(inner, "(?i)All\\s+Novels\\s+Chapter\\s+List.*", "")
    inner = regex_replace(inner, "(?i)Join our discord[^<]*", "")
    inner = regex_replace(inner, "(?s)<h2[^>]*>share our website[^<]*</h2>", "")
    inner = regex_replace(inner, "(?m)^[-—]{4,}\\s*$", "")

    local text = html_text(inner)
    if not text or text == "" then return nil end
    return text
  end

  local text = extractText(html)
  if not text or text == "" then
    local r = http_get(url)
    if r.success then
      text = extractText(r.body)
    end
  end
  if not text or text == "" then return "" end

  return applyStandardContentTransforms(text)
end

-- ── Paginated chapter list ────────────────────────────────────────────────────

function parsePage(bookUrl, page)
  if page > 1 then return { chapters = {}, totalPages = 1 } end

  local r = http_get(bookUrl)
  if not r.success then return { chapters = {}, totalPages = 1 } end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, "ul.lcp_catlist li a[href]") or {}) do
    if a.href and a.href ~= "" then
      local title = string_clean(a.text)
      if title ~= "" then
        table.insert(chapters, {
          title = title,
          url   = absUrl(a.href),
        })
      end
    end
  end

  if #chapters == 0 then
    for _, a in ipairs(html_select(r.body, "div.entry-content ul li a[href]") or {}) do
      if a.href and a.href ~= "" then
        local title = string_clean(a.text)
        if title ~= "" then
          table.insert(chapters, {
            title = title,
            url   = absUrl(a.href),
          })
        end
      end
    end
  end

  return { chapters = chapters, totalPages = 1 }
end
