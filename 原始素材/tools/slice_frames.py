# -*- coding: utf-8 -*-
"""
把两张序列帧大图切成单帧 PNG，供 Godot AnimatedSprite2D 使用。
- 网格参数来自 tools/analyze_sheets.py 的实测（行带 + 均匀列窗口）
- 统一画布 372x360，帧在画布里【脚底对齐、水平原样保留】，
  即原大图里角色怎么摆，播放时就怎么动，不重新居中
- 动作命名: sheet1 = walk/sleepy/cheer/cry, sheet2 = shy/lifted/sad/idle
输出: assets/animations/<动作>/<动作>_<1..3>.png + tools/preview.png
"""
from PIL import Image
import os

DIR = "assets/初始人物形象参考/"
OUT = "assets/animations"

# 行带/列窗口均为闭区间像素范围（含两端），两图内容互不越界（已实测验证）
SHEETS = [
    {
        "file": "待机序列帧1.png",
        "names": ["walk", "sleepy", "cheer", "cry"],
        "rows": [(6, 310), (319, 633), (635, 947), (951, 1264)],
        "cols": [(65, 430), (431, 796), (797, 1162)],
    },
    {
        "file": "序列帧动画2.png",
        "names": ["shy", "lifted", "sad", "idle"],
        "rows": [(10, 312), (320, 627), (641, 918), (925, 1277)],
        "cols": [(59, 424), (425, 790), (791, 1156)],
    },
]

CANVAS_W, CANVAS_H = 372, 360
BOTTOM_MARGIN = 2

def main():
    made = []
    for sheet in SHEETS:
        im = Image.open(DIR + sheet["file"]).convert("RGBA")
        assert len(sheet["rows"]) == len(sheet["names"]) == 4
        for (y0, y1), name in zip(sheet["rows"], sheet["names"]):
            folder = os.path.join(OUT, name)
            os.makedirs(folder, exist_ok=True)
            for idx, (x0, x1) in enumerate(sheet["cols"], start=1):
                cell_w = x1 - x0 + 1
                cell_h = y1 - y0 + 1
                frame = im.crop((x0, y0, x1 + 1, y1 + 1))
                canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
                canvas.paste(frame, ((CANVAS_W - cell_w) // 2, CANVAS_H - cell_h - BOTTOM_MARGIN))
                path = os.path.join(folder, f"{name}_{idx}.png")
                canvas.save(path)
                made.append((name, idx, path, cell_w, cell_h))
            print(f"[ok] {name}: 3 帧 -> {folder}")

    # 预览图：棋盘格底 + 每动作一行 3 帧，50% 缩放
    scale = 0.5
    fw, fh = int(CANVAS_W * scale), int(CANVAS_H * scale)
    gap = 6
    names = [n for s in SHEETS for n in s["names"]]
    pw = gap + (fw + gap) * 3
    ph = gap + (fh + gap) * len(names)
    preview = Image.new("RGBA", (pw, ph))
    for cy in range(0, ph, 24):          # 棋盘格
        for cx in range(0, pw, 24):
            c = (200, 200, 200, 255) if (cx // 24 + cy // 24) % 2 else (255, 255, 255, 255)
            for yy in range(cy, min(cy + 24, ph)):
                for xx in range(cx, min(cx + 24, pw)):
                    preview.putpixel((xx, yy), c)
    for row, name in enumerate(names):
        for col in range(1, 4):
            f = Image.open(os.path.join(OUT, name, f"{name}_{col}.png"))
            f = f.resize((fw, fh), Image.LANCZOS)
            preview.alpha_composite(f, (gap + (fw + gap) * (col - 1), gap + (fh + gap) * row))
    preview.save("tools/preview.png")
    print(f"[ok] 预览图 -> tools/preview.png  (共 {len(made)} 帧)")

if __name__ == "__main__":
    main()
