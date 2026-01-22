# NovelDokushaTT External Sources Repository

This repository contains external source extensions for NovelDokushaTT application.

**Repository:** https://github.com/HnDK0/external-sources

## Structure

```
external-sources/
├── README.md                    # This file
├── index.json                   # Main language index (no count fields)
├── scripts/                     # Automation scripts
│   ├── generate_index.py        # Generate index files
│   └── validate_repo.py         # Validate repository structure
├── en/                         # English sources
│   ├── index.json              # English sources list
│   └── *.jar                   # Compiled JAR files (GitHub releases)
├── ru/                         # Russian sources
│   └── index.json              # Russian sources list
├── zh/                         # Chinese sources
│   └── index.json              # Chinese sources list
└── icons/                      # Source icons
    └── *.png                   # Icon files
```

## How to Add a New Source

### Development Workflow

1. **Create Source Code** - Write Kotlin source following the extension API
2. **Compile to JAR** - Use the build system to create .jar file
3. **Create GitHub Release** - Upload JAR to releases with version tag
4. **Update index.json** - Add entry to appropriate language index
5. **Add Icon** - Upload icon to icons/ folder (optional)
6. **Create Pull Request** for review

### Source Code Format

Each source is a Kotlin class that implements `SourceInterface`:

```kotlin
import my.noveldokusha.core.LanguageCode
import my.noveldokusha.scraper.configs.*

class MySource(private val networkClient: NetworkClient) : SourceInterface.Catalog {
    override val baseUrl = "https://example.com"
    override val language = LanguageCode.ENGLISH

    // Implement required methods...
    override suspend fun getCatalogList(index: Int) = getCatalogList(config, index, networkClient)
}
```

### JAR Structure

JAR files must contain:
- Compiled Kotlin classes
- Proper manifest with Main-Class (if needed)
- Dependencies bundled or declared

### Index.json Format

**Main index.json** (no count fields):
```json
{
  "version": "1.0",
  "lastUpdated": "2024-01-22",
  "languages": {
    "en": {"url": "https://raw.githubusercontent.com/HnDK0/external-sources/main/en/index.json"},
    "ru": {"url": "https://raw.githubusercontent.com/HnDK0/external-sources/main/ru/index.json"}
  }
}
```

**Language index.json**:
```json
{
  "language": "en",
  "sources": [
    {
      "id": "mysource",
      "name": "My Source",
      "description": "Description of the source",
      "author": "Author Name",
      "version": "1.0.0",
      "jarUrl": "https://github.com/HnDK0/external-sources/releases/download/v1.0.0/mysource.jar",
      "iconUrl": "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/mysource.png"
    }
  ]
}
```

## Automation Scripts

### Generate Index Files
```bash
python scripts/generate_index.py
```
Generates main index.json and validates all language indexes.

### Validate Repository
```bash
python scripts/validate_repo.py
```
Checks:
- All required files exist
- JSON structure is correct
- No deprecated fields present
- JAR/Icon URLs are accessible
- Repository integrity

## Validation

All extensions are validated for:
- **Security**: No dangerous operations or imports
- **Compatibility**: Proper API usage and dependencies
- **Quality**: Code style and documentation
- **Functionality**: Working selectors and logic
- **Size**: Reasonable JAR size limits

## Contributing

1. **Fork** this repository
2. **Develop** your source extension
3. **Test** thoroughly on different devices
4. **Compile** and create GitHub release
5. **Update** index.json files
6. **Validate** with scripts
7. **Create Pull Request**

### Pull Request Checklist
- [ ] JAR file uploaded to GitHub releases
- [ ] index.json updated with correct format
- [ ] Icon added (optional but recommended)
- [ ] Scripts pass validation
- [ ] Source tested on real device
- [ ] Documentation updated if needed

Sources will be reviewed for security, quality, and functionality before merging.

## Build System

The build system automatically:
- Compiles Kotlin sources to JAR
- Validates API compatibility
- Generates index files
- Creates GitHub releases
- Updates documentation

See `EXTENSIONS_DEVELOPMENT.md` for detailed build instructions.
