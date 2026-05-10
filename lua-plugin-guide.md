# Гайд по написанию Lua-плагинов

> Основан на анализе реального кода: `LuaSourceAdapter.kt`, `LuaSourceLoader.kt`, `LuaFilterSupport.kt`, `LuaSettingsSupport.kt` и 27 существующих плагинов.

---

## Содержание

1. [Структура плагина](#структура-плагина)
2. [Метаданные](#метаданные)
3. [Обязательные функции](#обязательные-функции)
4. [Работа с HTTP](#работа-с-http)
5. [Работа с HTML и CSS-селекторами](#работа-с-html-и-css-селекторами)
6. [Очистка текста](#очистка-текста)
7. [Работа с JSON API](#работа-с-json-api)
8. [Каталог и пагинация](#каталог-и-пагинация)
9. [Список глав](#список-глав)
10. [Текст главы](#текст-главы)
11. [Фильтры каталога](#фильтры-каталога)
12. [Настройки плагина](#настройки-плагина)
13. [Хелперы и утилиты](#хелперы-и-утилиты)
14. [Полный справочник API](#полный-справочник-api)
15. [Полный шаблон плагина](#полный-шаблон-плагина)
16. [Частые ошибки](#частые-ошибки)

---

## Структура плагина

Плагин — это один `.lua` файл. Движок (`LuaEngine`) загружает его через `JsePlatform.standardGlobals()`, выполняет и передаёт `globals` в `LuaSourceAdapter`. Все функции и переменные, объявленные в глобальном пространстве, доступны адаптеру.

Минимальная структура файла:

```lua
-- 1. МЕТАДАННЫЕ (глобальные переменные)
id       = "my_source"
name     = "My Source"
version  = "1.0.0"
baseUrl  = "https://example.com"
language = "en"

-- 2. ЛОКАЛЬНЫЕ ХЕЛПЕРЫ
local function absUrl(href) ... end

-- 3. ОБЯЗАТЕЛЬНЫЕ ФУНКЦИИ
function getCatalogList(index) ... end
function getCatalogSearch(index, query) ... end
function getBookTitle(bookUrl) ... end
function getBookCoverImageUrl(bookUrl) ... end
function getBookDescription(bookUrl) ... end
function getChapterList(bookUrl) ... end
function getChapterText(html, url) ... end

-- 4. ОПЦИОНАЛЬНЫЕ ФУНКЦИИ
function getBookGenres(bookUrl) ... end
function getChapterListHash(bookUrl) ... end
function getFilterList() ... end
function getCatalogFiltered(index, filters) ... end
function getSettingsSchema() ... end
```

Адаптер автоматически определяет подкласс по наличию функций:

| Функции присутствуют | Подкласс адаптера |
|---|---|
| Только базовые | `LuaSourceAdapter` |
| + `getSettingsSchema` | `LuaSourceAdapterConfigurable` |
| + `getFilterList` | `LuaSourceAdapterFilterable` |
| + оба | `LuaSourceAdapterFull` |

---

## Метаданные

Все поля — глобальные переменные Lua.

```lua
id       = "source_id"        -- уникальный ID, используется как имя файла: source_id.lua
name     = "Source Name"      -- отображаемое название
version  = "1.0.0"            -- версия
baseUrl  = "https://..."      -- базовый URL (обязательный)
language = "en"               -- ISO 639-1: "en", "ru", "ja", "zh", "id"
                              -- или "MTL" для машинного перевода
icon     = "https://..."      -- URL иконки (опционально)
charset  = "UTF-8"            -- кодировка ответов (опционально, default UTF-8)
```

**Важно про `id`:** должен совпадать с именем `.lua` файла без расширения. Если `id = "royal_road"`, файл должен называться `royal_road.lua`.

---

## Обязательные функции

### getCatalogList(index)

Постраничный каталог. `index` начинается с 0.

```lua
function getCatalogList(index)
    local page = index + 1  -- большинство сайтов считают с 1
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

Возвращаемая таблица:
- `items` — массив `{ title, url, cover }`, где `cover` опционален
- `hasNext` — `true` если есть следующая страница

### getCatalogSearch(index, query)

Поиск. Если сайт возвращает всё на одной странице — возвращать `hasNext = false` при `index > 0`.

```lua
function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local url = baseUrl .. "/search?q=" .. url_encode(query)
    -- ... аналогично getCatalogList
end
```

### getBookTitle(bookUrl)

```lua
function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "h1.title")
    return el and string_clean(el.text) or nil
end
```

### getBookCoverImageUrl(bookUrl)

```lua
function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cover = html_attr(r.body, ".cover img", "src")
    return cover ~= "" and absUrl(cover) or nil
end
```

### getBookDescription(bookUrl)

```lua
function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".description")
    return el and string_trim(el.text) or nil
end
```

### getChapterList(bookUrl)

Возвращает массив `{ title, url, volume? }` в хронологическом порядке (от первой к последней).

```lua
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

Получает полный HTML страницы главы и URL. Должен вернуть строку с текстом.

```lua
function getChapterText(html, url)
    local cleaned = html_remove(html, "script", "style", ".ads", ".nav-links")
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end
```

---

## Работа с HTTP

### http_get(url [, config])

```lua
-- Простой GET
local r = http_get("https://example.com/page")

-- С заголовками
local r = http_get(url, {
    headers = {
        ["Referer"]          = baseUrl,
        ["X-Requested-With"] = "XMLHttpRequest",
        ["Accept"]           = "application/json",
    },
    charset = "UTF-8"  -- кодировка ответа (default UTF-8)
})

-- Проверка результата
if not r.success then
    log_error("Request failed: code=" .. tostring(r.code))
    return { items = {}, hasNext = false }
end
-- r.body  — строка с телом ответа
-- r.code  — HTTP код (200, 404, ...)
```

### http_post(url, body [, config])

```lua
-- Form-encoded POST
local r = http_post(
    baseUrl .. "/ajax",
    "action=loadChapters&id=" .. novelId,
    {
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Referer"]      = baseUrl
        }
    }
)

-- JSON POST
local r = http_post(
    baseUrl .. "/api/reader",
    json_stringify({ novel_id = 123, chapter = 1 }),
    {
        headers = {
            ["Content-Type"] = "application/json",
            ["Origin"]       = baseUrl
        }
    }
)
```

### http_get_batch(urls_table)

Параллельная загрузка нескольких URL. Порядок ответов соответствует порядку запросов.

```lua
local urls = {}
for p = 2, maxPage do
    table.insert(urls, baseUrl .. "/chapters?page=" .. p)
end

local results = http_get_batch(urls)
for i, res in ipairs(results) do
    if res.success then
        -- обрабатываем res.body
    end
end
```

### Работа с cookies

```lua
-- Получить cookies для домена
local cookies = get_cookies("https://example.com")
local token = cookies["session_token"]

-- Установить cookies
set_cookies("https://example.com", {
    ["session_id"] = "abc123",
    ["token"]      = "xyz"
})
```

### Задержки (rate limiting)

```lua
sleep(300)                        -- 300 мс
sleep(math.random(150, 350))      -- случайная задержка 150-350 мс
```

Используйте `sleep` между запросами в `getChapterList` если сайт агрессивно блокирует парсеры (пример: jaomix).

---

## Работа с HTML и CSS-селекторами

### Основные функции

```lua
-- Парсит HTML, возвращает { text, html, title, body }
local doc = html_parse(htmlString)

-- Возвращает массив элементов
local cards = html_select(htmlString, ".novel-card")

-- Возвращает первый элемент или nil
local el = html_select_first(htmlString, "h1.title")

-- Быстро получить атрибут первого совпадения
local src = html_attr(htmlString, ".cover img", "src")

-- Извлечь текст с сохранением переносов строк (<p>, <br>)
local text = html_text(innerHtml)

-- Удалить элементы из HTML
local cleanHtml = html_remove(html, "script", "style", ".ads", "#popup")
```

### Объект элемента

`html_select` и `html_select_first` возвращают таблицы со следующими полями:

```lua
el.text   -- текстовое содержимое (аналог element.innerText)
el.html   -- innerHTML
el.href   -- атрибут href (уже абсолютный если abs:href доступен)
el.src    -- атрибут src
el.title  -- атрибут title
el.class  -- атрибут class
el.id     -- атрибут id

-- Методы:
el:attr("data-id")        -- любой атрибут
el:select(".child")       -- найти дочерние элементы
el:get_text()             -- то же что el.text
el:get_html()             -- то же что el.html
el:remove()               -- удалить элемент из DOM
```

### Типичные паттерны с селекторами

```lua
-- Итерация по карточкам каталога
for _, card in ipairs(html_select(r.body, ".book-item")) do
    local titleEl = html_select_first(card.html, "h3 a")
    local cover   = html_attr(card.html, "img", "src")
    -- ...
end

-- Получить href с проверкой
local a = html_select_first(r.body, ".read-btn a")
if a and a.href ~= "" then
    chapterUrl = absUrl(a.href)
end

-- Получить data-атрибут
local postId = html_attr(r.body, "#novel-report", "data-post-id")
-- или через select:
local el = html_select_first(r.body, "#novel-report")
if el then
    local postId = el:attr("data-post-id")
end

-- Удалить мусор перед парсингом текста
local cleaned = html_remove(html,
    "script", "style",
    ".advertisement", ".popup",
    ".chapter-nav", "#comments"
)
```

### Работа с вложенными структурами

```lua
-- Многоуровневый поиск
for _, row in ipairs(html_select(r.body, "table tr")) do
    local cells = html_select(row.html, "td")
    if #cells >= 2 then
        local label = string_trim(cells[1].text)
        local value = string_trim(cells[2].text)
        if label == "Genre" then
            -- обрабатываем value
        end
    end
end
```

---

## Очистка текста

### Стандартная функция очистки контента

Используйте в каждом плагине — это шаблон из реальных плагинов:

```lua
local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end

    -- 1. Unicode нормализация (NFKC)
    text = string_normalize(text)

    -- 2. Удалить ссылки на сайт-источник
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")

    -- 3. Удалить заголовок главы в начале (дублируется в названии)
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")

    -- 4. Удалить строки переводчика/редактора
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")

    -- 5. Обрезать пробелы
    text = string_trim(text)
    return text
end
```

Для русских сайтов добавьте строку с кириллицей:

```lua
text = regex_replace(text, "(?im)^\\s*(Перевод|Переводчик|Редакция|Редактор|Аннотация|Сайт|Источник)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
```

### string_clean vs string_trim

```lua
-- string_clean: normalize Unicode + collapse whitespace + trim
-- Использовать для: title, author, genre — любые короткие поля
string_clean("  Название  главы  ") --> "Название главы"

-- string_trim: только trim пробелов
-- Использовать для: description, где важны переносы строк
string_trim("  текст  ") --> "текст"
```

**Правило:** `string_clean` для коротких метаданных (тайтл, жанр, глава), `string_trim` для длинных текстов описания.

### html_text — правильное извлечение текста

`html_text` использует `TextExtractor`, который понимает HTML-структуру:
- `<p>` → абзац + двойной перенос строки
- `<br>` → одинарный перенос строки
- `<hr>` → двойной перенос строки

```lua
-- ПРАВИЛЬНО: сохраняет структуру абзацев
local text = html_text(el.html)

-- НЕПРАВИЛЬНО для текста главы: теряет переносы строк
local text = el.text
```

### Регулярные выражения

Движок использует Java regex с поддержкой:
- `(?i)` — case-insensitive
- `(?m)` — multiline (`^` и `$` на каждой строке)
- `\\p{Z}` — Unicode пробелы
- `\\uFEFF` — BOM символ
- `\\A` — начало строки (абсолютное)

```lua
-- Удалить HTML теги
text = regex_replace(text, "<[^>]*>", "")

-- Найти числовые ID
local id = regex_match(url, "/novel/(\\d+)/")[1]

-- Удалить повторяющиеся пробелы
text = regex_replace(text, "\\s+", " ")
```

---

## Работа с JSON API

```lua
function getCatalogList(index)
    local r = http_get(apiBase .. "novels?page=" .. (index + 1))
    if not r.success then return { items = {}, hasNext = false } end

    -- Парсинг JSON
    local data = json_parse(r.body)
    if not data then
        log_error("json_parse failed for getCatalogList")
        return { items = {}, hasNext = false }
    end

    local items = {}
    -- data может быть массивом или объектом с полем data/items/results
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

    -- Определение hasNext
    local hasNext = data.hasNext                       -- булевое поле
        or (data.pagination and data.pagination.hasMore)
        or (#items > 0 and data.total and data.total > (index + 1) * 40)
        or (#items >= 20)  -- эвристика: если вернулось >= 20, вероятно есть ещё

    return { items = items, hasNext = hasNext == true or hasNext ~= false and #items > 0 }
end
```

### Глубокий доступ к полям

```lua
-- Безопасный доступ к вложенным полям
local cover = (novel.poster and novel.poster.medium) or ""
local title = (novel.names and (novel.names.rus or novel.names.eng)) or novel.name or ""

-- Сериализация обратно в JSON (для передачи в POST)
local body = json_stringify({
    page = 1,
    filters = { status = "ongoing" }
})
```

---

## Каталог и пагинация

### Стандартные схемы пагинации

**Схема 1: Параметр `?page=N`**

```lua
function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/catalog?page=" .. page
    -- ...
    return { items = items, hasNext = #items > 0 }
end
```

**Схема 2: Курсор / offset**

```lua
local ITEMS_PER_PAGE = 20
function getCatalogList(index)
    local offset = index * ITEMS_PER_PAGE
    local url = apiBase .. "novels?offset=" .. offset .. "&limit=" .. ITEMS_PER_PAGE
    -- ...
end
```

**Схема 3: Одна страница (весь список сразу)**

```lua
function getCatalogList(index)
    if index > 0 then return { items = {}, hasNext = false } end
    -- загружаем всё
end
```

**Схема 4: Автоопределение через detect_pagination**

```lua
local pagination = detect_pagination(r.body)
return { items = items, hasNext = pagination.hasNext }
```

### Паттерн построения URL фильтров

```lua
local url = baseUrl .. "/search?page=" .. page

-- Простые параметры
if sort ~= "" then url = url .. "&sort=" .. url_encode(sort) end
if status ~= "all" then url = url .. "&status=" .. status end

-- Массивы (несколько одинаковых параметров)
for _, v in ipairs(genres_included) do
    url = url .. "&genre[]=" .. url_encode(v)
end

-- Массивы через запятую
if #tags_included > 0 then
    url = url .. "&tags=" .. table.concat(tags_included, ",")
end
```

---

## Список глав

### Паттерн 1: Все главы на одной странице

```lua
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

### Паттерн 2: AJAX с пагинацией (как jaomix)

```lua
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    -- Определяем количество страниц
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

### Паттерн 3: JSON API с томами

```lua
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

### Параллельная загрузка через http_get_batch

```lua
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    -- Собрать URL всех страниц
    local slug = bookUrl:match("/([^/]+)$")
    local maxPage = 1
    for _, a in ipairs(html_select(r.body, ".pagination a")) do
        local p = tonumber(a.text)
        if p and p > maxPage then maxPage = p end
    end

    -- Загрузить все страницы параллельно
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

Необязательная функция. Если возвращает строку — используется для определения, изменился ли список глав (чтобы не перезагружать весь список).

```lua
function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    -- Возвращаем что-то уникально идентифицирующее текущее состояние:
    -- URL последней главы, количество глав, дату последнего обновления
    local lastChapter = html_select_first(r.body, ".chapter-list a:last-child")
    return lastChapter and lastChapter.href or nil
end
```

---

## Текст главы

`getChapterText(html, url)` получает полный HTML страницы и URL. Движок сам загружает страницу — плагин только парсит.

### Стандартный паттерн

```lua
function getChapterText(html, url)
    -- Шаг 1: Удалить нежелательные элементы
    local cleaned = html_remove(html,
        "script", "style",              -- всегда
        ".ads", ".advertisement",       -- реклама
        ".chapter-nav", ".nav-links",   -- навигация
        "#comments", ".disqus"          -- комментарии
    )

    -- Шаг 2: Найти контейнер с текстом
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then
        -- Запасные варианты
        el = html_select_first(cleaned, "#content, .entry-content, .text-content")
    end
    if not el then return "" end

    -- Шаг 3: Извлечь текст с сохранением структуры абзацев
    local text = html_text(el.html)

    -- Шаг 4: Стандартные трансформации
    return applyStandardContentTransforms(text)
end
```

### Распространённые CSS-селекторы для текста глав

```lua
-- Общие
".chapter-content"
"#chapter-content"
".entry-content"
"#content"
".text-content"
".chapter-text"
".content-area"

-- Специфичные для сайтов
"div.ui.text.container[data-container]"  -- RanobeHub
".chapter-content"                        -- NovelFire, RoyalRoad
".entry-content"                          -- Jaomix, WordPress
```

### Когда сайт шифрует контент / использует API

```lua
function getChapterText(html, chapterUrl)
    -- Извлечь параметры из URL
    local novelId  = chapterUrl:match("/novel/(%d+)/")
    local chapterNo = tonumber(chapterUrl:match("/chapter%-(%d+)"))
    if not novelId or not chapterNo then return "" end

    -- Запросить через API
    local r = http_post(
        baseUrl .. "/api/reader/get",
        json_stringify({ novel_id = novelId, chapter = chapterNo }),
        { headers = { ["Content-Type"] = "application/json" } }
    )
    if not r.success then return "" end

    local data = json_parse(r.body)
    if not data or not data.content then return "" end

    -- Собрать абзацы
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

## Фильтры каталога

Чтобы плагин поддерживал фильтры, нужно объявить две функции: `getFilterList()` и `getCatalogFiltered(index, filters)`.

### getFilterList()

Возвращает массив описаний фильтров. Список всегда исходит из Lua — никакого хардкода в Kotlin.

```lua
function getFilterList()
    return {
        -- Выбор одного значения из списка
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

        -- Множественный выбор (включить)
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

        -- Тройное состояние (включить / исключить / игнорировать)
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

        -- Переключатель
        {
            type         = "switch",
            key          = "completed_only",
            label        = "Completed Only",
            defaultValue = false
        },

        -- Текстовый ввод
        {
            type         = "text",
            key          = "author",
            label        = "Author Name",
            defaultValue = ""
        },

        -- Сортировка с направлением
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

Как Kotlin передаёт фильтры в `filters` (LuaTable):

| Тип фильтра | Ключ в filters | Значение |
|---|---|---|
| `select` | `filters["key"]` | строка |
| `checkbox` | `filters["key_included"]` | таблица-массив строк |
| `tristate` | `filters["key_included"]` | таблица-массив строк |
| `tristate` | `filters["key_excluded"]` | таблица-массив строк |
| `switch` | `filters["key"]` | `"true"` или `"false"` |
| `text` | `filters["key"]` | строка |
| `sort` | `filters["key"]` | строка (выбранное значение) |
| `sort` | `filters["key_ascending"]` | `"true"` или `"false"` |

```lua
function getCatalogFiltered(index, filters)
    local page = index + 1

    -- Читаем значения с дефолтами
    local sort        = filters["sort"]           or "latest"
    local genres_inc  = filters["genres_included"] or {}
    local genres_exc  = filters["genres_excluded"] or {}
    local lang_inc    = filters["language_included"] or {}
    local completed   = filters["completed_only"] or "false"
    local author      = filters["author"] or ""

    -- Сортировка с направлением
    local order_val = filters["order"]           or "rating"
    local order_asc = filters["order_ascending"] or "false"

    -- Строим URL
    local url = baseUrl .. "/search?page=" .. page
        .. "&sort=" .. url_encode(sort)

    if completed == "true" then url = url .. "&status=completed" end
    if author ~= "" then url = url .. "&author=" .. url_encode(author) end

    -- Массивы
    for _, v in ipairs(genres_inc) do url = url .. "&genre[]=" .. v end
    for _, v in ipairs(genres_exc) do url = url .. "&genre_ex[]=" .. v end
    for _, v in ipairs(lang_inc)   do url = url .. "&lang[]=" .. v    end

    url = url .. "&orderBy=" .. order_val
             .. "&asc=" .. (order_asc == "true" and "1" or "0")

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    -- Парсинг аналогичен getCatalogList
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

## Настройки плагина

Для постоянных настроек, сохраняемых между сессиями.

```lua
-- Константа — ключ настройки
local PREF_LANG = "my_source_language"

local function getLang()
    local v = get_preference(PREF_LANG)
    return (v ~= "" and v) or "en"  -- дефолт "en"
end

function getSettingsSchema()
    return {
        {
            key     = PREF_LANG,
            type    = "select",
            label   = "Language",
            current = getLang(),       -- текущее значение для UI
            options = {
                { value = "en", label = "English" },
                { value = "ru", label = "Russian" },
            }
        }
    }
end

-- Использование в функциях
function getCatalogList(index)
    local lang = getLang()
    local url = baseUrl .. "/" .. lang .. "/novels?page=" .. (index + 1)
    -- ...
end
```

**Правила именования ключей:** используйте префикс с ID плагина, чтобы избежать конфликтов: `"my_source_language"`, `"my_source_mode"`.

---

## Хелперы и утилиты

### Обязательный absUrl

Всегда определяйте эту функцию — она нужна для корректной обработки относительных URL:

```lua
local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end
```

### Извлечение ID из URL

```lua
-- Простой паттерн
local novelId = bookUrl:match("/novel/(%d+)")

-- Сегмент после последнего слеша
local slug = bookUrl:match("/([^/]+)$")

-- Регулярка через regex_match
local ids = regex_match(bookUrl, "/novel/(\\d+)-(.*?)(?:/|$)")
local id   = ids[1]
local slug = ids[2]
```

### Кэш (живёт на время сессии)

```lua
-- Локальная переменная модуля — живёт пока приложение не закрыто
local _bookDataCache = {}

local function fetchBookData(bookUrl)
    if _bookDataCache[bookUrl] then return _bookDataCache[bookUrl] end
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local data = json_parse(r.body)
    if data then _bookDataCache[bookUrl] = data end
    return data
end

-- Используем в нескольких функциях — один HTTP запрос вместо трёх
function getBookTitle(bookUrl)
    local data = fetchBookData(bookUrl)
    return data and string_clean(data.title) or nil
end

function getBookCoverImageUrl(bookUrl)
    local data = fetchBookData(bookUrl)
    return data and absUrl(data.cover) or nil
end
```

**Важно:** кэш сбрасывается при закрытии/перезапуске приложения. Не используйте его для данных, которые должны быть актуальными при каждом запуске.

---

## Полный справочник API

### HTTP

| Функция | Описание |
|---|---|
| `http_get(url [, config])` | GET запрос → `{success, body, code}` |
| `http_post(url, body [, config])` | POST запрос → `{success, body, code}` |
| `http_get_batch(urls)` | Параллельный GET → массив `{success, body, code}` |
| `get_cookies(url)` | Получить cookies для домена → таблица |
| `set_cookies(url, table)` | Установить cookies |

### HTML / DOM

| Функция | Описание |
|---|---|
| `html_parse(html)` | Парсинг → `{text, html, title, body}` |
| `html_select(html, selector)` | Все совпадения → массив элементов |
| `html_select_first(html, selector)` | Первое совпадение → элемент или nil |
| `html_attr(html, selector, attr)` | Атрибут первого совпадения → строка |
| `html_text(html)` | Текст с сохранением структуры абзацев |
| `html_remove(html, sel1, sel2, ...)` | Удалить элементы → HTML строка |

### Строки

| Функция | Описание |
|---|---|
| `string_clean(s)` | normalize + collapse whitespace + trim |
| `string_trim(s)` | trim пробелов |
| `string_normalize(s)` | Unicode NFKC нормализация |
| `string_split(s, sep)` | Разбить строку → массив |
| `string_starts_with(s, prefix)` | boolean |
| `string_ends_with(s, suffix)` | boolean |
| `regex_replace(s, pattern, replacement)` | Заменить по регекспу |
| `regex_match(s, pattern)` | Найти все совпадения → массив |
| `unescape_unicode(s)` | Разэкранировать `\uXXXX` последовательности |

### URL

| Функция | Описание |
|---|---|
| `url_encode(s)` | URL-encode в UTF-8 |
| `url_encode_charset(s, charset)` | URL-encode в указанной кодировке (для GBK) |
| `url_resolve(base, href)` | Разрешить относительный URL |

### JSON

| Функция | Описание |
|---|---|
| `json_parse(s)` | Строка → Lua таблица/значение |
| `json_stringify(v)` | Lua таблица → JSON строка |

### Крипто / Кодирование

| Функция | Описание |
|---|---|
| `base64_encode(s)` | Base64 encode |
| `base64_decode(s)` | Base64 decode |
| `aes_decrypt(data, key, iv)` | AES/CBC/PKCS5 расшифровка |

### Хранилище

| Функция | Описание |
|---|---|
| `get_preference(key)` | Чтение из SharedPreferences "lua_preferences" |
| `set_preference(key, value)` | Запись в SharedPreferences "lua_preferences" |

### Утилиты

| Функция | Описание |
|---|---|
| `sleep(ms)` | Задержка в миллисекундах |
| `detect_pagination(html)` | Определить hasNext → `{hasNext, next_url}` |
| `log_info(msg)` | Лог INFO (Timber) |
| `log_error(msg)` | Лог ERROR (Timber) |
| `os_time()` | Unix timestamp в миллисекундах |

---

## Полный шаблон плагина

Минимальный рабочий шаблон с комментариями:

```lua
-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "my_source"
name     = "My Source"
version  = "1.0.0"
baseUrl  = "https://example.com"
language = "en"
icon     = "https://raw.githubusercontent.com/user/repo/main/icons/my_source.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

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

-- ── Каталог ───────────────────────────────────────────────────────────────────

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

-- ── Поиск ─────────────────────────────────────────────────────────────────────

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

-- ── Детали книги ──────────────────────────────────────────────────────────────

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

-- ── Список глав ───────────────────────────────────────────────────────────────

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
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".chapter-list a:last-child")
    return el and el.href or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
    local cleaned = html_remove(html, "script", "style", ".ads", ".chapter-nav")
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end

-- ── Фильтры (опционально) ─────────────────────────────────────────────────────

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

## Частые ошибки

### 1. Неправильная работа с nil

```lua
-- ❌ Падает если r.body пустой или html_select вернул nil
local title = html_select_first(r.body, "h1").text

-- ✅ Проверяем nil
local el = html_select_first(r.body, "h1")
local title = el and string_clean(el.text) or nil
```

### 2. Использование el.text вместо html_text для текста главы

```lua
-- ❌ Теряет переносы строк между абзацами
local text = el.text

-- ✅ Сохраняет структуру <p>, <br>
local text = html_text(el.html)
```

### 3. Игнорирование кодировки

```lua
-- ❌ Кириллица ломается на GBK/Big5 сайтах
local r = http_get(url)

-- ✅ Указываем кодировку
charset = "GBK"  -- в метаданных плагина
-- или для конкретного запроса:
local r = http_get(url, { charset = "GBK" })
-- и соответственно для поиска:
url = baseUrl .. "/search?q=" .. url_encode_charset(query, "GBK")
```

### 4. Относительные URL без absUrl

```lua
-- ❌ Может вернуть "/novel/123" вместо "https://example.com/novel/123"
url = a.href

-- ✅
url = absUrl(a.href)
```

### 5. Неправильный порядок глав

```lua
-- Большинство сайтов показывают новые главы первыми в HTML.
-- getChapterList должен возвращать в хронологическом порядке (старые → новые).
-- Если сайт отдаёт в обратном порядке:

-- Вариант 1: разворачиваем результат
local reversed = {}
for i = #chapters, 1, -1 do
    table.insert(reversed, chapters[i])
end
return reversed

-- Вариант 2: загружаем страницы с конца (как jaomix)
for page = maxPage, 1, -1 do
    -- ...
end
```

### 6. Забытая проверка r.success

```lua
-- ❌ Если запрос упал — json_parse вызовется на строке ошибки
local data = json_parse(http_get(url).body)

-- ✅
local r = http_get(url)
if not r.success then return { items = {}, hasNext = false } end
local data = json_parse(r.body)
if not data then return { items = {}, hasNext = false } end
```

### 7. Неправильный ключ фильтра в getCatalogFiltered

```lua
-- Если в getFilterList объявлен key = "genres" с типом "tristate",
-- в filters придут ключи "genres_included" и "genres_excluded" — НЕ "genres"

-- ❌
local genres = filters["genres"]

-- ✅
local genres_inc = filters["genres_included"] or {}
local genres_exc = filters["genres_excluded"] or {}
```

### 8. Отсутствие log_error при отладке

```lua
-- Добавляйте логи в критичных местах — они видны через Timber/Logcat
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
