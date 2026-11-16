#!/usr/bin/env python3
"""Makes the app's icons from MyGo Music's own (resources/icon.png in
egoist/mygo-music, 1024x1024, a macOS rounded square with a margin and a
shadow).

    pip install pillow numpy scipy
    python3 tool/icons/make_icons.py path/to/mygo-music/resources/icon.png

What it writes:
  - Android: legacy mipmap-*/ic_launcher.png (the icon as it is, for
    launchers before adaptive icons) and an adaptive icon
    (mipmap-anydpi-v26/ic_launcher.xml): a foreground of its artwork sized into
    the 66 dp safe zone and carried on to the layer's edges (over a background
    of the icon's red), so a circle,
    squircle or rounded-square mask never cuts the tonearm or the record.
  - Web: favicon.png/.ico and icons/Icon-192/512 (the icon as it is),
    Icon-maskable-192/512 (the artwork inside the maskable safe circle, 80%
    of the size, carried on to the edges), apple-touch-icon(-precomposed).png.
  - iOS: AppIcon.appiconset (the artwork edge to edge, no alpha; iOS rounds
    the corners itself).
  - build/icon-previews/*.png: the adaptive and maskable icons under circle,
    squircle and rounded-square masks, to look at.

"The artwork" is the rounded square cut out of the icon (pixels 100-923)
with its transparent corners filled in from the nearest opaque pixel, so it
can go edge to edge.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
RES = os.path.join(ROOT, 'android/app/src/main/res')
WEB = os.path.join(ROOT, 'web')
IOS = os.path.join(ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset')
PREVIEW = os.path.join(ROOT, 'build/icon-previews')

# The rounded square's opaque extent in the 1024 px icon.
BOX = (100, 100, 924, 924)

# How far from the artwork's centre (as a fraction of its width) its
# outermost part that must stay whole reaches: the tonearm's head, top
# right, measured on the icon (about 0.53). Sizes below keep it inside masks.
REACH = 0.54


def artwork(icon: Image.Image) -> Image.Image:
    a = np.array(icon.crop(BOX).convert('RGBA'))
    opaque = a[:, :, 3] == 255
    # For every pixel, the nearest opaque one: fills the rounded corners.
    _, (iy, ix) = ndimage.distance_transform_edt(~opaque, return_indices=True)
    filled = a[iy, ix]
    filled[:, :, 3] = 255
    return Image.fromarray(filled, 'RGBA')


def red(art: Image.Image):
    """The icon's red, top and bottom, from its right edge (no record there)."""
    a = np.array(art)
    w = a.shape[1]
    top = a[int(0.06 * w):int(0.12 * w), int(0.9 * w):int(0.96 * w), :3].reshape(-1, 3).mean(0)
    bottom = a[int(0.86 * w):int(0.9 * w), int(0.94 * w):int(0.98 * w), :3].reshape(-1, 3).mean(0)
    return tuple(int(v) for v in top), tuple(int(v) for v in bottom)


def gradient(size, top, bottom):
    t = np.linspace(0, 1, size)[:, None, None]
    rows = (np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t)
    img = np.repeat(rows, size, axis=1)
    alpha = np.full((size, size, 1), 255)
    return Image.fromarray(np.concatenate([img, alpha], 2).astype('uint8'), 'RGBA')


def bleed(art, size, scale):
    """A size x size square with the artwork at scale x size in its centre
    and its edges carried on outwards to the borders (each border pixel
    repeating the artwork's nearest edge, softened), so the artwork has no
    visible frame: the record runs off the left and bottom as it does in the
    icon, the red continues above and to the right."""
    # The outermost few percent are the rounded square's rim (a highlight on
    # top, a lighter edge below): cut, so the edges carried on are the art's.
    trim = round(art.size[0] * 0.045)
    art = art.crop((trim, trim, art.size[0] - trim, art.size[1] - trim))
    s = round(size * scale * art.size[0] / (art.size[0] + 2 * trim))
    a = np.array(art.resize((s, s), Image.LANCZOS)).astype(float)
    pad0 = (size - s) // 2
    pad1 = size - s - pad0
    out = np.pad(a, ((pad0, pad1), (pad0, pad1), (0, 0)), mode='edge')
    # Soften the repeated pixels (they'd be streaks), more the further out.
    blurred = ndimage.gaussian_filter(out, sigma=(size * 0.05, size * 0.05, 0))
    yy, xx = np.mgrid[0:size, 0:size]
    d = np.maximum(np.maximum(pad0 - xx, xx - (pad0 + s - 1)), np.maximum(pad0 - yy, yy - (pad0 + s - 1)))
    w = np.clip(d / max(1, size * 0.02), 0, 1)[:, :, None]
    out = out * (1 - w) + blurred * w
    out[:, :, 3] = 255
    return Image.fromarray(out.clip(0, 255).astype('uint8'), 'RGBA')


def save(img, path, rgb=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (img.convert('RGB') if rgb else img).save(path, optimize=True)


def mask(img, kind):
    size = img.size[0]
    m = Image.new('L', (size * 4, size * 4), 0)
    d = ImageDraw.Draw(m)
    s = size * 4
    if kind == 'circle':
        d.ellipse((0, 0, s - 1, s - 1), fill=255)
    elif kind == 'squircle':
        n = 5.0
        pts = []
        for i in range(720):
            th = 2 * np.pi * i / 720
            c, si = np.cos(th), np.sin(th)
            x = np.sign(c) * abs(c) ** (2 / n)
            y = np.sign(si) * abs(si) ** (2 / n)
            pts.append(((x + 1) / 2 * (s - 1), (y + 1) / 2 * (s - 1)))
        d.polygon(pts, fill=255)
    else:  # rounded square, as Android's default "rounded" shape
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=s * 0.18, fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), m)
    return out


def main(src):
    icon = Image.open(src).convert('RGBA')
    assert icon.size == (1024, 1024), icon.size
    art = artwork(icon)
    top, bottom = red(art)
    print('red', top, bottom)

    # --- Android -------------------------------------------------------
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    # The 66 dp safe circle of the 108 dp layer: radius 33 dp. The tonearm
    # reaches REACH of the artwork's width from its centre, so the artwork
    # may be 33 / REACH dp wide; it is drawn a little smaller.
    art_dp = 33 / REACH * 0.98
    for name, k in densities.items():
        save(icon.resize((round(48 * k),) * 2, Image.LANCZOS), f'{RES}/mipmap-{name}/ic_launcher.png')
        # The foreground is the whole 108 dp layer, edge to edge.
        save(bleed(art, round(108 * k), art_dp / 108), f'{RES}/mipmap-{name}/ic_launcher_foreground.png', rgb=True)
    os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
    with open(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- Made by tool/icons/make_icons.py from MyGo Music\'s icon. -->\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    os.makedirs(f'{RES}/drawable', exist_ok=True)
    with open(f'{RES}/drawable/ic_launcher_background.xml', 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- The red of MyGo Music\'s icon, top to bottom (tool/icons/make_icons.py). -->\n'
                '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
                f'    <gradient android:angle="270" android:startColor="#FF{top[0]:02X}{top[1]:02X}{top[2]:02X}" '
                f'android:endColor="#FF{bottom[0]:02X}{bottom[1]:02X}{bottom[2]:02X}"/>\n'
                '</shape>\n')

    # --- Web -----------------------------------------------------------
    for size in (192, 512):
        save(icon.resize((size, size), Image.LANCZOS), f'{WEB}/icons/Icon-{size}.png')
        # Maskable: the safe zone is a circle of radius 40% of the size.
        save(bleed(art, size, 0.40 / REACH * 0.98), f'{WEB}/icons/Icon-maskable-{size}.png', rgb=True)
    save(icon.resize((32, 32), Image.LANCZOS), f'{WEB}/favicon.png')
    icon.resize((48, 48), Image.LANCZOS).save(f'{WEB}/favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)])
    touch = art.resize((180, 180), Image.LANCZOS)
    save(touch, f'{WEB}/apple-touch-icon.png', rgb=True)
    save(touch, f'{WEB}/apple-touch-icon-precomposed.png', rgb=True)

    # --- iOS -----------------------------------------------------------
    if os.path.isdir(IOS):
        import json
        with open(f'{IOS}/Contents.json') as f:
            contents = json.load(f)
        for image in contents['images']:
            pts = float(image['size'].split('x')[0])
            px = round(pts * int(image['scale'].rstrip('x')))
            save(art.resize((px, px), Image.LANCZOS), f"{IOS}/{image['filename']}", rgb=True)

    # --- Previews --------------------------------------------------------
    os.makedirs(PREVIEW, exist_ok=True)
    k = 4
    fg = Image.open(f'{RES}/mipmap-xxxhdpi/ic_launcher_foreground.png').convert('RGBA')
    layer = gradient(round(108 * k), top, bottom)
    layer.alpha_composite(fg)
    layer.save(f'{PREVIEW}/adaptive-layers-108dp.png')
    view = layer.crop((18 * k, 18 * k, 90 * k, 90 * k))  # the 72 dp a launcher shows
    maskable = Image.open(f'{WEB}/icons/Icon-maskable-512.png').resize((288, 288), Image.LANCZOS)
    sheet = Image.new('RGBA', (3 * 300 + 20, 2 * 300 + 20), (40, 40, 44, 255))
    for i, kind in enumerate(('circle', 'squircle', 'rounded')):
        sheet.alpha_composite(mask(view, kind), (10 + i * 300, 10))
        sheet.alpha_composite(mask(maskable, kind), (10 + i * 300, 310))
    sheet.save(f'{PREVIEW}/masks.png')
    print('previews in', PREVIEW)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '../mygo-music/resources/icon.png')
