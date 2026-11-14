import os
import urllib.request

FONT_URLS = {
    "BarlowSemiCondensed-Regular.ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/barlowsemicondensed/BarlowSemiCondensed-Regular.ttf",
    "BarlowSemiCondensed-SemiBold.ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/barlowsemicondensed/BarlowSemiCondensed-SemiBold.ttf",
    "JetBrainsMono-Regular.ttf": "https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/fonts/ttf/JetBrainsMono-Regular.ttf",
    "JetBrainsMono-SemiBold.ttf": "https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/fonts/ttf/JetBrainsMono-SemiBold.ttf",
}


def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    fonts_dir = os.path.join(project_root, "assets", "fonts")
    os.makedirs(fonts_dir, exist_ok=True)

    for filename, url in FONT_URLS.items():
        dest = os.path.join(fonts_dir, filename)
        if os.path.exists(dest) and os.path.getsize(dest) > 10000:
            print(f"[SKIP] {filename} already present ({os.path.getsize(dest)} bytes)")
            continue
        print(f"[FETCH] Downloading {filename}...")
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = resp.read()
        with open(dest, "wb") as f:
            f.write(data)
        print(f"[OK] Saved {filename} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
