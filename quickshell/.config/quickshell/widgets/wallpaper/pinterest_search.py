#!/usr/bin/env python3
import sys, time, os, re, json
import urllib.request, urllib.parse

LOG_FILE = "/tmp/qs_pinterest_scraper.log"
CONTROL_FILE = "/tmp/ddg_search_control"

def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} - {msg}\n")
    except:
        pass

def get_state():
    try:
        with open(CONTROL_FILE, "r") as f:
            return f.read().strip()
    except:
        return "run"

def main():
    log("=== PINTEREST SEARCH STARTING ===")
    if len(sys.argv) < 2:
        log("ERROR: No query provided.")
        return

    query = sys.argv[1].strip() + " wallpaper"
    log(f"Query: '{query}'")

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
    }

    search_url = f"https://www.pinterest.com/search/pins/?q={urllib.parse.quote(query)}&rs=typed"

    log(f"Fetching Pinterest search from: {search_url}")
    links_found = 0

    for attempt in range(3):
        try:
            req = urllib.request.Request(search_url, headers=headers)
            html = urllib.request.urlopen(req, timeout=15).read().decode("utf-8", errors="replace")

            pattern = r'"encoding_url"\s*:\s*"([^"]+)"'
            urls = re.findall(pattern, html)

            if not urls:
                log(f"Attempt {attempt + 1}: No images found.")
                time.sleep(1)
                continue

            log(f"Found {len(urls)} encoded URLs on attempt {attempt + 1}.")

            seen = set()
            for encoded_url in urls:
                state = get_state()
                if state == "stop":
                    log("Stop signal detected. Exiting cleanly.")
                    return

                while state == "pause":
                    time.sleep(1)
                    state = get_state()

                try:
                    decoded = urllib.parse.unquote(encoded_url)
                except Exception:
                    continue

                if decoded in seen:
                    continue
                seen.add(decoded)

                thumb_url = decoded
                full_url = decoded

                if "236x" in decoded or "400x" in decoded or "474x" in decoded:
                    full_url = decoded.replace("236x", "1920x").replace("400x", "1920x").replace("474x", "1920x")
                elif "600x" in decoded or "736x" in decoded:
                    full_url = decoded

                try:
                    sys.stdout.write(f"{thumb_url}|{full_url}||\n")
                    sys.stdout.flush()
                    links_found += 1
                except BrokenPipeError:
                    log("Broken pipe detected. Exiting.")
                    os._exit(0)

            break

        except BrokenPipeError:
            os._exit(0)
        except Exception as e:
            log(f"Attempt {attempt + 1} Error: {str(e)}")
            time.sleep(2)

    log(f"=== PINTEREST SEARCH COMPLETE. Links: {links_found} ===")

if __name__ == "__main__":
    try: os.remove(LOG_FILE)
    except: pass

    try:
        main()
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)
    except KeyboardInterrupt:
        os._exit(1)
    except Exception as e:
        log(f"FATAL: {str(e)}")
        os._exit(1)
