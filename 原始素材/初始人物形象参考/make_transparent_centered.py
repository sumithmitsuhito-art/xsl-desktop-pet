# -*- coding: utf-8 -*-
"""把伪透明棋盘格背景抠成真透明，并将主体居中到原尺寸画布。"""
from collections import deque

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "人物图标参考.png"
DST = "人物图标_透明居中.png"

NEUTRAL_TOL = 28     # max(R,G,B)-min(R,G,B) 小于此值视为中性色（灰/白）
LIGHT_MIN = 195      # 中性且最暗通道不低于此值，视为棋盘格候选

im = Image.open(SRC).convert("RGBA")
a = np.array(im)
h, w = a.shape[:2]
rgb = a[:, :, :3].astype(np.int16)

# 1) 棋盘格候选：中性浅色（白 ~255 / 浅灰 ~224，允许轻微偏色）
mx = rgb.max(axis=2)
mn = rgb.min(axis=2)
cand = ((mx - mn) <= NEUTRAL_TOL) & (mn >= LIGHT_MIN)

# 2) 从四边泛洪，只有与边缘连通的候选才算背景（保护角色内部的白色部分）
reach = np.zeros((h, w), dtype=bool)
dq = deque()
for x in range(w):
    for y in (0, h - 1):
        if cand[y, x] and not reach[y, x]:
            reach[y, x] = True
            dq.append((y, x))
for y in range(h):
    for x in (0, w - 1):
        if cand[y, x] and not reach[y, x]:
            reach[y, x] = True
            dq.append((y, x))
while dq:
    y, x = dq.popleft()
    for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
        if 0 <= ny < h and 0 <= nx < w and cand[ny, nx] and not reach[ny, nx]:
            reach[ny, nx] = True
            dq.append((ny, nx))

a[reach, 3] = 0

# 3) 剩余不透明区域只保留最大连通域（清掉“即梦AI”水印等残留碎块）
solid = a[:, :, 3] > 0
lab, n = ndimage.label(solid)
if n > 1:
    sizes = ndimage.sum(solid, lab, index=range(1, n + 1))
    keep = 1 + int(np.argmax(sizes))
    a[(lab != keep) & solid, 3] = 0

# 4) 边缘过渡带：泛洪只会精确到 min>=195 的像素，轮廓与背景之间还留着一条
#    6~7px 宽、完全不透明的渐变带，深色背景下呈灰晕。从透明边界向内生长
#    穿过整条过渡带，按亮度反解 alpha，并把颜色重映射到最近的深色轮廓。
lum = rgb.mean(axis=2)
neutral = (mx - mn) <= 30
dark_core = neutral & (lum < 105)                      # 轮廓深色核心，保持不透明
grow_cand = neutral & (lum >= 110) & (a[:, :, 3] > 0)  # 可覆盖的过渡像素

ramp = np.zeros((h, w), dtype=bool)
frontier = ndimage.binary_dilation(a[:, :, 3] == 0) & grow_cand
for _ in range(10):
    new = frontier & ~ramp
    if not new.any():
        break
    ramp |= new
    frontier = ndimage.binary_dilation(ramp) & grow_cand

ramp_alpha = np.clip((235 - lum[ramp]) / (235 - 60), 0, 1)
a[ramp, 3] = (ramp_alpha * 255).astype(np.uint8)
_, (iy, ix) = ndimage.distance_transform_edt(~dark_core, return_indices=True)
a[ramp, :3] = a[iy[ramp], ix[ramp], :3]
a[a[:, :, 3] < 8, 3] = 0

# 5) 裁剪主体并居中到原尺寸透明画布
ys, xs = np.where(a[:, :, 3] > 0)
y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
body = a[y0:y1, x0:x1]

out = np.zeros((h, w, 4), dtype=np.uint8)
bh, bw = body.shape[:2]
ty, tx = (h - bh) // 2, (w - bw) // 2
out[ty:ty + bh, tx:tx + bw] = body

Image.fromarray(out, "RGBA").save(DST)
print(f"源图 {w}x{h} -> 主体 {bw}x{bh}，居中偏移 ({tx},{ty})，已保存 {DST}")
