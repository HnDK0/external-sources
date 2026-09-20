-- ── Метаданные ────────────────────────────────────────────────────────────────
id           = "mangalik"
name         = "Mangalik"
-- Version: 1.0.0
version      = "1.0.0"
baseUrl      = "https://mangalik.net/"
language     = "ar"
content_type = "manga"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/mangalik.png"

-- WordPress + тема Madara (WP-Manga). Каталог/поиск/детали — обычный HTML,
-- страницы глав — картинки (CDN s2solo.mangalik.net), список глав рендерится
-- в HTML страницы книги (newest-first), чтение через getPageList.

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Кэш страницы книги на сессию: движок вызывает detail-функции параллельно.
local _pageCache = {}

local function fetchBookPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- Рейтинг: <div class="post-total-rating"><span class="score font-meta total_votes">4.1</span></div>
-- Шкала Madara 0-5 — голое число понимается приложением как рейтинг.
local function extractRating(html)
    local el = html_select_first(html, ".post-total-rating .score")
    if el then
        local r = string_clean(el.text)
        if r ~= "" then return r end
    end
    return nil
end

-- Обложка из карточки/страницы: data-src (lazy) или src.
local function coverSrc(html, selector)
    local src = html_attr(html, selector, "data-src")
    if src == "" then src = html_attr(html, selector, "src") end
    return src
end

-- Парсер карточек результатов: используется поиском и фильтрованным каталогом.
local function parseMangaCards(body)
    local items = {}
    for _, card in ipairs(html_select(body, ".c-tabs-item__content, .page-item-detail")) do
        local titleEl = html_select_first(card.html, "h3 a, h5 a")
        if titleEl then
            local bookUrl = absUrl(titleEl.href)
            local cover   = absUrl(coverSrc(card.html, ".post-thumb img, .tab-thumb img"))
            local t = string_clean(titleEl.text)
            if bookUrl ~= "" and t ~= "" then
                local item = { title = t, url = bookUrl, cover = cover }
                local rating = extractRating(card.html)
                if rating then item.rating = rating end
                table.insert(items, item)
            end
        end
    end
    return items
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "manga/"
    if page > 1 then url = baseUrl .. "page/" .. tostring(page) .. "/" end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".page-item-detail")) do
        local titleEl = html_select_first(card.html, ".post-title h3.h5 a, .post-title a")
        if titleEl then
            local bookUrl = absUrl(titleEl.href)
            local cover   = absUrl(coverSrc(card.html, ".item-thumb img, .post-thumb img"))
            local t = string_clean(titleEl.text)
            if bookUrl ~= "" and t ~= "" then
                local item = { title = t, url = bookUrl, cover = cover }
                local rating = extractRating(card.html)
                if rating then item.rating = rating end
                table.insert(items, item)
            end
        end
    end

    return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "?s=" .. url_encode(query) .. "&post_type=wp-manga"
    if page > 1 then url = baseUrl .. "page/" .. tostring(page) .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga" end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseMangaCards(r.body)
    return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".post-title h1")
    if not el then return nil end
    local t = string_clean(el.text)
    return t ~= "" and t or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    local src = coverSrc(body, ".summary_image img")
    if src == "" then src = html_attr(body, "meta[property='og:image']", "content") end
    if src ~= "" then return absUrl(src) end
    return nil
end

function getBookDescription(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".summary__content")
    if el then
        local text = string_trim(html_text(el.html))
        if text ~= "" then return text end
    end
    return nil
end

function getBookGenres(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return {} end
    local genres = {}
    for _, a in ipairs(html_select(body, ".genres-content a")) do
        local g = string_trim(a.text)
        if g ~= "" then table.insert(genres, g) end
    end
    return genres
end

function getBookRating(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    return extractRating(body)
end

-- Статус: блок .post-status содержит несколько .post-content_item со
-- своими заголовками (سنة الانتاج, الحالة, ...). Ищем блок с заголовком
-- "الحالة" (статус) и берём его значение (OnGoing/Completed — как на сайте).
function getBookStatus(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    for _, item in ipairs(html_select(body, ".post-status .post-content_item")) do
        local heading = html_select_first(item.html, ".summary-heading")
        local value   = html_select_first(item.html, ".summary-content")
        if heading and value then
            local h = string_clean(heading.text)
            local v = string_clean(value.text)
            if h == "الحالة" and v ~= "" then return v end
        end
    end
    return nil
end

-- Дата обновления: стандартный WP-метатег article:modified_time (ISO со временем)
function getBookLastUpdate(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    local v = html_attr(body, "meta[property='article:modified_time']", "content")
    if v == "" then return nil end
    local y, m, d = string.match(v, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return y and (y .. "-" .. m .. "-" .. d) or nil
end

-- ── Список глав ───────────────────────────────────────────────────────────────

-- HTML страницы книги содержит полный список .wp-manga-chapter (newest-first),
-- разворачиваем в хронологический порядок, как ожидает движок.
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local reversed = {}
    for _, a in ipairs(html_select(r.body, "li.wp-manga-chapter a[href]")) do
        local chUrl = absUrl(a.href)
        local t = string_trim(a.text)
        if chUrl ~= "" and t ~= "" then
            table.insert(reversed, { title = t, url = chUrl })
        end
    end

    local chapters = {}
    for i = #reversed, 1, -1 do table.insert(chapters, reversed[i]) end
    return chapters
end

-- Хэш: всегда прямой http_get (не fetchPage!), иначе кэш сделает хэш вечно старым.
function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "li.wp-manga-chapter a[href]")
    return el and el.href or nil
end

-- ── Страницы главы (манга) ────────────────────────────────────────────────────

-- Движок передаёт загруженный HTML главы. Возвращаем URL картинок по порядку.
function getPageList(html, url)
    if not html or html == "" then
        local r = http_get(url)
        if not r.success then return {} end
        html = r.body
    end
    local pages = {}
    local seen = {}
    for _, img in ipairs(html_select(html, ".reading-content img.wp-manga-chapter-img")) do
        local src = img.src
        if src == "" then src = img:attr("data-src") end
        src = absUrl(src)
        if src ~= "" and not seen[src] then
            seen[src] = true
            table.insert(pages, src)
        end
    end
    return pages
end

-- Легаси-фолбэк для сборок без поддержки page-list: HTML с <img>.
function getChapterText(html, url)
    if not html or html == "" then
        local r = http_get(url)
        if not r.success then return "" end
        html = r.body
    end
    local imgs = {}
    for _, img in ipairs(html_select(html, ".reading-content img.wp-manga-chapter-img")) do
        local src = img.src
        if src == "" then src = img:attr("data-src") end
        src = absUrl(src)
        if src ~= "" then
            table.insert(imgs, '<img src="' .. src:gsub("&", "&amp;") .. '">')
        end
    end
    return table.concat(imgs, "\n")
end

-- ── Фильтры и сортировка ──────────────────────────────────────────────────────
-- Расширенный поиск Madara: /?s=&post_type=wp-manga + параметры.
-- Жанры передаются как genre[]=url_encode(арабский slug) — сервер сравнивает
-- с raw арабским слагом таксономии, поэтому value == арабский лейбл.

function getFilterList()
    return {
        {
            type         = "select",
            key          = "m_orderby",
            label        = "ترتيب",
            defaultValue = "latest",
            options = {
                { value = "latest",    label = "الاحدث"        },
                { value = "alphabet",  label = "A-Z"           },
                { value = "rating",    label = "التقييم"       },
                { value = "trending",  label = "شائع"          },
                { value = "views",     label = "الاكثر مشاهدة" },
                { value = "new-manga", label = "جديد"          },
            }
        },
        {
            type         = "select",
            key          = "status",
            label        = "الحالة",
            defaultValue = "",
            options = {
                { value = "",         label = "الكل"     },
                { value = "on-going", label = "مستمرة"   },
                { value = "end",      label = "مكتملة"   },
                { value = "canceled", label = "ملغاة"    },
                { value = "on-hold",  label = "متوقفة"   },
            }
        },
        {
            type         = "select",
            key          = "adult",
            label        = "المحتوى",
            defaultValue = "",
            options = {
                { value = "",  label = "الكل"       },
                { value = "0", label = "بدون +18"   },
                { value = "1", label = "فقط +18"    },
            }
        },
        {
            type    = "checkbox",
            key     = "genre",
            label   = "التصنيفات",
            options = {
                { value = "اكشن",                    label = "اكشن" },
                { value = "مغامرة",                  label = "مغامرة" },
                { value = "كوميديا",                 label = "كوميديا" },
                { value = "دراما",                   label = "دراما" },
                { value = "رومانسى",                 label = "رومانسى" },
                { value = "شوجو",                    label = "شوجو" },
                { value = "شونين",                   label = "شونين" },
                { value = "سينين",                   label = "سينين" },
                { value = "جوسى",                    label = "جوسى" },
                { value = "ويب تون",                 label = "ويب تون" },
                { value = "الحياه المدرسيه",         label = "الحياه المدرسيه" },
                { value = "قوة خارقة",               label = "قوة خارقة" },
                { value = "غموض",                    label = "غموض" },
                { value = "تاريخى",                  label = "تاريخى" },
                { value = "اثاره",                   label = "اثاره" },
                { value = "الحياه اليومية",          label = "الحياه اليومية" },
                { value = "فنون قتاليه",             label = "فنون قتاليه" },
                { value = "سحر",                     label = "سحر" },
                { value = "ايسكاي",                  label = "ايسكاي" },
                { value = "فانتازيا",                label = "فانتازيا" },
                { value = "خيال علمى",               label = "خيال علمى" },
                { value = "رعب",                     label = "رعب" },
                { value = "حريم",                    label = "حريم" },
                { value = "حريم عكسى",               label = "حريم عكسى" },
                { value = "تناسخ",                   label = "تناسخ" },
                { value = "مانهوا",                  label = "مانهوا" },
                { value = "مانجا",                   label = "مانجا" },
                { value = "الغموض",                  label = "الغموض" },
                { value = "عنف",                     label = "عنف" },
                { value = "عنف جنسى",                label = "عنف جنسى" },
                { value = "نفسى",                    label = "نفسى" },
                { value = "بوليسي",                  label = "بوليسي" },
                { value = "جريمة",                   label = "جريمة" },
                { value = "تحقيقات",                 label = "تحقيقات" },
                { value = "قتال",                    label = "قتال" },
                { value = "قتالات",                  label = "قتالات" },
                { value = "وحوش",                    label = "وحوش" },
                { value = "شياطين",                  label = "شياطين" },
                { value = "مصاصى الدماء",            label = "مصاصى الدماء" },
                { value = "مستذئب",                  label = "مستذئب" },
                { value = "زومبي",                   label = "زومبي" },
                { value = "النجاة",                  label = "النجاة" },
                { value = "نجاة",                    label = "نجاة" },
                { value = "ما بعد نهاية العالم",     label = "ما بعد نهاية العالم" },
                { value = "نهاية العالم",            label = "نهاية العالم" },
                { value = "عالم مختلف",              label = "عالم مختلف" },
                { value = "ذكريات من عالم آخر",      label = "ذكريات من عالم آخر" },
                { value = "داخل اللعبه",             label = "داخل اللعبه" },
                { value = "داخل روايه",              label = "داخل روايه" },
                { value = "العاب فيديو",             label = "العاب فيديو" },
                { value = "الالعاب",                 label = "الالعاب" },
                { value = "رياضه",                   label = "رياضه" },
                { value = "رياضى",                   label = "رياضى" },
                { value = "طبخ",                     label = "طبخ" },
                { value = "موسيقى",                  label = "موسيقى" },
                { value = "ميكا",                    label = "ميكا" },
                { value = "نينجا",                   label = "نينجا" },
                { value = "ساموراي",                 label = "ساموراي" },
                { value = "ساموري",                  label = "ساموري" },
                { value = "عسكري",                   label = "عسكري" },
                { value = "عسكريه",                  label = "عسكريه" },
                { value = "حرب",                     label = "حرب" },
                { value = "حربى",                    label = "حربى" },
                { value = "سياسي",                   label = "سياسي" },
                { value = "شرطة",                    label = "شرطة" },
                { value = "مافيا",                   label = "مافيا" },
                { value = "جانحون",                  label = "جانحون" },
                { value = "المخالفون للقانون",       label = "المخالفون للقانون" },
                { value = "نبالة",                   label = "نبالة" },
                { value = "نبلاء",                   label = "نبلاء" },
                { value = "ممالك",                   label = "ممالك" },
                { value = "عوالم",                   label = "عوالم" },
                { value = "الهة",                    label = "الهة" },
                { value = "الهه",                    label = "الهه" },
                { value = "مانا",                    label = "مانا" },
                { value = "نظام",                    label = "نظام" },
                { value = "زراعة",                   label = "زراعة" },
                { value = "تجاره",                   label = "تجاره" },
                { value = "شركه",                    label = "شركه" },
                { value = "اقتصاد",                  label = "اقتصاد" },
                { value = "عمل مكتبي",               label = "عمل مكتبي" },
                { value = "مدرسه",                   label = "مدرسه" },
                { value = "مدرسي",                   label = "مدرسي" },
                { value = "رعاية اطفال",             label = "رعاية اطفال" },
                { value = "رعاية طفل",               label = "رعاية طفل" },
                { value = "اطفال",                   label = "اطفال" },
                { value = "كل الاعمار",              label = "كل الاعمار" },
                { value = "عائلى",                   label = "عائلى" },
                { value = "زواج مدبر",               label = "زواج مدبر" },
                { value = "عوده بالزمن",             label = "عوده بالزمن" },
                { value = "السفر عبر الزمن",         label = "السفر عبر الزمن" },
                { value = "سفر عبر الزمن",           label = "سفر عبر الزمن" },
                { value = "زمكانى",                  label = "زمكانى" },
                { value = "زمنكاني",                 label = "زمنكاني" },
                { value = "عصر حديث",                label = "عصر حديث" },
                { value = "حديث",                    label = "حديث" },
                { value = "الخيال العلمي",           label = "الخيال العلمي" },
                { value = "الخيال العلمى",           label = "الخيال العلمى" },
                { value = "الواقع الافتراضي",        label = "الواقع الافتراضي" },
                { value = "واقع افتراضى",            label = "واقع افتراضى" },
                { value = "واقعى",                   label = "واقعى" },
                { value = "خيال",                    label = "خيال" },
                { value = "خيالي",                   label = "خيالي" },
                { value = "فانتازا",                 label = "فانتازا" },
                { value = "فانتسي",                  label = "فانتسي" },
                { value = "فنتازيا",                 label = "فنتازيا" },
                { value = "مانها",                   label = "مانها" },
                { value = "ايتشى",                   label = "ايتشى" },
                { value = "اتشى",                    label = "اتشى" },
                { value = "ايشى",                    label = "ايشى" },
                { value = "يورى",                    label = "يورى" },
                { value = "يورى خفيف",               label = "يورى خفيف" },
                { value = "بالغ",                    label = "بالغ" },
                { value = "راشد",                    label = "راشد" },
                { value = "ناضج",                    label = "ناضج" },
                { value = "متحول",                   label = "متحول" },
                { value = "جندر بندر",               label = "جندر بندر" },
                { value = "جندر اسواب",              label = "جندر اسواب" },
                { value = "امرأة شريرة",             label = "امرأة شريرة" },
                { value = "بطل خارق",                label = "بطل خارق" },
                { value = "بطل غير اعتيادى",         label = "بطل غير اعتيادى" },
                { value = "بطل غير اعتيادي",         label = "بطل غير اعتيادي" },
                { value = "بطل مجنون",               label = "بطل مجنون" },
                { value = "بطل وحش",                 label = "بطل وحش" },
                { value = "الفتاة الوحش",            label = "الفتاة الوحش" },
                { value = "شرير",                    label = "شرير" },
                { value = "سايكوباث",                label = "سايكوباث" },
                { value = "علم نفس",                 label = "علم نفس" },
                { value = "فلسفه",                   label = "فلسفه" },
                { value = "مؤامرات",                 label = "مؤامرات" },
                { value = "خيار",                    label = "خيار" },
                { value = "تخطيط",                   label = "تخطيط" },
                { value = "استدعاء",                 label = "استدعاء" },
                { value = "تجسيد",                   label = "تجسيد" },
                { value = "انتقال",                  label = "انتقال" },
                { value = "ارتقاء",                  label = "ارتقاء" },
                { value = "تراجع",                   label = "تراجع" },
                { value = "صقل",                     label = "صقل" },
                { value = "تدريب",                   label = "تدريب" },
                { value = "تملك",                    label = "تملك" },
                { value = "ترويض",                   label = "ترويض" },
                { value = "ترويض وحوش",              label = "ترويض وحوش" },
                { value = "طرد الارواح الشريره",     label = "طرد الارواح الشريره" },
                { value = "اشباح",                   label = "اشباح" },
                { value = "ارواح",                   label = "ارواح" },
                { value = "تناسخ الارواح",           label = "تناسخ الارواح" },
                { value = "طبي",                     label = "طبي" },
                { value = "هندسة",                   label = "هندسة" },
                { value = "اليات",                   label = "اليات" },
                { value = "الات",                    label = "الات" },
                { value = "العاب الكترونية",         label = "العاب الكترونية" },
                { value = "العاب تقليدية",           label = "العاب تقليدية" },
                { value = "العاب رعب",               label = "العاب رعب" },
                { value = "كوما-4",                  label = "كوما-4" },
                { value = "مجموعة قصص",              label = "مجموعة قصص" },
                { value = "مقطع طولي",               label = "مقطع طولي" },
                { value = "ون شوت",                  label = "ون شوت" },
                { value = "مانجا ملونه",             label = "مانجا ملونه" },
                { value = "ملونه",                   label = "ملونه" },
                { value = "الالوان الممتلئه",        label = "الالوان الممتلئه" },
                { value = "تلوين رسم",               label = "تلوين رسم" },
                { value = "تلوين رسمي",              label = "تلوين رسمي" },
                { value = "تلوين هواة",              label = "تلوين هواة" },
                { value = "مقتبسة",                  label = "مقتبسة" },
                { value = "حائز علي جائزة",          label = "حائز علي جائزة" },
                { value = "حصريه",                   label = "حصريه" },
                { value = "روايه",                   label = "روايه" },
                { value = "رواية عربية",             label = "رواية عربية" },
                { value = "سوردا عربية",             label = "سوردا عربية" },
                { value = "انمى",                    label = "انمى" },
                { value = "الحيوانات الاليفة",       label = "الحيوانات الاليفة" },
                { value = "حيوانات",                 label = "حيوانات" },
                { value = "حيوانات اليفه",           label = "حيوانات اليفه" },
                { value = "قطط",                     label = "قطط" },
                { value = "تنانين",                  label = "تنانين" },
                { value = "ملائكة",                  label = "ملائكة" },
                { value = "كائنات فضائية",           label = "كائنات فضائية" },
                { value = "بعد الكارثه",             label = "بعد الكارثه" },
                { value = "البقاء علي قيد الحياه",   label = "البقاء علي قيد الحياه" },
                { value = "التحديث",                 label = "التحديث" },
                { value = "مغني",                    label = "مغني" },
                { value = "ازياء",                   label = "ازياء" },
                { value = "اعمال",                   label = "اعمال" },
                { value = "اعمار",                   label = "اعمار" },
                { value = "اكاديميه",                label = "اكاديميه" },
                { value = "ابراج",                   label = "ابراج" },
                { value = "اساطير",                  label = "اساطير" },
                { value = "اساطيز",                  label = "اساطيز" },
                { value = "العصور الوسطى",           label = "العصور الوسطى" },
                { value = "عصور وسطى",               label = "عصور وسطى" },
                { value = "تاريخ",                   label = "تاريخ" },
                { value = "ناريخى",                  label = "ناريخى" },
                { value = "تنايخ",                   label = "تنايخ" },
                { value = "الحريم العكسي",           label = "الحريم العكسي" },
                { value = "شريحة من الحياة",         label = "شريحة من الحياة" },
                { value = "الحياه المدرسية",         label = "الحياه المدرسية" },
                { value = "حياه مدرسية",             label = "حياه مدرسية" },
                { value = "معالج",                   label = "معالج" },
                { value = "سوء فهم",                 label = "سوء فهم" },
                { value = "انتقام",                  label = "انتقام" },
                { value = "ثأر",                     label = "ثأر" },
                { value = "اضطهاد",                  label = "اضطهاد" },
                { value = "تنمر",                    label = "تنمر" },
                { value = "هوس",                     label = "هوس" },
                { value = "هواه",                    label = "هواه" },
                { value = "سم",                      label = "سم" },
                { value = "دماء",                    label = "دماء" },
                { value = "دموى",                    label = "دموى" },
                { value = "مأساوي",                  label = "مأساوي" },
                { value = "ماساة",                   label = "ماساة" },
                { value = "تراجيدي",                 label = "تراجيدي" },
                { value = "تشويق",                   label = "تشويق" },
                { value = "تحقيق",                   label = "تحقيق" },
                { value = "تحري",                    label = "تحري" },
            }
        },
    }
end

-- Каталог с фильтрами: /?s=&post_type=wp-manga + m_orderby/status/adult/genre[].
-- Пагинация Madara на query-URL: &paged=N.
-- Жанры: OR-логика (объединение) — сайт не поддерживает AND (op=1 игнорируется).
function getCatalogFiltered(index, filters)
    local page = index + 1
    local orderby = filters["m_orderby"] or ""
    local status  = filters["status"]    or ""
    local adult   = filters["adult"]     or ""
    local genres  = filters["genre_included"] or {}

    local url = baseUrl .. "?s=&post_type=wp-manga"
    if orderby ~= "" then url = url .. "&m_orderby=" .. url_encode(orderby) end
    for _, g in ipairs(genres) do
        url = url .. "&genre%5B%5D=" .. url_encode(g)
    end
    if adult ~= "" then url = url .. "&adult=" .. url_encode(adult) end
    if status ~= "" then url = url .. "&status%5B%5D=" .. url_encode(status) end
    if page > 1 then url = url .. "&paged=" .. tostring(page) end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseMangaCards(r.body)
    return { items = items, hasNext = #items > 0 }
end