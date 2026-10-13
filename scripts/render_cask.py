#!/usr/bin/env python3
"""Render the Homebrew cask for a release from homebrew/Casks/focusrite-volume-control.rb.

The release workflow copies the rendered cask into the tap repository, so this repo's
cask stays the single source of truth. Unsigned builds get a postflight that clears
the quarantine attribute, since Gatekeeper blocks un-notarized apps downloaded by brew.

Usage:
  render_cask.py --version 1.6 --sha256 <hex> [--unsigned] [--auto-updates] SRC DEST
"""

import argparse
import re
import sys

QUARANTINE_POSTFLIGHT = '''
  # Unsigned build: clear quarantine so Gatekeeper doesn't block the app
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Volume Control.app"]
  end
'''


def render(source: str, version: str, sha256: str, unsigned: bool, auto_updates: bool) -> str:
    if not re.fullmatch(r"[0-9]+(\.[0-9]+)*", version):
        raise ValueError(f"unexpected version: {version!r}")
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise ValueError(f"unexpected sha256: {sha256!r}")

    def sub(pattern: str, replacement: str, text: str) -> str:
        result, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f"pattern not found in cask: {pattern}")
        return result

    cask = sub(r'^  version ".*"$', f'  version "{version}"', source)
    cask = sub(r'^  sha256 .*$', f'  sha256 "{sha256}"', cask)
    if auto_updates:
        cask = sub(r'^(  depends_on .*)$', r'  auto_updates true\n\1', cask)
    if unsigned:
        cask = sub(r'^(  app ".*")$', lambda m: m.group(1) + "\n" + QUARANTINE_POSTFLIGHT.rstrip("\n"), cask)
    return cask


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--unsigned", action="store_true", help="add the quarantine-clearing postflight")
    parser.add_argument("--auto-updates", action="store_true", help="the app updates itself (Sparkle)")
    parser.add_argument("source")
    parser.add_argument("dest")
    args = parser.parse_args()

    with open(args.source) as f:
        source = f.read()
    try:
        cask = render(source, args.version, args.sha256, args.unsigned, args.auto_updates)
    except ValueError as error:
        print(f"render_cask: {error}", file=sys.stderr)
        return 1
    with open(args.dest, "w") as f:
        f.write(cask)
    return 0


if __name__ == "__main__":
    sys.exit(main())
