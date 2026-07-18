import hashlib
import json

from mt_contracts.validation import validate_instance
from mt_pipeline.publish import pack_descriptor


def _write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def test_pack_descriptor_emits_sha_list_for_sidecars_and_optional_images(tmp_path):
    staging = tmp_path / "uk" / "20260718T090000Z"
    thumb_sha = hashlib.sha256(b"thumb").hexdigest()
    _write(staging / "descriptions/10/509/340.json", b'{"description":true}')
    _write(
        staging / "images/10/509/340.json",
        b'{"places":[{"thumb_sha256":"' + thumb_sha.encode() + b'"}]}',
    )
    _write(tmp_path / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp", b"thumb")
    _write(tmp_path / "thumbs/bb/" / ("b" * 64 + ".webp"), b"stale")
    _write(staging / "search/index.json", b'{"search":true}')

    descriptor = pack_descriptor.assemble_from_staging(
        staging,
        generated_at="2026-07-18T09:00:00Z",
    )

    validate_instance("pack-descriptor", descriptor)
    assert descriptor["region"] == "uk"
    assert descriptor["publish_version"] == "20260718T090000Z"
    objects = {(obj["kind"], obj["path"]): obj for obj in descriptor["objects"]}
    desc = objects[("description_index", "descriptions/10/509/340.json")]
    assert desc["sha256"] == hashlib.sha256(b'{"description":true}').hexdigest()
    assert desc["optional"] is False
    image = objects[("image_index", "images/10/509/340.json")]
    assert image["optional"] is True
    thumb = objects[("image_thumb", f"thumbs/{thumb_sha[:2]}/{thumb_sha}.webp")]
    assert thumb["bytes"] == 5
    assert ("image_thumb", "thumbs/bb/" + "b" * 64 + ".webp") not in objects
    assert objects[("search_index", "search/index.json")]["optional"] is False


def test_write_pack_descriptor_writes_deterministic_json(tmp_path):
    staging = tmp_path / "uk" / "20260718T090000Z"
    _write(staging / "descriptions/10/509/340.json", b"{}")

    path = pack_descriptor.write_pack_descriptor(
        staging,
        generated_at="2026-07-18T09:00:00Z",
    )

    payload = json.loads(path.read_text())
    validate_instance("pack-descriptor", payload)
    assert path == staging / "pack-descriptor.json"
