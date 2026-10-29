#!/usr/bin/env python3
"""App Store 用スクリーンショットを、シミュレータの素の画面から組み立てる。

    python3 Scripts/appstore_shots.py [--locale ja] [--only scenes]

AppStore/screenshots/raw/<ja|en>/<id>.png と captions.json を読み、
AppStore/screenshots/final/<サイズ>/<ja|en-US>/<n>-<id>.png に書く。
上に見出しと説明文、下に iPhone の画面。サイズごとにレイアウトは同じで、幅に合わせて拡縮する。
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "AppStore" / "screenshots"
SIZES = {  # App Store Connect の iPhone スロット。小さい画面は大きい方から自動で縮小される
    "1320x2868": (1320, 2868),  # Dynamic Island (large)
    "1206x2622": (1206, 2622),  # Dynamic Island (medium)。提出に必須
}
LOCALE_DIR = {"ja": "ja", "en": "en-US"}
BASE_W = 1320

JA_BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc"
JA_REG = "/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc"
EN_BOLD = ("/System/Library/Fonts/Helvetica.ttc", 1)
EN_REG = ("/System/Library/Fonts/Helvetica.ttc", 0)


def font(locale, bold, size):
    if locale == "ja":
        return ImageFont.truetype(JA_BOLD if bold else JA_REG, size)
    path, idx = EN_BOLD if bold else EN_REG
    return ImageFont.truetype(path, size, index=idx)


def wrap(draw, text, fnt, width, locale):
    """日本語は文字単位、英語は単語単位で折り返す。"""
    units = list(text) if locale == "ja" else text.split(" ")
    sep = "" if locale == "ja" else " "
    lines, cur = [], ""
    for u in units:
        trial = (cur + sep + u) if cur else u
        # 句読点が行頭に来ないよう、収まらなくてもそのまま前の行に付ける
        if draw.textlength(trial, font=fnt) <= width or u in "。、」)":
            cur = trial
        else:
            lines.append(cur)
            cur = u
    if cur:
        lines.append(cur)
    return lines


def background(w, h, color):
    top = tuple(min(255, int(c * 1.25) + 20) for c in color)
    bottom = tuple(int(c * 0.45) for c in color)
    img = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        img.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    img = img.resize((w, h))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse([w * 0.35, -h * 0.12, w * 1.45, h * 0.2], fill=(70, 70, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.12))
    from PIL import ImageChops
    return ImageChops.add(img, glow)


def compose(locale, shot, index, total, size):
    w, h = size
    k = w / BASE_W
    s = lambda v: int(round(v * k))
    cap = shot[locale]
    img = background(w, h, tuple(shot["color"]))
    d = ImageDraw.Draw(img)

    margin = s(84)
    head_font = font(locale, True, s(92 if locale == "ja" else 104))
    y = s(150)
    for line in cap["head"]:
        d.text((margin, y), line, font=head_font, fill=(255, 255, 255))
        y += int(head_font.size * 1.22)
    y += s(28)
    d.rectangle([margin, y, margin + s(64), y + s(5)], fill=(255, 255, 255, 140))
    y += s(40)
    sub_font = font(locale, False, s(50 if locale == "ja" else 52))
    for line in wrap(d, cap["sub"], sub_font, w - margin * 2, locale):
        d.text((margin, y), line, font=sub_font, fill=(226, 234, 250))
        y += int(sub_font.size * 1.5)

    # 画面: 幅 1000(基準)に縮めて下へはみ出させる
    raw = Image.open(SHOTS / "raw" / locale / f"{shot['id']}.png").convert("RGB")
    screen_w = s(990)
    screen_h = int(raw.height * screen_w / raw.width)
    screen = raw.resize((screen_w, screen_h), Image.LANCZOS)
    top = s(800)  # 説明文は 2 行までなので、どの画面でも画面の上端を揃える
    bezel = s(26)
    corner = s(150)
    x0 = (w - screen_w) // 2
    body = (x0 - bezel, top - bezel, x0 + screen_w + bezel, top + screen_h + bezel)

    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([body[0], body[1] + s(30), body[2], body[3] + s(30)],
                                              radius=corner + bezel, fill=(0, 0, 0, 140))
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(40)))
    img = Image.alpha_composite(img.convert("RGBA"), shadow)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(body, radius=corner + bezel, fill=(18, 18, 22), outline=(70, 72, 82), width=max(2, s(4)))

    mask = Image.new("L", (screen_w, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, screen_w - 1, screen_h - 1], radius=corner, fill=255)
    img.paste(screen, (x0, top), mask)
    # Dynamic Island
    iw, ih = s(280), s(82)
    d.rounded_rectangle([(w - iw) // 2, top + s(26), (w + iw) // 2, top + s(26) + ih], radius=ih // 2, fill=(0, 0, 0))
    return img.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--locale", choices=list(LOCALE_DIR))
    ap.add_argument("--only")
    a = ap.parse_args()
    shots = json.loads((SHOTS / "captions.json").read_text())["shots"]
    for locale in [a.locale] if a.locale else LOCALE_DIR:
        for name, size in SIZES.items():
            out = SHOTS / "final" / name / LOCALE_DIR[locale]
            out.mkdir(parents=True, exist_ok=True)
            for i, shot in enumerate(shots, 1):
                if a.only and shot["id"] != a.only:
                    continue
                compose(locale, shot, i, len(shots), size).save(out / f"{i}-{shot['id']}.png")
                print(out / f"{i}-{shot['id']}.png")


if __name__ == "__main__":
    main()
