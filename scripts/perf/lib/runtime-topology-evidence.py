#!/usr/bin/env python3
import csv
import json
import math
import os
import plistlib
import re
import sys


def validate_manifest(arguments):
    (path,) = arguments
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
    required = {
        "schema_version",
        "resource_boundary",
        "resolved_app_path",
        "bundle_id",
        "executable_sha256",
        "designated_requirement_sha256",
        "pid_binding_policy_version",
        "launch_oracle",
    }
    if set(payload) != required:
        missing = sorted(required - set(payload))
        extra = sorted(set(payload) - required)
        raise SystemExit(f"identity manifest fields mismatch; missing={missing}, extra={extra}")
    if payload["schema_version"] != 1:
        raise SystemExit("identity manifest schema_version must be 1")
    if payload["resource_boundary"] != "private_manifest":
        raise SystemExit("identity manifest resource_boundary must be private_manifest")
    app_path = payload["resolved_app_path"]
    if not isinstance(app_path, str) or not os.path.isabs(app_path) or any(
        character in app_path for character in "\t\n"
    ):
        raise SystemExit("resolved_app_path must be an absolute single-line path")
    if os.path.normpath(app_path) != app_path:
        raise SystemExit("resolved_app_path must be normalized")
    bundle_id = payload["bundle_id"]
    if not isinstance(bundle_id, str) or not bundle_id or any(
        character in bundle_id for character in "\t\n"
    ):
        raise SystemExit("bundle_id must be a non-empty single-line string")
    for key in ("executable_sha256", "designated_requirement_sha256"):
        if not isinstance(payload[key], str) or not re.fullmatch(r"[0-9a-f]{64}", payload[key]):
            raise SystemExit(f"{key} must be a lowercase SHA-256")
    if payload["pid_binding_policy_version"] != "flowtab.runtime.pid-binding.v1":
        raise SystemExit("unsupported pid_binding_policy_version")
    if payload["launch_oracle"] != "unique_post_request_identity_match":
        raise SystemExit("unsupported launch_oracle")
    print(
        "\t".join(
            (
                app_path,
                bundle_id,
                payload["executable_sha256"],
                payload["designated_requirement_sha256"],
                payload["pid_binding_policy_version"],
            )
        )
    )


def read_plist(arguments):
    (path,) = arguments
    with open(path, "rb") as handle:
        payload = plistlib.load(handle)
    bundle_id = str(payload.get("CFBundleIdentifier", ""))
    executable = str(payload.get("CFBundleExecutable", ""))
    if not bundle_id or not executable or any(
        character in bundle_id + executable for character in "\t\n"
    ):
        raise SystemExit("App Info.plist lacks a usable bundle identifier or executable")
    print(f"{bundle_id}\t{executable}")


def write_json_atomically(output_path, payload, exclusive):
    temporary_path = output_path + ".tmp"
    flags = os.O_WRONLY | os.O_CREAT | (os.O_EXCL if exclusive else os.O_TRUNC)
    descriptor = os.open(temporary_path, flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary_path, output_path)
    directory_descriptor = os.open(os.path.dirname(output_path), os.O_RDONLY)
    try:
        os.fsync(directory_descriptor)
    finally:
        os.close(directory_descriptor)


def write_manifest(arguments):
    output_path, app_path, bundle_id, executable_sha256, requirement_sha256 = arguments
    payload = {
        "schema_version": 1,
        "resource_boundary": "private_manifest",
        "resolved_app_path": app_path,
        "bundle_id": bundle_id,
        "executable_sha256": executable_sha256,
        "designated_requirement_sha256": requirement_sha256,
        "pid_binding_policy_version": "flowtab.runtime.pid-binding.v1",
        "launch_oracle": "unique_post_request_identity_match",
    }
    write_json_atomically(output_path, payload, exclusive=True)


def write_launch_receipt(arguments):
    (
        output_path,
        manifest_sha256,
        app_path,
        bundle_id,
        executable_sha256,
        requirement_sha256,
        policy_version,
        request_monotonic_ns,
        request_epoch_seconds,
        observed_monotonic_ns,
        pid,
        process_start_identity,
        process_start_epoch_seconds,
    ) = arguments
    payload = {
        "schema_version": 1,
        "identity_manifest_sha256": manifest_sha256,
        "resolved_app_path": app_path,
        "bundle_id": bundle_id,
        "executable_sha256": executable_sha256,
        "designated_requirement_sha256": requirement_sha256,
        "pid_binding_policy_version": policy_version,
        "launch_oracle": "unique_post_request_identity_match",
        "launch_request_monotonic_ns": int(request_monotonic_ns),
        "launch_request_epoch_seconds": int(request_epoch_seconds),
        "launch_observed_monotonic_ns": int(observed_monotonic_ns),
        "pid": int(pid),
        "process_start_epoch_seconds": int(process_start_epoch_seconds),
        "process_start_identity": process_start_identity,
        "verdict": "matched",
    }
    write_json_atomically(output_path, payload, exclusive=False)


def percentile(values, percentile_value):
    ordered = sorted(values)
    index = math.ceil((percentile_value / 100.0) * len(ordered)) - 1
    return ordered[max(0, min(index, len(ordered) - 1))]


def summarize(arguments):
    (
        samples_path,
        summary_path,
        sample_interval,
        test_filter,
        identity_check_count,
        identity_verdict,
        ui_test_status,
        pid_bindings_path,
        launch_receipt_path,
    ) = arguments
    with open(samples_path, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    with open(pid_bindings_path, newline="", encoding="utf-8") as handle:
        identity_rows = list(csv.DictReader(handle))
    with open(launch_receipt_path, encoding="utf-8") as handle:
        launch_receipt = json.load(handle)
    if not rows:
        raise SystemExit("No FlowTab samples collected.")

    receipt_pid = str(launch_receipt["pid"])
    receipt_start_epoch_seconds = str(launch_receipt["process_start_epoch_seconds"])
    identity_contract_valid = (
        len(identity_rows) == len(rows)
        and int(identity_check_count) == len(identity_rows)
        and identity_verdict == "matched"
        and launch_receipt.get("verdict") == "matched"
        and all(
            row["verdict"] == "matched"
            and row["pid"] == receipt_pid
            and row["process_start_epoch_seconds"] == receipt_start_epoch_seconds
            for row in identity_rows
        )
        and all(row["pid"] == receipt_pid for row in rows)
    )
    cpu_values = [float(row["cpu_percent"]) for row in rows]
    rss_kb_values = [float(row["rss_kb"]) for row in rows]
    summary = [
        "Runtime topology pressure summary",
        f"test={test_filter}",
        f"uiWrapperStatus={ui_test_status}",
        f"sampleIntervalSeconds={sample_interval}",
        f"identityCheckCount={len(identity_rows)}",
        f"identityVerdict={identity_verdict}",
        f"identityContractVerdict={'matched' if identity_contract_valid else 'mismatch'}",
        f"samples={len(rows)}",
        f"cpuAvg={sum(cpu_values) / len(cpu_values):.2f}",
        f"cpuP95={percentile(cpu_values, 95):.2f}",
        f"cpuMax={max(cpu_values):.2f}",
        f"rssAvgMB={(sum(rss_kb_values) / len(rss_kb_values)) / 1024.0:.2f}",
        f"rssP95MB={percentile(rss_kb_values, 95) / 1024.0:.2f}",
        f"rssMaxMB={max(rss_kb_values) / 1024.0:.2f}",
    ]
    with open(summary_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(summary))
        handle.write("\n")
    print("\n".join(summary))
    if not identity_contract_valid:
        raise SystemExit(
            "PID-binding rows, samples, and target launch receipt do not form a one-to-one identity mapping."
        )


def main():
    if len(sys.argv) < 2:
        raise SystemExit("A command is required.")
    handlers = {
        "validate-manifest": validate_manifest,
        "read-plist": read_plist,
        "write-manifest": write_manifest,
        "write-launch-receipt": write_launch_receipt,
        "summarize": summarize,
    }
    command = sys.argv[1]
    if command not in handlers:
        raise SystemExit(f"Unknown command: {command}")
    handlers[command](sys.argv[2:])


if __name__ == "__main__":
    main()
