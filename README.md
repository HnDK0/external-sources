# NoveLA External Sources

This repository contains external novel sources for the NoveLA application. Sources are written in Lua and loaded dynamically.

## Repository Structure

- `en/` - English sources
- `ru/` - Russian sources
- `zh/` - Chinese sources
- `id/` - Indonesian sources
- `multi/` - Multilanguage sources
- `icons/` - Source icons
- `index.yaml` - Main source index
- `[lang]/index.yaml` - Language-specific index

## Development Guide

If you want to create your own source plugin, please refer to the [NoveLA Lua Plugin Development Guide](GUIDE.md). It contains a full description of the available Lua API and examples.

## How to Add a New Source

1. Create a Lua plugin in the corresponding language folder.
2. Add an icon to the `icons/` folder.
3. Update the language-specific `index.yaml`.
4. Update the main `index.yaml` and source counters.
