-- ═══════════════════════════════════════════════════════════════════════════
-- WTR-LAB source plugin for NoveLA
-- Version 1.1.7 (2026-08-26)
--
-- 1.1.7 (2026-08-26) — comprehensive upgrade on top of upstream 1.1.6.
--   Fixes two long-standing root causes of bad reader UX and adds full
--   novel-finder filter parity:
--
--   Gibberish-chapters fix (root cause):
--   • Chapter bodies returned as `arr:`/`str:` AES-256-GCM payloads by
--     /api/reader/get are now decrypted LOCALLY in pure Lua (no third-party
--     proxy round-trip needed). The old fly.dev proxy is kept only as an
--     automatic fallback, and a clear error is raised if both paths fail.
--     Previously, when fly.dev was slow/dead, the raw `arr:…` blob was
--     saved as the chapter text — this was the "large gibberish every
--     2-3 chapters" complaint.
--
--   "Security Check" / Turnstile fix (root cause):
--   • WTR-Lab has an APPLICATION-LEVEL per-IP rate limit on
--     /api/reader/get: once the counter crosses threshold (15), the API
--     returns HTTP 200 with `{"success":false,"requireTurnstile":true,…}`
--     and only submitting a valid turnstileToken resets it. The plugin now
--     detects this, retries with backoff (2 extra attempts — blocking is
--     per-instance and intermittent, so retries often land on a healthy
--     instance), and on persistent failure raises an actionable error
--     telling the user to solve the challenge once in the integrated
--     browser (instead of the old "[?] Unknown API error").
--   • IMPORTANT — do NOT add `cf_options = { whitelist = true }`:
--     NoveLA's CloudfareVerificationInterceptor ALREADY auto-detects
--     both real Cloudflare challenges AND wtr-lab's own `requireTurnstile`
--     JSON responses (marker + `server: cloudflare` + HTTP 200) and runs
--     the integrated WebView bypass ladder (hidden WebView → manual
--     WebViewActivity → retry). `whitelist = true` DISABLES that recovery
--     path for wtr-lab.com — the community v2.0.0 draft shipped it with a
--     comment claiming the opposite; keep it out.
--
--   Full novel-finder filter parity:
--   • Tag list expanded 208 → 882 (every tag the site exposes, incl.
--     Honghuang #801), split into 11 category-grouped tristate pickers
--     matching the site's own finder grouping (Protagonist / Power
--     Systems / Worldbuilding / Socio-Political / Relationships /
--     Narrative / Beings & Factions / Professional / Tone / Adaptations /
--     Misc). NoveLA renders every tristate option as an eagerly-built
--     chip, so a single 882-item list was a literal wall of chips.
--     getCatalogFiltered collects the included/excluded ids from all 11
--     groups into one combined ti=/te= list (single tc= operator applies
--     to the combined set — request params identical to a flat layout).
--   • Tag Search: two free-text filters (Tag Search include / exclude)
--     on top of the 11 grouped chip pickers. Type keywords like
--     "Honghuang, Naruto, adapted" and the plugin resolves them to the
--     matching tag IDs via case-insensitive substring matching against
--     all 882 tag labels, then merges the IDs into the same ti=/te=
--     params the chip pickers populate. Numeric IDs (e.g. "801") are
--     also accepted verbatim. Lets users find a specific tag in one
--     text field instead of scrolling through up to 190 chips per group.
--   • Added Minimum Reviews filter (minrc, 5-50 step 5); full
--     addition_age list (3month / 6month / last_month / last_year /
--     this_year); Daily View / Character Count / Weighted ordering.
--     WORKING chapter & character count filters via
--     count_type/count_filter/count_value (the old `minc=` parameter
--     was silently ignored by the site).
--
--   Catalog/search infrastructure:
--   • Switched from HTML scraping to the Next.js data JSON API
--     (/_next/data/{buildId}/en/novel-list.json / -finder.json) with
--     session buildId caching + stale-once refresh-retry. Reliable,
--     and the response's `count` field enables exact pagination:
--     `hasNext = #items > 0 and returned >= PAGE_SIZE and page *
--     PAGE_SIZE < countNum` (PAGE_SIZE = 10) — short-circuits on a
--     partial final page so it no longer over-fetches one empty page
--     at the end of a list. Note: the site returns `count` as a JSON
--     STRING (must tonumber() it).
--
--   Update detection:
--   • getChapterListHash now returns "<chapterCount>|<serie_data.updated_at>"
--     so re-translations / metadata edits that don't change the chapter
--     count are still detected. In 1.1.6 it returned the literal string
--     "Chapters" (both the label and the number span carry translate="no",
--     so html_select_first returned the label) — chapter-list updates were
--     NEVER detected.
--
--   Robustness:
--   • b64ToBytes now fails loud on a dangling base64 char (len%4==1)
--     instead of silently dropping it; the GCM tag check catches the
--     corruption anyway, but a nil lets the caller distinguish "malformed
--     input" from "decrypted garbage" and exercise the proxy fallback cleanly.
--   • cleanParagraph: line-anchored, word-bounded watermark/credit patterns
--     with correctly-escaped \\s (the community v2.0.0 draft used single
--     backslashes → Lua string literal "s", making those patterns dead).
--   • Optional Chapter Fetch Delay setting (None/2s/4s/6s) — may reduce
--     "Security Check" triggers during bulk downloads, at the cost of speed.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ───────────────────────────────────────────────────────────────
id = "wtrlab"
name = "WTR-LAB"
version = "1.1.7"
baseUrl = "https://wtr-lab.com/"
language = "MTL"
icon = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/wtr-lab.png"
description = "Machine-translated novels (wtr-lab.com). AI and raw (web) translation modes, full novel-finder filters. If a 'Security Check' error appears, open any chapter of the book in the integrated browser, complete the verification, then retry."

-- ── Settings keys ──────────────────────────────────────────────────────────
local PREF_MODE = "wtrlab_mode"           -- "ai" | "raw"  (key kept from 1.x so existing settings survive)
local PREF_DELAY = "wtrlab_chapter_delay" -- ms pause before each chapter fetch

-- ── Caches (live until app restart) ────────────────────────────────────────
local termCache = {}    -- [novelId] = { termByOriginal }
local _pageCache = {}   -- book page HTML
local _buildIdCache = nil

local function getMode()
    local v = get_preference(PREF_MODE)
    return (v ~= "" and v) or "ai"
end

local function getChapterDelay()
    local v = tonumber(get_preference(PREF_DELAY))
    if v == nil or v < 0 then v = 0 end
    return v
end

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then
        return ""
    end
    if string_starts_with(href, "http") then
        return href
    end
    if string_starts_with(href, "//") then
        return "https:" .. href
    end
    return url_resolve(baseUrl, href)
end

local function fetchPage(url)
    if _pageCache[url] then
        return _pageCache[url]
    end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
    end
    return r.success and r.body or nil
end

-- Rating from the metrics block "Rating ★ 3.9 (563)" (book page + catalog cards)
local function extractRating(html)
    for _, el in ipairs(html_select(html, "div.items-center.text-center")) do
        local label = html_select_first(el.html, "span[translate='no']")
        if label and string_trim(label.text) == "Rating" then
            local m = regex_match(html_text(el.html), "([\\d.]+)")
            if m and m[1] then
                return m[1]
            end
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Pure-Lua AES-256-GCM decryption (for `arr:` / `str:` encrypted chapter bodies)
--
-- Site-side scheme (reverse-engineered from wtr-lab's reader JS, verified
-- against live payloads): AES-256-GCM, static key below, payload format
--     arr:<b64 IV>:<b64 GCM tag>:<b64 ciphertext>   (body is a JSON array)
--     str:<b64 IV>:<b64 GCM tag>:<b64 ciphertext>   (body is one string)
-- The auth tag is NOT verified (unnecessary for display; skipping it avoids
-- a full GHASH implementation for the tag path).
-- ═══════════════════════════════════════════════════════════════════════════

local GCM_KEY = "IJAFUUxjM25hyzL2AZrn0wl7cESED6Ru"

-- F/byte XOR: use bit32 when the host provides it, else arithmetic fallback.
local HAS_BIT32 = (bit32 ~= nil and type(bit32) == "table" and type(bit32.bxor) == "function")

local function bxorB(a, b)
    if HAS_BIT32 then
        return bit32.bxor(a, b)
    end
    local r, p = 0, 1
    for _ = 1, 8 do
        local ab = a % 2
        local bb = b % 2
        if ab ~= bb then r = r + p end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return r
end

local function gmul2(a) -- xtime
    local h = a >= 128 and 1 or 0
    a = a * 2
    if a >= 256 then a = a - 256 end
    if h == 1 then a = bxorB(a, 27) end -- 0x1B
    return a
end

local function gmul3(a)
    return bxorB(gmul2(a), a)
end

-- AES S-box
local SBOX = {
    0x63,0x7C,0x77,0x7B,0xF2,0x6B,0x6F,0xC5,0x30,0x01,0x67,0x2B,0xFE,0xD7,0xAB,0x76,
    0xCA,0x82,0xC9,0x7D,0xFA,0x59,0x47,0xF0,0xAD,0xD4,0xA2,0xAF,0x9C,0xA4,0x72,0xC0,
    0xB7,0xFD,0x93,0x26,0x36,0x3F,0xF7,0xCC,0x34,0xA5,0xE5,0xF1,0x71,0xD8,0x31,0x15,
    0x04,0xC7,0x23,0xC3,0x18,0x96,0x05,0x9A,0x07,0x12,0x80,0xE2,0xEB,0x27,0xB2,0x75,
    0x09,0x83,0x2C,0x1A,0x1B,0x6E,0x5A,0xA0,0x52,0x3B,0xD6,0xB3,0x29,0xE3,0x2F,0x84,
    0x53,0xD1,0x00,0xED,0x20,0xFC,0xB1,0x5B,0x6A,0xCB,0xBE,0x39,0x4A,0x4C,0x58,0xCF,
    0xD0,0xEF,0xAA,0xFB,0x43,0x4D,0x33,0x85,0x45,0xF9,0x02,0x7F,0x50,0x3C,0x9F,0xA8,
    0x51,0xA3,0x40,0x8F,0x92,0x9D,0x38,0xF5,0xBC,0xB6,0xDA,0x21,0x10,0xFF,0xF3,0xD2,
    0xCD,0x0C,0x13,0xEC,0x5F,0x97,0x44,0x17,0xC4,0xA7,0x7E,0x3D,0x64,0x5D,0x19,0x73,
    0x60,0x81,0x4F,0xDC,0x22,0x2A,0x90,0x88,0x46,0xEE,0xB8,0x14,0xDE,0x5E,0x0B,0xDB,
    0xE0,0x32,0x3A,0x0A,0x49,0x06,0x24,0x5C,0xC2,0xD3,0xAC,0x62,0x91,0x95,0xE4,0x79,
    0xE7,0xC8,0x37,0x6D,0x8D,0xD5,0x4E,0xA9,0x6C,0x56,0xF4,0xEA,0x65,0x7A,0xAE,0x08,
    0xBA,0x78,0x25,0x2E,0x1C,0xA6,0xB4,0xC6,0xE8,0xDD,0x74,0x1F,0x4B,0xBD,0x8B,0x8A,
    0x70,0x3E,0xB5,0x66,0x48,0x03,0xF6,0x0E,0x61,0x35,0x57,0xB9,0x86,0xC1,0x1D,0x9E,
    0xE1,0xF8,0x98,0x11,0x69,0xD9,0x8E,0x94,0x9B,0x1E,0x87,0xE9,0xCE,0x55,0x28,0xDF,
    0x8C,0xA1,0x89,0x0D,0xBF,0xE6,0x42,0x68,0x41,0x99,0x2D,0x0F,0xB0,0x54,0xBB,0x16
}

local RCON = {0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1B,0x36,0x6C,0xD8,0xAB,0x4D}

-- AES-256 key expansion → flat round-key array of 15 * 16 bytes
local function aesExpandKey(keyBytes)
    -- keyBytes: 32 bytes; returns rk[1..240] (1-indexed flat)
    local w = {}          -- w[i] = 4-byte word tables, w[1..60]
    for i = 1, 8 do
        w[i] = { keyBytes[i * 4 - 3], keyBytes[i * 4 - 2], keyBytes[i * 4 - 1], keyBytes[i * 4] }
    end
    for i = 9, 60 do
        local t = { w[i - 1][1], w[i - 1][2], w[i - 1][3], w[i - 1][4] }
        if (i - 1) % 8 == 0 then
            -- RotWord + SubWord + Rcon
            t = { t[2], t[3], t[4], t[1] }
            for j = 1, 4 do t[j] = SBOX[t[j] + 1] end
            t[1] = bxorB(t[1], RCON[(i - 1) / 8 + 1 > 14 and 14 or (i - 1) / 8])
        elseif (i - 1) % 8 == 4 then
            for j = 1, 4 do t[j] = SBOX[t[j] + 1] end
        end
        local prev = w[i - 8]
        w[i] = {
            bxorB(prev[1], t[1]),
            bxorB(prev[2], t[2]),
            bxorB(prev[3], t[3]),
            bxorB(prev[4], t[4])
        }
    end
    -- flatten to round keys: rk[round][byte]
    local rk = {}
    for round = 0, 14 do
        for j = 1, 4 do
            local word = w[round * 4 + j]
            for b = 1, 4 do
                rk[round * 16 + (j - 1) * 4 + b] = word[b]
            end
        end
    end
    return rk
end

-- AES-256 encrypt one 16-byte block (state table mutated in place)
local function aesEncryptBlock(state, rk)
    -- AddRoundKey(0)
    for i = 1, 16 do state[i] = bxorB(state[i], rk[i]) end

    for round = 1, 13 do
        -- SubBytes
        for i = 1, 16 do state[i] = SBOX[state[i] + 1] end
        -- ShiftRows (state is column-major: s[c*4+r])
        local t
        t = state[2];  state[2]  = state[6];  state[6]  = state[10]; state[10] = state[14]; state[14] = t
        t = state[3];  state[3]  = state[11]; state[11] = t
        t = state[7];  state[7]  = state[15]; state[15] = t
        t = state[16]; state[16] = state[12]; state[12] = state[8];  state[8]  = state[4];  state[4]  = t
        -- MixColumns
        for c = 0, 3 do
            local i1 = c * 4 + 1
            local a0, a1, a2, a3 = state[i1], state[i1 + 1], state[i1 + 2], state[i1 + 3]
            state[i1]     = bxorB(bxorB(gmul2(a0), gmul3(a1)), bxorB(a2, a3))
            state[i1 + 1] = bxorB(bxorB(a0, gmul2(a1)), bxorB(gmul3(a2), a3))
            state[i1 + 2] = bxorB(bxorB(a0, a1), bxorB(gmul2(a2), gmul3(a3)))
            state[i1 + 3] = bxorB(bxorB(gmul3(a0), a1), bxorB(a2, gmul2(a3)))
        end
        -- AddRoundKey(round)
        local off = round * 16
        for i = 1, 16 do state[i] = bxorB(state[i], rk[off + i]) end
    end

    -- Final round (no MixColumns)
    for i = 1, 16 do state[i] = SBOX[state[i] + 1] end
    local t
    t = state[2];  state[2]  = state[6];  state[6]  = state[10]; state[10] = state[14]; state[14] = t
    t = state[3];  state[3]  = state[11]; state[11] = t
    t = state[7];  state[7]  = state[15]; state[15] = t
    t = state[16]; state[16] = state[12]; state[12] = state[8];  state[8]  = state[4];  state[4]  = t
    local off = 14 * 16
    for i = 1, 16 do state[i] = bxorB(state[i], rk[off + i]) end
    return state
end

-- GF(2^128) multiply for GHASH (right-shift algorithm, SP 800-38D)
local function gfMul(x, y)
    local z = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    local v = { y[1], y[2], y[3], y[4], y[5], y[6], y[7], y[8],
                y[9], y[10], y[11], y[12], y[13], y[14], y[15], y[16] }
    for i = 0, 127 do
        local byte = x[math.floor(i / 8) + 1]
        local bit = math.floor(byte / 2 ^ (7 - (i % 8))) % 2
        if bit == 1 then
            for j = 1, 16 do z[j] = bxorB(z[j], v[j]) end
        end
        local lsb = v[16] % 2
        for j = 16, 2, -1 do
            v[j] = math.floor(v[j] / 2) + (v[j - 1] % 2) * 128
        end
        v[1] = math.floor(v[1] / 2)
        if lsb == 1 then v[1] = bxorB(v[1], 0xE1) end
    end
    return z
end

-- GCM J0 derivation (IV here is 16 bytes → GHASH path; 12-byte IVs also handled)
local function gcmJ0(iv, H)
    if #iv == 12 then
        return { iv[1], iv[2], iv[3], iv[4], iv[5], iv[6], iv[7], iv[8],
                 iv[9], iv[10], iv[11], iv[12], 0, 0, 0, 1 }
    end
    -- J0 = GHASH_H(IV || 0^{s+64} || [len(IV)]_{64})
    local bitLen = #iv * 8
    local blocks = {}
    for i = 1, #iv do blocks[i] = iv[i] end
    local pad = (16 - (#iv % 16)) % 16
    for _ = 1, pad do blocks[#blocks + 1] = 0 end
    -- 8 zero bytes + 64-bit big-endian bit length (upper bytes are 0 for sane sizes)
    for _ = 1, 8 do blocks[#blocks + 1] = 0 end
    local lenBytes = { 0, 0, 0, 0, 0, 0, 0, 0 }
    local n = bitLen
    for i = 8, 1, -1 do
        lenBytes[i] = n % 256
        n = math.floor(n / 256)
    end
    for i = 1, 8 do blocks[#blocks + 1] = lenBytes[i] end

    local y = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    for start = 1, #blocks, 16 do
        local blk = {}
        for i = 1, 16 do blk[i] = blocks[start + i - 1] or 0 end
        for i = 1, 16 do y[i] = bxorB(y[i], blk[i]) end
        y = gfMul(y, H)
    end
    return y
end

local function inc32(block)
    local carry = 1
    for i = 16, 13, -1 do
        local v = block[i] + carry
        block[i] = v % 256
        carry = math.floor(v / 256)
        if carry == 0 then break end
    end
    return block
end

-- Pure-Lua base64 → byte table.
-- IMPORTANT: the host `base64_decode` returns a UTF-8 Java String, which
-- CORRUPTS binary data (IV/ciphertext bytes ≥ 0x80). Binary-safe decoding
-- must be done entirely in Lua via string.char/string.byte.
local B64DEC = {}
do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #chars do
        B64DEC[string.byte(chars, i)] = i - 1
    end
end

local function b64ToBytes(s)
    s = string.gsub(s, "%s", "")
    s = string.gsub(s, "=", "")
    local out = {}
    local len = #s
    local i = 1
    while i + 3 <= len do
        local a = B64DEC[string.byte(s, i)]
        local b = B64DEC[string.byte(s, i + 1)]
        local c = B64DEC[string.byte(s, i + 2)]
        local d = B64DEC[string.byte(s, i + 3)]
        if not (a and b and c and d) then return nil end
        out[#out + 1] = string.char(
            a * 4 + math.floor(b / 16),
            (b % 16) * 16 + math.floor(c / 4),
            (c % 4) * 64 + d
        )
        i = i + 4
    end
    if i + 2 == len then
        -- 3 leftover chars (unpadded, encodes 2 bytes)
        local a = B64DEC[string.byte(s, i)]
        local b = B64DEC[string.byte(s, i + 1)]
        local c = B64DEC[string.byte(s, i + 2)]
        if not (a and b and c) then return nil end
        out[#out + 1] = string.char(
            a * 4 + math.floor(b / 16),
            (b % 16) * 16 + math.floor(c / 4)
        )
        i = i + 3
    elseif i + 1 == len then
        -- 2 leftover chars (unpadded, encodes 1 byte)
        local a = B64DEC[string.byte(s, i)]
        local b = B64DEC[string.byte(s, i + 1)]
        if not (a and b) then return nil end
        out[#out + 1] = string.char(a * 4 + math.floor(b / 16))
        i = i + 2
    end
    -- After the leftover branches, every input char must have been consumed
    -- (i == len + 1). A single dangling char (len % 4 == 1) is impossible to
    -- decode to any whole byte in either padded or unpadded base64, so fail
    -- loud here -- the GCM tag check would catch the corruption anyway, but a
    -- nil lets the caller distinguish "malformed" from "decrypted garbage".
    if i ~= len + 1 then return nil end
    local bytes = {}
    local n = 0
    for j = 1, #out do
        local part = out[j]
        for k = 1, #part do
            n = n + 1
            bytes[n] = string.byte(part, k)
        end
    end
    return bytes
end

-- Decrypt an "arr:"/"str:" payload → plaintext string (tag NOT verified)
local function gcmDecrypt(payload)
    local prefix = string.sub(payload, 1, 4)
    local body = string.sub(payload, 5)
    local parts = {}
    for part in string.gmatch(body, "[^:]+") do
        parts[#parts + 1] = part
    end
    if #parts ~= 3 then return nil, "bad payload format" end
    local iv = b64ToBytes(parts[1])
    local ct = b64ToBytes(parts[3])
    if not iv or not ct or #iv < 1 or #ct < 1 then return nil, "bad base64" end

    local keyBytes = {}
    for i = 1, 32 do keyBytes[i] = string.byte(GCM_KEY, i) end
    local rk = aesExpandKey(keyBytes)

    -- H = AES_K(0^128)
    local H = aesEncryptBlock({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, rk)
    local j0 = gcmJ0(iv, H)

    -- CTR decrypt starting from inc32(J0)
    local counter = { j0[1], j0[2], j0[3], j0[4], j0[5], j0[6], j0[7], j0[8],
                      j0[9], j0[10], j0[11], j0[12], j0[13], j0[14], j0[15], j0[16] }
    local out = {}
    for start = 1, #ct, 16 do
        counter = inc32(counter)
        local ks = aesEncryptBlock({ counter[1], counter[2], counter[3], counter[4],
                                     counter[5], counter[6], counter[7], counter[8],
                                     counter[9], counter[10], counter[11], counter[12],
                                     counter[13], counter[14], counter[15], counter[16] }, rk)
        for i = 1, 16 do
            local idx = start + i - 1
            if idx <= #ct then
                out[#out + 1] = string.char(bxorB(ct[idx], ks[i]))
            end
        end
    end
    return table.concat(out), prefix
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter body decryption: local AES-GCM first, fly.dev proxy as fallback
-- ═══════════════════════════════════════════════════════════════════════════

local function decryptBody(rawBody)
    if not string_starts_with(rawBody, "arr:") and not string_starts_with(rawBody, "str:") then
        return rawBody
    end

    -- 1) Local decryption (preferred — no third party involved)
    local ok, plaintext, errOrPrefix = pcall(gcmDecrypt, rawBody)
    if ok and plaintext and #plaintext > 0 then
        log_info("wtrlab: decrypted body locally (" .. tostring(errOrPrefix) .. ", " .. tostring(#plaintext) .. " chars)")
        return plaintext
    end
    log_error("wtrlab: local AES-GCM decrypt failed (ok=" .. tostring(ok) ..
        " err=" .. tostring(plaintext ~= nil and plaintext or errOrPrefix) .. ")")

    -- 2) Fallback: public decrypt proxy (as used by plugin v1.x)
    local r = http_post("https://wtr-lab-proxy.fly.dev/chapter", json_stringify({
        payload = rawBody
    }), {
        headers = {
            ["Content-Type"] = "application/json"
        }
    })
    if not r.success then
        log_error("wtrlab: decrypt proxy failed code=" .. tostring(r.code))
        return nil
    end
    local data = json_parse(r.body)
    if type(data) == "table" then
        if data[1] ~= nil then
            return json_stringify(data)
        end
        if data.body ~= nil then
            return json_stringify(data.body)
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Next.js data API (catalog / search / filters)
-- ═══════════════════════════════════════════════════════════════════════════

local function getBuildId()
    if _buildIdCache then
        return _buildIdCache
    end
    local fr = http_get(baseUrl .. "en/novel-finder")
    if not fr.success then
        return nil
    end
    local buildId = string.match(fr.body, '"buildId":"([^"]+)"')
    if buildId then
        _buildIdCache = buildId
    end
    return buildId
end

-- Fetch a _next/data JSON page. Refreshes a stale buildId once and retries.
-- Returns pageProps table or nil.
local function fetchNextData(pathPattern, params)
    for attempt = 1, 2 do
        local buildId = getBuildId()
        if not buildId then
            return nil
        end
        local url = baseUrl .. "_next/data/" .. buildId .. pathPattern .. "?" .. params
        local r = http_get(url)
        if r.success then
            local data = json_parse(r.body)
            if data and data.pageProps then
                return data.pageProps
            end
        end
        -- 404 / unexpected shape → buildId is stale (site redeployed): retry once
        if attempt == 1 then
            log_info("wtrlab: stale buildId, refreshing")
            _buildIdCache = nil
        end
    end
    return nil
end

local function seriesToItems(series)
    local seen = {}
    local items = {}
    for _, novel in ipairs(series) do
        local rawId = tostring(novel.raw_id or "")
        if rawId ~= "" and not seen[rawId] then
            seen[rawId] = true
            local title = (novel.data and novel.data.title) or ""
            local cover = (novel.data and novel.data.image) or ""
            local slug = novel.slug or ""
            local item = {
                title = string_clean(title),
                url = baseUrl .. "en/novel/" .. rawId .. "/" .. slug,
                cover = absUrl(cover)
            }
            if novel.rating ~= nil then
                item.rating = tostring(novel.rating)
            end
            table.insert(items, item)
        end
    end
    return items
end

-- The site paginates catalog/finder results at a fixed 10 items per page
-- (verified for both novel-list.json and novel-finder.json). Used to
-- short-circuit pagination on a short final page without relying on the
-- (post-dedup) item count, which would mis-count if the API ever returned
-- a duplicate raw_id within one page.
local PAGE_SIZE = 10

local function pagePropsToResult(pp, page)
    if not pp or not pp.series then
        return { items = {}, hasNext = false }
    end
    local items = seriesToItems(pp.series)
    local returned = #pp.series
    -- NOTE: the site returns "count" as a JSON *string* — coerce it
    local countNum = tonumber(pp.count)
    local hasNext
    if countNum ~= nil then
        -- Two conditions must both hold: the page was full (a short page is
        -- always the last one, regardless of what `count` claims), AND there
        -- are more items past this page by the fixed page size. The old
        -- `page * #items < countNum` used the (variable) returned count,
        -- which on a partial final page (e.g. count=12, page 2 returns 2)
        -- evaluated to 2*2<12 = true and fetched a 3rd empty page.
        hasNext = #items > 0 and returned >= PAGE_SIZE and page * PAGE_SIZE < countNum
    else
        -- No total count: assume more pages only when the page was full.
        hasNext = returned >= PAGE_SIZE
    end
    return { items = items, hasNext = hasNext }
end


-- ── Tag search index & resolver ─────────────────────────────────────
-- Auto-generated by scripts/gen_tag_search_index.py from
-- research/real_tags.json (882 tags). Do not hand-edit; re-run
-- the generator after refreshing real_tags.json.
--
-- Format: one "id|Label" pair per line. Parsed once at plugin
-- load into ALL_TAGS (array of {id=string, label=lowercase}).
-- tagSearchResolve(text) returns a dedup'd list of ids whose
-- label contains any comma/space/newline-separated token, OR
-- whose id matches a token. Empty/whitespace-only text → empty list.

local TAG_SEARCH_INDEX = [==[
1|Abandoned Children
2|Ability Steal
3|Absent Parents
4|Abusive Characters
5|Academy
6|Accelerated Growth
7|Acting
8|Adapted from Manga
9|Adapted from Manhua
10|Adapted to Anime
11|Adapted to Drama
12|Adapted to Drama CD
13|Adapted to Game
14|Adapted to Manga
15|Adapted to Manhua
16|Adapted to Manhwa
17|Adapted to Movie
18|Adapted to Visual Novel
19|Adopted Children
20|Adopted Protagonist
21|Adultery
22|Adventurers
23|Affair
24|Age Progression
25|Age Regression
26|Aggressive Characters
27|Alchemy
28|Aliens
29|All-Girls School
30|Alternate World
31|Amnesia
32|Amusement Park
33|Anal
34|Ancient China
35|Ancient Times
36|Androgynous Characters
37|Androids
38|Angels
39|Animal Characteristics
40|Animal Rearing
41|Anti-Magic
42|Anti-social Protagonist
43|Antihero Protagonist
44|Antique Shop
45|Apartment Life
46|Apathetic Protagonist
47|Apocalypse
48|Appearance Changes
49|Appearance Different from Actual Age
50|Archery
51|Aristocracy
52|Arms Dealers
53|Army
54|Army Building
55|Arranged Marriage
56|Arrogant Characters
57|Artifact Crafting
58|Artifacts
59|Artificial Intelligence
60|Artists
61|Assassins
62|Astrologers
63|Autism
64|Automatons
65|Average-looking Protagonist
66|Award-winning Work
67|Awkward Protagonist
68|Bands
69|Based on a Movie
70|Based on a Song
71|Based on a TV Show
72|Based on a Video Game
73|Based on a Visual Novel
74|Based on an Anime
75|Battle Academy
76|Battle Competition
77|BDSM
78|Beast Companions
79|Beastkin
80|Beasts
81|Beautiful Female Lead
82|Bestiality
83|Betrayal
84|Bickering Couple
85|Biochip
86|Bisexual Protagonist
87|Black Belly
88|Blackmail
89|Blacksmith
90|Blind Dates
91|Blind Protagonist
92|Blood Manipulation
93|Bloodlines
94|Body Swap
95|Body Tempering
96|Body-double
97|Bodyguards
98|Books
99|Bookworm
100|Boss-Subordinate Relationship
101|Brainwashing
102|Breast Fetish
103|Broken Engagement
104|Brother Complex
105|Brotherhood
106|Buddhism
107|Bullying
108|Business Management
109|Businessmen
110|Butlers
111|Calm Protagonist
112|Cannibalism
113|Card Games
114|Carefree Protagonist
115|Caring Protagonist
116|Cautious Protagonist
117|Celebrities
118|Character Growth
119|Charismatic Protagonist
120|Charming Protagonist
121|Chat Rooms
122|Cheats
123|Chefs
124|Child Abuse
125|Child Protagonist
126|Childcare
127|Childhood Friends
128|Childhood Love
129|Childhood Promise
130|Childish Protagonist
131|Chuunibyou
132|Clan Building
133|Classic
134|Clever Protagonist
135|Clingy Lover
136|Clones
137|Clubs
138|Clumsy Love Interests
139|Co-Workers
140|Cohabitation
141|Cold Love Interests
142|Cold Protagonist
143|Collection of Short Stories
144|College/University
145|Coma
146|Comedic Undertone
147|Coming of Age
148|Complex Family Relationships
149|Conditional Power
150|Confident Protagonist
151|Confinement
152|Conflicting Loyalties
153|Contracts
154|Cooking
155|Corruption
156|Cosmic Wars
157|Cosplay
158|Couple Growth
159|Court Official
160|Cousins
161|Cowardly Protagonist
162|Crafting
163|Crime
164|Criminals
165|Cross-dressing
166|Crossover
167|Cruel Characters
168|Cryostasis
169|Cultivation
170|Cunnilingus
171|Cunning Protagonist
172|Curious Protagonist
173|Curses
174|Cute Children
175|Cute Protagonist
176|Cute Story
177|Dancers
178|Dao Companion
179|Dao Comprehension
180|Daoism
181|Dark
182|Dead Protagonist
183|Death
184|Death of Loved Ones
185|Debts
186|Delinquents
187|Delusions
188|Demi-Humans
189|Demon Lord
190|Demonic Cultivation Technique
191|Demons
192|Dense Protagonist
193|Depictions of Cruelty
194|Depression
195|Destiny
196|Detectives
197|Determined Protagonist
198|Devoted Love Interests
199|Different Social Status
200|Disabilities
201|Discrimination
202|Disfigurement
203|Dishonest Protagonist
204|Distrustful Protagonist
205|Divination
206|Divine Protection
207|Divorce
208|Doctors
209|Dolls/Puppets
210|Domestic Affairs
211|Doting Love Interests
212|Doting Older Siblings
213|Doting Parents
214|Dragon Riders
215|Dragon Slayers
216|Dragons
217|Dreams
218|Drugs
219|Druids
220|Dungeon Master
221|Dungeons
222|Dwarfs
223|Dystopia
224|e-Sports
225|Early Romance
226|Earth Invasion
227|Easy Going Life
228|Economics
229|Editors
230|Eidetic Memory
231|Elderly Protagonist
232|Elemental Magic
233|Elves
234|Emotionally Weak Protagonist
235|Empires
236|Enemies Become Allies
237|Enemies Become Lovers
238|Engagement
239|Engineer
240|Enlightenment
241|Episodic
242|Eunuch
243|European Ambience
244|Evil Gods
245|Evil Organizations
246|Evil Protagonist
247|Evil Religions
248|Evolution
249|Exhibitionism
250|Exorcism
251|Eye Powers
252|Fairies
253|Fallen Angels
254|Fallen Nobility
255|Familial Love
256|Familiars
257|Family
258|Family Business
259|Family Conflict
260|Famous Parents
261|Famous Protagonist
262|Fanaticism
264|Fantasy Creatures
265|Fantasy World
266|Farming
267|Fast Cultivation
268|Fast Learner
269|Fat Protagonist
270|Fat to Fit
271|Fated Lovers
272|Fearless Protagonist
273|Fellatio
274|Female Master
275|Female Protagonist
276|Female to Male
277|Feng Shui
278|Firearms
279|First Love
280|First-time Intercourse
281|Flashbacks
282|Fleet Battles
283|Folklore
284|Forced into a Relationship
285|Forced Living Arrangements
286|Forced Marriage
287|Forgetful Protagonist
288|Former Hero
289|Fox Spirits
290|Friends Become Enemies
291|Friendship
292|Fujoshi
293|Futanari
294|Futuristic Setting
295|Galge
296|Gambling
297|Game Elements
298|Game Ranking System
299|Gamers
300|Gangs
301|Gate to Another World
302|Genderless Protagonist
303|Generals
304|Genetic Modifications
305|Genies
306|Genius Protagonist
307|Ghosts
308|Gladiators
309|Glasses-wearing Love Interests
310|Glasses-wearing Protagonist
311|Goblins
312|God Protagonist
313|God-human Relationship
314|Goddesses
315|Godly Powers
316|Gods
317|Golems
318|Gore
319|Grave Keepers
320|Grinding
321|Guardian Relationship
322|Guilds
323|Gunfighters
324|Hackers
325|Half-human Protagonist
326|Handjob
327|Handsome Male Lead
328|Hard-Working Protagonist
329|Harem-seeking Protagonist
330|Harsh Training
331|Hated Protagonist
332|Healers
333|Heartwarming
334|Heaven
335|Heavenly Tribulation
336|Hell
337|Helpful Protagonist
338|Herbalist
339|Heroes
340|Heterochromia
341|Hidden Abilities
342|Hiding True Abilities
343|Hiding True Identity
344|Hikikomori
345|Homunculus
346|Honest Protagonist
347|Hospital
348|Hot-blooded Protagonist
349|Human Experimentation
350|Human Weapon
351|Human-Nonhuman Relationship
352|Humanoid Protagonist
353|Hunters
354|Hypnotism
355|Identity Crisis
356|Imaginary Friend
357|Immortals
358|Imperial Harem
359|Incest
360|Incubus
361|Indecisive Protagonist
362|Industrialization
363|Inferiority Complex
364|Inheritance
365|Inscriptions
366|Insects
367|Interconnected Storylines
368|Interdimensional Travel
369|Introverted Protagonist
370|Investigations
371|Invisibility
372|Jack of All Trades
373|Jealousy
374|Jiangshi
375|Jobless Class
376|JSDF
377|Kidnappings
378|Kind Love Interests
379|Kingdom Building
380|Kingdoms
381|Knights
382|Kuudere
383|Lack of Common Sense
384|Language Barrier
385|Late Romance
386|Lawyers
387|Lazy Protagonist
388|Leadership
389|Legends
390|Level System
391|Library
392|Limited Lifespan
393|Living Abroad
394|Living Alone
395|Loli
396|Loneliness
397|Loner Protagonist
398|Long Separations
399|Long-distance Relationship
400|Lost Civilizations
401|Lottery
402|Love at First Sight
403|Love Interest Falls in Love First
404|Love Rivals
405|Love Triangles
406|Lovers Reunited
407|Low-key Protagonist
408|Loyal Subordinates
409|Lucky Protagonist
410|Magic
411|Magic Beasts
412|Magic Formations
413|Magical Girls
414|Magical Space
415|Magical Technology
416|Maids
417|Male Protagonist
418|Male to Female
419|Male Yandere
420|Management
421|Mangaka
422|Manipulative Characters
423|Manly Gay Couple
424|Marriage
425|Marriage of Convenience
426|Martial Spirits
427|Masochistic Characters
428|Master-Disciple Relationship
429|Master-Servant Relationship
430|Masturbation
431|Matriarchy
432|Mature Protagonist
433|Medical Knowledge
434|Medieval
435|Mercenaries
436|Merchants
437|Military
438|Mind Break
439|Mind Control
440|Misandry
441|Mismatched Couple
442|Misunderstandings
443|MMORPG
444|Mob Protagonist
445|Models
446|Modern Day
447|Modern Knowledge
448|Money Grubber
449|Monster Girls
450|Monster Society
451|Monster Tamer
452|Monsters
453|Movies
454|Mpreg
455|Multiple Identities
456|Multiple Personalities
457|Multiple POV
458|Multiple Protagonists
459|Multiple Realms
460|Multiple Reincarnated Individuals
461|Multiple Timelines
462|Multiple Transported Individuals
463|Murders
464|Music
465|Mutated Creatures
466|Mutations
467|Mute Character
468|Mysterious Family Background
469|Mysterious Illness
470|Mysterious Past
471|Mystery Solving
472|Mythical Beasts
473|Mythology
474|Naive Protagonist
475|Narcissistic Protagonist
476|Nationalism
477|Near-Death Experience
478|Necromancer
479|Neet
480|Netorare
481|Netorase
482|Netori
483|Nightmares
484|Ninjas
485|Nobles
486|Non-humanoid Protagonist
487|Non-linear Storytelling
488|Nudity
489|Nurses
490|Obsessive Love
491|Office Romance
492|Older Love Interests
493|Omegaverse
494|Oneshot
495|Online Romance
496|Onmyouji
497|Orcs
498|Organized Crime
499|Orgy
500|Orphans
501|Otaku
502|Otome Game
503|Outcasts
504|Outdoor Intercourse
505|Outer Space
506|Overpowered Protagonist
507|Overprotective Siblings
508|Pacifist Protagonist
509|Paizuri
510|Parallel Worlds
511|Parasites
512|Parent Complex
513|Parody
514|Part-Time Job
515|Past Plays a Big Role
516|Past Trauma
517|Persistent Love Interests
518|Personality Changes
519|Perverted Protagonist
520|Pets
521|Pharmacist
522|Philosophical
523|Phobias
524|Phoenixes
525|Photography
526|Pill Based Cultivation
527|Pill Concocting
528|Pilots
529|Pirates
530|Playboys
531|Playful Protagonist
532|Poetry
533|Poisons
534|Police
535|Polite Protagonist
536|Politics
537|Polyandry
538|Polygamy
539|Poor Protagonist
540|Poor to Rich
541|Popular Love Interests
542|Possession
543|Possessive Characters
544|Post-apocalyptic
545|Power Couple
546|Power Struggle
547|Pragmatic Protagonist
548|Precognition
549|Pregnancy
550|Pretend Lovers
551|Previous Life Talent
552|Priestesses
553|Priests
554|Prison
555|Proactive Protagonist
556|Programmer
557|Prophecies
558|Prostitutes
559|Protagonist Falls in Love First
560|Protagonist Strong from the Start
561|Protagonist with Multiple Bodies
562|Psychic Powers
563|Psychopaths
564|Puppeteers
565|Quiet Characters
566|Quirky Characters
567|R-15
568|R-18
569|Race Change
570|Racism
571|Rape
572|Rape Victim Becomes Lover
573|Rebellion
574|Reincarnated as a Monster
575|Reincarnated as an Object
576|Reincarnated in a Game World
577|Reincarnated in Another World
578|Reincarnation
579|Religions
580|Reluctant Protagonist
581|Reporters
582|Restaurant
583|Resurrection
584|Returning from Another World
585|Revenge
586|Reverse Harem
587|Reverse Rape
588|Reversible Couple
589|Rich to Poor
590|Righteous Protagonist
591|Rivalry
592|Romantic Subplot
593|Roommates
594|Royalty
595|Ruthless Protagonist
596|Sadistic Characters
597|Saints
598|Salaryman
599|Samurai
600|Saving the World
601|Schemes And Conspiracies
602|Schizophrenia
603|Scientists
604|Sculptors
605|Sealed Power
606|Second Chance
607|Secret Crush
608|Secret Identity
609|Secret Organizations
610|Secret Relationship
611|Secretive Protagonist
612|Secrets
613|Sect Development
614|Seduction
615|Seeing Things Other Humans Can't
616|Selfish Protagonist
617|Selfless Protagonist
618|Seme Protagonist
619|Senpai-Kouhai Relationship
620|Sentient Objects
621|Sentimental Protagonist
622|Serial Killers
623|Servants
624|Seven Deadly Sins
625|Seven Virtues
626|Sex Friends
627|Sex Slaves
628|Sexual Abuse
629|Sexual Cultivation Technique
630|Shameless Protagonist
631|Shapeshifters
632|Sharing A Body
633|Sharp-tongued Characters
634|Shield User
635|Shikigami
636|Short Story
637|Shota
638|Shoujo-Ai Subplot
639|Shounen-Ai Subplot
640|Showbiz
641|Shy Characters
642|Sibling Rivalry
643|Sibling's Care
644|Siblings
645|Siblings Not Related by Blood
646|Sickly Characters
647|Sign Language
648|Singers
649|Single Parent
650|Sister Complex
651|Skill Assimilation
652|Skill Books
653|Skill Creation
654|Slave Harem
655|Slave Protagonist
656|Slaves
657|Sleeping
658|Slow Growth at Start
659|Slow Romance
660|Smart Couple
661|Social Outcasts
662|Soldiers
663|Soul Power
664|Souls
665|Spatial Manipulation
666|Spear Wielder
667|Special Abilities
668|Spies
669|Spirit Advisor
670|Spirit Users
671|Spirits
672|Stalkers
673|Stockholm Syndrome
674|Stoic Characters
675|Store Owner
676|Straight Seme
677|Straight Uke
678|Strategic Battles
679|Strategist
680|Strength-based Social Hierarchy
681|Strong Love Interests
682|Strong to Stronger
683|Stubborn Protagonist
684|Student Council
685|Student-Teacher Relationship
686|Succubus
687|Sudden Strength Gain
688|Sudden Wealth
689|Suicides
690|Summoned Hero
691|Summoning Magic
692|Survival
693|Survival Game
694|Sword And Magic
695|Sword Wielder
696|System
697|Teachers
698|Teamwork
699|Technological Gap
700|Tentacles
701|Terminal Illness
702|Terrorists
703|Thieves
704|Threesome
705|Thriller
706|Time Loop
707|Time Manipulation
708|Time Paradox
709|Time Skip
710|Time Travel
711|Timid Protagonist
712|Tomboyish Female Lead
713|Torture
714|Toys
715|Tragic Past
716|Transformation Ability
717|Transmigration
718|Transplanted Memories
719|Transported into a Game World
720|Transported Modern Structure
721|Transported to Another World
722|Trap
723|Tribal Society
724|Trickster
725|Tsundere
726|Twins
727|Twisted Personality
728|Ugly Protagonist
729|Ugly to Beautiful
730|Unconditional Love
731|Underestimated Protagonist
732|Unique Cultivation Technique
733|Unique Weapon User
734|Unique Weapons
735|Unlimited Flow
736|Unlucky Protagonist
737|Unreliable Narrator
738|Unrequited Love
739|Valkyries
740|Vampires
741|Villainess Noble Girls
742|Virtual Reality
743|Vocaloid
744|Voice Actors
745|Voyeurism
746|Waiters
747|War Records
748|Wars
749|Weak Protagonist
750|Weak to Strong
751|Wealthy Characters
752|Werebeasts
753|Wishes
754|Witches
755|Wizards
756|World Hopping
757|World Travel
758|World Tree
759|Writers
760|Yandere
761|Youkai
762|Younger Brothers
763|Younger Love Interests
764|Younger Sisters
765|Zombies
766|Marvel
767|One Piece
768|Harry Potter
769|Naruto
770|Bleach
771|Pokemon
772|Douluo Dalu
773|Dragon Ball
774|Yu-Gi-Oh!
775|Warhammer
776|Jujutsu Kaisen
777|Hunter x Hunter
778|DC Universe
779|Hollywood
780|Football
781|Gao Wu
782|Live Streaming
783|Cyberpunk 2077
784|Game Creator
785|Swallowed Star
786|Simulator
787|Single Female Lead
788|Western Names
789|Dark Fantasy
790|Minecraft
791|League of Legends
792|Mortal Flow
793|Proficiency
794|DnD
795|Three Kingdoms
796|Journey to the West
797|Devouring
798|Eavesdropping
799|Lord of the Mysteries
800|Conferred Gods
801|Honghuang
802|Territory Management
803|Heaven Defying Comprehension
804|Detective Conan
806|Business Wars
807|Copy
808|Faith Dependent Deities
809|Basketball
810|Undead Protagonist
811|Sign In
812|Demon Slayer
813|Game of Thrones
814|Fairy Tail
815|Genshin Impact
816|Frieren
817|Star Wars
818|Honkai
819|Witcher
820|Siheyuan
821|Hong Kong
822|Array
823|Lord
824|Life Script
825|More Children More Blessings
826|Overlord
827|Class Awakening
828|Spiritual Energy Revival
829|Reborn
830|Reality-Game Fusion
831|Reborn as the Villain
832|BTTH
833|Arknights
834|Uma Musume
835|Steampunk
836|The Boys
837|One Punch Man
838|Ultraman
839|Black Clover
840|Danmachi
841|Daily Intelligence
842|Simultaneous Transmigration
843|Kamen Rider
844|Nasuverse
845|Versatile Mage
846|Adapted to Donghua
847|Highschool DxD
848|Furry Relationship
849|Immortal Protagonist
850|Toaru
851|Digimon
852|The Walking Dead
853|Lord of the Ring
854|Classroom of the Elite
855|Stand User
856|Resident Evil
857|Touhou Project
858|Project Moon
859|JoJo’s Bizarre Adventure
860|Machinist 
861|Qing Transmigration
862|Kirkmanverse
863|Pirates of Caribbean
864|King's Avatar
865|Hikigaya
866|Strike the Blood
867|Zenless Zone Zero
868|Fabulous Beast
869|The Eminence in Shadow
870|Slay the Gods
871|Behind-the-Scenes Mastermind
872|Final Fantasy
873|1900s
874|1910s
875|1920s
876|1930s
877|1940s
878|1950s
879|1960s
880|1970s
881|1980s
882|1990s
883|2000s
884|2010s
]==]

local ALL_TAGS = {}
do
    for line in TAG_SEARCH_INDEX:gmatch("[^\n]+") do
        local id, label = line:match("^([^|]+)|(.+)$")
        if id and label then
            ALL_TAGS[#ALL_TAGS + 1] = { id = id, label = label:lower() }
        end
    end
end

-- Resolve a free-text Tag Search field to a dedup'd list of tag IDs.
-- Tokens are split on comma, semicolon, newline, tab, or any run
-- of whitespace. Each token is matched case-insensitively as a
-- substring of every tag label; if the token itself is a numeric
-- tag id it is also accepted verbatim. Returned ids are unique.
function tagSearchResolve(text)
    if not text or text == "" then return {} end
    local lower = text:lower()
    local seen = {}
    local out = {}
    -- gmatch with a single-char-but-greedy alternation: comma,
    -- semicolon, newline, tab, or any run of spaces (any unicode
    -- whitespace would be nicer but Lua's %s is ASCII-only).
    for token in lower:gmatch("[^,;\n\t ]+") do
        if token ~= "" then
            for _, t in ipairs(ALL_TAGS) do
                if t.label:find(token, 1, true) or t.id == token then
                    if not seen[t.id] then
                        seen[t.id] = true
                        out[#out + 1] = t.id
                    end
                end
            end
        end
    end
    return out
end

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local pp = fetchNextData("/en/novel-list.json", "page=" .. tostring(page) .. "&orderBy=reader")
    if not pp then
        log_error("wtrlab: getCatalogList failed")
        return { items = {}, hasNext = false }
    end
    return pagePropsToResult(pp, page)
end

-- ── Search ──────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local params = "text=" .. url_encode(query) .. "&page=" .. tostring(page)
    local pp = fetchNextData("/en/novel-finder.json", params)
    if not pp then
        log_error("wtrlab: getCatalogSearch failed")
        return { items = {}, hasNext = false }
    end
    return pagePropsToResult(pp, page)
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    local el = html_select_first(body, "h1")
    if el then
        return string_trim(el.text)
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    local cover = html_attr(body, ".image-wrap img[alt]:not([aria-hidden])", "src")
    if cover ~= "" then
        return absUrl(cover)
    end
    return nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    local el = html_select_first(body, ".desc-wrap .description")
    if el then
        return string_trim(el.text)
    end
    return nil
end

-- NOTE: intentionally NOT using fetchPage — the hash must reflect fresh state
function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then
        return nil
    end
    local chapterCount = nil
    for _, block in ipairs(html_select(r.body, "div.items-center.text-center")) do
        local label = html_select_first(block.html, "span[translate='no']")
        if label and string_trim(label.text) == "Chapters" then
            -- The block is: <span translate="no">Chapters</span><span translate="no">753</span>
            -- (both spans carry translate='no', so selecting the first span returns
            -- the LABEL — extract the number from the block text instead)
            local m = regex_match(html_text(block.html), "(\\d+)")
            if m and m[1] then
                chapterCount = m[1]
                break
            end
        end
    end
    -- Combine with the book's serie_data.updated_at timestamp so that a
    -- re-translation / metadata edit that doesn't change the chapter count
    -- is still detected as an update. The first "updated_at":"..." in the
    -- raw HTML is pageProps.serie.serie_data.updated_at (the book's own row,
    -- serialized before recommendations / other_series / last_chapters).
    -- Full timestamp (not date-only) so same-day edits are caught.
    local updatedAt = string.match(r.body, '"updated_at":"([^"]+)"')
    if not chapterCount and not updatedAt then
        return nil
    end
    return (chapterCount or "?") .. "|" .. (updatedAt or "")
end

-- ── Chapter list ─────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local novelId = string.match(bookUrl, "/novel/(%d+)/")
    if not novelId then
        log_error("wtrlab: cannot extract novelId from " .. bookUrl)
        return {}
    end
    local slug = string.match(bookUrl, "/novel/%d+/([^/?#]+)") or ""
    if slug == "" then
        log_error("wtrlab: cannot extract slug from " .. bookUrl)
        return {}
    end

    local apiUrl = baseUrl .. "api/chapters/" .. novelId
    local r = http_get(apiUrl, {
        headers = {
            ["Referer"] = bookUrl
        }
    })
    if not r.success then
        log_error("wtrlab: chapters API failed code=" .. tostring(r.code))
        return {}
    end

    local data = json_parse(r.body)
    if not data or not data.chapters then
        log_error("wtrlab: cannot parse chapters JSON")
        return {}
    end

    local chapters = {}
    for i = 1, #data.chapters do
        local ch = data.chapters[i]
        local order = ch.order or i
        local title = ch.title or ("Chapter " .. tostring(order))
        local chUrl = baseUrl .. "novel/" .. novelId .. "/" .. slug .. "/chapter-" .. tostring(order)
        table.insert(chapters, {
            title = tostring(order) .. ": " .. title,
            url = chUrl
        })
    end

    log_info("wtrlab: loaded " .. tostring(#chapters) .. " chapters for novelId=" .. novelId)
    return chapters
end

-- ── Chapter text ─────────────────────────────────────────────────────────────

local function cleanParagraph(text)
    text = string_normalize(text)
    -- Strip repeated chapter headers at the start
    text = regex_replace(text, "(?i)\\A[\\s\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    -- Strip translator/editor credit lines (line-anchored)
    text = regex_replace(text,
        "(?i)^[\\s\\uFEFF]*(Translator|Editor|Proofreader|Translated\\s+by|Edited\\s+by|Read\\s+(at|on|latest))[:\\s\\u2014-][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    -- Strip watermark lines (whole-line match, word-bounded — avoids eating story text)
    text = regex_replace(text,
        "(?i)^[^\\n\\r]{0,100}\\b(patreon(?:\\.com)?|ko-fi|paypal(?:\\.me)?|discord(?:\\.gg|\\.com)|wtr-lab(?:\\.com)?)\\b[^\\n\\r]{0,100}(\\r?\\n|$)", "")
    return string_trim(text)
end

local function applyGlossaryAndPatches(text, glossary, patches)
    if glossary then
        for idx, term in pairs(glossary) do
            local marker1 = "※" .. tostring(idx) .. "⛬"
            local marker2 = "※" .. tostring(idx) .. "〓"
            text = text:gsub(marker1, term)
            text = text:gsub(marker2, term)
        end
    end
    if patches then
        for _, patch in ipairs(patches) do
            if patch.zh and patch.en then
                text = text:gsub(patch.zh, patch.en)
            end
        end
    end
    return text
end

local function buildParagraphs(resolvedBody, glossary, patches)
    local paragraphs = {}
    local bodyArray = json_parse(resolvedBody)

    if type(bodyArray) == "table" and bodyArray[1] ~= nil then
        for _, item in ipairs(bodyArray) do
            if type(item) == "string" then
                local text = cleanParagraph(item)
                if text ~= "[image]" and text ~= "" then
                    text = applyGlossaryAndPatches(text, glossary, patches)
                    if text ~= "" then
                        table.insert(paragraphs, text)
                    end
                end
            end
        end
    else
        for _, line in ipairs(string_split(resolvedBody, "\n")) do
            local text = string_trim(line)
            if text ~= "" then
                table.insert(paragraphs, text)
            end
        end
    end

    return paragraphs
end

-- POST /api/reader/get with Turnstile-aware retry.
-- Returns the parsed JSON table, or nil after exhausting retries (error raised).
local function fetchChapterJson(novelId, chapterNo, chapterUrl, translateParam)
    local requestBody = json_stringify({
        translate = translateParam,
        language = "none",
        raw_id = novelId,
        chapter_no = chapterNo,
        retry = false,
        force_retry = false
    })

    local MAX_ATTEMPTS = 3
    local lastTurnstileCount = nil

    for attempt = 1, MAX_ATTEMPTS do
        local r = http_post(baseUrl .. "api/reader/get", requestBody, {
            headers = {
                ["Content-Type"] = "application/json",
                ["Referer"] = chapterUrl,
                ["Origin"] = regex_replace(baseUrl, "/$", "")
            }
        })

        if not r.success then
            log_error("wtrlab: API reader/get failed code=" .. tostring(r.code) .. " body=" .. tostring(r.body):sub(1, 120))
            error("WTR-Lab API request failed (code " .. tostring(r.code) .. "). " ..
                "If this mentions Cloudflare, complete the challenge once in the integrated browser and retry.")
        end

        local json = json_parse(r.body)
        if not json then
            error("WTR-Lab returned an unexpected response (not JSON). " ..
                "This is usually a Cloudflare challenge — open the chapter once in the integrated browser, then retry.")
        end

        if json.requireTurnstile then
            lastTurnstileCount = json.count
            if attempt < MAX_ATTEMPTS then
                -- The block is enforced per backend instance and is intermittent:
                -- a short backoff often lands on a healthy instance.
                local waitMs = 2500 * attempt
                log_info("wtrlab: site security check (count=" .. tostring(json.count) ..
                    "), retry " .. attempt .. "/" .. tostring(MAX_ATTEMPTS - 1) .. " in " .. waitMs .. "ms")
                sleep(waitMs)
            end
        elseif json.success == false then
            local errCode = json.code or "?"
            local errMsg = json.message or json.error or "Unknown API error"
            error("[" .. tostring(errCode) .. "] " .. errMsg)
        else
            return json
        end
    end

    error("WTR-Lab security check required (rate limit reached, " ..
        tostring(lastTurnstileCount) .. "/15 requests).\n" ..
        "Fix: open ANY chapter of this book in the integrated browser (browser icon on the book/chapter page), " ..
        "tap 'Verify you are human' once, then download again. This resets the limit for your IP.")
end

function getChapterText(html, chapterUrl)
    if not chapterUrl or chapterUrl == "" then
        chapterUrl = html_attr(html, "link[rel='canonical']", "href")
    end
    if not chapterUrl or chapterUrl == "" then
        log_error("wtrlab: no chapterUrl available")
        return ""
    end

    log_info("wtrlab: getChapterText url=" .. chapterUrl)

    local novelId = string.match(chapterUrl, "/novel/(%d+)/")
    if not novelId then
        log_error("wtrlab: 'novel' not found in URL: " .. chapterUrl)
        return ""
    end

    local chapterNo = tonumber(string.match(chapterUrl, "/chapter%-(%d+)")) or 1
    local mode = getMode()
    local translateParam = (mode == "raw") and "web" or "ai"

    log_info("wtrlab: novelId=" .. novelId .. " chapterNo=" .. tostring(chapterNo) .. " translate=" .. translateParam)

    -- Optional pacing between chapter fetches (may reduce security-check triggers)
    local delay = getChapterDelay()
    if delay > 0 then
        sleep(delay)
    end

    local json = fetchChapterJson(novelId, chapterNo, chapterUrl, translateParam)

    local outerData = json.data
    local data = nil
    if outerData then
        data = outerData.data or outerData
    end
    if not data then
        log_error("wtrlab: no 'data' in response")
        return ""
    end

    local body = data.body
    if not body then
        log_error("wtrlab: no 'body' in data")
        return ""
    end

    local rawBody
    if type(body) == "table" then
        rawBody = json_stringify(body)
    else
        rawBody = tostring(body)
    end

    if rawBody == "" or rawBody == "null" then
        log_error("wtrlab: body is empty")
        return ""
    end

    local resolvedBody = decryptBody(rawBody)
    if not resolvedBody then
        error("WTR-Lab chapter body is encrypted and could not be decrypted " ..
            "(local AES-GCM failed and the fallback proxy is unreachable). Try again later.")
    end

    -- ── v2 book-level glossary (Chinese original → preferred translation) ──
    local termByOriginal = {}

    if mode ~= "raw" then
        local cache = termCache[novelId]

        if cache then
            termByOriginal = cache.termByOriginal
        else
            local v2Url = baseUrl .. "api/v2/reader/terms/" .. novelId .. ".json"
            local v2r = http_get(v2Url, {
                headers = {
                    ["Referer"] = chapterUrl,
                    ["Origin"] = regex_replace(baseUrl, "/$", "")
                }
            })
            if v2r.success then
                local v2data = json_parse(v2r.body)
                local termsArray = nil
                if v2data and type(v2data) == "table" and v2data.glossaries then
                    for _, glossary in ipairs(v2data.glossaries) do
                        if glossary.data and glossary.data.terms then
                            termsArray = glossary.data.terms
                            break
                        end
                    end
                end
                if termsArray then
                    for _, term in ipairs(termsArray) do
                        local original = term[2]
                        local translations = term[1]
                        if original and original ~= "" and type(translations) == "table" and translations[1] then
                            termByOriginal[original] = translations[1]
                        end
                    end
                    termCache[novelId] = { termByOriginal = termByOriginal }
                end
            end
        end
    end

    -- ── Chapter-level glossary (※idx⛬ / ※idx〓 markers) ─────────────────────
    local glossary = {}
    if mode ~= "raw" and data.glossary_data and data.glossary_data.terms then
        local terms = data.glossary_data.terms
        for i = 1, #terms do
            local termEntry = terms[i]
            if type(termEntry) == "table" then
                local idx = i - 1 -- 0-based, matches the ※idx⛬ markers
                local raw = termEntry[1] or ""
                local original = termEntry[2] or ""
                local matched = original ~= "" and termByOriginal[original]
                local termValue = matched or raw
                if termValue ~= "" then
                    glossary[idx] = termValue
                end
            end
        end
    end

    -- ── Patch list (zh → en replacements) ────────────────────────────────────
    local patches = {}
    if data.patch then
        for _, patchItem in ipairs(data.patch) do
            if patchItem.zh and patchItem.en and patchItem.zh ~= "" then
                table.insert(patches, {
                    zh = patchItem.zh,
                    en = patchItem.en
                })
            end
        end
    end

    local paragraphs = buildParagraphs(resolvedBody, glossary, patches)

    if #paragraphs == 0 then
        log_error("wtrlab: 0 paragraphs parsed")
        return ""
    end

    log_info("wtrlab: parsed " .. tostring(#paragraphs) .. " paragraphs")

    return table.concat(paragraphs, "\n\n")
end

-- ── Settings schema ──────────────────────────────────────────────────────────

function getSettingsSchema()
    return {{
        key = PREF_MODE,
        type = "select",
        label = "Translation Mode",
        current = getMode(),
        options = {{
            value = "ai",
            label = "AI (Beta)"
        }, {
            value = "raw",
            label = "Raw (Web)"
        }}
    }, {
        key = PREF_DELAY,
        type = "select",
        label = "Chapter Fetch Delay (may reduce 'Security Check' triggers)",
        current = tostring(getChapterDelay()),
        options = {{
            value = "0",
            label = "None"
        }, {
            value = "2000",
            label = "2 seconds"
        }, {
            value = "4000",
            label = "4 seconds"
        }, {
            value = "6000",
            label = "6 seconds"
        }}
    }}
end

-- ── Book metadata ────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then
        return {}
    end

    local genres = {}
    for _, el in ipairs(html_select(body, "a[href*='novel-list?genre='] span")) do
        local label = string_trim(el.text)
        if label ~= "" then
            table.insert(genres, label)
        end
    end

    return genres
end

function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    return extractRating(body)
end

function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    for _, block in ipairs(html_select(body, "div.items-center.text-center")) do
        if block.text and block.text:find("Status") then
            local st = string.match(block.text, "Status%s+(.+)")
            if st then
                st = string_clean(st)
                return st ~= "" and st or nil
            end
        end
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    return string.match(body, '"updated_at":"(%d%d%d%d%-%d%d%-%d%d)')
end

-- ── Filter list (full parity with wtr-lab.com/en/novel-finder) ───────────────

function getFilterList()
    return {
        {
            type = "select",
            key = "orderBy",
            label = "Order by",
            defaultValue = "update",
            options = {
                {value = "update", label = "Update Date"},
                {value = "date", label = "Addition Date"},
                {value = "random", label = "Random"},
                {value = "daily_rank", label = "Daily View"},
                {value = "weekly_rank", label = "Weekly View"},
                {value = "monthly_rank", label = "Monthly View"},
                {value = "view", label = "All-Time View"},
                {value = "name", label = "Name"},
                {value = "reader", label = "Reader"},
                {value = "chapter", label = "Chapter Count"},
                {value = "character", label = "Character Count"},
                {value = "rating", label = "Rating"},
                {value = "total_rate", label = "Review Count"},
                {value = "vote", label = "Vote Count"},
                {value = "weighted", label = "Top Rated (weighted)"}
            }
        },
        {
            type = "select",
            key = "order",
            label = "Order",
            defaultValue = "desc",
            options = {
                {value = "desc", label = "Descending"},
                {value = "asc", label = "Ascending"}
            }
        },
        {
            type = "select",
            key = "status",
            label = "Status",
            defaultValue = "all",
            options = {
                {value = "all", label = "All"},
                {value = "ongoing", label = "Ongoing"},
                {value = "completed", label = "Completed"},
                {value = "hiatus", label = "Hiatus"},
                {value = "dropped", label = "Dropped"}
            }
        },
        {
            type = "select",
            key = "release_status",
            label = "Release Status",
            defaultValue = "all",
            options = {
                {value = "all", label = "All"},
                {value = "released", label = "Released"},
                {value = "voting", label = "On Voting"}
            }
        },
        {
            type = "select",
            key = "addition_age",
            label = "Added",
            defaultValue = "all",
            options = {
                {value = "all", label = "Any Time"},
                {value = "day", label = "< 2 Days"},
                {value = "week", label = "< 1 Week"},
                {value = "month", label = "< 1 Month"},
                {value = "3month", label = "< 3 Months"},
                {value = "6month", label = "< 6 Months"},
                {value = "year", label = "< 1 Year"},
                {value = "last_month", label = "Last Month"},
                {value = "last_year", label = "Last Year"},
                {value = "this_year", label = "This Year"}
            }
        },
        {
            type = "select",
            key = "count_chapters",
            label = "Chapter Count",
            defaultValue = "",
            options = {
                {value = "", label = "Any"},
                {value = "100", label = "100+"},
                {value = "150", label = "150+"},
                {value = "200", label = "200+"},
                {value = "250", label = "250+"},
                {value = "500", label = "500+"},
                {value = "750", label = "750+"},
                {value = "1000", label = "1000+"},
                {value = "1500", label = "1500+"},
                {value = "2000", label = "2000+"},
                {value = "2500", label = "2500+"},
                {value = "5000", label = "5000+"}
            }
        },
        {
            type = "select",
            key = "count_mode",
            label = "Count Mode",
            defaultValue = "min",
            options = {
                {value = "min", label = "At Least"},
                {value = "max", label = "At Most"}
            }
        },
        {
            type = "select",
            key = "count_characters",
            label = "Character Count",
            defaultValue = "",
            options = {
                {value = "", label = "Any"},
                {value = "100000", label = "100k+"},
                {value = "250000", label = "250k+"},
                {value = "500000", label = "500k+"},
                {value = "750000", label = "750k+"},
                {value = "1000000", label = "1M+"},
                {value = "1500000", label = "1.5M+"},
                {value = "2000000", label = "2M+"},
                {value = "2500000", label = "2.5M+"},
                {value = "3000000", label = "3M+"},
                {value = "4000000", label = "4M+"},
                {value = "5000000", label = "5M+"},
                {value = "7500000", label = "7.5M+"},
                {value = "10000000", label = "10M+"}
            }
        },
        {
            type = "select",
            key = "min_rating",
            label = "Minimum Rating",
            defaultValue = "",
            options = {
                {value = "", label = "Any"},
                {value = "1.0", label = "1.0+"},
                {value = "1.5", label = "1.5+"},
                {value = "2.0", label = "2.0+"},
                {value = "2.5", label = "2.5+"},
                {value = "3.0", label = "3.0+"},
                {value = "3.5", label = "3.5+"},
                {value = "4.0", label = "4.0+"},
                {value = "4.5", label = "4.5+"},
                {value = "5.0", label = "5.0"}
            }
        },
        {
            type = "select",
            key = "min_reviews",
            label = "Minimum Reviews",
            defaultValue = "",
            options = {
                {value = "", label = "Any"},
                {value = "5", label = "5+"},
                {value = "10", label = "10+"},
                {value = "15", label = "15+"},
                {value = "20", label = "20+"},
                {value = "25", label = "25+"},
                {value = "30", label = "30+"},
                {value = "35", label = "35+"},
                {value = "40", label = "40+"},
                {value = "45", label = "45+"},
                {value = "50", label = "50+"}
            }
        },
        {
            type = "select",
            key = "genre_operator",
            label = "Genre (And/Or)",
            defaultValue = "and",
            options = {
                {value = "and", label = "And"},
                {value = "or", label = "Or"}
            }
        },
        {
            type = "tristate",
            key = "genres",
            label = "Genres",
            options = {
                                {value = "1", label = "Action"}, {value = "2", label = "Adult"}, {value = "3", label = "Adventure"},
                {value = "4", label = "Comedy"}, {value = "5", label = "Drama"}, {value = "6", label = "Ecchi"},
                {value = "7", label = "Erciyuan"}, {value = "8", label = "Fan-fiction"}, {value = "9", label = "Fantasy"},
                {value = "10", label = "Game"}, {value = "11", label = "Gender Bender"}, {value = "12", label = "Harem"},
                {value = "13", label = "Historical"}, {value = "14", label = "Horror"}, {value = "15", label = "Josei"},
                {value = "16", label = "Martial Arts"}, {value = "17", label = "Mature"}, {value = "18", label = "Mecha"},
                {value = "19", label = "Military"}, {value = "20", label = "Mystery"}, {value = "21", label = "Psychological"},
                {value = "22", label = "Romance"}, {value = "23", label = "School Life"}, {value = "24", label = "Sci-fi"},
                {value = "25", label = "Seinen"}, {value = "26", label = "Shoujo"}, {value = "27", label = "Shoujo-ai"},
                {value = "28", label = "Shounen"}, {value = "29", label = "Shounen-ai"}, {value = "30", label = "Slice of Life"},
                {value = "31", label = "Smut"}, {value = "32", label = "Sports"}, {value = "33", label = "Supernatural"},
                {value = "34", label = "Tragedy"}, {value = "35", label = "Urban Life"}, {value = "36", label = "Wuxia"},
                {value = "37", label = "Xianxia"}, {value = "38", label = "Xuanhuan"}, {value = "39", label = "Yaoi"},
                {value = "40", label = "Yuri"},
            }
        },
        {
            type = "select",
            key = "tag_operator",
            label = "Tag (And/Or)",
            defaultValue = "and",
            options = {
                {value = "and", label = "And"},
                {value = "or", label = "Or"}
            }
        },
        -- Tag Search (free-text; resolves to tag IDs via tagSearchResolve)
        {
            type = "text",
            key = "tag_search_inc",
            label = "Tag Search (include)",
            defaultValue = ""
        },
        {
            type = "text",
            key = "tag_search_exc",
            label = "Tag Search (exclude)",
            defaultValue = ""
        },
-- 11 grouped tag filters (auto-generated by scripts/gen_grouped_tags.py
--  from research/real_tags.json -- 882 tags across 11 site categories).
--  Do not hand-edit; re-run the generator after refreshing real_tags.json.
-- 11 grouped tag filters (auto-generated by scripts/gen_grouped_tags.py
--  from research/real_tags.json -- 882 tags across 11 site categories).
--  Do not hand-edit; re-run the generator after refreshing real_tags.json.
        {
            type = "tristate",
            key = "tags_protagonist",
            label = "Protagonist Archetypes (190)",
            options = {
                {value = "1", label = "Abandoned Children"}, {value = "3", label = "Absent Parents"}, {value = "6", label = "Accelerated Growth"},
                {value = "19", label = "Adopted Children"}, {value = "20", label = "Adopted Protagonist"}, {value = "24", label = "Age Progression"},
                {value = "25", label = "Age Regression"}, {value = "26", label = "Aggressive Characters"}, {value = "36", label = "Androgynous Characters"},
                {value = "42", label = "Anti-social Protagonist"}, {value = "43", label = "Antihero Protagonist"}, {value = "46", label = "Apathetic Protagonist"},
                {value = "49", label = "Appearance Different from Actual Age"}, {value = "56", label = "Arrogant Characters"}, {value = "63", label = "Autism"},
                {value = "65", label = "Average-looking Protagonist"}, {value = "67", label = "Awkward Protagonist"}, {value = "81", label = "Beautiful Female Lead"},
                {value = "871", label = "Behind-the-Scenes Mastermind"}, {value = "86", label = "Bisexual Protagonist"}, {value = "87", label = "Black Belly"},
                {value = "91", label = "Blind Protagonist"}, {value = "99", label = "Bookworm"}, {value = "111", label = "Calm Protagonist"},
                {value = "114", label = "Carefree Protagonist"}, {value = "115", label = "Caring Protagonist"}, {value = "116", label = "Cautious Protagonist"},
                {value = "118", label = "Character Growth"}, {value = "119", label = "Charismatic Protagonist"}, {value = "120", label = "Charming Protagonist"},
                {value = "125", label = "Child Protagonist"}, {value = "130", label = "Childish Protagonist"}, {value = "131", label = "Chuunibyou"},
                {value = "134", label = "Clever Protagonist"}, {value = "142", label = "Cold Protagonist"}, {value = "145", label = "Coma"},
                {value = "147", label = "Coming of Age"}, {value = "150", label = "Confident Protagonist"}, {value = "158", label = "Couple Growth"},
                {value = "161", label = "Cowardly Protagonist"}, {value = "165", label = "Cross-dressing"}, {value = "171", label = "Cunning Protagonist"},
                {value = "172", label = "Curious Protagonist"}, {value = "175", label = "Cute Protagonist"}, {value = "182", label = "Dead Protagonist"},
                {value = "186", label = "Delinquents"}, {value = "192", label = "Dense Protagonist"}, {value = "197", label = "Determined Protagonist"},
                {value = "200", label = "Disabilities"}, {value = "203", label = "Dishonest Protagonist"}, {value = "204", label = "Distrustful Protagonist"},
                {value = "212", label = "Doting Older Siblings"}, {value = "213", label = "Doting Parents"}, {value = "231", label = "Elderly Protagonist"},
                {value = "234", label = "Emotionally Weak Protagonist"}, {value = "240", label = "Enlightenment"}, {value = "246", label = "Evil Protagonist"},
                {value = "248", label = "Evolution"}, {value = "254", label = "Fallen Nobility"}, {value = "260", label = "Famous Parents"},
                {value = "261", label = "Famous Protagonist"}, {value = "268", label = "Fast Learner"}, {value = "269", label = "Fat Protagonist"},
                {value = "270", label = "Fat to Fit"}, {value = "272", label = "Fearless Protagonist"}, {value = "275", label = "Female Protagonist"},
                {value = "276", label = "Female to Male"}, {value = "287", label = "Forgetful Protagonist"}, {value = "288", label = "Former Hero"},
                {value = "292", label = "Fujoshi"}, {value = "302", label = "Genderless Protagonist"}, {value = "306", label = "Genius Protagonist"},
                {value = "310", label = "Glasses-wearing Protagonist"}, {value = "312", label = "God Protagonist"}, {value = "325", label = "Half-human Protagonist"},
                {value = "327", label = "Handsome Male Lead"}, {value = "328", label = "Hard-Working Protagonist"}, {value = "330", label = "Harsh Training"},
                {value = "331", label = "Hated Protagonist"}, {value = "803", label = "Heaven Defying Comprehension"}, {value = "337", label = "Helpful Protagonist"},
                {value = "342", label = "Hiding True Abilities"}, {value = "343", label = "Hiding True Identity"}, {value = "344", label = "Hikikomori"},
                {value = "346", label = "Honest Protagonist"}, {value = "348", label = "Hot-blooded Protagonist"}, {value = "350", label = "Human Weapon"},
                {value = "352", label = "Humanoid Protagonist"}, {value = "849", label = "Immortal Protagonist"}, {value = "361", label = "Indecisive Protagonist"},
                {value = "363", label = "Inferiority Complex"}, {value = "369", label = "Introverted Protagonist"}, {value = "375", label = "Jobless Class"},
                {value = "382", label = "Kuudere"}, {value = "383", label = "Lack of Common Sense"}, {value = "387", label = "Lazy Protagonist"},
                {value = "392", label = "Limited Lifespan"}, {value = "395", label = "Loli"}, {value = "397", label = "Loner Protagonist"},
                {value = "407", label = "Low-key Protagonist"}, {value = "409", label = "Lucky Protagonist"}, {value = "417", label = "Male Protagonist"},
                {value = "418", label = "Male to Female"}, {value = "422", label = "Manipulative Characters"}, {value = "427", label = "Masochistic Characters"},
                {value = "432", label = "Mature Protagonist"}, {value = "444", label = "Mob Protagonist"}, {value = "447", label = "Modern Knowledge"},
                {value = "456", label = "Multiple Personalities"}, {value = "458", label = "Multiple Protagonists"}, {value = "467", label = "Mute Character"},
                {value = "468", label = "Mysterious Family Background"}, {value = "474", label = "Naive Protagonist"}, {value = "475", label = "Narcissistic Protagonist"},
                {value = "477", label = "Near-Death Experience"}, {value = "479", label = "Neet"}, {value = "486", label = "Non-humanoid Protagonist"},
                {value = "500", label = "Orphans"}, {value = "503", label = "Outcasts"}, {value = "506", label = "Overpowered Protagonist"},
                {value = "508", label = "Pacifist Protagonist"}, {value = "516", label = "Past Trauma"}, {value = "518", label = "Personality Changes"},
                {value = "519", label = "Perverted Protagonist"}, {value = "530", label = "Playboys"}, {value = "531", label = "Playful Protagonist"},
                {value = "535", label = "Polite Protagonist"}, {value = "539", label = "Poor Protagonist"}, {value = "547", label = "Pragmatic Protagonist"},
                {value = "551", label = "Previous Life Talent"}, {value = "555", label = "Proactive Protagonist"}, {value = "560", label = "Protagonist Strong from the Start"},
                {value = "563", label = "Psychopaths"}, {value = "565", label = "Quiet Characters"}, {value = "566", label = "Quirky Characters"},
                {value = "569", label = "Race Change"}, {value = "829", label = "Reborn"}, {value = "831", label = "Reborn as the Villain"},
                {value = "574", label = "Reincarnated as a Monster"}, {value = "575", label = "Reincarnated as an Object"}, {value = "577", label = "Reincarnated in Another World"},
                {value = "578", label = "Reincarnation"}, {value = "580", label = "Reluctant Protagonist"}, {value = "584", label = "Returning from Another World"},
                {value = "590", label = "Righteous Protagonist"}, {value = "595", label = "Ruthless Protagonist"}, {value = "596", label = "Sadistic Characters"},
                {value = "598", label = "Salaryman"}, {value = "602", label = "Schizophrenia"}, {value = "605", label = "Sealed Power"},
                {value = "606", label = "Second Chance"}, {value = "611", label = "Secretive Protagonist"}, {value = "616", label = "Selfish Protagonist"},
                {value = "617", label = "Selfless Protagonist"}, {value = "618", label = "Seme Protagonist"}, {value = "621", label = "Sentimental Protagonist"},
                {value = "630", label = "Shameless Protagonist"}, {value = "633", label = "Sharp-tongued Characters"}, {value = "637", label = "Shota"},
                {value = "641", label = "Shy Characters"}, {value = "842", label = "Simultaneous Transmigration"}, {value = "651", label = "Skill Assimilation"},
                {value = "653", label = "Skill Creation"}, {value = "655", label = "Slave Protagonist"}, {value = "658", label = "Slow Growth at Start"},
                {value = "674", label = "Stoic Characters"}, {value = "676", label = "Straight Seme"}, {value = "677", label = "Straight Uke"},
                {value = "682", label = "Strong to Stronger"}, {value = "683", label = "Stubborn Protagonist"}, {value = "687", label = "Sudden Strength Gain"},
                {value = "690", label = "Summoned Hero"}, {value = "711", label = "Timid Protagonist"}, {value = "712", label = "Tomboyish Female Lead"},
                {value = "715", label = "Tragic Past"}, {value = "717", label = "Transmigration"}, {value = "718", label = "Transplanted Memories"},
                {value = "719", label = "Transported into a Game World"}, {value = "721", label = "Transported to Another World"}, {value = "722", label = "Trap"},
                {value = "724", label = "Trickster"}, {value = "727", label = "Twisted Personality"}, {value = "728", label = "Ugly Protagonist"},
                {value = "810", label = "Undead Protagonist"}, {value = "731", label = "Underestimated Protagonist"}, {value = "736", label = "Unlucky Protagonist"},
                {value = "737", label = "Unreliable Narrator"}, {value = "741", label = "Villainess Noble Girls"}, {value = "749", label = "Weak Protagonist"},
                {value = "750", label = "Weak to Strong"},
            }
        },

        {
            type = "tristate",
            key = "tags_power_systems",
            label = "Power Systems (99)",
            options = {
                {value = "2", label = "Ability Steal"}, {value = "27", label = "Alchemy"}, {value = "37", label = "Androids"},
                {value = "41", label = "Anti-Magic"}, {value = "48", label = "Appearance Changes"}, {value = "822", label = "Array"},
                {value = "59", label = "Artificial Intelligence"}, {value = "64", label = "Automatons"}, {value = "85", label = "Biochip"},
                {value = "92", label = "Blood Manipulation"}, {value = "93", label = "Bloodlines"}, {value = "94", label = "Body Swap"},
                {value = "95", label = "Body Tempering"}, {value = "101", label = "Brainwashing"}, {value = "122", label = "Cheats"},
                {value = "827", label = "Class Awakening"}, {value = "136", label = "Clones"}, {value = "149", label = "Conditional Power"},
                {value = "807", label = "Copy"}, {value = "168", label = "Cryostasis"}, {value = "169", label = "Cultivation"},
                {value = "173", label = "Curses"}, {value = "178", label = "Dao Companion"}, {value = "179", label = "Dao Comprehension"},
                {value = "190", label = "Demonic Cultivation Technique"}, {value = "797", label = "Devouring"}, {value = "205", label = "Divination"},
                {value = "206", label = "Divine Protection"}, {value = "220", label = "Dungeon Master"}, {value = "230", label = "Eidetic Memory"},
                {value = "232", label = "Elemental Magic"}, {value = "250", label = "Exorcism"}, {value = "251", label = "Eye Powers"},
                {value = "808", label = "Faith Dependent Deities"}, {value = "267", label = "Fast Cultivation"}, {value = "278", label = "Firearms"},
                {value = "295", label = "Galge"}, {value = "784", label = "Game Creator"}, {value = "297", label = "Game Elements"},
                {value = "298", label = "Game Ranking System"}, {value = "781", label = "Gao Wu"}, {value = "304", label = "Genetic Modifications"},
                {value = "305", label = "Genies"}, {value = "315", label = "Godly Powers"}, {value = "320", label = "Grinding"},
                {value = "332", label = "Healers"}, {value = "335", label = "Heavenly Tribulation"}, {value = "341", label = "Hidden Abilities"},
                {value = "354", label = "Hypnotism"}, {value = "365", label = "Inscriptions"}, {value = "371", label = "Invisibility"},
                {value = "390", label = "Level System"}, {value = "401", label = "Lottery"}, {value = "410", label = "Magic"},
                {value = "412", label = "Magic Formations"}, {value = "413", label = "Magical Girls"}, {value = "414", label = "Magical Space"},
                {value = "415", label = "Magical Technology"}, {value = "426", label = "Martial Spirits"}, {value = "439", label = "Mind Control"},
                {value = "443", label = "MMORPG"}, {value = "792", label = "Mortal Flow"}, {value = "478", label = "Necromancer"},
                {value = "496", label = "Onmyouji"}, {value = "502", label = "Otome Game"}, {value = "511", label = "Parasites"},
                {value = "526", label = "Pill Based Cultivation"}, {value = "527", label = "Pill Concocting"}, {value = "542", label = "Possession"},
                {value = "548", label = "Precognition"}, {value = "793", label = "Proficiency"}, {value = "561", label = "Protagonist with Multiple Bodies"},
                {value = "562", label = "Psychic Powers"}, {value = "830", label = "Reality-Game Fusion"}, {value = "576", label = "Reincarnated in a Game World"},
                {value = "583", label = "Resurrection"}, {value = "615", label = "Seeing Things Other Humans Can't"}, {value = "629", label = "Sexual Cultivation Technique"},
                {value = "631", label = "Shapeshifters"}, {value = "632", label = "Sharing A Body"}, {value = "811", label = "Sign In"},
                {value = "786", label = "Simulator"}, {value = "652", label = "Skill Books"}, {value = "663", label = "Soul Power"},
                {value = "665", label = "Spatial Manipulation"}, {value = "667", label = "Special Abilities"}, {value = "670", label = "Spirit Users"},
                {value = "855", label = "Stand User"}, {value = "691", label = "Summoning Magic"}, {value = "693", label = "Survival Game"},
                {value = "694", label = "Sword And Magic"}, {value = "696", label = "System"}, {value = "707", label = "Time Manipulation"},
                {value = "716", label = "Transformation Ability"}, {value = "732", label = "Unique Cultivation Technique"}, {value = "735", label = "Unlimited Flow"},
                {value = "742", label = "Virtual Reality"}, {value = "753", label = "Wishes"}, {value = "755", label = "Wizards"},
            }
        },

        {
            type = "tristate",
            key = "tags_worldbuilding",
            label = "Worldbuilding (56)",
            options = {
                {value = "873", label = "1900s"}, {value = "874", label = "1910s"}, {value = "875", label = "1920s"},
                {value = "876", label = "1930s"}, {value = "877", label = "1940s"}, {value = "878", label = "1950s"},
                {value = "879", label = "1960s"}, {value = "880", label = "1970s"}, {value = "881", label = "1980s"},
                {value = "882", label = "1990s"}, {value = "883", label = "2000s"}, {value = "884", label = "2010s"},
                {value = "30", label = "Alternate World"}, {value = "32", label = "Amusement Park"}, {value = "34", label = "Ancient China"},
                {value = "35", label = "Ancient Times"}, {value = "47", label = "Apocalypse"}, {value = "133", label = "Classic"},
                {value = "221", label = "Dungeons"}, {value = "223", label = "Dystopia"}, {value = "243", label = "European Ambience"},
                {value = "265", label = "Fantasy World"}, {value = "294", label = "Futuristic Setting"}, {value = "301", label = "Gate to Another World"},
                {value = "334", label = "Heaven"}, {value = "336", label = "Hell"}, {value = "347", label = "Hospital"},
                {value = "368", label = "Interdimensional Travel"}, {value = "391", label = "Library"}, {value = "400", label = "Lost Civilizations"},
                {value = "434", label = "Medieval"}, {value = "446", label = "Modern Day"}, {value = "450", label = "Monster Society"},
                {value = "454", label = "Mpreg"}, {value = "459", label = "Multiple Realms"}, {value = "460", label = "Multiple Reincarnated Individuals"},
                {value = "461", label = "Multiple Timelines"}, {value = "462", label = "Multiple Transported Individuals"}, {value = "493", label = "Omegaverse"},
                {value = "505", label = "Outer Space"}, {value = "510", label = "Parallel Worlds"}, {value = "544", label = "Post-apocalyptic"},
                {value = "554", label = "Prison"}, {value = "582", label = "Restaurant"}, {value = "828", label = "Spiritual Energy Revival"},
                {value = "835", label = "Steampunk"}, {value = "699", label = "Technological Gap"}, {value = "795", label = "Three Kingdoms"},
                {value = "706", label = "Time Loop"}, {value = "708", label = "Time Paradox"}, {value = "710", label = "Time Travel"},
                {value = "720", label = "Transported Modern Structure"}, {value = "723", label = "Tribal Society"}, {value = "756", label = "World Hopping"},
                {value = "757", label = "World Travel"}, {value = "758", label = "World Tree"},
            }
        },

        {
            type = "tristate",
            key = "tags_socio_political",
            label = "Socio-Political Structures (71)",
            options = {
                {value = "5", label = "Academy"}, {value = "29", label = "All-Girls School"}, {value = "51", label = "Aristocracy"},
                {value = "52", label = "Arms Dealers"}, {value = "53", label = "Army"}, {value = "54", label = "Army Building"},
                {value = "61", label = "Assassins"}, {value = "75", label = "Battle Academy"}, {value = "76", label = "Battle Competition"},
                {value = "100", label = "Boss-Subordinate Relationship"}, {value = "108", label = "Business Management"}, {value = "806", label = "Business Wars"},
                {value = "132", label = "Clan Building"}, {value = "137", label = "Clubs"}, {value = "153", label = "Contracts"},
                {value = "156", label = "Cosmic Wars"}, {value = "159", label = "Court Official"}, {value = "162", label = "Crafting"},
                {value = "185", label = "Debts"}, {value = "218", label = "Drugs"}, {value = "226", label = "Earth Invasion"},
                {value = "228", label = "Economics"}, {value = "235", label = "Empires"}, {value = "242", label = "Eunuch"},
                {value = "247", label = "Evil Religions"}, {value = "258", label = "Family Business"}, {value = "266", label = "Farming"},
                {value = "282", label = "Fleet Battles"}, {value = "296", label = "Gambling"}, {value = "300", label = "Gangs"},
                {value = "303", label = "Generals"}, {value = "308", label = "Gladiators"}, {value = "322", label = "Guilds"},
                {value = "353", label = "Hunters"}, {value = "358", label = "Imperial Harem"}, {value = "362", label = "Industrialization"},
                {value = "376", label = "JSDF"}, {value = "379", label = "Kingdom Building"}, {value = "380", label = "Kingdoms"},
                {value = "381", label = "Knights"}, {value = "388", label = "Leadership"}, {value = "823", label = "Lord"},
                {value = "408", label = "Loyal Subordinates"}, {value = "420", label = "Management"}, {value = "428", label = "Master-Disciple Relationship"},
                {value = "429", label = "Master-Servant Relationship"}, {value = "431", label = "Matriarchy"}, {value = "437", label = "Military"},
                {value = "448", label = "Money Grubber"}, {value = "485", label = "Nobles"}, {value = "529", label = "Pirates"},
                {value = "536", label = "Politics"}, {value = "540", label = "Poor to Rich"}, {value = "579", label = "Religions"},
                {value = "589", label = "Rich to Poor"}, {value = "594", label = "Royalty"}, {value = "599", label = "Samurai"},
                {value = "609", label = "Secret Organizations"}, {value = "613", label = "Sect Development"}, {value = "656", label = "Slaves"},
                {value = "678", label = "Strategic Battles"}, {value = "680", label = "Strength-based Social Hierarchy"}, {value = "684", label = "Student Council"},
                {value = "685", label = "Student-Teacher Relationship"}, {value = "688", label = "Sudden Wealth"}, {value = "698", label = "Teamwork"},
                {value = "802", label = "Territory Management"}, {value = "702", label = "Terrorists"}, {value = "747", label = "War Records"},
                {value = "748", label = "Wars"}, {value = "751", label = "Wealthy Characters"},
            }
        },

        {
            type = "tristate",
            key = "tags_relationships",
            label = "Relationship Tropes (136)",
            options = {
                {value = "21", label = "Adultery"}, {value = "23", label = "Affair"}, {value = "33", label = "Anal"},
                {value = "55", label = "Arranged Marriage"}, {value = "77", label = "BDSM"}, {value = "82", label = "Bestiality"},
                {value = "84", label = "Bickering Couple"}, {value = "88", label = "Blackmail"}, {value = "90", label = "Blind Dates"},
                {value = "102", label = "Breast Fetish"}, {value = "103", label = "Broken Engagement"}, {value = "104", label = "Brother Complex"},
                {value = "105", label = "Brotherhood"}, {value = "124", label = "Child Abuse"}, {value = "127", label = "Childhood Friends"},
                {value = "128", label = "Childhood Love"}, {value = "129", label = "Childhood Promise"}, {value = "135", label = "Clingy Lover"},
                {value = "138", label = "Clumsy Love Interests"}, {value = "141", label = "Cold Love Interests"}, {value = "148", label = "Complex Family Relationships"},
                {value = "151", label = "Confinement"}, {value = "160", label = "Cousins"}, {value = "170", label = "Cunnilingus"},
                {value = "184", label = "Death of Loved Ones"}, {value = "198", label = "Devoted Love Interests"}, {value = "199", label = "Different Social Status"},
                {value = "207", label = "Divorce"}, {value = "211", label = "Doting Love Interests"}, {value = "225", label = "Early Romance"},
                {value = "236", label = "Enemies Become Allies"}, {value = "237", label = "Enemies Become Lovers"}, {value = "238", label = "Engagement"},
                {value = "249", label = "Exhibitionism"}, {value = "255", label = "Familial Love"}, {value = "257", label = "Family"},
                {value = "259", label = "Family Conflict"}, {value = "271", label = "Fated Lovers"}, {value = "273", label = "Fellatio"},
                {value = "279", label = "First Love"}, {value = "280", label = "First-time Intercourse"}, {value = "284", label = "Forced into a Relationship"},
                {value = "285", label = "Forced Living Arrangements"}, {value = "286", label = "Forced Marriage"}, {value = "290", label = "Friends Become Enemies"},
                {value = "848", label = "Furry Relationship"}, {value = "293", label = "Futanari"}, {value = "309", label = "Glasses-wearing Love Interests"},
                {value = "321", label = "Guardian Relationship"}, {value = "326", label = "Handjob"}, {value = "329", label = "Harem-seeking Protagonist"},
                {value = "351", label = "Human-Nonhuman Relationship"}, {value = "359", label = "Incest"}, {value = "373", label = "Jealousy"},
                {value = "377", label = "Kidnappings"}, {value = "378", label = "Kind Love Interests"}, {value = "385", label = "Late Romance"},
                {value = "398", label = "Long Separations"}, {value = "399", label = "Long-distance Relationship"}, {value = "402", label = "Love at First Sight"},
                {value = "403", label = "Love Interest Falls in Love First"}, {value = "404", label = "Love Rivals"}, {value = "405", label = "Love Triangles"},
                {value = "406", label = "Lovers Reunited"}, {value = "419", label = "Male Yandere"}, {value = "423", label = "Manly Gay Couple"},
                {value = "424", label = "Marriage"}, {value = "425", label = "Marriage of Convenience"}, {value = "430", label = "Masturbation"},
                {value = "438", label = "Mind Break"}, {value = "441", label = "Mismatched Couple"}, {value = "825", label = "More Children More Blessings"},
                {value = "480", label = "Netorare"}, {value = "481", label = "Netorase"}, {value = "482", label = "Netori"},
                {value = "488", label = "Nudity"}, {value = "490", label = "Obsessive Love"}, {value = "491", label = "Office Romance"},
                {value = "492", label = "Older Love Interests"}, {value = "495", label = "Online Romance"}, {value = "499", label = "Orgy"},
                {value = "504", label = "Outdoor Intercourse"}, {value = "507", label = "Overprotective Siblings"}, {value = "509", label = "Paizuri"},
                {value = "512", label = "Parent Complex"}, {value = "517", label = "Persistent Love Interests"}, {value = "537", label = "Polyandry"},
                {value = "538", label = "Polygamy"}, {value = "541", label = "Popular Love Interests"}, {value = "543", label = "Possessive Characters"},
                {value = "545", label = "Power Couple"}, {value = "549", label = "Pregnancy"}, {value = "550", label = "Pretend Lovers"},
                {value = "558", label = "Prostitutes"}, {value = "559", label = "Protagonist Falls in Love First"}, {value = "568", label = "R-18"},
                {value = "571", label = "Rape"}, {value = "572", label = "Rape Victim Becomes Lover"}, {value = "586", label = "Reverse Harem"},
                {value = "587", label = "Reverse Rape"}, {value = "588", label = "Reversible Couple"}, {value = "592", label = "Romantic Subplot"},
                {value = "607", label = "Secret Crush"}, {value = "610", label = "Secret Relationship"}, {value = "614", label = "Seduction"},
                {value = "619", label = "Senpai-Kouhai Relationship"}, {value = "626", label = "Sex Friends"}, {value = "627", label = "Sex Slaves"},
                {value = "628", label = "Sexual Abuse"}, {value = "638", label = "Shoujo-Ai Subplot"}, {value = "639", label = "Shounen-Ai Subplot"},
                {value = "642", label = "Sibling Rivalry"}, {value = "643", label = "Sibling's Care"}, {value = "644", label = "Siblings"},
                {value = "645", label = "Siblings Not Related by Blood"}, {value = "787", label = "Single Female Lead"}, {value = "649", label = "Single Parent"},
                {value = "650", label = "Sister Complex"}, {value = "654", label = "Slave Harem"}, {value = "659", label = "Slow Romance"},
                {value = "660", label = "Smart Couple"}, {value = "672", label = "Stalkers"}, {value = "673", label = "Stockholm Syndrome"},
                {value = "681", label = "Strong Love Interests"}, {value = "704", label = "Threesome"}, {value = "713", label = "Torture"},
                {value = "714", label = "Toys"}, {value = "725", label = "Tsundere"}, {value = "726", label = "Twins"},
                {value = "730", label = "Unconditional Love"}, {value = "738", label = "Unrequited Love"}, {value = "745", label = "Voyeurism"},
                {value = "760", label = "Yandere"}, {value = "762", label = "Younger Brothers"}, {value = "763", label = "Younger Love Interests"},
                {value = "764", label = "Younger Sisters"},
            }
        },

        {
            type = "tristate",
            key = "tags_narrative",
            label = "Narrative (46)",
            options = {
                {value = "31", label = "Amnesia"}, {value = "83", label = "Betrayal"}, {value = "112", label = "Cannibalism"},
                {value = "121", label = "Chat Rooms"}, {value = "143", label = "Collection of Short Stories"}, {value = "152", label = "Conflicting Loyalties"},
                {value = "163", label = "Crime"}, {value = "164", label = "Criminals"}, {value = "166", label = "Crossover"},
                {value = "183", label = "Death"}, {value = "187", label = "Delusions"}, {value = "798", label = "Eavesdropping"},
                {value = "241", label = "Episodic"}, {value = "281", label = "Flashbacks"}, {value = "318", label = "Gore"},
                {value = "349", label = "Human Experimentation"}, {value = "355", label = "Identity Crisis"}, {value = "356", label = "Imaginary Friend"},
                {value = "364", label = "Inheritance"}, {value = "367", label = "Interconnected Storylines"}, {value = "370", label = "Investigations"},
                {value = "824", label = "Life Script"}, {value = "455", label = "Multiple Identities"}, {value = "457", label = "Multiple POV"},
                {value = "463", label = "Murders"}, {value = "470", label = "Mysterious Past"}, {value = "471", label = "Mystery Solving"},
                {value = "483", label = "Nightmares"}, {value = "487", label = "Non-linear Storytelling"}, {value = "494", label = "Oneshot"},
                {value = "498", label = "Organized Crime"}, {value = "513", label = "Parody"}, {value = "515", label = "Past Plays a Big Role"},
                {value = "546", label = "Power Struggle"}, {value = "557", label = "Prophecies"}, {value = "573", label = "Rebellion"},
                {value = "585", label = "Revenge"}, {value = "591", label = "Rivalry"}, {value = "600", label = "Saving the World"},
                {value = "601", label = "Schemes And Conspiracies"}, {value = "608", label = "Secret Identity"}, {value = "612", label = "Secrets"},
                {value = "636", label = "Short Story"}, {value = "692", label = "Survival"}, {value = "705", label = "Thriller"},
                {value = "709", label = "Time Skip"},
            }
        },

        {
            type = "tristate",
            key = "tags_beings_factions",
            label = "Beings & Factions (68)",
            options = {
                {value = "22", label = "Adventurers"}, {value = "28", label = "Aliens"}, {value = "38", label = "Angels"},
                {value = "62", label = "Astrologers"}, {value = "78", label = "Beast Companions"}, {value = "79", label = "Beastkin"},
                {value = "80", label = "Beasts"}, {value = "188", label = "Demi-Humans"}, {value = "189", label = "Demon Lord"},
                {value = "191", label = "Demons"}, {value = "216", label = "Dragons"}, {value = "219", label = "Druids"},
                {value = "222", label = "Dwarfs"}, {value = "233", label = "Elves"}, {value = "239", label = "Engineer"},
                {value = "244", label = "Evil Gods"}, {value = "245", label = "Evil Organizations"}, {value = "252", label = "Fairies"},
                {value = "253", label = "Fallen Angels"}, {value = "256", label = "Familiars"}, {value = "264", label = "Fantasy Creatures"},
                {value = "289", label = "Fox Spirits"}, {value = "307", label = "Ghosts"}, {value = "311", label = "Goblins"},
                {value = "313", label = "God-human Relationship"}, {value = "314", label = "Goddesses"}, {value = "316", label = "Gods"},
                {value = "317", label = "Golems"}, {value = "319", label = "Grave Keepers"}, {value = "338", label = "Herbalist"},
                {value = "339", label = "Heroes"}, {value = "345", label = "Homunculus"}, {value = "357", label = "Immortals"},
                {value = "360", label = "Incubus"}, {value = "366", label = "Insects"}, {value = "374", label = "Jiangshi"},
                {value = "389", label = "Legends"}, {value = "411", label = "Magic Beasts"}, {value = "449", label = "Monster Girls"},
                {value = "451", label = "Monster Tamer"}, {value = "452", label = "Monsters"}, {value = "465", label = "Mutated Creatures"},
                {value = "466", label = "Mutations"}, {value = "472", label = "Mythical Beasts"}, {value = "484", label = "Ninjas"},
                {value = "497", label = "Orcs"}, {value = "524", label = "Phoenixes"}, {value = "534", label = "Police"},
                {value = "552", label = "Priestesses"}, {value = "553", label = "Priests"}, {value = "597", label = "Saints"},
                {value = "620", label = "Sentient Objects"}, {value = "624", label = "Seven Deadly Sins"}, {value = "625", label = "Seven Virtues"},
                {value = "635", label = "Shikigami"}, {value = "664", label = "Souls"}, {value = "669", label = "Spirit Advisor"},
                {value = "671", label = "Spirits"}, {value = "679", label = "Strategist"}, {value = "686", label = "Succubus"},
                {value = "695", label = "Sword Wielder"}, {value = "700", label = "Tentacles"}, {value = "739", label = "Valkyries"},
                {value = "740", label = "Vampires"}, {value = "752", label = "Werebeasts"}, {value = "754", label = "Witches"},
                {value = "761", label = "Youkai"}, {value = "765", label = "Zombies"},
            }
        },

        {
            type = "tristate",
            key = "tags_professional",
            label = "Professional Archetypes (64)",
            options = {
                {value = "7", label = "Acting"}, {value = "44", label = "Antique Shop"}, {value = "50", label = "Archery"},
                {value = "60", label = "Artists"}, {value = "68", label = "Bands"}, {value = "809", label = "Basketball"},
                {value = "89", label = "Blacksmith"}, {value = "97", label = "Bodyguards"}, {value = "109", label = "Businessmen"},
                {value = "110", label = "Butlers"}, {value = "117", label = "Celebrities"}, {value = "123", label = "Chefs"},
                {value = "157", label = "Cosplay"}, {value = "177", label = "Dancers"}, {value = "196", label = "Detectives"},
                {value = "208", label = "Doctors"}, {value = "214", label = "Dragon Riders"}, {value = "215", label = "Dragon Slayers"},
                {value = "224", label = "e-Sports"}, {value = "229", label = "Editors"}, {value = "274", label = "Female Master"},
                {value = "780", label = "Football"}, {value = "299", label = "Gamers"}, {value = "323", label = "Gunfighters"},
                {value = "324", label = "Hackers"}, {value = "779", label = "Hollywood"}, {value = "386", label = "Lawyers"},
                {value = "782", label = "Live Streaming"}, {value = "860", label = "Machinist "}, {value = "416", label = "Maids"},
                {value = "421", label = "Mangaka"}, {value = "433", label = "Medical Knowledge"}, {value = "435", label = "Mercenaries"},
                {value = "436", label = "Merchants"}, {value = "445", label = "Models"}, {value = "453", label = "Movies"},
                {value = "464", label = "Music"}, {value = "489", label = "Nurses"}, {value = "514", label = "Part-Time Job"},
                {value = "521", label = "Pharmacist"}, {value = "525", label = "Photography"}, {value = "528", label = "Pilots"},
                {value = "532", label = "Poetry"}, {value = "533", label = "Poisons"}, {value = "556", label = "Programmer"},
                {value = "564", label = "Puppeteers"}, {value = "581", label = "Reporters"}, {value = "603", label = "Scientists"},
                {value = "604", label = "Sculptors"}, {value = "622", label = "Serial Killers"}, {value = "623", label = "Servants"},
                {value = "634", label = "Shield User"}, {value = "640", label = "Showbiz"}, {value = "648", label = "Singers"},
                {value = "662", label = "Soldiers"}, {value = "666", label = "Spear Wielder"}, {value = "668", label = "Spies"},
                {value = "675", label = "Store Owner"}, {value = "697", label = "Teachers"}, {value = "703", label = "Thieves"},
                {value = "733", label = "Unique Weapon User"}, {value = "744", label = "Voice Actors"}, {value = "746", label = "Waiters"},
                {value = "759", label = "Writers"},
            }
        },

        {
            type = "tristate",
            key = "tags_tone",
            label = "Tone & Atmosphere (27)",
            options = {
                {value = "4", label = "Abusive Characters"}, {value = "107", label = "Bullying"}, {value = "146", label = "Comedic Undertone"},
                {value = "155", label = "Corruption"}, {value = "167", label = "Cruel Characters"}, {value = "176", label = "Cute Story"},
                {value = "181", label = "Dark"}, {value = "789", label = "Dark Fantasy"}, {value = "193", label = "Depictions of Cruelty"},
                {value = "194", label = "Depression"}, {value = "195", label = "Destiny"}, {value = "201", label = "Discrimination"},
                {value = "262", label = "Fanaticism"}, {value = "291", label = "Friendship"}, {value = "333", label = "Heartwarming"},
                {value = "396", label = "Loneliness"}, {value = "442", label = "Misunderstandings"}, {value = "469", label = "Mysterious Illness"},
                {value = "476", label = "Nationalism"}, {value = "522", label = "Philosophical"}, {value = "523", label = "Phobias"},
                {value = "567", label = "R-15"}, {value = "570", label = "Racism"}, {value = "646", label = "Sickly Characters"},
                {value = "661", label = "Social Outcasts"}, {value = "689", label = "Suicides"}, {value = "701", label = "Terminal Illness"},
            }
        },

        {
            type = "tristate",
            key = "tags_adaptations",
            label = "Adaptations (85)",
            options = {
                {value = "8", label = "Adapted from Manga"}, {value = "9", label = "Adapted from Manhua"}, {value = "10", label = "Adapted to Anime"},
                {value = "846", label = "Adapted to Donghua"}, {value = "11", label = "Adapted to Drama"}, {value = "12", label = "Adapted to Drama CD"},
                {value = "13", label = "Adapted to Game"}, {value = "14", label = "Adapted to Manga"}, {value = "15", label = "Adapted to Manhua"},
                {value = "16", label = "Adapted to Manhwa"}, {value = "17", label = "Adapted to Movie"}, {value = "18", label = "Adapted to Visual Novel"},
                {value = "833", label = "Arknights"}, {value = "66", label = "Award-winning Work"}, {value = "69", label = "Based on a Movie"},
                {value = "70", label = "Based on a Song"}, {value = "71", label = "Based on a TV Show"}, {value = "72", label = "Based on a Video Game"},
                {value = "73", label = "Based on a Visual Novel"}, {value = "74", label = "Based on an Anime"}, {value = "839", label = "Black Clover"},
                {value = "770", label = "Bleach"}, {value = "832", label = "BTTH"}, {value = "854", label = "Classroom of the Elite"},
                {value = "800", label = "Conferred Gods"}, {value = "783", label = "Cyberpunk 2077"}, {value = "840", label = "Danmachi"},
                {value = "778", label = "DC Universe"}, {value = "812", label = "Demon Slayer"}, {value = "804", label = "Detective Conan"},
                {value = "851", label = "Digimon"}, {value = "794", label = "DnD"}, {value = "772", label = "Douluo Dalu"},
                {value = "773", label = "Dragon Ball"}, {value = "868", label = "Fabulous Beast"}, {value = "814", label = "Fairy Tail"},
                {value = "872", label = "Final Fantasy"}, {value = "816", label = "Frieren"}, {value = "813", label = "Game of Thrones"},
                {value = "815", label = "Genshin Impact"}, {value = "768", label = "Harry Potter"}, {value = "847", label = "Highschool DxD"},
                {value = "865", label = "Hikigaya"}, {value = "801", label = "Honghuang"}, {value = "818", label = "Honkai"},
                {value = "777", label = "Hunter x Hunter"}, {value = "859", label = "JoJo’s Bizarre Adventure"}, {value = "796", label = "Journey to the West"},
                {value = "776", label = "Jujutsu Kaisen"}, {value = "843", label = "Kamen Rider"}, {value = "864", label = "King's Avatar"},
                {value = "862", label = "Kirkmanverse"}, {value = "791", label = "League of Legends"}, {value = "799", label = "Lord of the Mysteries"},
                {value = "853", label = "Lord of the Ring"}, {value = "766", label = "Marvel"}, {value = "790", label = "Minecraft"},
                {value = "769", label = "Naruto"}, {value = "844", label = "Nasuverse"}, {value = "767", label = "One Piece"},
                {value = "837", label = "One Punch Man"}, {value = "826", label = "Overlord"}, {value = "863", label = "Pirates of Caribbean"},
                {value = "771", label = "Pokemon"}, {value = "858", label = "Project Moon"}, {value = "861", label = "Qing Transmigration"},
                {value = "856", label = "Resident Evil"}, {value = "820", label = "Siheyuan"}, {value = "870", label = "Slay the Gods"},
                {value = "817", label = "Star Wars"}, {value = "866", label = "Strike the Blood"}, {value = "785", label = "Swallowed Star"},
                {value = "836", label = "The Boys"}, {value = "869", label = "The Eminence in Shadow"}, {value = "852", label = "The Walking Dead"},
                {value = "850", label = "Toaru"}, {value = "857", label = "Touhou Project"}, {value = "838", label = "Ultraman"},
                {value = "834", label = "Uma Musume"}, {value = "845", label = "Versatile Mage"}, {value = "743", label = "Vocaloid"},
                {value = "775", label = "Warhammer"}, {value = "819", label = "Witcher"}, {value = "774", label = "Yu-Gi-Oh!"},
                {value = "867", label = "Zenless Zone Zero"},
            }
        },

        {
            type = "tristate",
            key = "tags_misc",
            label = "Miscellaneous Narrative Elements (40)",
            options = {
                {value = "39", label = "Animal Characteristics"}, {value = "40", label = "Animal Rearing"}, {value = "45", label = "Apartment Life"},
                {value = "57", label = "Artifact Crafting"}, {value = "58", label = "Artifacts"}, {value = "96", label = "Body-double"},
                {value = "98", label = "Books"}, {value = "106", label = "Buddhism"}, {value = "113", label = "Card Games"},
                {value = "126", label = "Childcare"}, {value = "139", label = "Co-Workers"}, {value = "140", label = "Cohabitation"},
                {value = "144", label = "College/University"}, {value = "154", label = "Cooking"}, {value = "174", label = "Cute Children"},
                {value = "841", label = "Daily Intelligence"}, {value = "180", label = "Daoism"}, {value = "202", label = "Disfigurement"},
                {value = "209", label = "Dolls/Puppets"}, {value = "210", label = "Domestic Affairs"}, {value = "217", label = "Dreams"},
                {value = "227", label = "Easy Going Life"}, {value = "277", label = "Feng Shui"}, {value = "283", label = "Folklore"},
                {value = "340", label = "Heterochromia"}, {value = "821", label = "Hong Kong"}, {value = "372", label = "Jack of All Trades"},
                {value = "384", label = "Language Barrier"}, {value = "393", label = "Living Abroad"}, {value = "394", label = "Living Alone"},
                {value = "440", label = "Misandry"}, {value = "473", label = "Mythology"}, {value = "501", label = "Otaku"},
                {value = "520", label = "Pets"}, {value = "593", label = "Roommates"}, {value = "647", label = "Sign Language"},
                {value = "657", label = "Sleeping"}, {value = "729", label = "Ugly to Beautiful"}, {value = "734", label = "Unique Weapons"},
                {value = "788", label = "Western Names"},
            }
        }
    }
end

-- ── Filtered catalog ─────────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
    local page = index + 1
    local orderBy = filters["orderBy"] or "update"
    local order = filters["order"] or "desc"
    local status = filters["status"] or "all"
    local release_status = filters["release_status"] or "all"
    local addition_age = filters["addition_age"] or "all"
    local min_rating = filters["min_rating"] or ""
    local min_reviews = filters["min_reviews"] or ""
    local count_chapters = filters["count_chapters"] or ""
    local count_mode = filters["count_mode"] or "min"
    local count_characters = filters["count_characters"] or ""
    local genre_op = filters["genre_operator"] or "and"
    local tag_op = filters["tag_operator"] or "and"

    local genres_inc = filters["genres_included"] or {}
    local genres_exc = filters["genres_excluded"] or {}

    -- Tags are split across 11 category-grouped tristate filters (matches
    -- the site's own finder grouping; NoveLA renders every tristate option
    -- as an eagerly-built chip, so a single 882-item list would be unusable).
    -- Collect included/excluded tag ids from every group into one combined
    -- ti=/te= list. The single tc= operator applies to the combined set.
    local tags_inc, tags_exc = {}, {}
    for _, gkey in ipairs({
        "tags_protagonist", "tags_power_systems", "tags_worldbuilding",
        "tags_socio_political", "tags_relationships", "tags_narrative",
        "tags_beings_factions", "tags_professional", "tags_tone",
        "tags_adaptations", "tags_misc"
    }) do
        for _, v in ipairs(filters[gkey .. "_included"] or {}) do
            tags_inc[#tags_inc + 1] = v
        end
        for _, v in ipairs(filters[gkey .. "_excluded"] or {}) do
            tags_exc[#tags_exc + 1] = v
        end
    end

    -- Tag Search: resolve free-text tokens to tag IDs and merge
    for _, id in ipairs(tagSearchResolve(filters["tag_search_inc"]) or {}) do
        tags_inc[#tags_inc + 1] = id
    end
    for _, id in ipairs(tagSearchResolve(filters["tag_search_exc"]) or {}) do
        tags_exc[#tags_exc + 1] = id
    end
    local params = "orderBy=" .. orderBy .. "&order=" .. order .. "&status=" .. status ..
        "&release_status=" .. release_status .. "&addition_age=" .. addition_age ..
        "&page=" .. tostring(page)

    -- Rating filters
    if min_rating ~= "" then
        params = params .. "&minr=" .. min_rating
    end
    if min_reviews ~= "" then
        params = params .. "&minrc=" .. min_reviews
    end

    -- Count filters (the site supports ONE count_type at a time;
    -- chapters take priority over characters)
    if count_chapters ~= "" then
        params = params .. "&count_type=chapter&count_filter=" .. count_mode .. "&count_value=" .. count_chapters
    elseif count_characters ~= "" then
        params = params .. "&count_type=character&count_filter=min&count_value=" .. count_characters
    end

    -- The site forces minrc=5 for weighted ordering (matches site behaviour)
    if orderBy == "weighted" and min_reviews == "" then
        params = params .. "&minrc=5"
    end

    -- Genres
    if #genres_inc > 0 then
        params = params .. "&gi=" .. table.concat(genres_inc, ",") .. "&gc=" .. genre_op
    end
    if #genres_exc > 0 then
        params = params .. "&ge=" .. table.concat(genres_exc, ",")
    end

    -- Tags
    if #tags_inc > 0 then
        params = params .. "&ti=" .. table.concat(tags_inc, ",") .. "&tc=" .. tag_op
    end
    if #tags_exc > 0 then
        params = params .. "&te=" .. table.concat(tags_exc, ",")
    end

    local pp = fetchNextData("/en/novel-finder.json", params)
    if not pp then
        log_error("wtrlab: getCatalogFiltered failed")
        return { items = {}, hasNext = false }
    end
    return pagePropsToResult(pp, page)
end
