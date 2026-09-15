# Исследование русскоязычных манг-сайтов

## Группа A — работают, готовы к реализации

### 1. ReadManga
- **Домен:** readmanga.me
- **API:** GroupLe (`$baseUrl/api/catalog/search`)
- **Site-Id:** 11
- **Статус:** ✅ Работает
- **Удаление:** DMCA только по запросам

### 2. MintManga
- **Домен:** mintmanga.one
- **API:** GroupLe (как ReadManga)
- **Site-Id:** 2
- **Статус:** ✅ Работает
- **Примечание:** 18+ версия ReadManga

### 3. SelfManga
- **Домен:** 1.selfmanga.live
- **API:** GroupLe (как ReadManga)
- **Site-Id:** 11
- **Статус:** ✅ Работает
- **Примечание:** Самиздат

### 4. SeiManga
- **Домен:** 1.seimanga.me
- **API:** GroupLe (как ReadManga)
- **Site-Id:** 21
- **Статус:** ✅ Работает

### 5. Rumix
- **Домен:** rumix.me
- **API:** GroupLe (как ReadManga)
- **Статус:** ✅ Работает
- **Примечание:** Зеркало

### 6. MangaLib
- **Домен:** mangalib.me
- **API:** LibGroup (`api.cdnlibs.org`)
- **Site-Id:** 1
- **Статус:** ✅ Работает
- **Примечание:** Клон RanobeLib с siteId=1

### 7. HentaiLib
- **Домен:** hentailib.me
- **API:** LibGroup (`api.cdnlibs.org`)
- **Site-Id:** 4
- **Статус:** ✅ Работает
- **Примечание:** 18+ версия MangaLib

### 8. MangaPoisk
- **Домен:** mangapoisk.me (mangapoisk.ru → редирект)
- **API:** Собственный
- **Статус:** ✅ Работает
- **Трафик:** 768K/мес

---

## Группа B — работают, но нужно изучать API

### 9. MangaBuff
- **Домен:** mangabuff.ru
- **Статус:** ✅ Работает (за DDoS-Guard)
- **Трафик:** 43M/мес
- **Примечание:** Требует VPN для доступа из некоторых регионов

### 10. MangaClub
- **Домен:** mangaclub.ru
- **Статус:** ✅ Работает
- **Трафик:** 24K/мес
- **Примечание:** manga.club (официальный) закрыт

---

## Группа C — не работают / не найдены

| Сайт | Статус |
|------|--------|
| MangaChan | Не найден |
| MultiManga | Не найден |
| Usagi | Неизвестно |
| UniComics | Комиксы (Marvel/DC), не манга |

---

## Приоритеты реализации

1. ReadManga (GroupLe клон)
2. MangaLib (LibGroup клон, clone RanobeLib)
3. HentaiLib (LibGroup клон)
4. SelfManga (GroupLe клон)
5. SeiManga (GroupLe клон)
6. MintManga (GroupLe клон)
7. Rumix (GroupLe клон)
8. MangaPoisk (свой API)
