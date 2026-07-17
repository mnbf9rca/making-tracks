"""Process-isolated image decode and WebP thumbnail encoding."""

from __future__ import annotations

import base64
import io
import json
import sys
import warnings
from pathlib import Path

MAX_IMAGE_PIXELS = 16_000_000
THUMB_MAX_EDGE = 512
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        print("usage: image_worker <image-path>", file=sys.stderr)
        return 2
    try:
        payload = transcode(Path(args[0]))
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1
    sys.stdout.write(json.dumps(payload, sort_keys=True, separators=(",", ":")))
    return 0


def transcode(path: Path) -> dict[str, object]:
    from PIL import Image

    Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(path) as image:
                if image.format not in ALLOWED_FORMATS:
                    raise ValueError(f"unsupported image format: {image.format!r}")
                width, height = image.size
                if width <= 0 or height <= 0 or width * height > MAX_IMAGE_PIXELS:
                    raise ValueError("image dimensions exceed decode cap")
                image.load()
                image.thumbnail((THUMB_MAX_EDGE, THUMB_MAX_EDGE))
                final_width, final_height = image.size
                out = io.BytesIO()
                image.convert("RGB").save(out, format="WEBP", quality=82, method=6)
    except (Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
        raise ValueError("image dimensions exceed decode cap") from exc
    return {
        "webp_b64": base64.b64encode(out.getvalue()).decode("ascii"),
        "width": final_width,
        "height": final_height,
    }


if __name__ == "__main__":
    raise SystemExit(main())
