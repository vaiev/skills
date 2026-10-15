"""Public-release docs, frontmatter, and a scan for committed secrets."""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SKILLS = {
    "sidecomputer-getting-started": ROOT / "sidecomputer" / "getting-started" / "SKILL.md",
    "sidecomputer-dispatch": ROOT / "sidecomputer" / "dispatch" / "SKILL.md",
    "sidecomputer-admin": ROOT / "sidecomputer" / "admin" / "SKILL.md",
}

# Split so this file does not itself contain a contiguous secret marker.
SECRET_MARKERS = (
    "BEGIN " "OPENSSH PRIVATE KEY",
    "BEGIN " "RSA PRIVATE KEY",
    "BEGIN " "EC PRIVATE KEY",
    "BEGIN " "DSA PRIVATE KEY",
    "BEGIN " "PRIVATE KEY",
    "x-access-" "token:",
    "gh" "p_",
    "github_" "pat_",
    "sk" "-",
    "xo" "x",
)


class ReleaseDocsTest(unittest.TestCase):
    def test_readme_has_quickstart_diagram_and_canonical_paths(self) -> None:
        text = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("## Quickstart", text)
        self.assertIn("```mermaid", text)
        self.assertIn("vaiev/skills/sidecomputer/dispatch/SKILL.md", text)
        self.assertIn("Apache License, Version 2.0", text)
        lowered = text.lower()
        self.assertNotIn("authenticated", lowered)
        self.assertIn("self-asserted", lowered)
        self.assertIn("HUB_BOT", text)
        self.assertIn("security decision", lowered)
        self.assertIn("no rotate tool", lowered)
        self.assertIn("artifact_redaction", text)
        self.assertIn("as `all`", text)
        self.assertNotIn("once that fix has landed", lowered)
        self.assertNotIn("verified sender", lowered)

    def test_license_is_apache_2(self) -> None:
        text = (ROOT / "LICENSE").read_text(encoding="utf-8")
        self.assertIn("Apache License", text)
        self.assertIn("Version 2.0, January 2004", text)
        self.assertIn("http://www.apache.org/licenses/", text)
        self.assertIn("Copyright 2026 VAIEV", text)

    def test_security_and_contributing_exist(self) -> None:
        security = (ROOT / "SECURITY.md").read_text(encoding="utf-8")
        contributing = (ROOT / "CONTRIBUTING.md").read_text(encoding="utf-8")
        security_lower = security.lower()
        self.assertIn("private vulnerability reporting", security_lower)
        self.assertIn("https://github.com/vaiev", security)
        self.assertIn("until then", security_lower)
        self.assertNotIn("authenticated", security_lower)
        self.assertIn("self-asserted", security_lower)
        self.assertIn("artifact_redaction", security)
        self.assertIn("as `all`", security)
        self.assertNotIn("once that fix has landed", security_lower)
        self.assertIn("python3 -m unittest discover -s tests -v", contributing)
        workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        self.assertIn("python3 -m unittest discover -s tests -v", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("actions/checkout@11d5960a326750d5838078e36cf38b85af677262", workflow)
        self.assertIn("actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065", workflow)
        self.assertNotIn("actions/checkout@v4", workflow)

    def test_skill_frontmatter(self) -> None:
        for name, path in SKILLS.items():
            text = path.read_text(encoding="utf-8")
            self.assertTrue(text.startswith("---\n"), path)
            end = text.find("\n---\n", 4)
            self.assertGreater(end, 4, path)
            block = text[4:end]
            self.assertIn(f"name: {name}\n", block)
            self.assertIn("description:", block)

    def test_tree_has_no_secret_material(self) -> None:
        skip = {".git", "__pycache__"}
        for path in ROOT.rglob("*"):
            if not path.is_file() or skip.intersection(path.parts):
                continue
            if path.suffix in {".png", ".jpg", ".gif", ".webp"}:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            for marker in SECRET_MARKERS:
                self.assertNotIn(marker, text, f"{marker} in {path}")


if __name__ == "__main__":
    unittest.main()
