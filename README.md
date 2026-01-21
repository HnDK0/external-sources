# NovelDokushaTT External Sources Repository

This repository contains external source configurations for NovelDokushaTT application.

## Structure

```
external-sources/
├── README.md                    # This file
├── index.json                   # Main language index
├── en/                         # English sources
│   ├── index.json              # English sources list
│   └── *.kts                   # Kotlin scripts for sources
├── ru/                         # Russian sources
│   └── index.json              # Russian sources list
├── zh/                         # Chinese sources
│   └── index.json              # Chinese sources list
└── icons/                      # Source icons
    └── *.png                   # Icon files
```

## How to Add a New Source

1. **Create a Gist** on GitHub with your `.kts` script
2. **Add to index.json** in the appropriate language folder
3. **Add icon** to the icons folder (optional)
4. **Create Pull Request** for review

## Source Script Format

Each source is a Kotlin script (.kts) that returns an `HtmlSelectors` object:

```kotlin
import my.noveldokusha.core.LanguageCode
import my.noveldokusha.scraper.configs.*

HtmlSelectors(
    baseUrl = "https://example.com",
    language = LanguageCode.ENGLISH,
    // ... selectors configuration
)
```

## Validation

All scripts are validated for:
- Security (no dangerous imports/operations)
- Syntax correctness
- Required fields presence
- Size limits (50KB max)

## Contributing

1. Fork this repository
2. Add your source following the format above
3. Test your source (when evaluator is ready)
4. Create Pull Request

Sources will be reviewed for security and functionality before merging.
