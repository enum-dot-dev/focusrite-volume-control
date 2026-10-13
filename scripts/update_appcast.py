#!/usr/bin/env python3
"""Add a release to the Sparkle appcast (site/appcast.xml), newest first.

The release workflow runs this after signing the DMG with Sparkle's sign_update,
then commits the appcast so GitHub Pages serves it. An existing item for the same
version is replaced, so re-running a release is safe.

Usage:
  update_appcast.py APPCAST --version 1.6 --url URL --length BYTES --signature SIG
                    [--minimum-system-version 14.5] [--release-notes-url URL] [--pub-date RFC822]
"""

import argparse
import sys
import xml.etree.ElementTree as ET
from typing import Optional
from email.utils import formatdate

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)


def sparkle(tag: str) -> str:
    return f"{{{SPARKLE_NS}}}{tag}"


def add_release(tree: ET.ElementTree, version: str, url: str, length: int, signature: str,
                minimum_system_version: str, release_notes_url: Optional[str], pub_date: str) -> None:
    channel = tree.getroot().find("channel")
    if channel is None:
        raise ValueError("appcast has no <channel>")

    for item in channel.findall("item"):
        if item.findtext(sparkle("version")) == version:
            channel.remove(item)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {version}"
    ET.SubElement(item, "pubDate").text = pub_date
    # CFBundleVersion and CFBundleShortVersionString are both stamped from the tag
    ET.SubElement(item, sparkle("version")).text = version
    ET.SubElement(item, sparkle("shortVersionString")).text = version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = minimum_system_version
    if release_notes_url:
        ET.SubElement(item, sparkle("fullReleaseNotesLink")).text = release_notes_url
    ET.SubElement(item, "enclosure", {
        "url": url,
        "length": str(length),
        "type": "application/octet-stream",
        sparkle("edSignature"): signature,
    })

    # Keep items newest first, after the channel's own metadata
    items = sorted(channel.findall("item") + [item],
                   key=lambda i: version_key(i.findtext(sparkle("version")) or ""), reverse=True)
    for existing in channel.findall("item"):
        channel.remove(existing)
    channel.extend(items)


def version_key(version: str) -> tuple:
    return tuple(int(part) if part.isdigit() else 0 for part in version.split("."))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("appcast")
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True, type=int)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--minimum-system-version", default="14.5")
    parser.add_argument("--release-notes-url")
    parser.add_argument("--pub-date", default=formatdate(usegmt=True))
    args = parser.parse_args()

    tree = ET.parse(args.appcast)
    try:
        add_release(tree, args.version, args.url, args.length, args.signature,
                    args.minimum_system_version, args.release_notes_url, args.pub_date)
    except ValueError as error:
        print(f"update_appcast: {error}", file=sys.stderr)
        return 1
    ET.indent(tree, space="  ")
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)
    with open(args.appcast, "a") as f:
        f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
