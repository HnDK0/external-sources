import my.noveldokusha.core.LanguageCode
import my.noveldokusha.scraper.configs.*

// NovelBin.kts - Конвертированный источник из NovelBin.kt
// Поддерживает HTML scraping с AJAX chapter loading

HtmlSelectors(
    baseUrl = "https://novelbin.com/",
    language = LanguageCode.ENGLISH,

    // Каталог - поиск новел по названию и обложке
    catalog = CatalogSelectors(
        item = elements(".col-novel-main .row"),
        title = text(".novel-title a"),
        url = attr("href", ".novel-title a"),
        cover = attr("data-src", "img[data-src]")
    ),

    // Поиск - тот же формат что и каталог
    search = SearchSelectors(
        item = elements(".col-novel-main .row"),
        title = text(".novel-title a"),
        url = attr("href", ".novel-title a"),
        cover = attr("src", "img[src]")
    ),

    // Страница книги - метаданные
    book = BookSelectors(
        cover = attr("content", "meta[property='og:image']"),
        description = text("div.desc-text")
    ),

    // Главы - с AJAX загрузкой
    chapters = ChapterSelectors(
        list = elements("ul.list-chapter li a"),
        title = attr("title", "a"),
        content = text("#chr-content")
            .removeElementsDOM("script", ".ads")
            .applyStandardContentTransforms(baseUrl)
    ),

    // AJAX chapter loading - специальная логика для NovelBin
    chapterPaginationType = ChapterPaginationType.AJAX_BASED,
    ajaxChapterListProvider = ajaxChapterListProvider@{ bookUrl, networkClient ->
        try {
            // Получаем novelId из meta[property=og:url] на странице книги
            val response = networkClient.get(bookUrl)
            val doc = response.toDocument()
            val novelId = doc.selectFirst("meta[property=og:url]")
                ?.attr("content")
                ?.toUrlBuilderSafe()
                ?.build()
                ?.lastPathSegment
                ?: return@ajaxChapterListProvider emptyList()

            // Делаем GET запрос к AJAX endpoint с novelId в query
            val ajaxUrl = "https://novelbin.com/ajax/chapter-archive?novelId=$novelId"
            val ajaxResponse = networkClient.get(ajaxUrl)
            val ajaxDoc = ajaxResponse.toDocument()

            // Парсим список глав
            ajaxDoc.select("ul.list-chapter li a").map { element ->
                ChapterResult(
                    title = element.text(),
                    url = element.attr("href")
                )
            }
        } catch (e: Exception) {
            Timber.w("Failed to get chapters for NovelBin URL $bookUrl: ${e.message}")
            emptyList()
        }
    },

    // Стандартный поиск (POST отключен)
    postSearchEnabled = false,
    postSearchUrl = null,
    postSearchDataBuilder = null,

    // URL builders для каталога и поиска
    buildCatalogUrl = { index ->
        val page = index + 1
        val path = if (page == 1) "sort/top-view-novel" else "sort/top-view-novel?page=$page"
        "$baseUrl$path"
    },

    buildSearchUrl = { index, query ->
        val page = index + 1
        val path = if (page == 1) "search?keyword=$query" else "search?keyword=$query&page=$page"
        "$baseUrl$path"
    },

    // URL transformers
    transformBookUrl = UrlTransformers.standardBookUrl(baseUrl),
    transformChapterUrl = UrlTransformers.standardChapterUrl(baseUrl)
)
