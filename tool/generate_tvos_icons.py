#!/usr/bin/env python3
"""Regenerate tvOS catalog artwork from icons/new-icon.png (requires Pillow)."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'tvos/Runner/Assets.xcassets/AppIcon.brandassets'
SOURCE = ROOT / 'icons/new-icon.png'


def generate():
    logo = Image.open(SOURCE).convert('RGBA')
    # Preserve the existing logo exactly; its three colors become parallax layers.
    layers = {name: Image.new('RGBA', logo.size) for name in ('Front', 'Middle', 'Back')}
    pixels = {name: image.load() for name, image in layers.items()}
    for y in range(logo.height):
        for x in range(logo.width):
            r, g, b, a = logo.getpixel((x, y))
            if a:
                name = 'Front' if r >= max(g, b) else ('Back' if g >= b else 'Middle')
                pixels[name][x, y] = (r, g, b, a)
    for stack in CATALOG.glob('*.imagestack'):
        for imageset in stack.glob('*.imagestacklayer/Content.imageset'):
            layer = imageset.parent.stem
            for item in json.loads((imageset / 'Contents.json').read_text())['images']:
                path = imageset / item['filename']
                with Image.open(path) as old:
                    size = old.size
                side = round(size[1] * 5 / 6)
                artwork = layers[layer].resize((side, side), Image.Resampling.LANCZOS)
                canvas = Image.new('RGBA', size, 'white' if layer == 'Back' else (0, 0, 0, 0))
                canvas.alpha_composite(artwork, ((size[0] - side) // 2, (size[1] - side) // 2))
                if layer == 'Back':
                    canvas = canvas.convert('RGB')
                canvas.save(path, optimize=True)
    for imageset in CATALOG.glob('*.imageset'):
        for item in json.loads((imageset / 'Contents.json').read_text())['images']:
            path = imageset / item['filename']
            with Image.open(path) as old:
                size = old.size
            side = round(size[1] * 5 / 6)
            artwork = logo.resize((side, side), Image.Resampling.LANCZOS)
            canvas = Image.new('RGBA', size, 'white')
            canvas.alpha_composite(artwork, ((size[0] - side) // 2, (size[1] - side) // 2))
            canvas.convert('RGB').save(path, optimize=True)


if __name__ == '__main__':
    generate()
