# Lua Source Guide v5 — Полное и исчерпывающее руководство по написанию плагинов NoveLA

> **Цель документа:** Этот гайд является самодостаточным. Имея только его, любая LLM (или человек) может написать полнофункциональный источник для NoveLA без доступа к исходному коду проекта. Гайд базируется на глубоком анализе 27 реальных нативных источников и покрывает 100% их функционала.

---

## Содержание

1.  [Введение и Чеклист разработки](#1-введение-и-чеклист-разработки)
2.  [Архитектура и Жизненный цикл плагина](#2-архитектура-и-жизненный-цикл-плагина)
3.  [Анализ сайта (Decision Tree)](#3-анализ-сайта-decision-tree)
4.  [Структура Lua-файла (Identity & Metadata)](#4-структура-lua-файла-identity--metadata)
5.  [Глобальное Lua API — Полный справочник](#5-глобальное-lua-api--полный-справочник)
    *   [5.1. Networking (Сетевые запросы OkHttp)](#51-networking-сетевые-запросы-okhttp)
    *   [5.2. Jsoup Bridge (Мощный парсинг HTML)](#52-jsoup-bridge-мощный-парсинг-html)
    *   [5.3. Utilities (JSON, Regex, URL, Base64)](#53-utilities-json-regex-url-base64)
    *   [5.4. Crypto & Security (AES Дешифровка)](#54-crypto--security-aes-дешифровка)
    *   [5.5. AI Translation (Google Translate)](#55-ai-translation-google-translate)
    *   [5.6. Preferences & UI Config](#56-preferences--ui-config)
6.  [Реализация функций каталога (Catalog & Search)](#6-реализация-функций-каталога-catalog--search)
    *   [6.1. getCatalogList и все типы пагинации](#61-getcataloglist-и-все-типы-пагинации)
    *   [6.2. getCatalogSearch и сложная логика поиска](#62-getcatalogsearch-и-сложная-логика-поиска)
7.  [Реализация функций книги (Book Details)](#7-реализация-функций-книги-book-details)
8.  [Реализация функций глав (Chapter List & Text)](#8-реализация-функций-глав-chapter-list--text)
    *   [8.1. getChapterList: Списки, AJAX и Тома](#81-getchapterlist-списки-ajax-и-тома)
    *   [8.2. getChapterText: Извлечение, Склейка и Чистка](#82-getchaptertext-извлечение-склейка-и-чистка)
9.  [Сценарии разработки (Patterns 1–15)](#9-сценарии-разработки-patterns-1–15)
10. [Миграция сложного источника (RanobeLib)](#10-миграция-сложного-источника-ranobelib)
11. [Best Practices и Оптимизация](#11-best-practices-и-оптимизация)
12. [Антипаттерны и Ошибки](#12-антипаттерны-и-ошибки)
13. [Отладка и логирование](#13-отладка-и-логирование)
14. [Регистрация источника](#14-регистрация-источника)

---

## 1. Введение и Чеклист разработки

Lua-плагин NoveLA — это независимый скрипт, работающий внутри Android-приложения. Он выступает связующим звеном между сайтом и интерфейсом приложения, преобразуя сырые данные (HTML/JSON) в структурированные объекты.

### Чеклист создания источника:
- [ ] **Шаг 1: Анализ сайта.** Используйте Chrome DevTools (F12). Изучите структуру URL каталога, параметры пагинации, эндпоинты API и способ подгрузки глав (AJAX или HTML).
- [ ] **Шаг 2: Создание файла.** Создайте `.lua` файл в папке языка (напр. `ru/mysource.lua`).
- [ ] **Шаг 3: Идентификаторы.** Заполните `id`, `name`, `baseUrl`. Убедитесь, что ID уникален и написан в snake_case.
- [ ] **Шаг 4: Сетевой слой.** Проверьте, нужны ли специфические заголовки (User-Agent, Referer) или кодировка (напр. GBK для Китая).
- [ ] **Шаг 5: Каталог и Поиск.** Реализуйте функции для получения списка книг. Учтите пагинацию (флаг `hasNext`).
- [ ] **Шаг 6: Детали книги.** Реализуйте получение описания и обложки.
- [ ] **Шаг 7: Главы.** Реализуйте получение списка глав (с учетом томов) и парсинг текста главы.
- [ ] **Шаг 8: Чистка текста.** Удалите все рекламные блоки, скрипты и элементы навигации.
- [ ] **Шаг 9: Регистрация.** Добавьте плагин в `index.yaml` и проверьте иконку.

---

## 2. Архитектура и Жизненный цикл плагина

Приложение NoveLA работает с плагином как с объектом типа `SourceInterface.Catalog`.

1.  **Инстанциация**: Приложение загружает скрипт и вызывает `return { ... }`. Полученная таблица функций кэшируется.
2.  **Browse Mode**: Когда пользователь заходит в каталог, вызывается `getCatalogList(0)`. При скролле вниз — `getCatalogList(1)`, `getCatalogList(2)` и т.д., пока возвращается `hasNext = true`.
3.  **Search Mode**: При вводе запроса вызывается `getCatalogSearch(0, query)`.
4.  **Metadata Fetching**: При открытии карточки книги приложение вызывает:
    - `getBookTitle(url)` — подтверждение заголовка.
    - `getBookDescription(url)` — получение синопсиса.
    - `getBookCoverImageUrl(url)` — загрузка качественной обложки.
5.  **Chapter List**: Вызывается `getChapterList(url)`. Плагин должен вернуть массив глав в порядке от старых к новым.
6.  **Reading**: При открытии главы:
    - Приложение скачивает HTML страницы.
    - Вызывает `getChapterText(html)`.
    - Результат (текст с `<p>` тегами) отображается в читалке.

---

## 3. Анализ сайта (Decision Tree)

**1. Как сайт отдает контент?**
-   **Чистый HTML**: Данные вшиты в страницу. Используйте `http_get` + `html_parse`.
-   **JSON API**: Сайт использует REST API. Используйте `http_get` + `json_parse`.
-   **Шифрование/Защита**: Текст зашифрован (AES) или скрыт. Используйте `aes_decrypt` или WebView куки.

**2. Как организована пагинация каталога?**
-   **Page-based**: `?page=1`, `?page=2`. (RoyalRoad, NovelFull)
-   **Offset-based**: `?offset=0`, `?offset=20`. (Jaomix)
-   **Cursor-based**: `?after=token_abc`. (API-ориентированные сайты)

**3. Как получить список глав?**
-   **NONE**: Все главы сразу на странице книги. (RoyalRoad)
-   **PAGE_BASED**: Список глав разбит на страницы. (NovelFire)
-   **AJAX**: Список глав грузится отдельным запросом. (NovelBin, NovelBuddy)

---

## 4. Структура Lua-файла (Identity & Metadata)

```lua
return {
    -- === IDENTITY ===
    id = "my_custom_source",      -- Уникальный ID плагина (snake_case)
    name = "My Custom Source",    -- Отображаемое имя в списке
    version = "1.2.0",            -- Версия плагина
    language = "ru",              -- Код языка (ru, en, zh, id, multi)
    baseUrl = "https://mysite.com", -- Базовый домен

    -- === MANDATORY FUNCTIONS ===
    getCatalogList = function(index) ... end,
    getCatalogSearch = function(index, query) ... end,
    getBookTitle = function(url) ... end,
    getBookCoverImageUrl = function(url) ... end,
    getBookDescription = function(url) ... end,
    getChapterList = function(url) ... end,
    getChapterText = function(html) ... end,

    -- === OPTIONAL ===
    getChapterListHash = function(url) ... end, -- Хеш для обновлений
    getScreenConfig = function() ... end,       -- UI настроек
}
```

---

## 5. Глобальное Lua API — Полный справочник

### 5.1. Networking (OkHttp)

#### `http_get(url, config, charset)`
Выполняет GET запрос.
-   **url**: Полная строка URL.
-   **config**: (Таблица, опц) `{ headers = { ["Name"] = "Val" }, cookies = "..." }`.
-   **charset**: (Строка, опц) Напр. "GBK". По умолчанию "UTF-8".
-   **Возвращает**: `{ success, body, code, url }`.

#### `http_post(url, body, config)`
Выполняет POST запрос.
-   **body**: Строка (JSON или Form-data).
-   **config**: Аналогично GET, поддерживает `charset` внутри таблицы.

#### `get_cookies(url)` / `set_cookies(url, cookie_str)`
Прямое управление куками приложения.

---

### 5.2. Jsoup Bridge (Парсинг HTML)

#### `html_parse(html_string)`
Превращает строку в объект Document.

#### `html_select(element, selector)`
Возвращает **массив** элементов по CSS-селектору.
```lua
local items = html_select(doc, "div.item")
```

#### `html_text(element)`
Извлекает чистый текст с сохранением абзацев.

#### Методы Element:
-   `el:get_text()`: Весь текст внутри.
-   `el:attr("name")`: Значение атрибута.
-   `el.href` / `el.src`: **Абсолютные** URL.
-   `el:remove("selector")`: Удаление мусора из DOM.

---

### 5.3. Utilities (JSON, Regex, URL, Base64)

#### JSON
-   `json_parse(str)` / `json_stringify(table)`

#### URL
-   `url_encode(str, charset)` / `url_resolve(base, rel)`

#### Regex
-   `regex_match(text, pattern)` / `regex_replace(text, pat, repl)`

#### String & Base64
-   `unescape_unicode(text)`: `\uXXXX` -> символы.
-   `string_normalize(text)`: Очистка Unicode (NFKC).
-   `base64_decode(str)` / `base64_encode(str)`

---

### 5.4. Crypto & Security (AES Дешифровка)

#### `aes_decrypt(data_base64, key_str, iv_str)`
-   Алгоритм: **AES/CBC/PKCS5Padding**.
-   `data_base64`: Зашифрованная строка в Base64.
-   `key_str`, `iv_str`: Ключ и IV (16/32 симв).

---

### 5.5. AI Translation (Google Translate)

#### `google_translate(text, source_lang, target_lang)`
-   `source_lang`: "en", "zh-CN", "auto".
-   `target_lang`: "ru", "en" и т.д.

---

### 5.6. Preferences & UI Config

#### `get_preference(key)` / `set_preference(key, value)`
Хранит настройки плагина.

#### `getScreenConfig()`
Описывает динамический UI настроек.

---

## 6. Реализация функций каталога (Catalog & Search)

### 6.1. getCatalogList и все типы пагинации

#### **Page-based (Постраничная)**
```lua
getCatalogList = function(index)
    local page = index + 1
    local res = http_get(baseUrl .. "/novels?page=" .. page)
    local doc = html_parse(res.body)
    local items = html_select(doc, ".novel-card")
    local result = {}
    for i=1, #items do
        table.insert(result, {
            title = items[i]:select(".title")[1]:get_text():trim(),
            url = items[i]:select("a")[1].href,
            cover = items[i]:select("img")[1].src
        })
    end
    return { items = result, hasNext = #html_select(doc, ".next") > 0 }
end
```

#### **Offset-based (Jaomix)**
```lua
getCatalogList = function(index)
    local limit = 20
    local offset = index * limit
    local res = http_get(baseUrl .. "/api/list?offset=" .. offset .. "&limit=" .. limit)
    local data = json_parse(res.body)
    -- ... парсинг JSON ...
    return { items = books, hasNext = data.total > offset + limit }
end
```

### 6.2. getCatalogSearch и сложная логика поиска

#### **POST Поиск (FreeWebNovel)**
```lua
getCatalogSearch = function(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local body = "searchkey=" .. url_encode(query)
    local res = http_post(baseUrl .. "/search", body, {
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
    })
    -- ... парсинг res.body ...
end
```

#### **Обработка редиректов (PiaoTia)**
```lua
getCatalogSearch = function(index, query)
    local res = http_get(baseUrl .. "/search?q=" .. url_encode(query))
    if res.url:find("/book/") then
        return { items = {{ title = query, url = res.url, cover = "" }}, hasNext = false }
    end
    -- ... обычный парсинг ...
end
```

---

## 7. Реализация функций книги (Book Details)

```lua
getBookDescription = function(url)
    local res = http_get(url)
    local doc = html_parse(res.body)
    local desc = doc:select(".description")[1]
    desc:remove("script, .ads")
    return html_text(desc)
end
```

---

## 8. Реализация функций глав (Chapter List & Text)

### 8.1. getChapterList: Списки, AJAX и Тома

#### **AJAX Список (NovelBuddy)**
```lua
getChapterList = function(url)
    local res = http_get(url)
    local bookId = res.body:match("bookId%s*=%s*(%d+)")
    local apiRes = http_get(baseUrl .. "/api/chapters?id=" .. bookId)
    local data = json_parse(apiRes.body)
    local chapters = {}
    for _, ch in ipairs(data) do
        table.insert(chapters, {
            title = ch.name,
            url = baseUrl .. "/read/" .. ch.id,
            volume = "Том " .. ch.vol -- Группировка в UI
        })
    end
    return chapters
end
```

### 8.2. getChapterText: Извлечение, Склейка и Чистка

#### **Чистка мусора**
```lua
getChapterText = function(html)
    local doc = html_parse(html)
    local content = html_select(doc, ".content")[1]
    content:remove("script, style, .ads, .social, .nav")
    local text = html_text(content)
    return "<p>" .. text:gsub("\n", "</p><p>") .. "</p>"
end
```

#### **Рекурсивная склейка (Novel543)**
```lua
getChapterText = function(html)
    local doc = html_parse(html)
    local parts = { html_text(doc:select(".content")[1]) }
    local current = doc
    while true do
        local next = current:select("a:contains(Next Part)")[1]
        if not next then break end
        local res = http_get(next.href)
        current = html_parse(res.body)
        table.insert(parts, html_text(current:select(".content")[1]))
    end
    return "<p>" .. table.concat(parts, "</p><p>") .. "</p>"
end
```

---

## 9. Сценарии разработки (Patterns 1–15)

1.  **Обратный порядок**: `for i=#list, 1, -1` для переворота глав.
2.  **Динамические Обложки**: Сборка URL из ID книги.
3.  **Cloudflare**: Использование кук из `get_cookies(baseUrl)`.
4.  **JSONP**: Regex `callback%((.*)%)` для извлечения JSON.
5.  **Custom Base64**: Алфавитные замены перед декодированием.
6.  **Meta-Tags**: Обложка и описание из `<meta property="og:...">`.
7.  **Dynamic Script ID**: Поиск ID книги в тегах `<script>`.
8.  **Login**: Сохранение сессии в `Preferences`.
9.  **Image Proxy**: Пропуск обложек через `weserv.nl`.
10. **CSS Escaping**: `.sm\\:text-lg` для селекторов с двоеточием.
11. **Encoding Fix**: Обязательно `charset = "GBK"` для Китая.
12. **Content Normalization**: Всегда `string_normalize` для текстов.
13. **Volume Detection**: Regex `title:match("(Том %d+)")`.
14. **Placeholder**: Если обложки нет, верните `""`.
15. **API Delay**: Использование `log_info` для микро-пауз.

---

## 10. Миграция сложного источника (RanobeLib)

Пример API со сложной вложенностью:
```lua
source.getChapterList = function(url)
    local slug = url:match("me/([^/?]+)")
    local res = http_get("https://api.lib.social/api/manga/" .. slug .. "/chapters?site_id[]=3")
    local data = json_parse(res.body).data
    local chapters = {}
    for i, item in ipairs(data) do
        table.insert(chapters, {
            title = "Глава " .. item.number .. (item.name and (": " .. item.name) or ""),
            url = baseUrl .. "/" .. slug .. "/v" .. item.volume .. "/c" .. item.number,
            volume = "Том " .. item.volume
        })
    end
    return reversed_list(chapters)
end
```

---

## 11. Best Practices и Оптимизация

1.  **DOM**: Удаляйте `img, video, iframe` из глав если не нужны.
2.  **Надежность**: Проверяйте `if item ~= nil` перед вызовом методов.
3.  **Абсолютные ссылки**: Пользуйтесь `.href` и `.src`.
4.  **Форматирование**: Всегда оборачивайте текст в `<p>`.

---

## 12. Антипаттерны и Ошибки

-   ❌ **Regex для HTML**: Только Jsoup.
-   ❌ **Сетевой спам**: Не делайте десятки запросов в одной функции.
-   ❌ **Хардкод**: Все метаданные в YAML.
-   ❌ **Текст стеной**: Читалка игнорирует переносы без `<p>`.

---

## 13. Отладка и Логирование

```lua
log_info("Debug: " .. tostring(val))
log_error("Error: " .. res.code)
```
**Настройки -> Отладка -> Журнал логов.**

---

## 14. Регистрация источника

1.  Файл: `lang/source_id.lua`.
2.  Иконка: `icons/source_id.png`.
3.  Индекс: `lang/index.yaml` (добавить запись).
4.  Глобальный индекс: `index.yaml` (обновить `count`).
