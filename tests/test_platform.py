"""Platform skill family: frontmatter, index links, and a scan for real addresses and operator data."""

from __future__ import annotations

import ipaddress
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAMILY = ROOT / "platform"
SKILLS = ("openstack-cloud", "knot-dnssec", "dns-cutover", "postgres-dual-backup", "sops-secrets", "project-starter")
# Documentation and example ranges only (RFC 5737, one RFC 1918 example net, loopback).
ALLOWED = [ipaddress.ip_network(n) for n in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24", "10.0.0.0/16", "127.0.0.0/8")]
IPV4 = re.compile(r"(?<![\d.])(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?![\d.])")
# Real age recipients and home-directory paths must not appear in public playbooks.
OPERATOR_DATA = (re.compile(r"\bage1[0-9a-z]{20,}"), re.compile(r"/home/[a-z]+/"))


class PlatformSkillsTest(unittest.TestCase):
    def test_every_skill_has_frontmatter_named_after_its_folder(self) -> None:
        for name in SKILLS:
            text = (FAMILY / name / "SKILL.md").read_text(encoding="utf-8")
            self.assertTrue(text.startswith("---\n"), name)
            block = text[4:text.find("\n---\n", 4)]
            self.assertIn(f"name: {name}\n", block)
            self.assertIn("description:", block)

    def test_family_and_root_readme_list_the_skills(self) -> None:
        family = (FAMILY / "README.md").read_text(encoding="utf-8")
        root = (ROOT / "README.md").read_text(encoding="utf-8")
        for name in SKILLS:
            self.assertIn(f"vaiev/skills/platform/{name}/SKILL.md", family)
        self.assertIn("platform/README.md", root)

    def test_no_real_addresses_or_operator_data(self) -> None:
        for path in FAMILY.rglob("*.md"):
            text = path.read_text(encoding="utf-8")
            for match in IPV4.findall(text):
                addr = ipaddress.ip_address(match)
                self.assertTrue(any(addr in net for net in ALLOWED), f"{match} in {path}")
            for pattern in OPERATOR_DATA:
                self.assertIsNone(pattern.search(text), f"{pattern.pattern} in {path}")


if __name__ == "__main__":
    unittest.main()
