import ast
import pathlib

import mt_pipeline

_BANNED = {
    "now",
    "utcnow",
    "today",
    "time",
    "monotonic",
    "perf_counter",
    "random",
    "shuffle",
    "uuid4",
    "uuid1",
    "urandom",
    "randint",
    "choice",
}


def test_no_wallclock_or_randomness_in_extractor_modules():
    root = pathlib.Path(mt_pipeline.__file__).parent / "extractors"
    offenders = []
    for path in sorted(root.rglob("*.py")):
        for node in ast.walk(ast.parse(path.read_text())):
            if isinstance(node, ast.Attribute) and node.attr in _BANNED:
                offenders.append(f"{path.name}:{node.attr}")
    assert offenders == []


def test_determinism_scan_covers_register_extractors():
    root = pathlib.Path(mt_pipeline.__file__).parent / "extractors"
    scanned = {path.relative_to(root).as_posix() for path in root.rglob("*.py")}

    assert "historic_england.py" in scanned
    assert "open_plaques.py" in scanned
