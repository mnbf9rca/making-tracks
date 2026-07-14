import ast
import pathlib

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
}


def test_metadata_is_never_a_record_field():
    fields = set(source_record.SourceRecord.__dataclass_fields__)
    assert "run_id" not in fields
    assert "completed_at" not in fields


def test_no_wallclock_or_randomness_outside_completed_at():
    src_dir = pathlib.Path(stages.__file__).parent
    offenders = []
    for path in sorted(src_dir.glob("*.py")):
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute) and node.attr in _BANNED:
                fn = _enclosing_func(tree, node)
                if not (path.name == "stages.py" and fn == "_completed_at" and node.attr == "now"):
                    offenders.append(f"{path.name}:{fn}:{node.attr}")
    assert offenders == [], f"non-determinism outside stages._completed_at: {offenders}"


def _enclosing_func(tree, target):
    for fn in [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]:
        if any(node is target for node in ast.walk(fn)):
            return fn.name
    return None
