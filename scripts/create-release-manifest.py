#!/usr/bin/env python3

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--zig-version", required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--artifact", required=True, action="append", metavar="TARGET=PATH")
    args = parser.parse_args()

    artifacts = []
    for item in args.artifact:
        target, separator, path_text = item.partition("=")
        if not separator:
            parser.error(f"artifact must be TARGET=PATH: {item}")
        path = Path(path_text)
        if not path.is_file():
            parser.error(f"artifact does not exist: {path}")
        artifacts.append(
            {
                "target": target,
                "filename": path.name,
                "sha256": sha256(path),
            }
        )

    artifacts.sort(key=lambda artifact: artifact["target"])
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "tag": args.tag,
        "commit": args.commit,
        "zig_version": args.zig_version,
        "artifacts": artifacts,
    }
    (output_dir / "release-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (output_dir / "SHA256SUMS").write_text(
        "".join(f"{artifact['sha256']}  {artifact['filename']}\n" for artifact in artifacts),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
