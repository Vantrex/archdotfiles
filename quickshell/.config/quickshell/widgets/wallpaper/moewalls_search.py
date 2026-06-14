#!/usr/bin/env python3
"""
Scraper for moewalls.com — anime animated wallpapers (WebM/MP4).
Output: thumb_url|video_url|width|height  (same pipe format as the other scrapers)
"""
import sys, json, time, re, os
import urllib.request, urllib.parse

BASE          = "https://moewalls.com"
CONTROL_FILE  = "/tmp/ddg_search_control"
LOG_FILE      = "/tmp/qs_python_scraper.log"
MAX_RESULTS   = 30
PAGE_DELAY    = 0.35

def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} [moewalls] {msg}\n")
    except:
        pass

def get_state():
    try:
        with open(CONTROL_FILE) as f: return f.read().strip()
    except: return "run"

def fetch(url, timeout=12):
    headers = {
        "User-Agent":      "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0",
        "Accept":          "text/html,application/xhtml+xml,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer":         BASE + "/",
    }
    req = urllib.request.Request(url, headers=headers)
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", errors="replace")

def abs_url(url):
    """Convert relative /wp-content/... URL to absolute."""
    if url.startswith("//"):
        return "https:" + url
    if url.startswith("/"):
        return BASE + url
    return url

def extract_posts(html):
    """
    Return list of (thumb_url, post_url) from a listing page.
    Pairs by matching the slug in the thumbnail filename to the post URL.
    """
    # Post URLs: paths with 5+ segments (exclude feeds, categories, tags, etc.)
    all_hrefs = re.findall(r'href=["\'](' + re.escape(BASE) + r'/[^"\']+/)["\']', html)
    post_links = []
    seen = set()
    skip = {"feed", "category", "tag", "resolution", "page", "search",
            "wp-", "comment", "xmlrpc", "wp-json", "wp-login"}
    for l in all_hrefs:
        if l in seen: continue
        seen.add(l)
        path = l[len(BASE):]
        if path.count("/") >= 3 and not any(s in path for s in skip):
            post_links.append(l)

    # Thumbnails with '-thumb-' in filename (prefer larger size)
    all_thumbs = re.findall(
        r'(https://moewalls\.com/wp-content/uploads/[^\s"\']+?-thumb-[^\s"\']+?\.(?:jpg|png))',
        html
    )
    # Dedupe, prefer 728x* over 364x*
    thumb_by_slug = {}
    for t in all_thumbs:
        base_slug = re.sub(r'-thumb-.*$', '', t.split('/')[-1])
        existing = thumb_by_slug.get(base_slug)
        if existing is None or "728x" in t:
            thumb_by_slug[base_slug] = t

    pairs = []
    seen_posts = set()
    for slug, thumb in thumb_by_slug.items():
        for post in post_links:
            if slug in post and post not in seen_posts:
                pairs.append((thumb, post))
                seen_posts.add(post)
                break

    return pairs

def extract_video(html):
    """Return (video_url, width, height) from a post page."""
    # <source src="/wp-content/..." type="video/...">
    for pat in [
        r'<source[^>]+src=["\']([^"\']+\.(?:webm|mp4))["\']',
        r'<source[^>]+src=([^\s"\'<>]+\.(?:webm|mp4))',
        r'["\']file["\']\s*:\s*["\']([^"\']+\.(?:webm|mp4))["\']',
        r'(https?://[^\s"\'<>]+\.(?:webm|mp4))',
    ]:
        m = re.search(pat, html, re.IGNORECASE)
        if m:
            url = abs_url(m.group(1))
            if "moewalls.com" in url or url.startswith("https://"):
                break
    else:
        return None, 0, 0

    # og:image:width/height reflect the actual video resolution on moewalls.
    mw = re.search(r'og:image:width["\']?\s+content=["\'](\d+)["\']', html, re.IGNORECASE)
    mh = re.search(r'og:image:height["\']?\s+content=["\'](\d+)["\']', html, re.IGNORECASE)
    width  = int(mw.group(1)) if mw else 0
    height = int(mh.group(1)) if mh else 0

    # Fall back: pick the largest recognisable width/height pair in the page.
    if not width:
        fm = re.search(r'\b(3840|2560|3440|4096|1920)\b', html)
        if fm: width = int(fm.group(1))
    if not height:
        fh = re.search(r'\b(2160|1440|1080)\b', html)
        if fh: height = int(fh.group(1))

    if not width:  width  = 1920
    if not height: height = 1080

    # Skip anything below 1920px wide.
    if width < 1920:
        return None, 0, 0

    return url, width, height

def main():
    try: os.remove(LOG_FILE)
    except: pass

    if len(sys.argv) < 2:
        return
    query = sys.argv[1].strip()
    log(f"=== NEW SEARCH: '{query}' ===")

    found = 0
    for page in range(1, 8):
        if get_state() == "stop" or found >= MAX_RESULTS:
            break

        listing_url = (f"{BASE}/?s={urllib.parse.quote(query)}" if page == 1
                       else f"{BASE}/page/{page}/?s={urllib.parse.quote(query)}")
        log(f"Listing page {page}: {listing_url}")

        try:
            listing_html = fetch(listing_url)
        except Exception as e:
            log(f"Listing error: {e}")
            break

        posts = extract_posts(listing_html)
        log(f"{len(posts)} posts paired")
        if not posts:
            break

        for thumb_url, post_url in posts:
            if get_state() == "stop" or found >= MAX_RESULTS:
                break
            log(f"Post: {post_url}")
            try:
                post_html = fetch(post_url)
            except Exception as e:
                log(f"Post error: {e}")
                continue

            video_url, width, height = extract_video(post_html)
            if not video_url:
                log(f"  No video found")
                continue

            log(f"  → {video_url} ({width}x{height})")
            try:
                sys.stdout.write(f"{thumb_url}|{video_url}|{width}|{height}\n")
                sys.stdout.flush()
                found += 1
            except BrokenPipeError:
                os._exit(0)

            time.sleep(PAGE_DELAY)

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
