#!/usr/bin/env python3
"""Create VietCode app icons from the portrait supplied by the user.

This runs *before* flutter build so both native Windows icon resources and
Flutter's About-page asset use the same user-selected image. The source file
is committed once; generated binaries must not be hand-edited.
"""
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets/branding/vietcode_photo.jpg"


def write_png(im: Image.Image, relative: str, size: int) -> None:
    out = ROOT / relative
    out.parent.mkdir(parents=True, exist_ok=True)
    im.resize((size, size), Image.Resampling.LANCZOS).save(out, "PNG")


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"User-supplied VietCode icon missing: {SOURCE}")
    with Image.open(SOURCE) as original:
        square = ImageOps.fit(original.convert("RGBA"), (1024, 1024),
                              method=Image.Resampling.LANCZOS)
    for path, size in (
        ("assets/branding/app_icon.png", 128),
        ("web/favicon.png", 256),
        ("site/icon.png", 256),
    ):
        write_png(square, path, size)

    ico = ROOT / "windows/runner/resources/app_icon.ico"
    ico.parent.mkdir(parents=True, exist_ok=True)
    square.save(ico, format="ICO", sizes=[
        (16, 16), (24, 24), (32, 32),
        (48, 48), (64, 64), (128, 128), (256, 256),
    ])

    mac = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    if mac.is_dir():
        for size in (16, 32, 64, 128, 256, 512, 1024):
            write_png(square,
                      f"macos/Runner/Assets.xcassets/AppIcon.appiconset/"
                      f"app_icon_{size}.png", size)
    print(f"VietCode branding generated from {SOURCE.name}")


if __name__ == "__main__":
    main()
