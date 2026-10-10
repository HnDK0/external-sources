# Гайд по написанию Lua-плагинов

> Основан на анализе реального кода: `LuaSourceAdapter.kt`, `LuaSourceLoader.kt`, `LuaFilterSupport.kt`, `LuaSettingsSupport.kt` и 27 существующих плагинов.

---

## Содержание

1. [Структура плагина](#структура-плагина)
2. [Метаданные](#метаданные)
3. [Обязательные функции](#обязательные-функции)
4. [Работа с HTTP](#работа-с-http)
5. [Кэширование страниц (fetchPage)](#кэширование-страниц-fetchpage)
6. [Работа с HTML и CSS-селекторами](#работа-с-html-и-css-селекторами)
7. [Очистка текста](#очистка-текста)
8. [Работа с JSON API](#работа-с-json-api)
9. [Каталог и пагинация](#каталог-и-пагинация)
10. [Список глав](#список-глав)
11. [Пагинированный список глав (parsePage)](#пагинированный-список-глав-parsepage)
12. [Текст главы](#текст-главы)
13. [Видео-плагины (content_type = "video")](#видео-плагины-content_type--video)
14. [Ошибки плагина (show_error)](#ошибки-плагина-show_error)
15. [Фильтры каталога](#фильтры-каталога)
16. [Настройки плагина](#настройки-плагина)
17. [Хелперы и утилиты](#хелперы-и-утилиты)
18. [Общие библиотеки (require_lib)](#общие-библиотеки-require_lib)
19. [Тяжёлые операции (Kotlin API)](#тяжёлые-операции-kotlin-api)
20. [Полный справочник API](#полный-справочник-api)
21. [Полный шаблон плагина](#полный-шаблон-плагина)
22. [Частые ошибки](#частые-ошибки)

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
function getChapterList(bookUrl) ... end      -- нужен ТОЛЬКО если нет parsePage (см. ниже)
function getChapterText(html, url) ... end

-- 4. ОПЦИОНАЛЬНЫЕ ФУНКЦИИ
function getBookGenres(bookUrl) ... end
function getBookStatus(bookUrl) ... end       -- статус книги, см. секцию ниже
function getBookLastUpdate(bookUrl) ... end   -- дата обновления, см. секцию ниже
function getChapterListHash(bookUrl) ... end  -- нужен ТОЛЬКО если нет parsePage (см. ниже)
function parsePage(bookUrl, page) ... end     -- список глав с пагинацией; если есть — полностью
                                               -- заменяет getChapterList и getChapterListHash
function getFilterList() ... end
function getCatalogFiltered(index, filters) ... end
function getSettingsSchema() ... end
function getUserAgentPreset() ... end         -- имя UA-пресета, см. «Работа с HTTP»
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
content_type = "manga"        -- только для манги; для новелл не указывать (default novel)
content_type = "video"        -- видео-режим: встроенный плеер, см. «Видео-плагины»
cf_options  = {               -- настройки обхода Cloudflare/WAF (опционально)
    whitelist = false,         -- true = движок НЕ обходит CF для этого хоста
    ignore_markers = {        -- домены с этими маркерами пропускаются
        "cf-wrapper", "cf-error-details"
    },
    trigger_markers = {       -- домены с этими маркерами отправляются в обход
        "/WAF/VERIFY/CAPTCHA", "but-captcha"
    },
}
```

**Важно про `id`:** должен совпадать с именем `.lua` файла без расширения. Если `id = "royal_road"`, файл должен называться `royal_road.lua`.

**`cf_options`** управляет поведением встроенного Cloudflare-обхода движка. Если сайт возвращает CF-челлендж (коды 200/403/503/429 с `cf-challenge`, `__cf_chl_`, `cf-browser-verification` в заголовках или `Server: cloudflare`), движок автоматически решает Turnstile в скрытом WebView и выпекает `cf_clearance`. `cf_options` влияет на этот процесс:

- `whitelist = true` — движок **пропускает** обход и отдаёт ответ как есть. Используй, если сайт корректно работает без обхода (CF на CDN, но контент доступен напрямую) или если обход ломает авторизацию.
- `ignore_markers` — домены, URL которых содержит один из этих маркеров, **пропускаются** обходом (поведение аналогично `whitelist`).
- `trigger_markers` — домены, URL которых содержит один из этих маркеров, **всегда** отправляются в обход, даже если обычно обход не срабатывает.

Если `cf_options` не указан — движок обходит CF автоматически по хедерам ответа.

**`referer`** — кастомный Referer для картинок (опционально). Обложки (коверы) на CDN с hotlink-защитой требуют в Referer исходный сайт, а не хост самой картинки. Объявляется глобалом в корне скрипта — до всех функций:

```lua
referer = "https://site.com/"

baseUrl = "https://site.com"
name = "Example Source"

function getCatalogList(index) ... end
```

Как работает:

- **Приоритет:** `referer` из плагина → хост URL страницы (каталога/книги) → хост самой картинки (прежнее поведение, если ничего не задано).
- Значение уходит в заголовок как есть (только пробелы по краям обрезаются) — можно указывать даже с путём: `referer = "https://site.com/manga/"`.
- **Где применяется:** обложки в каталоге источника, на странице книги/манги, офлайн-скачивание обложек (библиотека/бэкап), картинки глав при экспорте в EPUB.
- Не влияет на HTTP-запросы самого плагина (`http_get`/`http_post`) — там по-прежнему свои `config.headers`.

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
- `items` — массив `{ title, url, cover, rating? }`, где `cover` и `rating` опциональны
- `hasNext` — `true` если есть следующая страница

`rating` — строка (например `"4.6"`), берётся из карточки списка, **без** отдельного
запроса к странице книги. Если в карточке рейтинга нет (например, в выдаче поиска) —
просто не указывай ключ. Числа тоже принимаются и конвертируются в строку.

Форматы `rating` (приложение разбирает их при отображении):

- `"4.3"` — голое число = рейтинг по шкале 0-5 (тип по умолчанию, обратная совместимость)
- `"Rating: 4.3"` — рейтинг, явно помеченный словом `Rating`
- `"Rating: 8.7/10"` — рейтинг по другой шкале: суффикс `/N` говорит приложению пересчитать к 0-5 (показывается как `4.4/5`)
- `"Rank: 3"` — ранг: слово `Rank` обязательно, показывается как есть

Тип определяется по слову: `rank` → ранг, `rating` → рейтинг, голое число → рейтинг.
Мусор не показывается: число вне 0-5 без явной шкалы, число больше заявленной шкалы, отсутствие числа.

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

### getBookRating(bookUrl) — опционально

Рейтинг книги (строка, например `"4.8"`) или `nil`, если его нет. Вызывается
при открытии книги и для бэкфилла в библиотеке, поэтому НЕ должен парсить
список глав — только рейтинг.

```lua
function getBookRating(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".rating .nub")
    return el and string_clean(el.text) or nil
end
```

Готовые шаблоны:

```lua
-- 1. Рейтинг: чистое число из атрибута карточки
rating = html_attr(card.html, ".info-rating", "data-rating")   -- "4.6"

-- 2. Рейтинг: извлечь число из грязного текста ("Рейтинг: 4.6 из 5" → "4.6")
local n = string.match(string_clean(el.text), "%d+%.?%d*")

-- 3. Рейтинг по шкале 10 — приложение само пересчитает к 0-5
rating = "Rating: " .. n .. "/10"                              -- "Rating: 8.7/10"

-- 4. Ранг (слово Rank обязательно)
rating = "Rank: " .. n                                         -- "Rank: 3"
```

Запятая как десятичный разделитель тоже понимается (`4,6` = `4.6`).

### getBookStatus(bookUrl) — опционально

Статус книги: текст как на сайте («Ongoing», «Completed», «Анонс», «Завершён» и т.п.) или `nil`, если сайт статус не показывает. Никакого маппинга на английские значения — приложение показывает текст как есть: общая иконка статуса (одинаковая для всех статусов) + подпись вида «Status: %s».

```lua
function getBookStatus(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local el = html_select_first(html, ".book-status")
    return el and string_clean(el.text) or nil
end
```

### getBookLastUpdate(bookUrl) — опционально

Дата обновления последней главы в едином виде `YYYY-MM-DD` (без времени — строка в UI не должна быть длинной) или `nil`, если распознать не удалось.

Главное правило — **реализуй только тот формат, который сайт реально отдаёт**. Сначала найди дату на странице книги (или в JSON API) по фикстуре и напиши парсер ровно под неё. Универсальный «парсер всех форматов» не нужен: он раздувает плагин и незаметно врёт (например, относительную дату в часах посчитает днями). Ниже два проверенных эталона — возьми тот, что соответствует твоему сайту.

Где искать:

- мета-тег `meta[property='article:modified_time']` — почти всегда ISO-дата со временем;
- `<time>` на странице книги или у последней главы (текст или атрибут `datetime`);
- JSON API книги: поля `updatedAt`, `lastUpdated`, `last_update`. **Сверяй поле с тем, что реально показывает страница** — оно может устаревать (у NovelArrow `updated_date_webnovel` отставало от UI на неделю, использовать его нельзя).

**Формат 1 — ISO-дата в мета-теге** (`en/novelarrow.lua`). Сайт всегда отдаёт `article:modified_time` в виде `2026-08-18T23:00:15.751Z` (это же значение показывает на странице книги) — достаточно вырезать первые 10 символов, хелпер не нужен:

```lua
function getBookLastUpdate(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local v = html_attr(html, "meta[property='article:modified_time']", "content")
    local y, m, d = string.match(v, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return y and (y .. "-" .. m .. "-" .. d) or nil
end
```

**Формат 2 — относительная дата** (`en/novelphoenix.lua`). Сайт показывает только строки вида `Updated 8 hours ago`, `Updated 3 days ago`, `Updated 2 years ago` (проверь реальные единицы: minutes/hours/days/weeks/months/years, singular и plural). Считается через `os.time()` (секунды) и `os.date()` — они доступны в песочнице движка; месяцы и годы — приблизительно (30/365 дней):

```lua
-- Приводит относительную дату сайта к YYYY-MM-DD. Не распозналось → nil.
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

На странице может быть несколько похожих элементов (у NovelPhoenix есть второй `p.update` — «Average score is 4.6» в блоке отзывов). Перебирай все и бери первый, кто прошёл формат — `normalizeUpdateDate` сам отбросит чужое:

```lua
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

Если формат не совпал — возвращай `nil`: приложение просто не покажет дату. Не выдумывай обработку форматов, которых на сайте нет.

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

### Дефолтные заголовки

Движок автоматически добавляет к **каждому** вызову `http_get`, `http_post` и `http_get_batch`:

| Заголовок | Значение |
|---|---|
| `User-Agent` | Глобальный UA приложения (настраивается пользователем в настройках) |
| `Referer` | `scheme://host/` из URL запроса |
| `Accept-Language` | Локали устройства (например `ru-RU,ru;q=0.9,en-US;q=0.8`) |

Плагин может **переопределить** любой из них через `config.headers` — значения из плагина имеют приоритет над дефолтами. Делай это только когда нужно конкретное значение, отличное от дефолтного (например, `Referer` на страницу книги вместо корня домена).

```lua
-- Переопределяем только то что нужно — остальные дефолты сохраняются
local r = http_post(ajaxUrl, body, {
    headers = {
        ["Referer"]          = bookUrl,        -- переопределяем: нужна страница книги, не корень
        ["X-Requested-With"] = "XMLHttpRequest", -- добавляем: дефолта нет
        ["Accept"]           = "text/html, */*; q=0.01",
    }
})
```

### Переопределение User-Agent (getUserAgentPreset)

Иногда сайт отдаёт разную вёрстку в зависимости от User-Agent (мобильную/десктопную), и глобального UA приложения не хватает. Для этого плагин объявляет функцию:

```lua
function getUserAgentPreset()
  return "Safari Mobile"
end
```

Механизм (`LuaSourceAdapter.registerUAPreset`):
- Вызывается **один раз** при создании адаптера, без аргументов.
- Возвращённое имя пресета регистрируется на **`id` источника** и на **хост из `baseUrl`** — пресет применяется ко всем запросам источника, включая загрузку картинок на том же домене.
- Невалидное/пустое имя → пресет игнорируется (в лог пишется предупреждение).

Допустимые имена (`UAPresets`):

| Пресет (полное имя) | Алиас |
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

Приоритет User-Agent для запроса: значение из `config.headers` плагина → пресет по id источника → пресет по хосту → глобальный UA приложения. То есть **если плагин вручную задал `User-Agent` в `headers`, пресет не применится** — используй `getUserAgentPreset`, а не хардкод UA, чтобы не перебивать глобальные настройки пользователя.

Пример из репозитория — `en/readfrom.lua` (мобильная вёрстка readfrom.net).

### http_get(url [, config])

```lua
-- Простой GET — User-Agent, Referer, Accept-Language подставятся автоматически
local r = http_get("https://example.com/page")

-- С заголовками (только специфичные для запроса — дефолты не нужно дублировать)
local r = http_get(url, {
    headers = {
        ["X-Requested-With"] = "XMLHttpRequest",
        ["Accept"]           = "application/json",
    },
    charset = "UTF-8"  -- кодировка ответа (default UTF-8)
})

-- Бинарный режим — для изображений, шрифтов и прочих бинарных данных
local r = http_get("https://example.com/image.png", { binary = true })
if r.success then
    -- r.body = {137, 80, 78, 71, ...} — таблица байтов (1-based Lua-таблица)
    local bytes = r.body
    print("Size: " .. #bytes .. " bytes")
    -- Проверяем PNG-заголовок (первые 8 байт: 0x89 0x50 0x4E 0x47)
    if bytes[1] == 0x89 and bytes[2] == 0x50 then
        print("Valid PNG")
    end
end

-- Проверка результата
if not r.success then
    log_error("Request failed: code=" .. tostring(r.code))
    return { items = {}, hasNext = false }
end
-- r.body  — строка с телом ответа (или таблица байтов при binary = true)
-- r.code  — HTTP код (200, 404, ...)
-- r.headers — таблица заголовков ответа (работает одинаково для текста и бинарного режима)
```

Параметры `config` дополнительно к `headers` / `charset` / `binary`:

- `timeout` — бюджет запроса в **миллисекундах** (целое `> 0`). Задан → весь вызов (DNS, соединение, редиректы, чтение тела) ограничен этим временем и выполняется **одной попыткой** вместо длинной серии ретраев клиента (3+3+3+3+15 с). При ответах 5xx возможны короткие повторы внутри бюджета, поэтому фактическое время может незначительно превысить указанное. Не задан или `<= 0` → прежнее поведение клиента. Есть у `http_get` и у `http_get_batch` (там — глобально в `config` и per-URL в элементе); в `http_post` нет.
- `method = "HEAD"` — вместо GET уходит HEAD (регистр не важен): те же заголовки, тело ответа пустое (`r.body == ""`), кэш `http_get` не читается и не пишется, в запрос добавляется `Cache-Control: no-cache`. Годится как дешёвая проба живости ссылки — сервер проверяется по HTTP-коду, тело не скачивается. Другое значение метода → ошибка `allowed: GET, HEAD`. Есть у `http_get` и у `http_get_batch` (там — глобально в `config` и per-URL в элементе); в `http_post` нет.
- `followRedirects = false` — не переходить по 3xx: `r.code` останется `3xx`, а `r.headers.location` покажет цель (гейты-хостеры, где редирект — и есть ответ). По умолчанию `true`.

```lua
-- Проба живости ссылки: бюджет 3 с, тело не скачивается
local r = http_get(url, { timeout = 3000, method = "HEAD" })
local alive = r.success and r.code >= 200 and r.code < 400
```

### http_post(url, body [, config])

```lua
-- Form-encoded POST — Content-Type определяется автоматически по телу
local r = http_post(
    baseUrl .. "/ajax",
    "action=loadChapters&id=" .. novelId,
    {
        headers = {
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Referer"]          = bookUrl  -- переопределяем если нужна страница книги, не корень
        }
    }
)

-- JSON POST — Content-Type = application/json определится автоматически
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

Параллельная загрузка нескольких URL одним вызовом. Возвращается массив **той же длины и в том же порядке**, каждый элемент — таблица `{ success, body, code, headers }`.

Каждый элемент `items` — **строка URL** (настройки берутся из `config`) либо **таблица** `{ url = ..., headers = {...}, charset = ..., binary = ..., timeout = ..., followRedirects = ..., method = ... }` — тогда per-URL ключи перекрывают значения из `config`. Ключ `url` в таблице обязателен.

`success` честный: в текстовом режиме — успешный HTTP-код ответа, при `binary = true` — `code` в диапазоне 200..299. Сбой одного URL (сеть, SSRF-блок) даёт `{ success = false, code = -1, body = <текст ошибки>, headers = {} }` **только для этого элемента** — соседние запросы батча остаются успешными.

Запросы выполняются параллельно; кэш страниц, `method = "HEAD"`, `timeout`, `followRedirects`, `charset` — те же правила, что у `http_get`. Ошибки валидации (элемент не строка и не таблица, в таблице нет `url`, неподдерживаемый `method`) бросают исключение **до** отправки запросов в сеть.

```lua
-- Текстовый режим (по умолчанию)
local urls = {}
for p = 2, maxPage do
    table.insert(urls, baseUrl .. "/chapters?page=" .. p)
end

local results = http_get_batch(urls)
for i, res in ipairs(results) do
    if res.success then
        -- res.body — строка
    end
end

-- Бинарный режим — для пакетной загрузки изображений и прочих бинарных данных
local cover_urls = {
    "https://example.com/cover1.jpg",
    "https://example.com/cover2.jpg",
    "https://example.com/cover3.jpg"
}

local results = http_get_batch(cover_urls, { binary = true })
for i, res in ipairs(results) do
    if res.success then
        -- res.body — таблица байтов (1-based)
        print("Cover " .. i .. ": " .. #res.body .. " bytes")
    end
end
```

> **Примечание о `binary = true`:**
> - `resp.body` возвращается как Lua-таблица `{0x89, 0x50, 0x4E, ...}` (1-based) вместо строки
> - Бинарные ответы **не кэшируются** (TTL-кэш работает только для текста)
> - `resp.code`, `resp.headers`, `resp.success` работают одинаково для обоих режимов
> - Используй `#resp.body` для определения размера в байтах

Параметры `config` (значения по умолчанию на весь батч) и ключи элементов:

- `headers` — таблица заголовков, применяемых **ко всем запросам пачки**. Дефолтные заголовки движка (`Referer` из URL, `Accept-Language`) добавляются к каждому запросу пачки автоматически, поверх них идут `config.headers`, поверх них — `headers` элемента: каждый следующий уровень переопределяет предыдущий. `headers` конкретного элемента **сливаются поверх** глобальных: перечисленные ключи заменяются, остальные глобальные остаются.
- `binary = true` — тело каждой записи как таблица байтов (см. выше).
- `charset` — кодировка текстовых ответов (default `UTF-8`).
- `timeout` — бюджет в мс на каждый запрос (см. `http_get`): одна попытка вместо серии ретраев клиента.
- `followRedirects = false` — не переходить по 3xx, как у `http_get`.
- `method = "HEAD"` — как у `http_get`: тело пустое, кэш не читается и не пишется.

Каждый из этих ключей задаётся и в `config` (для всей пачки), и в элементе (только для этого URL) — per-URL значение перекрывает глобальное.

```lua
local results = http_get_batch(urls, {
    headers = { ["Referer"] = "https://ref.example/" },
})
```

Резолв нескольких хостеров одним батчем вместо последовательных `http_get`:

```lua
function getVideoList(episodeUrl)
    local id = episodeUrl:match("([%w%-]+)$")
    local items = {
        { url = "https://hoster-one.example/e/" .. id,   headers = { Referer = episodeUrl }, timeout = 8000 },
        { url = "https://hoster-two.example/e/" .. id,   headers = { Referer = episodeUrl }, followRedirects = false },
        { url = "https://hoster-three.example/e/" .. id, timeout = 5000 },
        "https://hoster-four.example/e/" .. id,          -- строка: настройки берутся из config
    }
    local results = http_get_batch(items, { timeout = 8000, headers = { Referer = episodeUrl } })
    for _, res in ipairs(results) do
        if res.success then
            -- разобрать res.body и вытащить ссылку на поток
        end
    end
end
```

> **`timeout` обязателен для потенциально мёртвых ссылок.** Без `timeout` каждый элемент уходит в полную лестницу ретраев клиента (3+3+3+3+15 с), а батч ждёт самого медленного элемента — одна «чёрная дыра» (TCP поднимается, 0 байт ответа) тормозит весь резолв. С `timeout` каждый запрос укладывается в свой бюджет одной попыткой.

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

### Работа с localStorage

Движок автоматически сохраняет localStorage из WebView при загрузке страниц (в `onPageFinished` и каждые 3 секунды). Плагины могут читать эти данные через `get_localStorage` — например, чтобы получить Bearer-токен или другой ключ авторизации.

```lua
-- Получить значение по URL и ключу
local token = get_localStorage("https://example.com", "auth_token")
if token and token ~= "" then
    -- Используем токен в заголовках
    local r = http_get(apiUrl, {
        headers = {
            ["Authorization"] = "Bearer " .. token,
        }
    })
end
```

Данные кэшируются по хосту. Если пользователь уже залогинен на сайте — токен будет доступен сразу. Если ключ отсутствует — возвращается `nil`.

### Задержки (rate limiting)

```lua
sleep(300)                        -- 300 мс
sleep(math.random(150, 350))      -- случайная задержка 150-350 мс
```

Используйте `sleep` между запросами в `getChapterList` если сайт агрессивно блокирует парсеры (пример: jaomix).

---

## Кэширование страниц (fetchPage)

Движок вызывает `getBookTitle`, `getBookCoverImageUrl`, `getBookDescription`, `getBookGenres`, `getBookStatus`, `getBookLastUpdate`, `getChapterListHash` и `getChapterList` **параллельно** — каждая из них по умолчанию делает свой `http_get(bookUrl)`. Итого 6–8 одинаковых запросов к одной странице.

Решение — локальный кэш через `fetchPage`. Добавляй его в каждый плагин где несколько функций читают одну и ту же страницу книги.

```lua
-- Объявить в начале файла, после метаданных
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

Затем во всех функциях деталей книги заменить `http_get(bookUrl)` на `fetchPage(bookUrl)`:

```lua
-- ❌ Каждая функция делает отдельный HTTP-запрос
function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    -- ...
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl)  -- второй запрос к той же странице
    if not r.success then return nil end
    -- ...
end

-- ✅ Все функции используют один закэшированный запрос
function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- ...
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)  -- берётся из кэша, HTTP не идёт
    if not body then return nil end
    -- ...
end
```

Если `getChapterList` тоже загружает страницу книги (например, для извлечения `novelId` из `og:url`), подключай и его:

```lua
function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)  -- бесплатно если уже закэшировано
    if not body then return {} end

    local ogUrl = html_attr(body, "meta[property='og:url']", "content")
    -- ... дальше AJAX запрос за главами
end
```

**Итог:** вместо 5–6 запросов к странице книги — **1 запрос + N AJAX**.

> **Важно:** кэш живёт только в рамках одного сеанса работы плагина. Между разными вызовами движка он сбрасывается — утечек памяти нет.

> **⚠️ Важно про `getChapterListHash` и `getChapterList`:**
> - `getChapterListHash` **НЕ ДОЛЖЕН** использовать `fetchPage`. Его задача — определить, изменился ли список глав (новые главы, обновления). Если он берёт страницу из кэша, хэш всегда будет старым, и триггер обновления не сработает. Всегда используйте прямой `http_get(bookUrl)`.
> - `getChapterList` **может** использовать `fetchPage`, но только для извлечения стабильных метаданных (например, `novelId` из `og:url`), а сам список глав получать отдельным незакэшированным запросом (AJAX, JSON API). Если же `getChapterList` парсит главы прямо из HTML страницы книги — он тоже должен использовать прямой `http_get`, а не `fetchPage`.

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
    -- ВАЖНО: всегда прямой http_get, НЕ fetchPage!
    -- Кэш сделает хэш неактуальным, и обновления глав не будут обнаружены.
    local r = http_get(bookUrl)
    if not r.success then return nil end
    -- Возвращаем что-то уникально идентифицирующее текущее состояние:
    -- URL последней главы, количество глав, дату последнего обновления
    local lastChapter = html_select_first(r.body, ".chapter-list a:last-child")
    return lastChapter and lastChapter.href or nil
end
```

---

## Пагинированный список глав (parsePage)

> Используй только если у сайта список глав разбит на несколько страниц через AJAX или пагинацию.
> Большинству плагинов это не нужно — `getChapterList` достаточно.
> Если `parsePage` реализован — `getChapterList` и `getChapterListHash` для этого плагина писать не нужно, движок их не вызовет.

### Зачем

`getChapterList` при каждом обновлении библиотеки перезагружает все страницы.
Если их 10 — это 10 запросов каждый раз. `parsePage` решает это: при обновлении
движок перечитывает только последнюю страницу и догружает новые если они появились.

### Что нужно реализовать

Одну функцию `parsePage(bookUrl, page)` которая возвращает главы одной страницы:

```lua
function parsePage(bookUrl, page)
    -- page — номер страницы, движок передаёт 1, 2, 3... N
    -- возвращаем главы этой страницы + сколько страниц всего
    return {
        chapters   = { { title = "...", url = "..." }, ... },
        totalPages = 10,
    }
end
```

Правила:
- Главы внутри страницы — в хронологическом порядке (старые сверху, новые снизу)
- `totalPages` — одинаковое число при каждом вызове, независимо от `page`
- Движок запрашивает страницы 1, 2, 3... где **1 = самые старые главы**, N = самые новые

### Что делает движок

**Первый раз (первое обновление библиотеки после добавления книги):**
1. Вызывает `parsePage(url, 1)` → получает главы + `totalPages = 10`
2. Вызывает `parsePage(url, 2)`, ..., `parsePage(url, 10)`
3. Сохраняет все главы и запоминает что последняя страница = 10

**При обновлении:**
1. Перечитывает только страницу 10 (последнюю)
2. Если `totalPages` вырос до 11 — догружает только страницу 11
3. Добавляет только новые главы — вместо 10 запросов делает 1–2

### Про порядок страниц на сайте

На разных сайтах порядок разный:

**Сайт отдаёт старые главы на странице 1** (прямой порядок, как ожидает движок):
```lua
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

Реальный пример — `syosetu.lua` внутри `getChapterList` использует ту же логику:
загружает страницу 1 сначала, определяет `totalPages` через `.c-pager__item--last`,
потом страницы 2..N.

---

**Сайт отдаёт новые главы на странице 1** (обратный порядок, как у jaomix):

Нужно инвертировать: движок просит страницу 1 (старые) → берём с сайта последнюю.

```lua
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

    -- Инвертируем: движок page=1 → сайт последняя страница (старые главы)
    --              движок page=N → сайт страница 1 (новые главы)
    local sitePage = totalPages - page + 1

    local raw = fetchAjaxPage(bookUrl, sitePage)

    -- Сайт внутри страницы тоже отдаёт новые сверху — разворачиваем
    local chapters = {}
    for i = #raw, 1, -1 do
        table.insert(chapters, raw[i])
    end

    sleep(math.random(150, 300))
    return { chapters = chapters, totalPages = totalPages }
end
```

### getChapterList — не нужен, если есть parsePage

Движок сам определяет, что использовать: если плагин объявляет `parsePage`,
движок **всегда** вызывает его (и для первой загрузки, и для обновлений),
`getChapterList` при этом не вызывается вообще. Объявлять `getChapterList`
"на всякий случай" не нужно — это мёртвый код, который никогда не выполнится,
пока в файле есть `parsePage`.

`getChapterList` нужен только плагинам **без** `parsePage` — то есть тем,
у кого список глав отдаётся одним запросом или сайт не поддерживает
постраничную подгрузку.

### getChapterListHash — тоже не нужен при parsePage

`getChapterListHash` — это механизм обнаружения обновлений для плагинов
**без** `parsePage`. Если `parsePage` реализован, движок сам следит
за обновлениями через него: перечитывает последнюю известную страницу
и сравнивает `totalPages`/главы напрямую — отдельный хэш ему не требуется,
и `getChapterListHash` для такого плагина писать не нужно.

Пример ниже актуален только для плагинов без `parsePage`:

```lua
-- Вариант 1: URL последней главы через быстрый запрос (jaomix)
function getChapterListHash(bookUrl)
    local pr = http_post(
        baseUrl .. "wp-admin/admin-ajax.php",
        "action=loadpagenavchapstt&page=1",   -- страница 1 сайта = самые новые
        { headers = { ["X-Requested-With"] = "XMLHttpRequest", ["Referer"] = bookUrl } }
    )
    if not pr.success then return nil end
    local el = html_select_first(pr.body, "div.title a[href]")
    return el and el.href or nil
end

-- Вариант 2: счётчик глав из API (novelbuddy, ranobehub)
function getChapterListHash(bookUrl)
    local manga = fetchMangaNextData(bookUrl)
    if not manga then return nil end
    local count = manga.stats and manga.stats.chapters_count
    return count and tostring(count) or manga.updated_at
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

## Видео-плагины (content_type = "video")

С `content_type = "video"` плагин открывает встроенный плеер (media3) вместо текстового читалера. Маппинг: сериал — обычный `Book` из каталога, эпизоды — обычные главы из `getChapterList`, сезон — поле `volume`.

Единственное отличие от обычного плагина: вместо `getChapterText` реализуй `getVideoList(episodeUrl)` — оно возвращает варианты потоков эпизода. `episodeUrl` приходит из `getChapterList`; страницу плагин сам запрашивает через `http_get`.

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

Правила:

- `getChapterText` видео-плагину не нужен: валидатор по `content_type` требует `getVideoList` (отсутствие — предупреждение в лог).
- `return nil` или `return {}` → в приложении «Источники не найдены» (не ошибка). `error("текст")` → текст ошибки на экране.
- `headers` применяются **ко всем запросам потока одинаково**: плейлист, сегменты HLS, субтитры, офлайн-загрузка. Обычный набор — `Referer` (страница эпизода) и `User-Agent`; куки источника берутся из общего jar приложения. Отдельных заголовков «только для плейлиста» контракт не предусматривает. Набор задаётся на каждый вариант потока — варианты качества могут нести свои заголовки.
- `subtitles`: поля `url` (HTTP), `label` — подпись дорожки в плеере, `lang` — код языка; mime определяется по расширению URL (`.srt`, `.vtt`).
- `quality`, `headers`, `subtitles`, `mime` опциональны; элементы без `url` пропускаются — это не ошибка.
- `mime` — подсказка типа потока для плеера: `hls`/`m3u8` (→ HLS), `mp4`, `mpd` (→ DASH); регистр не важен. Готовые значения: каноничные HLS/DASH (`application/x-mpegURL`, `application/vnd.apple.mpegurl`, `application/dash+xml`) и `video/…` (например `video/webm`) — проходят как есть. Нужен **только** для адресов **без медиа-расширения** (например `https://cdn…/?token=…`): без него меди3 смотрит последний сегмент пути, видит «/» и открывает поток прогрессивным источником → `UnrecognizedInputFormatException` на HLS. Расширение `.m3u8`/`.mp4` в URL определяет тип само — тогда поле не требуется. Неизвестное значение (например `application/octet-stream`) или его отсутствие игнорируются — плеер определяет тип по URL, как раньше (непустой, но нераспознанный mime сломал бы эту фоллбэк-логику, поэтому он отбрасывается). `mime` уезжает и в офлайн-загрузку (по нему media3 выбирает `HlsDownloader`).

### Стандарт getVideoList: скорость и отсев мёртвых хостов

Паттерн для всех видео-плагинов (задокументированное решение пользователя): серия из десятков embed-хостов не должна зависать на мёртвых ссылках.

1. **SKIP_HOSTS — до сетевого запроса.** Проверка хостов по списку/regex **до** любого HTTP. Даже с `timeout` в `http_get` единственный самый дешёвый «жёсткий таймаут» — не ходить на заведомо мёртвые/JS-only хосты вовсе: SKIP_HOSTS экономит и время, и сеть. Список обязан содержать причину (комментарий/поле `reason`) — почему хост в skip: замерено «0 байт ответа», редирект-цикл, «нет прямой ссылки» и т.п. Без причины список невозможно пересматривать.

2. **Один `http_get_batch` вместо последовательных `http_get` по каждому embed.** Собрать все кандидаты-ссылки → один батч (движок выполняет параллельно через `async(Dispatchers.IO)` в приложении) → разобрать ответы → дедупликация по URL → выдача.

3. **Почему это критично (замеры, из которых вырос стандарт).** Последовательный обход с «чёрными дырами» (TCP поднимается, 0 байт → уходит весь таймаут; без `timeout` NetworkClient повторяет 3+3+3+3+15 с) давал **17.9–19.9 с** на серию; после фикса — **1.2–2.7 с** без потери источников. Проба «проверки живости» каждой ссылки старым API (без `timeout`/`HEAD`) обошлась в **26–30 с** на серию; в нынешнем API она закрывается одной строкой — см. п. 4.

4. **Что есть в API сейчас.** `http_get` умеет `timeout` (бюджет в мс, одна попытка) и `method = "HEAD"` (пустое тело, кэш не трогается) — вместе это дешёвая проба живости: `http_get(url, { timeout = 3000, method = "HEAD" })`, смотрим HTTP-код (см. «Работа с HTTP» → `http_get`). `http_get_batch` принимает те же ключи — `headers`, `charset`, `binary`, `timeout`, `followRedirects`, `method` — глобально в `config` на всю пачку и per-URL в таблице-элементе (плюс сам элемент может быть строкой URL). Per-URL `headers` сливаются поверх глобальных, Range в батче не поддерживается; в запрос уходят и дефолтные движка `Accept-Language` и `Referer`, вычисленный из самого URL (`HttpGetBatchFunction` в `LuaSourceLoader.kt`). Подробности — «Работа с HTTP» → `http_get_batch`.

5. **Чек-лист нового видео-плагина:** skip-лист с причинами → один батч на все embed → дедуп → `Referer` из ссылки-источника в `headers` каждого варианта (обязателен для mp4upload и подобных) → выдача.

---

## Ошибки плагина (show_error)

### show_error(title, message)

Плагин может показать пользователю диалог с ошибкой, вызвав `show_error(title, message)`.

| Параметр | Тип     | Описание                     |
|----------|---------|------------------------------|
| `title`  | string  | Заголовок диалога            |
| `message`| string  | Текст ошибки (тело диалога)  |

### Когда использовать

- Платный контент / подписка
- Требуется авторизация на сайте
- Страница не найдена / глава удалена
- Источник временно недоступен

### Примеры

#### Платная глава

```lua
function getChapterText(doc)
    if doc:selectFirst(".paid-chapter") then
        show_error("Платный контент", "Эта глава доступна только по подписке.")
        return nil
    end
    -- ...парсинг текста...
end
```

#### Требуется логин

```lua
function getChapterPages(doc)
    if doc:selectFirst(".login-required") then
        show_error("Требуется авторизация", "Войдите на сайт, чтобы прочитать эту главу.")
        return nil
    end
    -- ...получение страниц...
end
```

#### Комбинирование с другими проверками

```lua
function getChapterText(doc)
    local errorDiv = doc:selectFirst(".error-message")
    if errorDiv then
        show_error("Ошибка источника", errorDiv:text())
        return nil
    end

    local content = doc:selectFirst(".chapter-content")
    if not content then
        show_error("Глава не найдена", "Не удалось извлечь текст главы.")
        return nil
    end

    return content:text()
end
```

### Поведение

- `show_error()` **останавливает загрузку** главы — после вызова функция должна вернуть `nil`
- Пользователь видит диалог с указанным заголовком и текстом
- При закрытии диалога читатель закрывается (возврат к списку глав)
- **Ретраи не выполняются** — ошибка плагина не является сетевой проблемой
- Существующие плагины без `show_error()` работают без изменений

### Важно

- `show_error()` вызывается **внутри** `getChapterText()` или `getChapterPages()`
- После вызова верните `nil` — иначе поведение не определено
- Не используйте `show_error()` для штатных ситуаций (глава просто отсутствует) — только для настоящих ошибок, требующих внимания пользователя

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

        -- Теги с автодополнением (текстовое поле + чипы)
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
| `tag_input` | `filters["key_included"]` | таблица-массив строк |

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

    -- Теги из tag_input
    local tags_inc = filters["tags_included"] or {}
    for _, v in ipairs(tags_inc) do url = url .. "&tag[]=" .. v end

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

### pow_solve(challenge, difficulty)

Kotlin-солвер Proof-of-Work (глобал только в новых версиях NoveLA): поиск nonce для byse/filemoon PoW (memory-hard функция gr), батчи 1024, бюджет 15 секунд. Возвращает nonce строкой или `nil` при таймауте/ошибке.

```lua
local nonce = pow_solve(challenge, 12)
if not nonce then
    log_error("my_source: pow_solve timeout")
    return nil
end
```

---

## Общие библиотеки (require_lib)

`require_lib(id)` — Lua-глобал (только в новых версиях NoveLA): читает общую библиотеку и возвращает её таблицу.

```lua
local urls = require_lib("urls")
local host = urls.hostOf(pageUrl)
```

Пути поиска `<id>.lua`:

| Окружение | Пути поиска |
|---|---|
| На устройстве | `lua_extensions/lib/<id>.lua` |
| Репо-тестер | `<scriptDir>/lib/<id>.lua`, затем `<scriptDir>/../libs/<id>.lua` и `<scriptDir>/../libs/*/<id>.lua` |

**Ошибки** — LuaError (не `nil`): невалидный id (не `[a-z0-9_]+`), файл отсутствует, либа не вернула таблицу.

Внутри либы `require_lib` доступен (метатаблица `__index` → глобалы) — можно ссылаться на другие либы; циклы между либами запрещены. Уже загруженные либы кэшируются (инвалидация по mtime/размеру файла).

### Структура libs/

`libs/` — в корне репозитория, общий для всех языков: один файл на экстрактор/декодер. Подпапки — чистая раскладка репо: **id либы = basename файла и не зависит от подпапки**, `require_lib` принимает только id.

| Файл | Содержимое |
|---|---|
| `libs/helpers/urls.lua` | `origin`, `hostOf`, `unescapeSlashes`, `resolve`, `driveDirectUrl` |
| `libs/helpers/hls.lua` | `pickStream`, `hasMediaExt` |
| `libs/helpers/text.lua` | `rot13`, `rot18` |
| `libs/hosters/aksor.lua` | `apiUrl`, `resolve` — JSON API Aksor по iframe |
| `libs/hosters/alloha.lua` | `resolve` — borth-пермутации, POST /bnsi → HLS |
| `libs/hosters/cvh.lua` | `videoUrl`, `sourceFrom` — player API CDN VideoHub |
| `libs/hosters/dailymotion.lua` | `parseMetadata`, `resolveDailymotion` — метаданные → HLS master |
| `libs/hosters/dood.lua` | `resolveDood` — экстрактор DOOD/dsvplay |
| `libs/hosters/dotplay.lua` | `resolve` — embed → api.php → base64 video_url |
| `libs/hosters/dropbox.lua` | `resolve` — shared link → прямой CDN URL |
| `libs/hosters/dtube.lua` | `resolve` — JSON api.d.tube → master.m3u8 |
| `libs/hosters/embeds.lua` | диспетчер `extractFromEmbed` (роутит по хостерам) |
| `libs/hosters/gdriveplayer.lua` | `decode` — atob+XOR скрипта → HLS playlist |
| `libs/hosters/hgcloud.lua` | `mirrors`, `mediaUrls`, `resolve` — packed-конфиг с зеркала |
| `libs/hosters/kodik.lua` | `resolve` — urlParams/d_sign → POST /ftor |
| `libs/hosters/mailru.lua` | `parseMeta`, `resolve` — metadataUrl → mp4 |
| `libs/hosters/mirrors.lua` | `mirrorOptions` — список mirror-опций эмбедов |
| `libs/hosters/mixdrop.lua` | `extractMixdrop` — MDCore.wurl → mp4 |
| `libs/hosters/mp4upload.lua` | `extractMp4upload` — player.src → mp4 |
| `libs/hosters/okru.lua` | `resolveOkRu` — data-options → flashvars.metadata |
| `libs/hosters/otaku.lua` | `resolve` — window.__P (base64∘xor) → m3u8 + субтитры |
| `libs/hosters/pixeldrain.lua` | `resolve` — embed /u/ → /api/file/ mp4 |
| `libs/hosters/rumble.lua` | `resolve` — jwplayer-конфиг → mp4/HLS |
| `libs/hosters/seekplayer.lua` | `decode` — hex blob API → AES-128-CBC JSON |
| `libs/hosters/share4max.lua` | `version`, `resolve` — Inertia XHR → props.streams |
| `libs/hosters/shared.lua` | `extract` — 4shared embed → первый `<source>` |
| `libs/hosters/sibnet.lua` | `resolve` — shell.php → единственный mp4 |
| `libs/hosters/soraplay.lua` | `parsePlayers`, `parseSources` — sources и список плееров |
| `libs/hosters/uqload.lua` | `packedMediaUrls`, `resolve` — packed-JS → jwplayer sources |
| `libs/hosters/vidbom.lua` | `isLink`, `parseSources` — семейство vidbom/vadbom/… → sources |
| `libs/hosters/videa.lua` | `request`, `parse` — токен _xt → XML (RC4 + base64) |
| `libs/hosters/videas.lua` | `parse` — embed videas.fr → прямой HLS/MP4 |
| `libs/hosters/vidmoly.lua` | `resolve` — redirect → player → packed media URLs |
| `libs/hosters/vidyard.lua` | `origin`, `resolve` — player/<id>.json → профили hls[] |
| `libs/hosters/vk.lua` | `videoExtUrl`, `resolve` — video_ext.php → mp4_144…1080 |
| `libs/hosters/voe.lua` | `extractVoe`, `extractSources` — обфусцированный JSON (1.3.0) |

**Критерий выноса в `libs/hosters/`**: generic-хостер-резолверы, которые может встроить любой сайт. Site-специфичный диспетчер/gate (kind-ID бэкенда, Livewire-гейты, собственный CDN сайта) остаётся в плагине — примеры: `record`/yummyanime, `yonaplay`/witanime, `gateUrl`/witanime.

Исторические `libs/common.lua` и `libs/decode.lua` **удалены**: URL-хелперы переехали в `urls`, `pickStream` — в `hls`, а `base64Decode`/`unpackAll` заменены на engine API `base64_decode_bytes`/`unpack_packed` (см. «Тяжёлые операции (Kotlin API)»). Отдельных Lua-декрипторов в `libs/` нет — весь крипто (AES-GCM/RC4/base64/hash) живёт в engine API Kotlin. Не используйте старые имена — `require_lib("common")` на новом репо бросит LuaError.

Формат файла: шапка-комментарий, локальные helpers, `return M`. Поля `version` в либах НЕТ.

### Синк либ (по sha256)

Каталог либ — секция `libraries` в корневом `index.yaml` (не в языковых):

```yaml
libraries:
  - id: "urls"
    url: "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/libs/helpers/urls.lua"
    sha256: "<hex>"
```

`sha256` считает `scripts/sync_index.py` автоматически из содержимого `libs/**/*.lua` (обход рекурсивный, URL содержит подпапку) — регенерация сама обновляет хеши. Приложение качает либу в flat `lua_extensions/lib/<id>.lua`, если sha256 локального файла отличается от каталожного — подпапка в URL на это не влияет. Версии в этом не участвуют. `libs/` входит в SKIP_DIRS синка (вместе с подпапками) — это не языковая папка.

После любой правки `libs/**/*.lua` обязательно прогони `GITHUB_REF_NAME=main python3 scripts/sync_index.py` — иначе каталожный sha256 устареет и приложение будет перекачивать либу при каждом pull. **`GITHUB_REF_NAME=main` обязателен**: без него синк на feature-ветке перепишет все URL в index.yaml на эту ветку и сломает релиз.

### Фоллбэк старых билдов

`require_lib` есть только в новых версиях приложения. **Не бросайте `error` в top-level** — плагин молча исчезнет из списка источников. Паттерн: проверка в начале каждой публичной функции, канон — `show_error(...)` + `error(..., 0)` (в проде `show_error` асинхронен и возвращает `nil`, поэтому без `error` функция продолжит работу без либ):

```lua
function getChapterText(html, url)
    if type(require_lib) ~= "function" then
        show_error("Требуется обновление NoveLA", "Плагину нужны общие библиотеки")
        error("Требуется обновление NoveLA (require_lib)", 0)
    end
    local embeds = require_lib("embeds")
    -- ...
end
```

---

## Тяжёлые операции (Kotlin API)

Хеши, шифры, байтовый base64 и распаковка P.A.C.K.E.R выполняются на стороне движка (Kotlin) — Lua только вызывает. Эти глобалы есть **только в новых версиях NoveLA** (см. «Паттерн guard» ниже).

| API | Сигнатура | Возврат / контракт |
|---|---|---|
| `sha256(data)` | `(data: str) -> str` | **Сырые байты** (binary-str, 32 шт.), НЕ hex; hex делает вызывающий. Неверный тип → LuaError |
| `md5(data)` | `(data: str) -> str` | **Сырые байты** (16 шт.), НЕ hex. Неверный тип → LuaError |
| `sha1(data [, "hex"\|"raw"])` | `(data: str, mode?: "hex"\|"raw") -> str` | **Сырые байты** (20 шт.) без режима и со `"raw"` (зеркало `sha256`); `"hex"` → 40-символьный hex. Неизвестный режим/неверный тип → LuaError |
| `crc32(data)` | `(data: str) -> number` | CRC-32 → **Lua-число** беззнакового значения `0..2^32-1` (в double лежит точно). `crc32("123456789")` = 3421780262 (0xCBF43926), `crc32("")` = 0. Неверный тип → LuaError |
| `hmac_sha256(key, data)` | `(key: str, data: str) -> str` | **Сырые байты** (32 шт.), НЕ hex; если нужен hex — `hexEncode(...)` на стороне вызывающего. Неверный тип → LuaError |
| `pbkdf2(password, salt, iterations, dkLen [, hash])` | `(str, str, int, int, "sha1"\|"sha256"\|"sha512"?) -> str` | PBKDF2-HMAC → **сырые байты** длины `dkLen`; `hash` по умолчанию `sha256`. Пароль читается как UTF-8-текст, соль — сырые байты. Неверный `hash`/тип, `iterations < 1`, `dkLen < 1` → LuaError |
| `aes_gcm_decrypt(key, iv, ct, tag)` | 4 аргумента, все **сырые байты** (binary-str) | Расшифровка AES-GCM; тег передаётся отдельным аргументом. **`nil` при любой ошибке** (битый тег, неверный ключ) — Lua делает nil-fallback. Разбор упакованных форм (`iv‖tag‖ct`, `arr:<b64 iv>:<b64 tag>:<b64 ct>`) — на стороне вызывающего. Неверный тип → LuaError |
| `rc4(key, data)` | `(key: str, data: str) -> str` | RC4, **сырые байты** на входе и выходе; пустой ключ → LuaError |
| `aes_ctr(data, key, iv)` | `(data, key, iv: str) -> str` | AES/CTR/NoPadding → **сырые байты**; режим симметричен (один вызов и шифрует, и дешифрует). key 16/24/32, iv строго 16 байт (контракт = блок AES; 8-байтовый nonce не принимается). Неверная длина key/iv → LuaError. Только в новых версиях |
| `rsa_decrypt(data, privateKey)` | `(data, privateKey: str) -> str` | RSA/ECB/PKCS1Padding → **сырые байты**; `privateKey` — standard base64 DER PKCS#8 (как принимает `base64_decode`). Битый base64/ключ/padding → LuaError (английское сообщение). Только в новых версиях |
| `aes_decrypt(data, key, iv)` | `(data, key, iv: str) -> str \| nil` | AES/CBC/PKCS5; key/iv — сырые байты. **`nil` при ошибке** |
| `base64_encode(s)` | `(s: str) -> str` | Base64 (Java String — для бинарных данных не годится) |
| `base64_decode(s)` | `(s: str) -> str \| nil` | Base64 → строка (UTF-8); `nil` при невалидном base64 |
| `base64_decode_bytes(s)` | `(s: str) -> str \| nil` | Base64 → **сырые байты** (binary-str с `\0` и т.п.); lenient: пробелы, url-safe `-_/`, автодопadding. `nil` при невалидном base64, неверный тип → LuaError |
| `unpack_packed(script)` | `(script: str) -> str` | Распаковка `eval(function(p,a,c,k,e,d)...)` → исходный src; **первый матч** в тексте; **`""` если упаковщика нет** (не `nil` — вызовы проверяют `un ~= ""`). Неверный тип → LuaError |
| `json_encode(value)` | `(value: bool\|num\|str\|table) -> str` | Компактный JSON (без пробелов), объектные ключи сортируются → детерминированный вывод. Таблица → **массив** при непрерывных целых ключах `1..n`, иначе **объект** (пустая таблица → `[]`, дырки → `{"1":..,"3":..}`). `nil` сверху, смешанные/неподдерживаемые ключи, циклы, функции, нефинитные числа → LuaError. **Каноничный encoder**; `json_stringify` — legacy (см. «JSON») |
| `inflate(data [, mode])` | `(data: str, mode?: "zlib"\|"gzip") -> str \| nil` | Декомпрессия → **сырые байты**; `mode` по умолчанию `"zlib"`. Битые/усечённые данные и неизвестный `mode` → `nil` (обработка данных, не ошибка вызова); неверный тип → LuaError. HTTP Content-Encoding (gzip/deflate/br) движок снимает сам — `inflate` нужен только для сжатых блобов **внутри** данных |
| `pow_solve(challenge, difficulty)` | `(str, int) -> str \| nil` | Nonce для byse/filemoon PoW; `nil` при таймауте/ошибке |
| `require_lib(id)` | `(id: str) -> table` | Общая библиотека из `libs/`; ошибки — LuaError (подробнее — «Общие библиотеки (require_lib)») |

Контракт **сырых байт** важен: ключи, IV, шифротекст и хеши — бинарь, `checkjstring()`/`tojstring()` (UTF-8 round-trip) их портит. Поэтому `sha256(...)` возвращает binary-str: `string.byte(sha256(x))` даёт байты, а `hexEncode` делает вызывающий, если нужен hex.

### Когда выносить в Kotlin

**Маркер:** цикл по байтам, битовые операции, крипто и декодеры, написанные в чистом Lua, — кандидат в engine API: посимвольный перебор бинарного блоба в Lua слишком медлен, а своих библиотек в песочнице нет. Остаётся в Lua: `fetch`/HTTP, JSON-выборка полей и сборка URL — это таблицы и строки, их Lua делает нормально.

Новые API появляются через TDD: golden-снапшоты → юнит-тесты (`HeavyOpsTest`) → паритет с тестером (`plugin-tester-jvm`), и только после этого строка в этот гайд.

Дорожная карта: `json_encode` / `inflate` / `pbkdf2` / `sha1` / `crc32` / `aes_ctr` / `rsa_decrypt` — добавлены (все — в таблицах выше). Новые кандидаты при появлении 2+ потребителей — по мере появления callsites.

### Паттерн guard

Глобалы выше появляются только в новых сборках. Плагин, который их использует, обязан проверять их **внутри первой публичной функции** и вызывать проверку **во всех публичных функциях** (канон `ensureEngine`; в `es/latanime.lua` одна объединённая `ensureLibs` — она же проверяет `require_lib` и engine API). Проверять нужно **только реально используемые API**:

```lua
local function ensureEngine()
    local missing = {}
    if rawget(_G, "sha256") == nil then missing[#missing + 1] = "sha256" end
    if rawget(_G, "unpack_packed") == nil then missing[#missing + 1] = "unpack_packed" end
    if #missing > 0 then
        show_error("Se requiere actualizar NoveLA",
            "Este complemento necesita funciones nuevas (" .. table.concat(missing, ", ") ..
            "). Actualice la aplicación a la última versión.")
        error("Se requiere una versión más reciente de la aplicación: " .. table.concat(missing, ","), 0)
    end
end
```

`rawget(_G, "<api>")` вместо прямого обращения — на старых билдах глобала нет, прямое чтение дало бы `nil` без ошибки, а сравнение с `nil` ловит именно отсутствие.

Для `require_lib` — отдельный слой на **top-level** (иначе на старых билдах top-level `require_lib(...)` — nil-call и плагин молча исчезнет из списка источников): поимённая загрузка через `pcall` с сохранением ошибки в `libErr` + `ensureLibs()` в публичных функциях (канон latanime:40-65). Текст сообщения — на языке плагина (es → испанский, остальные — английский).

---

## Полный справочник API

### Функции плагина (вызываются движком)

| Функция | Описание |
|---|---|
| `getUserAgentPreset()` | Имя UA-пресета (например `"Safari Mobile"`) — применяется ко всем запросам источника и его домена. Подробнее в «Работа с HTTP» |
| `getBookStatus(bookUrl)` | Статус книги — текст как на сайте или `nil`. См. «getBookStatus» |
| `getBookLastUpdate(bookUrl)` | Дата обновления последней главы `YYYY-MM-DD` или `nil`. См. «getBookLastUpdate» |

### HTTP

| Функция | Описание |
|---|---|
| `http_get(url [, config])` | GET/HEAD запрос → `{success, body, code}` (body — строка или таблица байтов при `binary = true`). config: `headers`, `charset`, `binary`, `followRedirects`, `timeout` (мс), `method` (`"GET"`/`"HEAD"`) |
| `http_post(url, body [, config])` | POST запрос → `{success, body, code}`; config: `headers`, `charset` |
| `http_get_batch(items [, config])` | Параллельный GET → массив той же длины, элемент `{success, body, code, headers}`; элемент — строка URL или таблица `{url, headers, charset, binary, timeout, followRedirects, method}`; config: `headers`, `charset`, `binary`, `followRedirects`, `timeout`, `method` (дефолт, per-URL перекрывает). Сбой одного URL → `{success=false, code=-1}` только у него |
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
| `json_stringify(v)` | Lua таблица → JSON строка. **Legacy**: `nil` при ошибке, порядок ключей не гарантирован. Канонично — `json_encode` (см. «Крипто / Кодирование») |

### Крипто / Кодирование

| Функция | Описание |
|---|---|
| `base64_encode(s)` | Base64 encode |
| `base64_decode(s)` | Base64 decode → строка; `nil` при невалидном base64 |
| `base64_decode_bytes(s)` | Base64 decode → **сырые байты** (lenient: пробелы, url-safe, автодопadding); `nil` при невалидном base64. Только в новых версиях |
| `aes_decrypt(data, key, iv)` | AES/CBC/PKCS5 расшифровка → строка или `nil` при ошибке |
| `aes_gcm_decrypt(key, iv, ct, tag)` | AES-GCM расшифровка, аргументы — сырые байты → строка или `nil` при ошибке. Только в новых версиях |
| `rc4(key, data)` | RC4 → сырые байты. Только в новых версиях |
| `aes_ctr(data, key, iv)` | AES/CTR → сырые байты, симметричен; key 16/24/32, iv строго 16; неверная длина → LuaError. Только в новых версиях |
| `rsa_decrypt(data, privateKey)` | RSA/ECB/PKCS1Padding → сырые байты; `privateKey` — standard base64 DER PKCS#8; ошибка → LuaError. Только в новых версиях |
| `sha256(data)` | SHA-256 → **сырые байты** (не hex). Только в новых версиях |
| `md5(data)` | MD5 → **сырые байты** (не hex). Только в новых версиях |
| `sha1(data [, "hex"\|"raw"])` | SHA-1 → **сырые байты** (20 шт.), `"hex"` → hex. Только в новых версиях |
| `crc32(data)` | CRC-32 → Lua-число `0..2^32-1`. Только в новых версиях |
| `hmac_sha256(key, data)` | HMAC-SHA256 → **сырые байты** (не hex). Только в новых версиях |
| `pbkdf2(password, salt, iterations, dkLen [, hash])` | PBKDF2-HMAC → **сырые байты** длины `dkLen`; `hash` = `sha1`/`sha256`/`sha512`, по умолчанию `sha256`; пароль — UTF-8-текст, соль — сырые байты; неверный `hash`, `iterations < 1`, `dkLen < 1` → LuaError. Только в новых версиях |
| `unpack_packed(script)` | Распаковка P.A.C.K.E.R → src; `""` если упаковщика нет. Только в новых версиях |
| `json_encode(v)` | Компактный JSON → строка; массив при непрерывных ключах `1..n`, иначе объект (ключи сортируются), пустая таблица → `[]`; `nil`/смешанные ключи/циклы/функции → LuaError. **Каноничный** encoder (см. `json_stringify` в «JSON»). Только в новых версиях |
| `inflate(data [, mode])` | Декомпрессия zlib (по умолчанию) или gzip → **сырые байты**; битые данные/неизвестный `mode` → `nil`. HTTP Content-Encoding движок декомпрессит сам — только для сжатых блобов внутри данных. Только в новых версиях |
| `pow_solve(challenge, difficulty)` | Поиск nonce для byse/filemoon PoW (memory-hard функция gr), батчи 1024, бюджет 15 с → nonce строкой или `nil` при таймауте/ошибке. Только в новых версиях |

### Хранилище

| Функция | Описание |
|---|---|
| `get_preference(key)` | Чтение из SharedPreferences "lua_preferences" |
| `set_preference(key, value)` | Запись в SharedPreferences "lua_preferences" |
| `get_localStorage(url, key)` | Чтение значения из localStorage WebView по URL и ключу (returns `nil` если ключ не найден) |

### Утилиты

| Функция | Описание |
|---|---|
| `sleep(ms)` | Задержка в миллисекундах |
| `detect_pagination(html)` | Определить hasNext → `{hasNext, next_url}` |
| `log_info(msg)` | Лог INFO (Timber) |
| `log_error(msg)` | Лог ERROR (Timber) |
| `show_error(title, message)` | Показать диалог ошибки пользователю. Останавливает загрузку главы, после вызова верните `nil` |
| `os_time()` | Unix timestamp в миллисекундах |
| `require_lib(id)` | Общая библиотека из `libs/` → таблица; ошибки — LuaError (невалидный id `[a-z0-9_]+`, файла нет, либа не вернула таблицу). Пути: `lua_extensions/lib/<id>.lua` на устройстве, `<scriptDir>/lib/` → `<scriptDir>/../libs/` → `<scriptDir>/../libs/*/` в тестере. Кэш по mtime/размеру. Только в новых версиях |

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

-- Статус и дата обновления (опционально): контракт — секции «getBookStatus»
-- и «getBookLastUpdate» в гайде. Движок показывает их в библиотеке.
function getBookStatus(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".book-status")
    return el and string_clean(el.text) or nil
end

-- Сайт отдаёт ISO-дату со временем в meta article:modified_time — оставляем
-- только YYYY-MM-DD (для относительных дат вида «Updated 3 days ago» см.
-- формат 2 в секции «getBookLastUpdate»).
function getBookLastUpdate(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local v = html_attr(r.body, "meta[property='article:modified_time']", "content")
    local y, m, d = string.match(v, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return y and (y .. "-" .. m .. "-" .. d) or nil
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
    -- ВАЖНО: прямой http_get, не fetchPage — нужен актуальный ответ
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

### 9. Повторные http_get к одной и той же странице

```lua
-- ❌ Движок вызывает функции параллельно — каждая делает свой запрос
function getBookTitle(bookUrl)
    local r = http_get(bookUrl)   -- запрос 1
    ...
end
function getBookDescription(bookUrl)
    local r = http_get(bookUrl)   -- запрос 2 к той же странице
    ...
end

-- ✅ Используй fetchPage — см. раздел "Кэширование страниц"
local _pageCache = {}
local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then _pageCache[url] = r.body end
    return r.success and r.body or nil
end
```

**Важно:** `getChapterListHash` **НЕ** нужно переводить на `fetchPage` — он всегда должен получать актуальный ответ через прямой `http_get`, иначе перестанут обнаруживаться новые главы.

### 10. Хардкод заголовков которые подставляются автоматически

`User-Agent`, `Referer` и `Accept-Language` добавляются движком к каждому запросу автоматически. Дублировать их в плагине не нужно — это замусоривает код и ломает глобальные настройки (например, пользовательский UA из настроек приложения перестаёт работать).

```lua
-- ❌ Дублируем то что движок уже делает сам — UA из настроек приложения игнорируется
local r = http_get(url, {
    headers = {
        ["User-Agent"]       = "Mozilla/5.0 ...",
        ["Accept-Language"]  = "ru-RU,ru;q=0.9",
        ["Referer"]          = baseUrl,
        ["X-Requested-With"] = "XMLHttpRequest",
    }
})

-- ✅ Указываем только то что движок не добавляет сам
local r = http_get(url, {
    headers = {
        ["X-Requested-With"] = "XMLHttpRequest",
    }
})

-- ✅ Переопределяем дефолт только когда нужно конкретное значение
local r = http_post(ajaxUrl, body, {
    headers = {
        ["Referer"]          = bookUrl,  -- нужна страница книги, а не корень домена
        ["X-Requested-With"] = "XMLHttpRequest",
    }
})
```

**Если сайту нужен специфичный User-Agent (мобильная/десктопная вёрстка) — не хардкодь его в `headers`.** Объяви `getUserAgentPreset()` — движок применит пресет ко всем запросам источника, не ломая глобальные настройки:

```lua
-- ✅ Штатный механизм: пресет применяется ко всем запросам источника и его домена
function getUserAgentPreset()
    return "Safari Mobile"
end
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