#!/usr/bin/env python3
"""Validate the exact FlowTab item emitted into a signed Sparkle appcast."""

from __future__ import annotations

import argparse
import hashlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SPARKLE = f"{{{SPARKLE_NAMESPACE}}}"


class ValidationError(RuntimeError):
    pass


def required_attribute(element: ET.Element, name: str) -> str:
    value = element.get(name)
    if value is None or not value.strip():
        raise ValidationError(f"enclosure is missing {name}")
    return value.strip()


def required_text(item: ET.Element, name: str) -> str:
    element = item.find(f"{SPARKLE}{name}")
    if element is None or element.text is None or not element.text.strip():
        raise ValidationError(f"item is missing sparkle:{name}")
    return element.text.strip()


def sparkle_metadata(
    item: ET.Element,
    enclosure: ET.Element,
    name: str,
) -> str:
    item_element = item.find(f"{SPARKLE}{name}")
    item_value = (
        item_element.text.strip()
        if item_element is not None
        and item_element.text is not None
        and item_element.text.strip()
        else None
    )
    enclosure_value = enclosure.get(f"{SPARKLE}{name}")
    if enclosure_value is not None:
        enclosure_value = enclosure_value.strip() or None
    if item_value is not None and enclosure_value is not None \
        and item_value != enclosure_value:
        raise ValidationError(
            f"item and enclosure disagree on sparkle:{name}"
        )
    value = item_value or enclosure_value
    if value is None:
        raise ValidationError(f"item is missing sparkle:{name}")
    return value


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--display-version", required=True)
    parser.add_argument("--build-version", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--channel", required=True)
    parser.add_argument("--minimum-system-version", required=True)
    parser.add_argument("--sha256", required=True)
    args = parser.parse_args()

    try:
        archive = args.archive.resolve(strict=True)
        appcast = args.appcast.resolve(strict=True)
        tree = ET.parse(appcast)
        matching: list[tuple[ET.Element, ET.Element]] = []
        for item in tree.findall("./channel/item"):
            enclosure = item.find("enclosure")
            if enclosure is None:
                continue
            if sparkle_metadata(item, enclosure, "version") \
                == args.build_version:
                matching.append((item, enclosure))
        if len(matching) != 1:
            raise ValidationError(
                "appcast must contain exactly one item for the expected build"
            )

        item, enclosure = matching[0]
        if sparkle_metadata(item, enclosure, "shortVersionString") \
            != args.display_version:
            raise ValidationError("display version does not match")
        if required_attribute(enclosure, "url") != args.download_url:
            raise ValidationError("download URL does not match")
        expected_length = archive.stat().st_size
        if required_attribute(enclosure, "length") != str(expected_length):
            raise ValidationError("enclosure length does not match the archive")
        if required_attribute(enclosure, "type") != "application/octet-stream":
            raise ValidationError("enclosure MIME type is not application/octet-stream")
        signature = required_attribute(enclosure, f"{SPARKLE}edSignature")
        if required_text(item, "channel") != args.channel:
            raise ValidationError("Sparkle channel does not match")
        if required_text(item, "minimumSystemVersion") \
            != args.minimum_system_version:
            raise ValidationError("minimum system version does not match")
        if digest(archive) != args.sha256.lower():
            raise ValidationError("archive SHA-256 does not match")

        print(signature)
        return 0
    except (
        ET.ParseError,
        OSError,
        ValidationError,
    ) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
