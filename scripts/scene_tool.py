#!/usr/bin/env python3
"""漫遊簡報：把一張插畫背景拆成會動的圖層（給 AI 用的工具）。

第一次使用先跑 scripts/setup_scene_tools.sh（會在 ~/.wander-deck/venv 裝 OpenCV）。
之後都用：~/.wander-deck/venv/bin/python scripts/scene_tool.py <指令> ...

指令：
  grid   <背景> <x0,y0,x1,y1> <輸出.png> [--scale 2]
         放大一塊區域並畫上座標格線，讓 AI 看圖找出物件的像素座標。
  cut    <背景> <x0,y0,x1,y1> <圖層.png> --scene <scene 資料夾> [--dark 200] [--min-area 60]
         [--line x,y0,y1] [--grow 0] [--grow-down 0]
         把框內「比背景暗」的物件剪成去背圖層（吊燈、駱駝、人物），
         並在 <scene 資料夾>/bg.png 裡把原位置補成背景（第一次會從原圖複製一份）。
         --line 會多畫一條直線加進剪影（例如吊燈的鍊子）。
         補背景後原位還看得到殘影：--grow 把挖的範圍往外擴幾像素，--grow-down 往下多挖（腳底影子）。
  region <背景> <多邊形 x,y;x,y;...> <圖層.png> --scene <scene 資料夾> [--feather 9]
         切一塊邊緣羽化的區域（樹葉、旗幟），原位不挖空，拿來套 breeze／flutter 效果。
  qr <圖片>
         解碼 QR code，確認它真的連到使用者說的網址（放上結尾頁之前一定要做）。
  preview <圖層.png> <輸出.png>
         把圖層疊在洋紅色底上放大，檢查剪得乾不乾淨。

每個指令最後都會印出一行 JSON：{"src": ..., "box": [x, y, 寬]}，
可以直接貼進 deck.json 的 scenes.<名稱>.layers。
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

try:
    import cv2
    import numpy as np
except ImportError:
    sys.exit("缺少 OpenCV。請先執行 scripts/setup_scene_tools.sh，再用 ~/.wander-deck/venv/bin/python 跑這支程式。")


def box_arg(s):
    return [int(float(v)) for v in s.split(",")]


def poly_arg(s):
    return [tuple(int(float(v)) for v in p.split(",")) for p in s.split(";")]


def load(path):
    im = cv2.imread(str(path))
    if im is None:
        sys.exit(f"讀不到圖片：{path}")
    return im


def fill_holes(m):
    ff = m.copy()
    mask = np.zeros((m.shape[0] + 2, m.shape[1] + 2), np.uint8)
    cv2.floodFill(ff, mask, (0, 0), 255)
    return m | cv2.bitwise_not(ff)


def scene_bg(scene_dir, src):
    """scene 資料夾裡的 bg.png 是「挖掉會動物件、補好背景」的版本，第一次從原圖複製。"""
    scene_dir.mkdir(parents=True, exist_ok=True)
    bg = scene_dir / "bg.png"
    if not bg.exists():
        shutil.copy(src, bg)
    return bg


def save_layer(out, im, mask, feather=0.8):
    ys, xs = np.where(mask > 0)
    if not len(xs):
        sys.exit("框裡沒有找到東西，試著調高 --dark 或換個框。")
    H, W = mask.shape
    x0, x1 = max(xs.min() - 3, 0), min(xs.max() + 4, W)
    y0, y1 = max(ys.min() - 3, 0), min(ys.max() + 4, H)
    a = cv2.GaussianBlur(mask, (0, 0), feather)[y0:y1, x0:x1] if feather else mask[y0:y1, x0:x1]
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(out), np.dstack([im[y0:y1, x0:x1], a]))
    return [int(x0), int(y0), int(x1 - x0)]


def cmd_grid(a):
    im = load(a.image)
    x0, y0, x1, y1 = a.box
    s, step = a.scale, 25
    c = cv2.resize(im[y0:y1, x0:x1].copy(), None, fx=s, fy=s, interpolation=cv2.INTER_CUBIC)
    for x in range((x0 // step + 1) * step, x1, step):
        X = (x - x0) * s
        cv2.line(c, (X, 0), (X, c.shape[0]), (0, 0, 255) if x % 100 == 0 else (200, 200, 255), 1)
        if x % 100 == 0:
            cv2.putText(c, str(x), (X + 2, 14), 0, .45, (0, 0, 255), 1)
    for y in range((y0 // step + 1) * step, y1, step):
        Y = (y - y0) * s
        cv2.line(c, (0, Y), (c.shape[1], Y), (255, 0, 0) if y % 100 == 0 else (255, 200, 200), 1)
        if y % 100 == 0:
            cv2.putText(c, str(y), (2, Y - 3), 0, .45, (255, 0, 0), 1)
    cv2.imwrite(a.out, c)
    print(json.dumps({"grid": a.out, "size": [im.shape[1], im.shape[0]]}))


def cmd_cut(a):
    src = load(a.image)
    bg_path = scene_bg(Path(a.scene), a.image)
    bg = load(bg_path)
    gray = cv2.cvtColor(src, cv2.COLOR_BGR2GRAY)
    x0, y0, x1, y1 = a.box
    m = np.zeros(gray.shape, np.uint8)
    m[y0:y1, x0:x1] = (gray[y0:y1, x0:x1] < a.dark) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    m = fill_holes(m)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    keep = np.zeros_like(m)
    for i in range(1, n):
        if st[i, cv2.CC_STAT_AREA] >= a.min_area:
            keep[lab == i] = 255
    if a.line:
        lx, ly0, ly1 = a.line
        cv2.line(keep, (lx, ly0), (lx, ly1), 255, 7)
    box = save_layer(a.out, src, keep)
    # 原位置補背景：先用周圍顏色填，再把附近的紙紋／沙粒細節貼回去，才不會糊成一片
    k = 9 + 2 * a.grow
    hole = cv2.dilate(keep, np.ones((k, k), np.uint8))
    if a.grow_down:                             # 腳底的影子通常比物件淺，門檻抓不到：往下多挖幾格
        hole = hole | np.roll(hole, a.grow_down, axis=0)
    base = cv2.inpaint(bg, hole, 15, cv2.INPAINT_TELEA).astype(np.float32)
    f = bg.astype(np.float32)
    detail = f - cv2.GaussianBlur(f, (0, 0), 1.5)
    shift = max(y1 - y0, 20)
    tex = np.roll(detail, -shift, axis=0) if y0 >= shift else np.roll(detail, shift, axis=0)
    soft = cv2.GaussianBlur(hole, (0, 0), 2.5).astype(np.float32)[..., None] / 255
    cv2.imwrite(str(bg_path), np.clip(base + tex * soft, 0, 255).astype(np.uint8))
    print(json.dumps({"src": a.out, "box": box, "bg": str(bg_path)}, ensure_ascii=False))


def cmd_region(a):
    load(a.image)
    bg = load(scene_bg(Path(a.scene), a.image))
    m = np.zeros(bg.shape[:2], np.uint8)
    cv2.fillPoly(m, [np.array(a.poly, np.int32)], 255)
    alpha = cv2.GaussianBlur(m, (0, 0), a.feather)
    ys, xs = np.where(alpha > 2)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(a.out, np.dstack([bg[y0:y1, x0:x1], alpha[y0:y1, x0:x1]]))
    print(json.dumps({"src": a.out, "box": [int(x0), int(y0), int(x1 - x0)]}, ensure_ascii=False))


def cmd_preview(a):
    im = cv2.imread(a.layer, cv2.IMREAD_UNCHANGED)
    al = im[..., 3:] / 255.0 if im.shape[2] == 4 else 1
    magenta = np.zeros(im.shape[:2] + (3,)); magenta[:] = (200, 60, 200)
    comp = (im[..., :3] * al + magenta * (1 - al)).astype(np.uint8)
    s = max(1, 600 // max(comp.shape[:2]))
    cv2.imwrite(a.out, cv2.resize(comp, None, fx=s, fy=s, interpolation=cv2.INTER_NEAREST))
    print(json.dumps({"preview": a.out}))


def cmd_qr(a):
    im = load(a.image)
    im = cv2.copyMakeBorder(im, 40, 40, 40, 40, cv2.BORDER_CONSTANT, value=(255, 255, 255))
    text, _, _ = cv2.QRCodeDetector().detectAndDecode(im)
    print(json.dumps({"qr": text or None}, ensure_ascii=False))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("grid"); g.add_argument("image"); g.add_argument("box", type=box_arg)
    g.add_argument("out"); g.add_argument("--scale", type=int, default=2)
    c = sub.add_parser("cut"); c.add_argument("image"); c.add_argument("box", type=box_arg); c.add_argument("out")
    c.add_argument("--scene", required=True); c.add_argument("--dark", type=int, default=200)
    c.add_argument("--min-area", type=int, default=60); c.add_argument("--line", type=box_arg)
    c.add_argument("--grow", type=int, default=0); c.add_argument("--grow-down", type=int, default=0)
    r = sub.add_parser("region"); r.add_argument("image"); r.add_argument("poly", type=poly_arg); r.add_argument("out")
    r.add_argument("--scene", required=True); r.add_argument("--feather", type=float, default=9)
    v = sub.add_parser("preview"); v.add_argument("layer"); v.add_argument("out")
    q = sub.add_parser("qr"); q.add_argument("image")
    a = p.parse_args()
    {"grid": cmd_grid, "cut": cmd_cut, "region": cmd_region, "preview": cmd_preview, "qr": cmd_qr}[a.cmd](a)


if __name__ == "__main__":
    main()
