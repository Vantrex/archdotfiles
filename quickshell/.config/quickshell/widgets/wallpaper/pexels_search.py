#!/usr/bin/env python3
"""
Pexels video search — high quality video wallpapers (nature, space, cities, abstract, etc.)
Output: thumb_url|video_url|width|height  (same pipe format as the other scrapers)

API key (free): https://www.pexels.com/api/
Store it in: ~/.config/wallpaper-picker/pexels_api_key
"""
import sys, json, time, os
import urllib.request, urllib.parse

KEY_FILE     = os.path.expanduser("~/.config/wallpaper-picker/pexels_api_key")
CONTROL_FILE = "/tmp/ddg_search_control"
LOG_FILE     = "/tmp/qs_python_scraper.log"
MIN_WIDTH    = 1920
PER_PAGE     = 15

def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} [pexels] {msg}\n")
    except:
        pass

def get_state():
    try:
        with open(CONTROL_FILE) as f: return f.read().strip()
    except: return "run"

def read_key():
    try:
        with open(KEY_FILE) as f:
            return f.read().strip()
    except:
        return None

def best_video_file(files):
    """Pick the highest-resolution video file >= MIN_WIDTH, prefer mp4."""
    candidates = [
        f for f in files
        if f.get("width", 0) >= MIN_WIDTH and f.get("file_type", "").startswith("video/")
    ]
    # Sort: prefer mp4, then by resolution descending
    candidates.sort(key=lambda f: (
        0 if "mp4" in f.get("link", "") else 1,
        -(f.get("width", 0) * f.get("height", 0))
    ))
    return candidates[0] if candidates else None

def main():
    try: os.remove(LOG_FILE)
    except: pass

    if len(sys.argv) < 2:
        return

    key = read_key()
    if not key:
        # Signal to QML that the key is missing
        sys.stdout.write("PEXELS_NO_KEY\n")
        sys.stdout.flush()
        return

    query = sys.argv[1].strip()
    log(f"=== NEW SEARCH: '{query}' ===")

    headers = {
        "Authorization": key,
        "User-Agent": "WallpaperPicker/1.0",
    }

    found = 0
    page = 1
    while found < 30 and get_state() != "stop":
        url = (f"https://api.pexels.com/videos/search"
               f"?query={urllib.parse.quote(query)}"
               f"&per_page={PER_PAGE}&page={page}"
               f"&orientation=landscape&size=large")
        log(f"Fetching page {page}: {url}")

        try:
            req = urllib.request.Request(url, headers=headers)
            data = json.loads(urllib.request.urlopen(req, timeout=10).read())
        except Exception as e:
            log(f"Error: {e}")
            break

        videos = data.get("videos", [])
        log(f"{len(videos)} results on page {page}")
        if not videos:
            break

        for v in videos:
            if get_state() == "stop":
                break

            thumb = v.get("image", "")
            vf = best_video_file(v.get("video_files", []))
            if not (thumb and vf):
                continue

            width  = vf.get("width", 0)
            height = vf.get("height", 0)
            vurl   = vf.get("link", "")
            if width < MIN_WIDTH or not vurl:
                continue

            log(f"  {vurl} ({width}x{height})")
            try:
                sys.stdout.write(f"{thumb}|{vurl}|{width}|{height}\n")
                sys.stdout.flush()
                found += 1
            except BrokenPipeError:
                os._exit(0)

        if not data.get("next_page"):
            break
        page += 1
        time.sleep(0.1)

    log(f"=== DONE. {found} results ===")

if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        os._exit(0)
    except KeyboardInterrupt:
        os._exit(1)
    except Exception as e:
        log(f"FATAL: {e}")
        os._exit(1)
