"""分析两张序列帧图的网格与每帧包围盒（一次性工具）"""
from PIL import Image
import numpy as np
from scipy import ndimage

DIR = "assets/初始人物形象参考/"

def band_bboxes(alpha):
    """用连通域+行列投影找帧包围盒"""
    mask = alpha > 0.05
    rowsum = mask.sum(axis=1)
    on = rowsum > 2
    # 行带
    rows = []
    start = None
    for i, v in enumerate(on):
        if v and start is None:
            start = i
        if not v and start is not None:
            rows.append((start, i - 1)); start = None
    if start is not None:
        rows.append((start, len(on) - 1))
    cells = []
    for (r0, r1) in rows:
        colsum = mask[r0:r1 + 1].sum(axis=0)
        onc = colsum > 2
        cs = None
        for i, v in enumerate(onc):
            if v and cs is None:
                cs = i
            if not v and cs is not None:
                cells.append((cs, r0, i - 1, r1)); cs = None
        if cs is not None:
            cells.append((cs, r0, len(onc) - 1, r1))
    return cells

for name in ["待机序列帧1.png", "序列帧动画2.png"]:
    im = Image.open(DIR + name).convert("RGBA")
    alpha = np.array(im)[:, :, 3].astype(np.float32) / 255.0
    cells = band_bboxes(alpha)
    print("=====", name, im.size, "cells:", len(cells))
    for (x0, y0, x1, y1) in cells:
        w = x1 - x0 + 1; h = y1 - y0 + 1
        cx = (x0 + x1) / 2; cy = (y0 + y1) / 2
        print(f"  x[{x0:4d},{x1:4d}] y[{y0:4d},{y1:4d}]  w={w:4d} h={h:4d}  center=({cx:.0f},{cy:.0f}) bottom={y1}")
