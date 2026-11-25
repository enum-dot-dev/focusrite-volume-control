"""Tests for render_cask.py. Run: python3 -m unittest discover -s scripts -p 'test_*.py'"""

import os
import shutil
import subprocess
import tempfile
import unittest

from render_cask import BETA_TOKEN, STABLE_TOKEN, render

TEMPLATE = os.path.join(os.path.dirname(__file__), "..", "homebrew", "Casks", "focusrite-volume-control.rb")
SHA = "a" * 64


def template() -> str:
    with open(TEMPLATE) as f:
        return f.read()


class RenderCaskTests(unittest.TestCase):
    def test_stable(self):
        cask = render(template(), "1.6.0", SHA, unsigned=False, auto_updates=False)
        self.assertIn(f'cask "{STABLE_TOKEN}" do', cask)
        self.assertIn('  version "1.6.0"', cask)
        self.assertIn(f'  sha256 "{SHA}"', cask)
        self.assertIn(f'  conflicts_with cask: "{BETA_TOKEN}"', cask)
        self.assertNotIn("postflight do", cask)
        self.assertNotIn("auto_updates", cask)

    def test_beta_swaps_token_and_conflict(self):
        cask = render(template(), "1.6.0-beta.2", SHA, unsigned=False, auto_updates=False, beta=True)
        self.assertIn(f'cask "{BETA_TOKEN}" do', cask)
        self.assertIn(f'  conflicts_with cask: "{STABLE_TOKEN}"', cask)
        self.assertNotIn(f'cask "{STABLE_TOKEN}" do', cask)
        self.assertIn('  version "1.6.0-beta.2"', cask)

    def test_beta_cask_also_takes_stable_versions(self):
        cask = render(template(), "1.6.0", SHA, unsigned=False, auto_updates=False, beta=True)
        self.assertIn('  version "1.6.0"', cask)

    def test_stable_cask_rejects_prerelease_versions(self):
        with self.assertRaises(ValueError):
            render(template(), "1.6.0-beta.1", SHA, unsigned=False, auto_updates=False)

    def test_rejects_bad_input(self):
        for version in ["", "v1.6.0", "1.6.0-", "1.6.0-beta..1", '1.6"; system "x']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                render(template(), version, SHA, unsigned=False, auto_updates=False, beta=True)
        with self.assertRaises(ValueError):
            render(template(), "1.6.0", "not-a-sha", unsigned=False, auto_updates=False)

    def test_unsigned_adds_quarantine_postflight_after_app(self):
        cask = render(template(), "1.6.0", SHA, unsigned=True, auto_updates=False)
        self.assertIn('  app "Volume Control.app"\n\n  # Unsigned build', cask)
        self.assertIn('"/usr/bin/xattr"', cask)

    def test_auto_updates_goes_before_conflicts_with(self):
        for beta in (False, True):
            cask = render(template(), "1.6.0", SHA, unsigned=False, auto_updates=True, beta=beta)
            self.assertIn("  auto_updates true\n  conflicts_with cask:", cask)

    @unittest.skipUnless(shutil.which("ruby"), "ruby not installed")
    def test_rendered_casks_are_valid_ruby(self):
        for beta in (False, True):
            for unsigned in (False, True):
                cask = render(template(), "1.6.0-beta.2" if beta else "1.6.0", SHA,
                              unsigned=unsigned, auto_updates=True, beta=beta)
                with tempfile.NamedTemporaryFile("w", suffix=".rb", delete=False) as f:
                    f.write(cask)
                try:
                    result = subprocess.run(["ruby", "-c", f.name], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                finally:
                    os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
