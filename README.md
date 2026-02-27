# Lua Sources Repository

Репозиторий Lua плагинов для NovelDokusha.

## Структура

```
lua-sources/
├── index.yaml          # Главный индекс репозитория
├── en/                  # Английские источники
│   ├── index.yaml      # Индекс английских источников
│   └── freewebnovel_advanced.lua
├── ru/                  # Русские источники
│   ├── index.yaml      # Индекс русских источников
│   └── ranobehub_advanced.lua
├── multi/               # Мультиязычные источники
│   ├── index.yaml      # Индекс мультиязычных источников
│   └── wtrlab_advanced.lua
└── icons/               # Иконки источников
    ├── freewebnovel.png
    ├── ranobehub.png
    └── wtr-lab.png
```

## Доступные источники

### English
- **FreeWebNovel (Advanced)** - Английские новеллы с POST поиском и пагинацией

### Русский
- **RanobeHub (Advanced)** - Русские ранобэ с API поддержкой и томами

### Multilanguage
- **WTR-Lab (Advanced)** - Мультиязычный источник с переводом и настройками

## Формат метаданных

Каждый источник описывается в YAML формате:

```yaml
- id: "source_id"
  name: "Source Name"
  version: "1.0.0"
  description: "Source description"
  url: "https://raw.githubusercontent.com/.../source.lua"
  icon: "https://raw.githubusercontent.com/.../icon.png"
  language: "en"
```

### Обязательные поля:
- `id` - Уникальный идентификатор источника
- `name` - Отображаемое имя
- `version` - Версия плагина
- `description` - Краткое описание
- `url` - Ссылка на Lua файл
- `icon` - Ссылка на иконку
- `language` - Языковой код (en, ru, multi и т.д.)

## Добавление нового источника

1. Создайте Lua плагин в соответствующей языковой папке
2. Добавьте иконку в папку `icons/`
3. Обновите `index.yaml` для языка
4. Обновите главный `index.yaml`
5. Обновите счетчики источников

## Lua API

Доступные функции в Lua плагинах:

### HTTP
- `http_get(url)` - GET запрос
- `http_post(url, data)` - POST запрос

### JSON
- `json_parse(jsonString)` - Парсинг JSON
- `json_stringify(table)` - Сериализация в JSON

### HTML
- `html_parse(html)` - Парсинг HTML
- `html_select(document, selector)` - CSS селекторы

### Утилиты
- `url_encode(text)` - URL кодирование
- `regex_match(text, pattern)` - Regex
- `detect_pagination(html)` - Детекция пагинации
- `translate_text(text, lang)` - Перевод

### Логирование
- `log_info(message)` - Информационное сообщение
- `log_error(message)` - Ошибка

## Структура Lua плагина

```lua
return {
    -- Обязательные метаданные
    id = "unique_plugin_id",
    name = "Human Readable Name",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://example.com/",
    
    -- Обязательные функции
    getCatalogList = function(index) ... end,
    getCatalogSearch = function(index, input) ... end,
    getBookTitle = function(bookUrl) ... end,
    getBookCoverImageUrl = function(bookUrl) ... end,
    getBookDescription = function(bookUrl) ... end,
    getChapterList = function(bookUrl) ... end,
    getChapterText = function(html) ... end,
    getChapterListHash = function(bookUrl) ... end
}
```

## Пример простого плагина

```lua
return {
    id = "example_source",
    name = "Example Source",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://example.com",
    
    getCatalogList = function(index)
        local url = "https://example.com/catalog?page=" .. index
        local response = http_get(url)
        
        if not response.success then
            return {items = {}, hasNext = false}
        end
        
        local doc = html_parse(response.body)
        local items = html_select(doc, ".book-item")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".title")[1]
            if titleElem then
                table.insert(books, {
                    title = titleElem.text,
                    url = "https://example.com" .. titleElem.href
                })
            end
        end
        
        return {items = books, hasNext = #books > 0}
    end,
    
    -- ... другие обязательные функции
}
```

## Тестирование

Для тестирования плагина:
1. Проверьте синтаксис Lua
2. Проверьте доступность URL в метаданных
3. Протестируйте основные функции
4. Проверьте работу с пагинацией

## Поддержка

Для вопросов и поддержки по созданию плагинов обращайтесь к документации Lua API.
