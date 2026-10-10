#!/usr/bin/env python3
"""漫遊簡報：風格包工具（只用 Python 標準函式庫）。

風格包＝一個資料夾，裡面有 style.json 和它用到的圖、樣式表、音樂。
格式說明見 docs/style-pack.md。

用法：
  style_pack.py check   <風格包資料夾或 .wdstyle>       檢查格式，有問題會列出來
  style_pack.py export  <風格包資料夾> [輸出.wdstyle]     打包成一個檔案（給別人用）
  style_pack.py import  <檔案.wdstyle> <放風格包的資料夾>   解開並檢查，放到 <資料夾>/<id>/
  style_pack.py install <風格包資料夾> <簡報資料夾>         把風格包裝進簡報（_style/），並在 deck.json 寫上 "style"

.wdstyle 其實就是 zip。匯入時只收白名單裡的檔案類型，不收程式（.js、.html…），
也不准檔名跳出資料夾（../），避免別人做的風格包動到你電腦上的其他東西。
"""
import json
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

FORMAT = "wander-style/1"
ALLOWED_EXT = {".json", ".css", ".md", ".txt", ".jpg", ".jpeg", ".png", ".webp", ".gif",
               ".mp3", ".m4a", ".aac", ".woff", ".woff2", ".otf", ".ttf"}
MAX_TOTAL = 80 * 1024 * 1024          # 整包最大 80MB
MAX_FILES = 400
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,39}$")
LICENSES = {"CC-BY-4.0", "CC-BY-SA-4.0", "CC0-1.0"}
EFFECTS = {"swing", "walk", "float", "breeze", "breeze-soft", "flutter", "none"}


def referenced_files(st):
    """style.json 裡提到的所有檔案路徑。"""
    refs = []
    for k in ("background", "css", "preview", "credits"):
        if st.get(k):
            refs.append((k, st[k]))
    if isinstance(st.get("music"), dict) and st["music"].get("file"):
        refs.append(("music.file", st["music"]["file"]))
    for name, sc in (st.get("scenes") or {}).items():
        if sc.get("background"):
            refs.append((f"scenes.{name}.background", sc["background"]))
        for i, layer in enumerate(sc.get("layers", []), 1):
            refs.append((f"scenes.{name} 第 {i} 個圖層", layer.get("src")))
    for i, p in enumerate(st.get("intro") or [], 1):
        if p.get("type", "image") == "image":
            refs.append((f"intro 第 {i} 頁", p.get("src")))
        for c in p.get("cards") if isinstance(p.get("cards"), list) else []:
            if c.get("frame"):
                refs.append((f"intro 第 {i} 頁的相框", c["frame"]))
    return refs


def safe_rel(p):
    return isinstance(p, str) and p and not p.startswith(("/", "\\")) and ".." not in Path(p).parts


def check_dir(d):
    """回傳問題清單；空清單＝合格。"""
    d = Path(d)
    problems = []
    meta = d / "style.json"
    if not meta.is_file():
        return ["沒有 style.json"]
    try:
        st = json.loads(meta.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return [f"style.json 格式錯誤（第 {e.lineno} 行）：{e.msg}"]
    if st.get("format") != FORMAT:
        problems.append(f"format 要寫「{FORMAT}」")
    if not ID_RE.match(str(st.get("id", ""))):
        problems.append("id 只能用小寫英文、數字和 -，2 到 40 個字（例如 kyoto-watercolor）")
    name = st.get("name")
    if not (isinstance(name, str) and name.strip()) and not (isinstance(name, dict) and any(name.values())):
        problems.append("缺 name（風格名稱）")
    if not re.match(r"^\d+\.\d+\.\d+$", str(st.get("version", ""))):
        problems.append("version 要像 1.0.0")
    if not str(st.get("author", "")).strip():
        problems.append("缺 author（作者）")
    if st.get("license") not in LICENSES:
        problems.append(f"license 要是 {', '.join(sorted(LICENSES))} 其中一個（建議 CC-BY-4.0）")
    if not st.get("credits"):
        problems.append("缺 credits（素材出處說明檔，通常是 CREDITS.md）")
    countries = st.get("countries", [])
    if not isinstance(countries, list) or any(not re.match(r"^[A-Z]{2}$", str(c)) for c in countries):
        problems.append("countries 要是國家代碼清單，例如 [\"JP\"]；適合所有地方就給 []")
    for what, p in referenced_files(st):
        if not safe_rel(p):
            problems.append(f"{what}：路徑「{p}」不合法（要是風格包裡的相對路徑）")
        elif not (d / p).is_file():
            problems.append(f"{what}：找不到檔案 {p}")
    for name, sc in (st.get("scenes") or {}).items():
        for layer in sc.get("layers", []):
            if layer.get("effect", "none") not in EFFECTS:
                problems.append(f"scenes.{name}：不認得的動畫效果「{layer.get('effect')}」")
            if not (isinstance(layer.get("box"), list) and len(layer["box"]) == 3):
                problems.append(f"scenes.{name}：圖層 {layer.get('src')} 的 box 要是 [x, y, 寬]")
    for i, p in enumerate(st.get("intro") or [], 1):
        if p.get("type") == "scene" and p.get("scene") not in (st.get("scenes") or {}):
            problems.append(f"intro 第 {i} 頁用到的 scene「{p.get('scene')}」沒有定義")
    total, count = 0, 0
    for f in d.rglob("*"):
        if f.is_symlink():
            problems.append(f"不能有捷徑（symlink）：{f.relative_to(d)}")
        elif f.is_file() and not f.name.startswith("."):
            count += 1
            total += f.stat().st_size
            if f.suffix.lower() not in ALLOWED_EXT:
                problems.append(f"不收這種檔案：{f.relative_to(d)}（只收圖片、樣式表、字型、音樂、說明）")
    if (d / st["css"]).is_file() if safe_rel(st.get("css")) else False:
        css = (d / st["css"]).read_text(encoding="utf-8", errors="replace")
        if re.search(r"@import|url\(\s*['\"]?\s*(https?:|//|file:|javascript:)", css, re.I):
            problems.append("css 不能載入網路上的東西（@import 或 http 網址）；簡報要能離線看")
    if total > MAX_TOTAL:
        problems.append(f"整包 {total / 1048576:.0f}MB，超過上限 {MAX_TOTAL // 1048576}MB")
    if count > MAX_FILES:
        problems.append(f"檔案 {count} 個，超過上限 {MAX_FILES} 個")
    return problems


def load_meta(d):
    return json.loads((Path(d) / "style.json").read_text(encoding="utf-8"))


def safe_extract(zip_path, dest):
    """只解開白名單內、路徑安全的檔案；回傳風格包根目錄（style.json 所在處）。"""
    with zipfile.ZipFile(zip_path) as z:
        infos = [i for i in z.infolist() if not i.is_dir()]
        if len(infos) > MAX_FILES:
            raise ValueError(f"檔案太多（{len(infos)} 個）")
        if sum(i.file_size for i in infos) > MAX_TOTAL:
            raise ValueError("解開後太大（超過 80MB）")
        for i in infos:
            name = i.filename.replace("\\", "/")
            parts = Path(name).parts
            if name.startswith("/") or ".." in parts or any(p.startswith("__MACOSX") for p in parts):
                continue
            if Path(name).name.startswith("."):
                continue
            if Path(name).suffix.lower() not in ALLOWED_EXT:
                raise ValueError(f"包裡有不收的檔案類型：{name}")
            if (i.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f"包裡有捷徑（symlink）：{name}")
            out = Path(dest, *parts)
            out.parent.mkdir(parents=True, exist_ok=True)
            with z.open(i) as src, open(out, "wb") as dst:
                shutil.copyfileobj(src, dst)
    metas = list(Path(dest).rglob("style.json"))
    if len(metas) != 1:
        raise ValueError("包裡要剛好有一個 style.json")
    return metas[0].parent


def cmd_check(target):
    t = Path(target)
    if t.is_file():
        with tempfile.TemporaryDirectory() as tmp:
            try:
                root = safe_extract(t, tmp)
            except (ValueError, zipfile.BadZipFile) as e:
                print(f"❌ {e}")
                return 1
            return report(root)
    return report(t)


def report(d):
    problems = check_dir(d)
    if problems:
        print("❌ 風格包有問題：")
        for p in problems:
            print("   - " + p)
        return 1
    st = load_meta(d)
    print(f"✅ 合格：{st['id']} {st['version']}（{st['license']}，作者 {st['author']}）")
    return 0


def cmd_export(src, out=None):
    src = Path(src)
    if report(src):
        return 1
    st = load_meta(src)
    out = Path(out or f"{st['id']}-{st['version']}.wdstyle")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(src.rglob("*")):
            if f.is_file() and not f.name.startswith(".") and f.suffix.lower() in ALLOWED_EXT:
                z.write(f, Path(st["id"]) / f.relative_to(src))
    print(f"已匯出：{out}")
    return 0


def cmd_import(pack, library):
    library = Path(library)
    with tempfile.TemporaryDirectory() as tmp:
        try:
            root = safe_extract(pack, tmp)
        except (ValueError, zipfile.BadZipFile) as e:
            print(f"❌ 無法匯入：{e}")
            return 1
        if report(root):
            return 1
        st = load_meta(root)
        dest = library / st["id"]
        if dest.exists():
            old = load_meta(dest) if (dest / "style.json").is_file() else {}
            backup = library / f".{st['id']}-{old.get('version', 'old')}.bak"
            if backup.exists():
                shutil.rmtree(backup)
            dest.rename(backup)
            print(f"已有同名風格包，舊版先備份成 {backup.name}")
        library.mkdir(parents=True, exist_ok=True)
        shutil.copytree(root, dest)
    print(f"已匯入：{dest}")
    return 0


def cmd_install(src, deck):
    src, deck = Path(src), Path(deck)
    if report(src):
        return 1
    st = load_meta(src)
    target = deck / "_style"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(src, target, ignore=shutil.ignore_patterns(".*"))
    cfg_file = deck / "deck.json"
    cfg = json.loads(cfg_file.read_text(encoding="utf-8")) if cfg_file.exists() else {}
    cfg["style"] = st["id"]
    cfg_file.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已把風格「{st['id']}」裝進 {deck}")
    return 0


def main(argv):
    cmds = {"check": (cmd_check, 1, 1), "export": (cmd_export, 1, 2),
            "import": (cmd_import, 2, 2), "install": (cmd_install, 2, 2)}
    if len(argv) < 2 or argv[1] not in cmds:
        print(__doc__)
        return 1
    fn, lo, hi = cmds[argv[1]]
    args = argv[2:]
    if not lo <= len(args) <= hi:
        print(__doc__)
        return 1
    return fn(*args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
