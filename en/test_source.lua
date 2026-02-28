-- Test Lua Source for Novela
-- Simple implementation for testing dynamic loading

return {
    id = "test_source",
    name = "Test Source",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://example.com",
    
    -- Catalog functions
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://example.com/catalog?page=" .. page
        
        log_info("Loading catalog page: " .. page)
        
        -- Mock data for testing
        local books = {}
        for i = 1, 10 do
            table.insert(books, {
                title = "Test Book " .. i,
                url = "https://example.com/book" .. i,
                cover = "https://example.com/cover" .. i .. ".jpg"
            })
        end
        
        return {
            items = books,
            hasNext = page < 5
        }
    end,
    
    getCatalogSearch = function(index, input)
        log_info("Searching for: " .. input)
        
        -- Mock search results
        local results = {}
        for i = 1, 5 do
            table.insert(results, {
                title = "Search Result " .. i .. " for " .. input,
                url = "https://example.com/search" .. i,
                cover = "https://example.com/search" .. i .. ".jpg"
            })
        end
        
        return {
            items = results,
            hasNext = false
        }
    end,
    
    -- Book functions
    getBookTitle = function(bookUrl)
        log_info("Getting book title for: " .. bookUrl)
        return "Test Book Title"
    end,
    
    getBookCoverImageUrl = function(bookUrl)
        log_info("Getting book cover for: " .. bookUrl)
        return "https://example.com/test-cover.jpg"
    end,
    
    getBookDescription = function(bookUrl)
        log_info("Getting book description for: " .. bookUrl)
        return "Test book description for Lua source testing."
    end,
    
    -- Chapter functions
    getChapterList = function(bookUrl)
        log_info("Getting chapter list for: " .. bookUrl)
        
        local chapters = {}
        for i = 1, 20 do
            table.insert(chapters, {
                title = "Chapter " .. i,
                url = "https://example.com/chapter" .. i,
                date = "2024-02-" .. string.format("%02d", i)
            })
        end
        
        return chapters
    end,
    
    getChapterText = function(html)
        log_info("Getting chapter text from HTML")
        return "This is test chapter content from Lua source.\n\nChapter content would be extracted from the provided HTML using the html_parse and html_select functions."
    end,
    
    -- Optional hash function
    getChapterListHash = function(bookUrl)
        log_info("Getting chapter list hash for: " .. bookUrl)
        return "test_hash_" .. bookUrl
    end
}
