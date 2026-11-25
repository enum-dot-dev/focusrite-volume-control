#!/usr/bin/env python3
"""Render a Homebrew cask for a release from homebrew/Casks/focusrite-volume-control.rb.

The release workflow copies the rendered casks into the tap repository, so this repo's
cask stays the single source of truth. Unsigned builds get a postflight_steps stanza that
clears the quarantine attribute, since Gatekeeper blocks un-notarized apps downloaded by
brew. Homebrew deprecated Ruby flight blocks (`postflight do ... system_command ...`), so
the stanza uses the declarative steps DSL with an install-time {{appdir}} token.

--beta renders focusrite-volume-control@beta instead. Both casks install the same app,
so each one conflicts with the other. Only the beta cask accepts prerelease versions
such as 1.6.0-beta.1.

Usage:
  render_cask.py --version 1.6.0 --sha256 <hex> [--beta] [--unsigned] [--auto-updates] SRC DEST
"""

import argparse
import re
import sys

STABLE_TOKEN = "focusrite-volume-control"
BETA_TOKEN = f"{STABLE_TOKEN}@beta"

STABLE_VERSION = r"[0-9]+(\.[0-9]+)*"
PRERELEASE_VERSION = STABLE_VERSION + r"(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?"

QUARANTINE_POSTFLIGHT = '''
  # Unsigned build: clear quarantine so Gatekeeper doesn't block the app
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-cr", "{{appdir}}/Volume Control.app"]
  end
'''


def render(source: str, version: str, sha256: str, unsigned: bool, auto_updates: bool,
           beta: bool = False) -> str:
    if not re.fullmatch(PRERELEASE_VERSION if beta else STABLE_VERSION, version):
        hint = "" if beta else " (prerelease versions go to the beta cask only)"
        raise ValueError(f"unexpected version: {version!r}{hint}")
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise ValueError(f"unexpected sha256: {sha256!r}")

    def sub(pattern: str, replacement, text: str) -> str:
        result, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f"pattern not found in cask: {pattern}")
        return result

    cask = sub(r'^  version ".*"$', f'  version "{version}"', source)
    cask = sub(r'^  sha256 .*$', f'  sha256 "{sha256}"', cask)
    if beta:
        cask = sub(rf'^cask "{re.escape(STABLE_TOKEN)}" do$', f'cask "{BETA_TOKEN}" do', cask)
        cask = sub(r'^  conflicts_with cask: ".*"$', f'  conflicts_with cask: "{STABLE_TOKEN}"', cask)
    if auto_updates:
        # Homebrew's stanza order puts auto_updates before conflicts_with and depends_on
        cask = sub(r'^(  (?:conflicts_with|depends_on) .*)$', r'  auto_updates true\n\1', cask)
    if unsigned:
        cask = sub(r'^(  app ".*")$', lambda m: m.group(1) + "\n" + QUARANTINE_POSTFLIGHT.rstrip("\n"), cask)
    return cask


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--beta", action="store_true", help=f"render {BETA_TOKEN} instead of {STABLE_TOKEN}")
    parser.add_argument("--unsigned", action="store_true", help="add the quarantine-clearing postflight")
    parser.add_argument("--auto-updates", action="store_true", help="the app updates itself (Sparkle)")
    parser.add_argument("source")
    parser.add_argument("dest")
    args = parser.parse_args()

    with open(args.source) as f:
        source = f.read()
    try:
        cask = render(source, args.version, args.sha256, args.unsigned, args.auto_updates, args.beta)
    except ValueError as error:
        print(f"render_cask: {error}", file=sys.stderr)
        return 1
    with open(args.dest, "w") as f:
        f.write(cask)
    return 0


if __name__ == "__main__":
    sys.exit(main())
