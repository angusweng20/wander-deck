#!/usr/bin/env python3
"""漫遊簡報 Wander Deck — 掃描簡報資料夾，產生縮圖、大圖和 _wander/data.js。

只用 macOS 內建的 sips 和 Python 標準函式庫；ffmpeg 有裝的話會替影片做封面。

簡報資料夾長這樣：
    我的簡報/
      deck.json            ← 所有設定（標題、順序、開場、音樂…）
      簡報.html            ← 打開就是簡報
      01 某個主題/          ← 一個資料夾＝一個主題，可以再分一層子主題
      _assets/             ← 背景、LOGO、音樂等素材（底線開頭的資料夾不會變成主題）
      _wander/             ← 這支程式產生的東西，可以整個刪掉重建

用法：
    python3 _wander/build.py            # 更新
    python3 _wander/build.py --check    # 只檢查設定，不產生圖片
"""
import json
import re
import shutil
import struct
import subprocess
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent          # _wander
ROOT = HERE.parent                              # 簡報資料夾
CONFIG = ROOT / "deck.json"
THUMB = HERE / "thumbs"
LARGE = HERE / "large"

PHOTO_EXT = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".tif", ".tiff", ".webp"}
VIDEO_EXT = {".mov", ".mp4", ".m4v"}
AUDIO_EXT = {".mp3", ".m4a", ".aac", ".wav"}
THUMB_PX, LARGE_PX = 480, 2400

DEFAULTS = {
    "title": "漫遊簡報",
    "subtitle": "點一個主題，想從哪裡開始都可以",
    "lang": "zh-Hant-TW",
    "theme": {},
    "background": None,
    "logo": None,
    "music": {"file": None, "volume": 50},
    "topics": {"order": [], "hidden": [], "walls": [], "labels": {}},
    "intro": [],
    "scenes": {},
    "outro": None,
    "text": {},
}

warnings = []


def warn(msg):
    warnings.append(msg)


def nfc(s):
    # macOS 檔名可能是拆開的注音符號形式，統一成一般寫法才比得對
    return unicodedata.normalize("NFC", s)


def rel(p):
    return Path(p).relative_to(ROOT).as_posix()


def display_name(folder_name):
    # 網頁上拿掉開頭的「1.」「02 」這類排序編號，資料夾本身不動
    return re.sub(r"^\s*\d+\s*[.、．)\-_ ]\s*", "", folder_name) or folder_name


def is_stale(src, out):
    return not out.exists() or out.stat().st_mtime < src.stat().st_mtime


# ---------- 圖片：轉檔、轉正、清掉拍攝資訊 ----------

def sips(*args):
    return subprocess.run(["sips", *map(str, args)], capture_output=True, text=True)


def image_size(path):
    out = sips("-g", "pixelWidth", "-g", "pixelHeight", path).stdout
    w = re.search(r"pixelWidth: (\d+)", out)
    h = re.search(r"pixelHeight: (\d+)", out)
    return (int(w.group(1)), int(h.group(1))) if w and h else (4, 3)


# EXIF 方向 → 要對像素做的動作（sips -r 是順時針）
ORIENT_FIX = {2: [("--flip", "horizontal")], 3: [("-r", 180)], 4: [("--flip", "vertical")],
              5: [("-r", 90), ("--flip", "horizontal")], 6: [("-r", 90)],
              7: [("-r", 270), ("--flip", "horizontal")], 8: [("-r", 270)]}


def exif_orientation(path):
    """直接從 JPEG 的 EXIF 讀方向。不能用 sips -g orientation：
    iPhone HEIC 轉出來的 JPG 明明寫著 6（要轉 90 度），sips 卻回報 <nil>。"""
    d = path.read_bytes()[:256 * 1024]
    i = d.find(b"Exif\x00\x00")
    if i < 0:
        return 1
    t = d[i + 6:]
    e = "<" if t[:2] == b"II" else ">"
    try:
        off = struct.unpack(e + "I", t[4:8])[0]
        for k in range(struct.unpack(e + "H", t[off:off + 2])[0]):
            tag, _, _, val = struct.unpack(e + "HHI4s", t[off + 2 + 12 * k:off + 14 + 12 * k])
            if tag == 0x112:
                return struct.unpack(e + "H", val[:2])[0]
    except struct.error:
        pass
    return 1


def bake_orientation(path):
    # 拍攝資訊清掉之後瀏覽器就不知道要轉，所以先把像素真的轉正
    for flag, val in ORIENT_FIX.get(exif_orientation(path), []):
        sips(flag, val, path)


def strip_metadata(path):
    """拿掉 JPEG 裡的 EXIF／XMP／IPTC（含 GPS 位置、拍攝時間、相機型號），保留色彩設定檔。"""
    data = path.read_bytes()
    if data[:2] != b"\xff\xd8":
        return
    out, i = bytearray(b"\xff\xd8"), 2
    while i + 4 <= len(data) and data[i] == 0xFF:
        marker = data[i + 1]
        if marker == 0xDA:                      # 影像資料開始，後面原樣保留
            break
        length = int.from_bytes(data[i + 2:i + 4], "big")
        seg = data[i:i + 2 + length]
        is_icc = marker == 0xE2 and seg[4:16] == b"ICC_PROFILE\0"
        if not (0xE1 <= marker <= 0xEF) or is_icc:
            out += seg
        i += 2 + length
    path.write_bytes(bytes(out + data[i:]))


def make_photo(src, out, size, quality):
    if not is_stale(src, out):
        return True
    out.parent.mkdir(parents=True, exist_ok=True)
    r = sips("-s", "format", "jpeg", "-s", "formatOptions", quality, "-Z", size, src, "--out", out)
    if r.returncode or not out.exists():
        warn(f"無法轉換圖片：{rel(src)}")
        return False
    bake_orientation(out)
    strip_metadata(out)
    return True


def make_video_poster(src, out):
    if not is_stale(src, out):
        return out.exists()
    if not shutil.which("ffmpeg"):
        return False
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", "0.5", "-i", str(src),
                    "-frames:v", "1", "-map_metadata", "-1",
                    "-vf", f"scale='min({THUMB_PX},iw)':-2", str(out)])
    return out.exists()


# ---------- 主題 ----------

def media_files(folder):
    return sorted((f for f in folder.iterdir() if f.is_file() and not f.name.startswith(".")),
                  key=lambda f: nfc(f.name))


def collect_items(folder):
    items = []
    for f in media_files(folder):
        ext = f.suffix.lower()
        key = Path(rel(f)).with_suffix(".jpg")
        if ext in PHOTO_EXT:
            if make_photo(f, THUMB / key, THUMB_PX, 78) and make_photo(f, LARGE / key, LARGE_PX, 84):
                w, h = image_size(THUMB / key)
                items.append({"type": "photo", "src": rel(LARGE / key), "thumb": rel(THUMB / key),
                              "ratio": round(w / h, 4)})
        elif ext in VIDEO_EXT:
            poster = THUMB / key
            has = make_video_poster(f, poster)
            items.append({"type": "video", "src": rel(f), "thumb": rel(poster) if has else None,
                          "ratio": round(image_size(poster)[0] / image_size(poster)[1], 4) if has else 16 / 9})
    return items


def build_topic(folder, cfg):
    name = nfc(folder.name)
    t = {"id": name, "name": cfg["topics"]["labels"].get(name, display_name(name)),
         "items": collect_items(folder), "children": []}
    if name in cfg["topics"]["walls"]:
        t["layout"] = "wall"
    for sub in sorted((d for d in folder.iterdir() if d.is_dir() and not d.name.startswith((".", "_"))),
                      key=lambda d: nfc(d.name)):
        child = build_topic(sub, cfg)
        if child["items"] or child["children"]:
            t["children"].append(child)
    return t


def covers(topic, n=3):
    thumbs = [i["thumb"] for i in topic["items"] if i["thumb"]][:n]
    for child in topic["children"]:
        if len(thumbs) >= n:
            break
        thumbs += covers(child, n - len(thumbs))
    return thumbs


def attach_covers(topic):
    topic["covers"] = covers(topic)
    for child in topic["children"]:
        attach_covers(child)


def all_items(topic):
    yield from topic["items"]
    for child in topic["children"]:
        yield from all_items(child)


def remove_unused(folder, used):
    # 照片搬走或改名後，舊的縮圖留著只會佔空間
    if not folder.exists():
        return
    for f in folder.rglob("*"):
        if f.is_file() and rel(f) not in used:
            f.unlink()
    for d in sorted((d for d in folder.rglob("*") if d.is_dir()), key=lambda d: -len(d.parts)):
        if not any(d.iterdir()):
            d.rmdir()


# ---------- 設定 ----------

def load_config():
    cfg = json.loads(json.dumps(DEFAULTS))
    if CONFIG.exists():
        try:
            user = json.loads(CONFIG.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            sys.exit(f"deck.json 格式錯誤（第 {e.lineno} 行第 {e.colno} 個字）：{e.msg}")
        for k, v in user.items():
            if isinstance(v, dict) and isinstance(cfg.get(k), dict):
                cfg[k].update(v)
            else:
                cfg[k] = v
    else:
        warn("找不到 deck.json，全部用預設值")
    t = cfg["topics"]
    for k in ("order", "hidden", "walls"):
        t[k] = [nfc(x) for x in t.get(k, [])]
    t["labels"] = {nfc(k): v for k, v in t.get("labels", {}).items()}
    return cfg


def check_asset(path, what):
    """設定裡寫到的素材檔要存在；不存在就提醒並當作沒設定。"""
    if not path:
        return None
    if not (ROOT / path).is_file():
        warn(f"{what} 找不到檔案：{path}")
        return None
    return path


def resolve_assets(cfg):
    cfg["background"] = check_asset(cfg["background"], "background（背景圖）")
    cfg["logo"] = check_asset(cfg["logo"], "logo")
    m = cfg["music"] if isinstance(cfg["music"], dict) else {"file": cfg["music"]}
    m["file"] = check_asset(m.get("file"), "music（背景音樂）")
    if m["file"] and (ROOT / m["file"]).stat().st_size == 0:
        warn(f"背景音樂是空檔案（0 KB），通常是下載失敗：{m['file']}")
        m["file"] = None
    m["volume"] = max(0, min(100, int(m.get("volume", 50))))
    cfg["music"] = m

    for name, sc in cfg["scenes"].items():
        sc["background"] = check_asset(sc.get("background"), f"scenes.{name}.background")
        if sc["background"] and not sc.get("size"):
            sc["size"] = list(image_size(ROOT / sc["background"]))
        for layer in sc.get("layers", []):
            layer["src"] = check_asset(layer.get("src"), f"scenes.{name} 的圖層")
        sc["layers"] = [l for l in sc.get("layers", []) if l["src"]]

    pages = []
    for i, p in enumerate(cfg["intro"], 1):
        if isinstance(p, str):
            p = {"type": "image", "src": p}
        if p.get("type", "image") == "image":
            if check_asset(p.get("src"), f"intro 第 {i} 頁"):
                pages.append(p)
            continue
        if p["type"] == "scene":
            if p.get("scene") not in cfg["scenes"] or not cfg["scenes"][p["scene"]]["background"]:
                warn(f"intro 第 {i} 頁：scene「{p.get('scene')}」沒有設定或缺背景，這頁略過")
                continue
            if p.get("title"):
                p["title"]["src"] = check_asset(p["title"].get("src"), f"intro 第 {i} 頁的標題圖")
            for c in p.get("cards", []):
                c["photo"] = check_asset(c.get("photo"), f"intro 第 {i} 頁的拍立得照片")
                if c.get("frame"):
                    c["frame"] = check_asset(c["frame"], f"intro 第 {i} 頁的拍立得相框")
            p["cards"] = [c for c in p.get("cards", []) if c["photo"]]
            pages.append(p)
        else:
            warn(f"intro 第 {i} 頁：不認得的 type「{p['type']}」")
    cfg["intro"] = pages

    o = cfg["outro"]
    if o:
        o["qr"] = check_asset(o.get("qr"), "outro.qr（QR code 圖）")
        if o.get("frame"):
            o["frame"] = check_asset(o["frame"], "outro.frame")


def resized_asset(path, px):
    """開場用的照片也可能帶 GPS：一律另存一份清乾淨的。"""
    src = ROOT / path
    if src.suffix.lower() not in PHOTO_EXT or src.suffix.lower() == ".png":
        return path
    out = HERE / "assets" / Path(path).with_suffix(".jpg")
    return rel(out) if make_photo(src, out, px, 88) else path


def main():
    check_only = "--check" in sys.argv
    cfg = load_config()
    resolve_assets(cfg)

    t = cfg["topics"]
    folders = [d for d in sorted(ROOT.iterdir(), key=lambda d: nfc(d.name))
               if d.is_dir() and not d.name.startswith((".", "_")) and nfc(d.name) not in t["hidden"]]
    names = [nfc(d.name) for d in folders]
    # walls、labels 也可以寫子主題的資料夾名稱
    all_names = {nfc(d.name) for d in ROOT.rglob("*") if d.is_dir()
                 and not any(p.startswith((".", "_")) for p in d.relative_to(ROOT).parts)}
    for key in ("order", "hidden", "walls", "labels"):
        for n in t[key]:
            ok = n in names if key == "order" else n in all_names
            if not ok:
                warn(f"topics.{key} 裡的「{n}」找不到這個資料夾")
    rank = {n: i for i, n in enumerate(t["order"])}
    folders.sort(key=lambda d: (rank.get(nfc(d.name), len(rank)), nfc(d.name)))

    if check_only:
        print("主題順序：" + "、".join(t["labels"].get(nfc(d.name), display_name(nfc(d.name))) for d in folders))
    else:
        topics = []
        for d in folders:
            tp = build_topic(d, cfg)
            if tp["items"] or tp["children"]:
                attach_covers(tp)
                topics.append(tp)
            n = sum(1 for _ in all_items(tp))
            print(f"  {tp['name']}：{n} 個檔案" + (f"，{len(tp['children'])} 個子主題" if tp["children"] else ""))

        used = {i[k] for tp in topics for i in all_items(tp) for k in ("thumb", "src") if i.get(k)}
        remove_unused(THUMB, used)
        remove_unused(LARGE, used)
        for p in cfg["intro"]:
            for c in p.get("cards", []):
                c["photo"] = resized_asset(c["photo"], 1600)

        data = {k: cfg[k] for k in ("title", "subtitle", "lang", "theme", "background", "logo",
                                     "music", "intro", "scenes", "outro", "text")}
        data["topics"] = topics
        (HERE / "data.js").write_text(
            "window.WANDER = " + json.dumps(data, ensure_ascii=False, indent=1) + ";\n", encoding="utf-8")

    for w in warnings:
        print("⚠️  " + w)
    print("完成：簡報已更新。" if not check_only else "檢查完成。")
    return 1 if warnings and check_only else 0


if __name__ == "__main__":
    sys.exit(main())
