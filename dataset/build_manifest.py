#!/usr/bin/env python3
"""
Computes a SHA-256 manifest of every generated shard file under dataset/output/.
Used as the integrity baseline: after upload, security-tests/test_05_integrity_verification.sh
re-downloads objects from MinIO and compares their hash against this manifest to detect
accidental corruption or tampering.
"""
import argparse
import hashlib
import json
import os


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default=os.path.join(os.path.dirname(__file__), "output"))
    args = parser.parse_args()

    manifest = {}
    for bucket in sorted(os.listdir(args.output_dir)):
        bucket_dir = os.path.join(args.output_dir, bucket)
        if not os.path.isdir(bucket_dir):
            continue
        for fname in sorted(os.listdir(bucket_dir)):
            fpath = os.path.join(bucket_dir, fname)
            if not os.path.isfile(fpath):
                continue
            manifest[f"{bucket}/{fname}"] = {
                "sha256": sha256_of(fpath),
                "size_bytes": os.path.getsize(fpath),
            }

    manifest_path = os.path.join(args.output_dir, "manifest.sha256.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)

    print(f"[+] Manifest written: {manifest_path} ({len(manifest)} objects hashed)")


if __name__ == "__main__":
    main()
