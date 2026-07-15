import ast
import pathlib
import textwrap

from mt_pipeline import source_record, stages

_BANNED = {
    "now",
    "utcnow",
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
    "today",
}


def test_metadata_is_never_a_record_field():
    fields = set(source_record.SourceRecord.__dataclass_fields__)
    assert "run_id" not in fields
    assert "completed_at" not in fields


def test_no_wallclock_or_randomness_outside_completed_at():
    src_dir = pathlib.Path(stages.__file__).parent
    offenders = []
    for path in sorted(src_dir.glob("*.py")):
        offenders.extend(_find_nondeterministic_calls(path.name, path.read_text()))
    assert offenders == [], f"non-determinism outside stages._completed_at: {offenders}"


def test_determinism_scan_catches_banned_imported_calls():
    source = """
        from time import time
        from random import random
        from uuid import uuid4
        import datetime

        def build_record():
            return time(), random(), uuid4(), datetime.date.today()
    """

    assert _find_nondeterministic_calls("example.py", textwrap.dedent(source)) == [
        "example.py:build_record:time",
        "example.py:build_record:random",
        "example.py:build_record:uuid4",
        "example.py:build_record:today",
    ]


def _enclosing_func(tree, target):
    for fn in [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]:
        if any(node is target for node in ast.walk(fn)):
            return fn.name
    return None


def _find_nondeterministic_calls(path_name: str, source: str) -> list[str]:
    tree = ast.parse(source)
    offenders = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = _call_name(node.func)
        if name not in _BANNED:
            continue
        fn = _enclosing_func(tree, node)
        if path_name == "stages.py" and fn == "_completed_at" and name == "now":
            continue
        if path_name == "fetch.py" and fn in {"get_json", "get_to_file"} and name == "monotonic":
            continue
        if (
            path_name == "progress.py"
            and fn in {"__init__", "tick", "done"}
            and name == "monotonic"
        ):
            continue
        offenders.append(f"{path_name}:{fn}:{name}")
    return offenders


def _call_name(func) -> str | None:
    if isinstance(func, ast.Attribute):
        return func.attr
    if isinstance(func, ast.Name):
        return func.id
    return None
