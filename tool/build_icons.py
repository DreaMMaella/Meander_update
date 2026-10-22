#!/usr/bin/env python3
"""Значки приложения из векторного исходника.

    python3 tool/build_icons.py
    python3 tool/build_icons.py --preview [каталог]   # только монтаж плиток

Исходник — apps/main_app/assets/icon/logo.svg. На выходе: слои адаптивного
значка Android (VectorDrawable — потому что растр на масках лаунчера
мылится), legacy-пинги для API < 26, hicolor-иконки Linux, многослойный .ico
для Windows и мастера 512/1024. iOS, macOS и web добирает после этого
`dart run flutter_launcher_icons` по блоку flutter_launcher_icons в pubspec.yaml.

--preview ничего в репозитории не трогает: рисует в /tmp/icon_work монтаж
плиток лаунчера с несколькими радиусами рисунка, чтобы выбрать размер глазом,
а не пересборкой APK. Правится выбранный радиус константой ADAPTIVE_RADIUS.

Нужен rsvg-convert (librsvg).

Почему фон тёмный в обеих темах: лого — салатовые узлы на чёрном, на светлом
фоне #92FF26 теряет контраст. Настоящая системная адаптивность — monochrome
слой: на Android 13+ лаунчер сам перекрашивает значок под обои и тему.
"""

import math
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps" / "main_app"
SVG_SRC = APP / "assets" / "icon" / "logo.svg"
ANDROID_RES = APP / "android" / "app" / "src" / "main" / "res"
LINUX_ICONS = APP / "linux" / "runner" / "icons" / "hicolor"

# AppColors.dark.background — фон значка.
BACKGROUND = "#121212"
# Сторона канваса адаптивного значка в dp: видно 72, ещё по 18 dp с каждой
# стороны лаунчеры отдают под маску и параллакс.
CANVAS = 108.0
# Лаунчер НЕ вписывает канвас 108 в плитку — он берёт центральные 72 dp и
# растягивает их на всю плитку (зум 108/72 = 1.5), а 18 dp по краям уходят под
# маску и параллакс. Замерено по его же скриншоту: рисунок с радиусом 33 dp
# доставал до края плитки (92-100% полуширины), а не лежал в центре, как 61%.
VISIBLE_WINDOW = 72.0
# Максимальный радиус рисунка в канвасе 108 dp, отдельно для каждого способа
# показать значок. Safe-zone адаптивного — круг 66 dp (r=33), всё дальше
# лаунчер срежет маской.
# 22 dp вместо положенных 33: из-за зума 1.5 рисунок в 33 dp заполнял всю
# плитку, и он попросил «гораздо меньше, на 30-40 %». 22 dp — это те же 61%
# полуширины плитки, что даёт legacy-пинг с радиусом 33 dp (33/54), то есть
# оба значка на телефоне выглядят одинаково.
ADAPTIVE_RADIUS = 22.0
# Legacy-пинги (API < 26 и лаунчеры, которые не понимают адаптивные) лаунчер
# показывает целиком, без зума: 54 dp = половина плитки. 33 dp = 61%
# полуширины — оптически тот же размер, что у адаптивного выше.
ANDROID_LEGACY_RADIUS = 33.0
# Linux и Windows: квадрат виден целиком и приложений вокруг много, там
# рисунок может занимать почти всю рамку — в 16 px отступ съедает читаемость.
FULL_RADIUS = 50.0
# Для сторов (iOS 1024, Play 512) квадрат показывают целиком и без маски,
# поэтому рисунок там держат с отступом от края — иначе он упирается в рамку.
STORE_RADIUS = 42.0
# Скругление squircle-маски (Pixel / OneUI) как доля стороны плитки.
MASK_CORNER = 0.30

ANDROID_MIPMAPS = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
LINUX_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]
STORE_SIZE = 512
IOS_MASTER_SIZE = 1024
WINDOWS_ICO = APP / "windows" / "runner" / "resources" / "app_icon.ico"
# Кадры .ico: Windows берёт из файла кадр под нужный размер, один 256 он
# ресейлит сам — заголовок окна превращается в кашу.
ICO_SIZES = [256, 128, 64, 48, 32, 16]


def num(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def parse_rects(svg_text):
    """Прямоугольники лого: координаты, скругление, заливка и матрица."""
    shapes = []
    for match in re.finditer(r"<rect\b([^>]*?)/>", svg_text):
        attrs = dict(re.findall(r'([\w:-]+)\s*=\s*"([^"]*)"', match.group(1)))
        matrix = re.search(
            r"matrix\(([^)]*)\)", attrs.get("transform", "")
        )
        rx = num(attrs.get("rx"))
        shapes.append(
            {
                "x": num(attrs.get("x")),
                "y": num(attrs.get("y")),
                "w": num(attrs["width"]),
                "h": num(attrs["height"]),
                # В SVG ry по умолчанию равен rx.
                "rx": min(rx, num(attrs.get("ry"), rx)) if rx else 0.0,
                "fill": attrs.get("fill", "#FFFFFF"),
                "m": [num(v) for v in matrix.group(1).split(",")]
                if matrix
                else None,
            }
        )
    if not shapes:
        sys.exit(f"В {SVG_SRC} не нашлось ни одного <rect>")
    return shapes


def transform_point(m, x, y):
    a, b, c, d, e, f = m
    return (a * x + c * y + e, b * x + d * y + f)


def shape_path(shape):
    """Path-данные для VectorDrawable (и SVG — синтаксис d один и тот же)."""
    x, y, w, h, r = (
        shape["x"],
        shape["y"],
        shape["w"],
        shape["h"],
        shape["rx"],
    )
    if shape["m"]:
        # Поворот: скругления у этих фигур нет, достаточно четырёх углов.
        corners = [
            transform_point(shape["m"], x + dx, y + dy)
            for dx, dy in ((0, 0), (w, 0), (w, h), (0, h))
        ]
        d = " ".join(
            f"{'M' if i == 0 else 'L'}{px:.3f},{py:.3f}"
            for i, (px, py) in enumerate(corners)
        )
        return d + " Z"
    if r <= 0:
        return f"M{x},{y} L{x + w},{y} L{x + w},{y + h} L{x},{y + h} Z"
    return (
        f"M{x + r},{y} L{x + w - r},{y} "
        f"A{r},{r} 0 0 1 {x + w},{y + r} L{x + w},{y + h - r} "
        f"A{r},{r} 0 0 1 {x + w - r},{y + h} L{x + r},{y + h} "
        f"A{r},{r} 0 0 1 {x},{y + h - r} L{x},{y + r} "
        f"A{r},{r} 0 0 1 {x + r},{y} Z"
    )


def art_bounds(shapes):
    """Габариты рисунка с учётом матриц — по ним считаем масштаб."""
    points = []
    for s in shapes:
        for dx, dy in ((0, 0), (s["w"], 0), (s["w"], s["h"]), (0, s["h"])):
            points.append(
                transform_point(s["m"], s["x"] + dx, s["y"] + dy)
                if s["m"]
                else (s["x"] + dx, s["y"] + dy)
            )
    xs, ys = zip(*points)
    return min(xs), min(ys), max(xs), max(ys)


def outline_points(shape, steps=16):
    """Точки контура фигуры, уже с учётом матрицы."""
    x, y, w, h, r = shape["x"], shape["y"], shape["w"], shape["h"], shape["rx"]
    if r <= 0:
        pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    else:
        # Четверти скругления; прямые участки между ними ближе к центру
        # габарита, чем дуги, — на максимальный радиус они не влияют.
        corners = (
            (x + r, y + r, 180.0),
            (x + w - r, y + r, 270.0),
            (x + w - r, y + h - r, 0.0),
            (x + r, y + h - r, 90.0),
        )
        pts = [
            (
                cx + r * math.cos(math.radians(a0 + 90.0 * i / steps)),
                cy + r * math.sin(math.radians(a0 + 90.0 * i / steps)),
            )
            for cx, cy, a0 in corners
            for i in range(steps + 1)
        ]
    return [
        transform_point(shape["m"], px, py) if shape["m"] else (px, py)
        for px, py in pts
    ]


def fit_transform(shapes, *, limit):
    """(scale, translateX, translateY): рисунок по центру канваса, не дальше
    limit dp от центра.

    Пока рисуем по габариту, центр канваса прообразуется в центр габарита при
    любом масштабе — поэтому радиус можно считать в координатах исходника.
    """
    x0, y0, x1, y1 = art_bounds(shapes)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    reach = max(
        math.dist((cx, cy), p) for s in shapes for p in outline_points(s)
    )
    scale = limit / reach
    tx = (CANVAS - (x1 - x0) * scale) / 2 - x0 * scale
    ty = (CANVAS - (y1 - y0) * scale) / 2 - y0 * scale
    return scale, tx, ty


def rgb_to_hex(color):
    match = re.match(r"rgb\(([^)]*)\)", color)
    if match:
        parts = [int(float(v)) for v in match.group(1).split(",")]
        return "#%02X%02X%02X" % tuple(parts)
    return color


def vector_layer(shapes, scale, tx, ty, *, monochrome=False):
    paths = []
    for shape in shapes:
        fill = "#FFFFFF" if monochrome else rgb_to_hex(shape["fill"])
        paths.append(
            f'    <path android:fillColor="{fill}" '
            f'android:pathData="{shape_path(shape)}"/>'
        )
    return (
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        f'    android:width="{CANVAS:.0f}dp"\n'
        f'    android:height="{CANVAS:.0f}dp"\n'
        f'    android:viewportWidth="{CANVAS:.0f}"\n'
        f'    android:viewportHeight="{CANVAS:.0f}">\n'
        f'  <group android:scaleX="{scale:.6f}" android:scaleY="{scale:.6f}"\n'
        f'      android:translateX="{tx:.6f}" android:translateY="{ty:.6f}">\n'
        + "\n".join(paths)
        + "\n  </group>\n</vector>\n"
    )


def background_layer():
    return (
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        f'    android:width="{CANVAS:.0f}dp"\n'
        f'    android:height="{CANVAS:.0f}dp"\n'
        f'    android:viewportWidth="{CANVAS:.0f}"\n'
        f'    android:viewportHeight="{CANVAS:.0f}">\n'
        f'  <path android:fillColor="{rgb_to_hex(BACKGROUND)}" '
        f'android:pathData="M0,0 L{CANVAS:.0f},0 L{CANVAS:.0f},'
        f'{CANVAS:.0f} L0,{CANVAS:.0f} Z"/>\n'
        "</vector>\n"
    )


def adaptive_icon():
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon '
        'xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n"
    )


def clip_path(clip_id, shape):
    if not shape:
        return ""
    return f'<defs><clipPath id="{clip_id}">{shape}</clipPath></defs>\n'


def icon_body(shapes, scale, tx, ty):
    """Фон + artwork в координатах канваса 108 — без внешнего <svg>.

    Общая часть для растеризации значка и для превью, где тот же рисунок
    входит в монтаж.
    """
    body = "\n".join(
        f'  <path d="{shape_path(s)}" fill="{rgb_to_hex(s["fill"])}"/>'
        for s in shapes
    )
    return (
        f'  <rect width="{CANVAS}" height="{CANVAS}" '
        f'fill="{rgb_to_hex(BACKGROUND)}"/>\n'
        f'  <g transform="translate({tx} {ty}) scale({scale})">\n'
        f"{body}\n"
        "  </g>\n"
    )


def mask_shape(clip, x0=0.0, y0=0.0, size=None):
    """Форма маски лаунчера в координатах канваса 108 dp.

    x0/y0/size — окно, которое лаунчер реально показывает: для адаптивного
    значка это центральные 72 dp, а не весь канвас (см. VISIBLE_WINDOW).
    """
    size = CANVAS if size is None else size
    cx, cy = x0 + size / 2, y0 + size / 2
    if clip == "circle":
        return f'<circle cx="{cx}" cy="{cy}" r="{size / 2}"/>'
    if clip == "squircle":
        return (
            f'<rect x="{x0}" y="{y0}" width="{size}" height="{size}" '
            f'rx="{size * MASK_CORNER:.2f}"/>'
        )
    return ""


def icon_svg(shapes, scale, tx, ty, *, clip=None):
    """Тот же значок целиком (фон + artwork) для растеризации.

    clip — форма маски: "circle", "squircle" или None (квадрат).
    """
    shape = mask_shape(clip)
    defs = clip_path("main", shape) if shape else ""
    attr = ' clip-path="url(#main)"' if shape else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {CANVAS} {CANVAS}" width="{CANVAS}" height="{CANVAS}">\n'
        f"{defs}"
        f"<g{attr}>\n"
        f"{icon_body(shapes, scale, tx, ty)}"
        "</g>\n"
        "</svg>\n"
    )


def raster(svg_text, out_path, size):
    scaled = re.sub(
        r'width="[\d.]+" height="[\d.]+"',
        f'width="{size}" height="{size}"',
        svg_text,
        count=1,
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as tmp:
        tmp.write(scaled)
        tmp_path = Path(tmp.name)
    try:
        subprocess.run(
            [
                "rsvg-convert",
                "-w",
                str(size),
                "-h",
                str(size),
                str(tmp_path),
                "-o",
                str(out_path),
            ],
            check=True,
        )
    finally:
        tmp_path.unlink()


def write_ico(frames, out_path):
    """Кадры PNG -> контейнер .ico.

    PNG внутри .ico читает Windows Vista и новее. Несжатые BMP-кадры, которые
    сыплет ImageMagick, дороже в десятки раз: 270 КБ против 6 КБ на кадр 256.
    """
    entries = bytearray()
    payload = b""
    offset = 6 + 16 * len(frames)
    for size, png in frames:
        data = png.read_bytes()
        # 256 в заголовке пишется нулём
        entries += struct.pack(
            "<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset
        )
        payload += data
        offset += len(data)
    out_path.write_bytes(
        struct.pack("<HHH", 0, 1, len(frames)) + bytes(entries) + payload
    )


PREVIEW_DIR = Path("/tmp/icon_work")
# Радиус для превью: от прежних 33 dp (он их увидел на телефоне) до вдвое
# меньше. Проценты в подписях считаем от 33.
PREVIEW_RADII = [33.0, 26.0, 22.0, 18.0]
PREVIEW_STORE_RADII = [42.0, 36.0, 30.0, 22.0]
SEEN_RADIUS = 33.0
PREVIEW_TILE = 168
# Фон монтажа: плитки #121212 на белом листе не видно грани.
PREVIEW_BG = "#3A4652"


def xml_escape(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def preview(out_dir):
    """Монтаж плиток лаунчера по нескольким радиусам.

    Чтобы выбрать размер глазом, а не пересборкой APK; ничего в репозитории
    не меняет. Плитка показана так, как её реально рисует лаунчер: под
    адаптивный ряд берётся окно центральных 72 dp и растягивается на всю
    плитку — иначе превью обманывает на зум 1.5, как обмануло первый раз.
    """
    shapes = parse_rects(SVG_SRC.read_text(encoding="utf-8"))
    bleed = (CANVAS - VISIBLE_WINDOW) / 2
    rows = (
        ("squircle", bleed, "squircle-маска (Pixel, Samsung)", PREVIEW_RADII,
         SEEN_RADIUS, ADAPTIVE_RADIUS),
        ("circle", bleed, "круглая маска (AOSP, Nova)", PREVIEW_RADII,
         SEEN_RADIUS, ADAPTIVE_RADIUS),
        (None, 0.0, "без маски — плитка в сторе (Play 512, iOS 1024)",
         PREVIEW_STORE_RADII, STORE_RADIUS, STORE_RADIUS),
    )
    tile, gap, pad = PREVIEW_TILE, 26, 22
    width = pad * 2 + len(PREVIEW_RADII) * tile + (len(PREVIEW_RADII) - 1) * gap
    parts = []
    y = pad
    for clip, offset, title, radii, ref, now in rows:
        parts.append(
            f'<text x="{pad}" y="{y + 19}" font-size="18" font-weight="bold" '
            f'fill="#F2F5F7">{xml_escape(title)}</text>'
        )
        y += 32
        window = CANVAS - 2 * offset
        shape = mask_shape(clip, offset, offset, window)
        for i, radius in enumerate(radii):
            x = pad + i * (tile + gap)
            scale, tx, ty = fit_transform(shapes, limit=radius)
            cid = f"c{len(parts)}"
            pct = round((radius / ref - 1) * 100)
            label = f"r={radius:.0f} dp"
            if pct:
                label += f", {pct:+d}%"
            if radius == now:
                label += " · сейчас в сборке"
            elif radius == ref:
                label += " · как на телефоне"
            attr = f' clip-path="url(#{cid})"' if shape else ""
            color = "#92FF26" if radius == now else "#E3E9EF"
            parts.append(
                f'<svg x="{x}" y="{y}" width="{tile}" height="{tile}" '
                f'viewBox="{offset} {offset} {window} {window}">\n'
                f"{clip_path(cid, shape)}"
                f"<g{attr}>\n"
                f"{icon_body(shapes, scale, tx, ty)}"
                "</g>\n</svg>\n"
            )
            parts.append(
                f'<text x="{x + tile / 2:.0f}" y="{y + tile + 21}" '
                f'text-anchor="middle" font-size="15" fill="{color}">'
                f"{xml_escape(label)}</text>"
            )
        y += tile + 26 + 24
    # Последний межстрочный отступ не нужен — под ним только сноска.
    y -= 24
    notes = (
        "Плитка 168 px ≈ значок 48 dp — как в списке приложений.",
        "Верхние два ряда — адаптивный: лаунчер берёт центральные 72 dp",
        "канваса и растягивает на всю плитку (зум 1.5). Safe-zone — 66 dp.",
        "Третий ряд — квадрат целиком, без зума: Play Store, iOS, web.",
    )
    for n, line in enumerate(notes):
        parts.append(
            f'<text x="{pad}" y="{y + 20 + n * 18}" font-size="14" '
            f'fill="#B9C4CE">{xml_escape(line)}</text>'
        )
    height = y + 20 + (len(notes) - 1) * 18 + pad
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" '
        f'height="{height}" font-family="DejaVu Sans">\n'
        f'<rect width="{width}" height="{height}" fill="{PREVIEW_BG}"/>\n'
        + "\n".join(parts)
        + "\n</svg>\n"
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    svg_path = out_dir / "icon_preview.svg"
    svg_path.write_text(svg, encoding="utf-8")
    png_path = out_dir / "icon_preview.png"
    subprocess.run(
        ["rsvg-convert", "-w", str(width * 2), str(svg_path),
         "-o", str(png_path)],
        check=True,
    )
    print(f"Превью: {png_path}")
    print(f"          {svg_path}")


def main():
    if len(sys.argv) > 1:
        if sys.argv[1] != "--preview":
            sys.exit("использование: build_icons.py [--preview [каталог]]")
        preview(
            Path(sys.argv[2]) if len(sys.argv) > 2 else PREVIEW_DIR
        )
        return
    if not SVG_SRC.exists():
        sys.exit(f"Нет исходника: {SVG_SRC}")
    shapes = parse_rects(SVG_SRC.read_text(encoding="utf-8"))
    # Три вписывания под три способа показать значок: адаптивный режут маски и
    # цумят 1.5×, legacy-пинг лаунчер показывает целиком, а Linux/Windows —
    # квадрат почти без полей, где в 16 px отступ съедает читаемость.
    adaptive = fit_transform(shapes, limit=ADAPTIVE_RADIUS)
    legacy = fit_transform(shapes, limit=ANDROID_LEGACY_RADIUS)
    full = fit_transform(shapes, limit=FULL_RADIUS)

    # --- Android: слои адаптивного значка --------------------------------
    scale, tx, ty = adaptive
    (ANDROID_RES / "drawable").mkdir(parents=True, exist_ok=True)
    (ANDROID_RES / "drawable" / "ic_launcher_foreground.xml").write_text(
        vector_layer(shapes, scale, tx, ty), encoding="utf-8"
    )
    (ANDROID_RES / "drawable" / "ic_launcher_monochrome.xml").write_text(
        vector_layer(shapes, scale, tx, ty, monochrome=True), encoding="utf-8"
    )
    (ANDROID_RES / "drawable" / "ic_launcher_background.xml").write_text(
        background_layer(), encoding="utf-8"
    )
    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (anydpi / name).write_text(adaptive_icon(), encoding="utf-8")

    # --- Android: legacy-растр для API < 26 ------------------------------
    scale, tx, ty = legacy
    legacy_svg = icon_svg(shapes, scale, tx, ty)
    legacy_round_svg = icon_svg(shapes, scale, tx, ty, clip="circle")
    for density, size in ANDROID_MIPMAPS.items():
        folder = ANDROID_RES / f"mipmap-{density}"
        raster(legacy_svg, folder / "ic_launcher.png", size)
        raster(legacy_round_svg, folder / "ic_launcher_round.png", size)

    # --- Linux: hicolor --------------------------------------------------
    scale, tx, ty = full
    square_svg = icon_svg(shapes, scale, tx, ty)
    for size in LINUX_SIZES:
        raster(
            square_svg,
            LINUX_ICONS / f"{size}x{size}" / "apps" / "meander.png",
            size,
        )
    scalable = LINUX_ICONS / "scalable" / "apps"
    scalable.mkdir(parents=True, exist_ok=True)
    (scalable / "meander.svg").write_text(square_svg, encoding="utf-8")

    # --- Заготовки для сторов -------------------------------------------
    # Свой масштаб: здесь масок нет, и рисунок впритык к краю выглядит так,
    # будто его обрезали.
    store_scale, store_tx, store_ty = fit_transform(shapes, limit=STORE_RADIUS)
    store_svg = icon_svg(shapes, store_scale, store_tx, store_ty)
    raster(
        store_svg, APP / "assets" / "icon" / "ic_launcher_512.png", STORE_SIZE
    )
    raster(
        store_svg, APP / "assets" / "icon" / "app_icon_1024.png",
        IOS_MASTER_SIZE,
    )

    # --- Windows: .ico ---------------------------------------------------
    # Масштаб берём «полный», как у Linux: в 16 px отступ стора съедает
    # половину кадра, и значок превращается в размытое пятно.
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp = Path(tmp_dir)
        frames = []
        for size in ICO_SIZES:
            png = tmp / f"app_icon_{size}.png"
            raster(square_svg, png, size)
            frames.append((size, png))
        WINDOWS_ICO.parent.mkdir(parents=True, exist_ok=True)
        write_ico(frames, WINDOWS_ICO)

    print(f"адаптивный: масштаб {adaptive[0]:.4f}, сдвиг "
          f"({adaptive[1]:.2f} {adaptive[2]:.2f})")
    print(f"legacy:     масштаб {legacy[0]:.4f}, сдвиг "
          f"({legacy[1]:.2f} {legacy[2]:.2f})")
    print(f"полный:     масштаб {full[0]:.4f}, сдвиг ({full[1]:.2f} {full[2]:.2f})")
    print(f"стор:       масштаб {store_scale:.4f}, сдвиг "
          f"({store_tx:.2f} {store_ty:.2f})")
    print(f"Android: {ANDROID_RES}")
    print(f"Linux:   {LINUX_ICONS}")


if __name__ == "__main__":
    main()
