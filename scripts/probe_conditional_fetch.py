"""Probe upstream conditional-fetch behavior for source classes.

Run from the repo root:
uv run --package making-tracks-pipeline --extra dev python scripts/probe_conditional_fetch.py \
  --output docs/research/2026-07-22-conditional-fetch-probe-results.json

The probe is intentionally bounded: one initial GET and, when validators are
present, one conditional GET per upstream class; all requests use the project
data-acquisition User-Agent, host allowlists, byte caps, and explicit GET method.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

from mt_pipeline import conditional_fetch_probe


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        help="write JSON probe results to this path; defaults to stdout",
    )
    args = parser.parse_args(argv)

    results = conditional_fetch_probe.run_default_probes()
    payload = conditional_fetch_probe.results_json(results)
    if args.output is None:
        sys.stdout.write(payload)
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
