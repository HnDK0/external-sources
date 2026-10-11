-- =====================================================================
-- Lib: chapter-text cleanup shared by the novel extractors.
-- Loaded via require_lib("content"). No dependencies on other libs.
--
-- Engine API used inside the functions only: string_normalize,
-- regex_replace, string_trim (all guarded, so the module still loads
-- outside the app).
-- =====================================================================
local version = "1.0.0"

local M = {}

local function logErr(msg)
    if type(log_error) == "function" then log_error(msg) end
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Chapter-heading prefix that gets stripped when it duplicates the
-- chapter title the engine already shows (guide:823). Language picks the
-- word for the ordinal; unknown/missing lang falls back to the dominant
-- ru/en cluster (Глава N | Chapter N).
local HEAD_BY_LANG = {
    ru = "(Глава\\s+\\d+|Chapter\\s+\\d+)",
    en = "(Chapter\\s+\\d+)",
    zh = "(第[\\d一二三四五六七八九十百]+[章节卷回部集篇]|Chapter\\s+\\d+)",
    ja = "(第\\s*\\d+話|Chapter\\s+\\d+)",
    id = "(Bab\\s+\\d+|Chapter\\s+\\d+)",
}

-- Credit lines: the English set is in every copy that has a credits
-- step at all; the per-language set is the union of the ru (ru/bookhamster,
-- ru/ifreedom, ru/jaomix), zh (zh/twkan, zh/sto9) and id (id/indowebnovel)
-- variants. Both are applied for the chosen language.
local CREDITS_EN =
    "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)"

local CREDITS_BY_LANG = {
    ru = "(?im)^\\s*(Перевод|Переводчик|Редакция|Редактор|Аннотация|Сайт|Источник|Студия)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)",
    zh = "(?im)^\\s*(翻译|譯者|译者|編輯|编辑|校對|校对|更新|閱讀|阅读|最新閱讀|最新阅读)[:\\s：][^\\n\\r]{0,70}(\\r?\\n|$)",
    id = "(?im)^\\s*(Penerjemah|Editor|Proofreader|Baca\\s+(di|novel|lanjutan)|Sumber|Donasi|Trakteer)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)",
}

-- Escape regex metacharacters of a literal chapter title or domain
-- (Java/Kotlin regex syntax: backslash-escape, not %-escape).
local function escapeLiteral(s)
    return (s:gsub("[%.%+%-%*%?%[%]%(%){}%$%^%|%%]", "\\%1"))
end

-- applyStandardContentTransforms (guide:812) as a shared function.
--   opts.domain      — baseUrl (or a bare host): lines mentioning it are dropped;
--   opts.chapterTitle — literal title to strip instead of the "Глава/Chapter N"
--                      prefix (duplicates the title field of the chapter);
--   opts.lang        — "ru" (default) / "en" / "zh" / "ja" / "id": picks the
--                      chapter-heading word and the extra credit lines.
-- Returns "" for an empty input, as every copy does.
function M.standardTransforms(text, opts)
    if not text or text == "" then return "" end
    opts = opts or {}
    local lang = opts.lang or "ru"

    if type(string_normalize) == "function" then
        text = string_normalize(text)
    end

    if type(regex_replace) ~= "function" then
        logErr("meta/content: regex_replace unavailable, transforms skipped")
        return trim(text)
    end

    -- 1. lines linking back to the source site (watermarks, "read more")
    local domain = opts.domain
    if type(domain) == "string" and domain ~= "" then
        domain = domain:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
        if domain ~= "" then
            text = regex_replace(text, "(?i)" .. escapeLiteral(domain) .. ".*?\\n", "")
        end
    end

    -- 2. leading chapter heading, duplicated in the title field
    local head = opts.chapterTitle
        and ("(" .. escapeLiteral(opts.chapterTitle) .. ")")
        or HEAD_BY_LANG[lang] or HEAD_BY_LANG.ru
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*(" .. head .. "[^\\n\\r]*[\\n\\r\\s]*)+", "")

    -- 3. translator / editor / "read at" credit lines
    text = regex_replace(text, CREDITS_EN, "")
    local credits = CREDITS_BY_LANG[lang]
    if credits then text = regex_replace(text, credits, "") end

    -- 4. trim (string_trim collapses nothing but the edges, as in the copies)
    if type(string_trim) == "function" then
        return string_trim(text)
    end
    return trim(text)
end

return M
