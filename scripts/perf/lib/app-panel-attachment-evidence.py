#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import struct
import subprocess
import sys
import tempfile


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def scalar(node, key):
    value = node.get(key)
    if isinstance(value, dict):
        return value.get("_value")
    return None


def reference_ids(node, target_name=None):
    matches = []
    if isinstance(node, dict):
        node_type = node.get("_type", {}).get("_name")
        if node_type == "Reference":
            target = (
                node.get("targetType", {})
                .get("name", {})
                .get("_value")
            )
            identifier = scalar(node, "id")
            if identifier and (
                target_name is None or target == target_name
            ):
                matches.append(identifier)
        for value in node.values():
            matches.extend(reference_ids(value, target_name))
    elif isinstance(node, list):
        for value in node:
            matches.extend(reference_ids(value, target_name))
    return matches


def attachment_records(node):
    records = []
    if isinstance(node, dict):
        if node.get("_type", {}).get("_name") == "ActionTestAttachment":
            payload_ids = reference_ids(node.get("payloadRef", {}))
            if payload_ids:
                records.append(
                    {
                        "name": scalar(node, "name"),
                        "filename": scalar(node, "filename"),
                        "lifetime": scalar(node, "lifetime"),
                        "uniform_type_identifier": scalar(
                            node,
                            "uniformTypeIdentifier",
                        ),
                        "payload_size": int(
                            scalar(node, "payloadSize") or 0
                        ),
                        "payload_id": payload_ids[0],
                    }
                )
        for value in node.values():
            records.extend(attachment_records(value))
    elif isinstance(node, list):
        for value in node:
            records.extend(attachment_records(value))
    return records


def xcresult_json(xcresult_path, identifier=None):
    command = [
        "xcrun",
        "xcresulttool",
        "get",
        "--path",
        xcresult_path,
        "--format",
        "json",
    ]
    if identifier:
        command.extend(["--id", identifier])
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"xcresult read failed: {detail}")
    return json.loads(completed.stdout)


def discover_attachments(xcresult_path):
    root = xcresult_json(xcresult_path)
    plan_ids = reference_ids(root, "ActionTestPlanRunSummaries")
    summaries = []
    for plan_id in plan_ids:
        plan = xcresult_json(xcresult_path, plan_id)
        for summary_id in reference_ids(plan, "ActionTestSummary"):
            summaries.append(xcresult_json(xcresult_path, summary_id))
    records = []
    for summary in summaries:
        records.extend(attachment_records(summary))
    return records


def png_dimensions(path):
    with open(path, "rb") as handle:
        header = handle.read(24)
    if len(header) != 24 or header[:8] != PNG_SIGNATURE:
        raise ValueError("attachment is not a complete PNG")
    if header[12:16] != b"IHDR":
        raise ValueError("PNG is missing its IHDR chunk")
    return struct.unpack(">II", header[16:24])


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_atomically(path, content):
    temporary = path + ".tmp"
    with open(temporary, "x", encoding="utf-8") as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def export_attachment(
    xcresult_path,
    output_directory,
    expected_name,
    minimum_width,
    minimum_height,
):
    records = discover_attachments(xcresult_path)
    matches = [
        record
        for record in records
        if record["name"] == expected_name
        and record["lifetime"] == "keepAlways"
        and record["uniform_type_identifier"] == "public.png"
    ]
    if len(matches) != 1:
        observed = sorted(
            record["name"] or "<unnamed>" for record in records
        )
        raise RuntimeError(
            f"expected one attachment named {expected_name!r}; "
            f"observed {observed}"
        )
    record = matches[0]
    os.makedirs(output_directory, exist_ok=False)
    output_path = os.path.join(output_directory, expected_name + ".png")
    completed = subprocess.run(
        [
            "xcrun",
            "xcresulttool",
            "export",
            "--path",
            xcresult_path,
            "--id",
            record["payload_id"],
            "--output-path",
            output_path,
            "--type",
            "file",
        ],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"xcresult attachment export failed: {detail}")
    width, height = png_dimensions(output_path)
    if width < minimum_width or height < minimum_height:
        raise RuntimeError(
            f"attachment dimensions {width}x{height} are below "
            f"{minimum_width}x{minimum_height}"
        )
    byte_count = os.path.getsize(output_path)
    if byte_count != record["payload_size"]:
        raise RuntimeError(
            f"attachment payload size mismatch: "
            f"recorded={record['payload_size']} exported={byte_count}"
        )
    manifest = {
        "schema_version": 1,
        "name": expected_name,
        "filename": os.path.basename(output_path),
        "width_pixels": width,
        "height_pixels": height,
        "byte_count": byte_count,
        "sha256": sha256(output_path),
        "lifetime": record["lifetime"],
        "uniform_type_identifier": record[
            "uniform_type_identifier"
        ],
    }
    manifest_path = os.path.join(
        output_directory,
        "attachment-evidence.json",
    )
    write_atomically(
        manifest_path,
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    )
    return manifest


def self_test():
    attachment = {
        "_type": {"_name": "ActionTestAttachment"},
        "filename": {"_value": "checkpoint.png"},
        "lifetime": {"_value": "keepAlways"},
        "name": {"_value": "checkpoint"},
        "payloadRef": {
            "_type": {"_name": "Reference"},
            "id": {"_value": "payload"},
        },
        "payloadSize": {"_value": "24"},
        "uniformTypeIdentifier": {"_value": "public.png"},
    }
    records = attachment_records({"attachments": [attachment]})
    assert len(records) == 1
    assert records[0]["name"] == "checkpoint"
    with tempfile.TemporaryDirectory(
        prefix="flowtab-attachment-self-test-"
    ) as directory:
        path = os.path.join(directory, "image.png")
        with open(path, "wb") as handle:
            handle.write(
                PNG_SIGNATURE
                + struct.pack(">I", 13)
                + b"IHDR"
                + struct.pack(">II", 1440, 900)
            )
        assert png_dimensions(path) == (1440, 900)
        assert len(sha256(path)) == 64
    print("App-panel attachment name, PNG dimensions, and SHA-256 parser passed.")


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    export = subparsers.add_parser("export")
    export.add_argument("--xcresult", required=True)
    export.add_argument("--output-dir", required=True)
    export.add_argument("--expected-name", required=True)
    export.add_argument("--minimum-width", type=int, default=440)
    export.add_argument("--minimum-height", type=int, default=1)
    subparsers.add_parser("self-test")
    arguments = parser.parse_args()
    if arguments.command == "self-test":
        self_test()
        return 0
    try:
        manifest = export_attachment(
            os.path.abspath(arguments.xcresult),
            os.path.abspath(arguments.output_dir),
            arguments.expected_name,
            arguments.minimum_width,
            arguments.minimum_height,
        )
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(manifest, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
