import my.noveldokusha.core.LanguageCode
import my.noveldokusha.scraper.configs.*

// TestSource.kts - Тестовый источник для проверки системы внешних источников
// Этот скрипт демонстрирует структуру и будет выполняться когда evaluator будет готов

HtmlSelectors(
    baseUrl = "https://test-novel-source.com",
    language = LanguageCode.ENGLISH,

    // Декларативные селекторы для каталога
    catalog = CatalogSelectors(
        item = elements(".novel-item"),
        title = text(".novel-title a"),
        url = attr("href", ".novel-title a"),
        cover = attr("src", ".novel-cover img")
    ),

    // Селекторы для поиска (опционально, fallback на catalog)
    search = SearchSelectors(
        item = elements(".search-result"),
        title = text(".search-title a"),
        url = attr("href", ".search-title a"),
        cover = attr("src", ".search-cover img")
    ),

    // Селекторы для страницы книги
    book = BookSelectors(
        cover = attr("src", ".book-cover img"),
        description = text(".book-description")
    ),

    // Селекторы для глав с трансформациями контента
    chapters = ChapterSelectors(
        list = elements(".chapter-list a"),
        content = text(".chapter-content")
            .removeAds()           // Удаление рекламы
            .normalizeUnicode()    // Нормализация текста
            .trim(),               // Очистка пробелов
        title = text(".chapter-title")
    ),

    // URL билдеры (без изменений)
    buildCatalogUrl = { index -> "$baseUrl/novels?page=${index + 1}" },
    buildSearchUrl = { index, query -> "$baseUrl/search?q=$query&page=${index + 1}" },

    // URL трансформеры (без изменений)
    transformBookUrl = UrlTransformers.standardBookUrl(baseUrl),
    transformChapterUrl = UrlTransformers.standardChapterUrl(baseUrl)
)
