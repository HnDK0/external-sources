"""Regression tests for the dependency scan that produces index.yaml `requires`.

Run: python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import re
import tempfile
import unittest
from pathlib import Path

import sync_index as s

ROOT = Path(__file__).resolve().parent.parent


class ScanRequiresTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lib_ids = s.library_ids(ROOT)

    def test_literal_loaders_are_dependencies(self):
        code = """
            local urls = require_lib("urls")
            local catalog = LIB('catalog')
            local meta = tryLib("meta")
        """
        self.assertEqual(["urls", "catalog", "meta"], s.scan_requires(code, self.lib_ids))

    def test_comments_are_not_dependencies(self):
        # The wording the corpus documents itself with.
        code = """
            -- Loaded via require_lib("otaku"); uses engine API
            --[[ require_lib('cdnlibs') ]]
            --[==[ LIB("readmanga") ]==]
            --- LIB("urls")
        """
        self.assertEqual([], s.scan_requires(code, self.lib_ids))

    def test_string_literals_are_not_dependencies(self):
        code = """
            local msg = "call require_lib('catalog') first"
            local other = 'LIB("urls") inside a string'
            local url = "https://example.com/a--b"
        """
        self.assertEqual([], s.scan_requires(code, self.lib_ids))

    def test_long_strings_are_not_dependencies(self):
        code = 'local doc = [==[ LIB("catalog") and require_lib("urls") ]==]'
        self.assertEqual([], s.scan_requires(code, self.lib_ids))

    def test_method_calls_are_not_dependencies(self):
        code = """
            if low:find("dood") then end
            local v = el:attr("content")
        """
        self.assertEqual([], s.scan_requires(code, self.lib_ids))

    def test_any_bare_call_with_a_library_id_is_a_dependency(self):
        # Conservative by design: a wrapper we have never seen is still caught,
        # at the cost of a dependency the plugin may not use. The failure mode
        # we refuse is the silent one (a lib required at runtime, undeclared).
        code = """
            local t = type("fetch")
            local ok = pcall(handler, "meta")
        """
        # A two-argument call (`pcall(handler, "meta")`) is not a loader form.
        self.assertEqual(["fetch"], s.scan_requires(code, self.lib_ids))

    def test_escaped_quote_does_not_swallow_following_code(self):
        code = 'local q = "say \\"hi\\""\nlocal u = require_lib("urls")'
        self.assertEqual(["urls"], s.scan_requires(code, self.lib_ids))

    def test_duplicates_are_collapsed_in_call_order(self):
        code = 'LIB("meta")\nLIB("urls")\nLIB("meta")'
        self.assertEqual(["meta", "urls"], s.scan_requires(code, self.lib_ids))


class ParsedDataTest(unittest.TestCase):
    """The committed indexes must only reference libraries that exist."""

    def test_every_requires_id_exists_in_libraries(self):
        lib_ids = s.library_ids(ROOT)
        self.assertTrue(lib_ids, "libs/ is empty")
        root = (ROOT / "index.yaml").read_text(encoding="utf-8")
        section = re.search(r"^libraries:\n((?:[ \t]+.*\n?)*)", root, re.MULTILINE)
        self.assertIsNotNone(section, "root index has no libraries section")
        declared = set(re.findall(r'^  - id: "([^"]+)"', section.group(1), re.MULTILINE))
        self.assertEqual(lib_ids, declared)

        for index in sorted(ROOT.glob("*/index.yaml")):
            text = index.read_text(encoding="utf-8")
            for raw in re.findall(r"^    requires: \[(.+)\]$", text, re.MULTILINE):
                for lib in re.findall(r'"([^"]+)"', raw):
                    self.assertIn(lib, lib_ids, f"{index.name}: unknown library '{lib}'")


class IconRewriteTest(unittest.TestCase):
    """icon в .lua должен вести на текущую базу: старая ветка отдаёт 404."""

    BASE = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/v2"

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def _plugin(self, icon_line):
        p = self.dir / "x.lua"
        p.write_text(f'id = "x"\nversion = "1.0.0"\n{icon_line}\n', encoding="utf-8")
        return p

    def test_old_branch_icon_is_rebased_in_the_plugin_file(self):
        p = self._plugin('icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/x.png"')
        self.assertTrue(s.fix_plugin_icon(p, self.BASE))
        self.assertIn(f'icon     = "{self.BASE}/icons/x.png"', p.read_text(encoding="utf-8"))

    def test_refs_heads_form_is_rebased_too(self):
        p = self._plugin('icon = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/x.png"')
        self.assertTrue(s.fix_plugin_icon(p, self.BASE))
        self.assertIn(f'icon = "{self.BASE}/icons/x.png"', p.read_text(encoding="utf-8"))

    def test_already_correct_icon_is_left_untouched(self):
        p = self._plugin(f'icon = "{self.BASE}/icons/x.png"')
        self.assertFalse(s.fix_plugin_icon(p, self.BASE))

    def test_non_raw_icon_is_left_untouched(self):
        p = self._plugin('icon = "https://example.com/icons/x.png"')
        self.assertFalse(s.fix_plugin_icon(p, self.BASE))
        self.assertIn("https://example.com/icons/x.png", p.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
