#!/usr/bin/env python3
"""Generate committed attribution artifacts."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from mt_pipeline.publish import credits


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if committed generated attribution artifacts are stale",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=credits.repo_root_from_module(),
        help="repository root",
    )
    args = parser.parse_args(argv)

    root = args.root.resolve()
    if args.check:
        stale = credits.stale_outputs(root)
        if stale:
            print("stale generated attribution artifacts:", file=sys.stderr)
            for path in stale:
                print(f"  {path.relative_to(root)}", file=sys.stderr)
            print(
                "run: uv run --package making-tracks-pipeline --extra dev "
                "python scripts/generate_attribution.py",
                file=sys.stderr,
            )
            return 1
        return 0

    credits.write_outputs(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
