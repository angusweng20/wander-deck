# 模擬 App：從背景啟動 pi --mode rpc，送「指定主題」的工作＋圖片，讀回結果
import base64, json, subprocess, sys, time, pathlib
S = pathlib.Path(sys.argv[1]); t0 = time.time()
p = subprocess.Popen(["pi", "--mode", "rpc", "--provider", "openai-codex", "--model", "gpt-5.5",
                      "--no-tools", "--no-session", "--no-context-files", "--no-skills", "--no-extensions", "--no-prompt-templates"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
imgs = [{"type": "image", "mimeType": "image/jpeg", "data": base64.b64encode((S/"thumbs"/f"img{i:02d}.jpg").read_bytes()).decode()} for i in range(1, 19)]
msg = ('附件是 img01–img18 共 18 張照片（依序）。使用者指定了三個主題：「雪」「夜」「山與河」。'
       '把每張照片分到最適合的一個主題；都不適合的放「其他」。只輸出 JSON：{"雪":["img01"],"夜":[],"山與河":[],"其他":[]}')
cmd = {"id": "r1", "type": "prompt", "message": msg, "images": imgs}
p.stdin.write((json.dumps(cmd, ensure_ascii=False) + "\n").encode()); p.stdin.flush()
text = None
for raw in p.stdout:
    ev = json.loads(raw.decode().rstrip("\r\n"))
    if ev.get("type") == "response": print("回應：", ev.get("success"), ev.get("error", ""))
    if ev.get("type") == "agent_end":
        for m in reversed(ev.get("messages", [])):
            if m.get("role") == "assistant":
                text = "".join(c.get("text", "") for c in m.get("content", []) if c.get("type") == "text"); break
        break
p.stdin.close(); p.terminate()
print(text); print(f"耗時 {time.time()-t0:.1f} 秒")
