// Wallpaper-adaptive spicetify dynamic theme
// Injects CSS custom properties via <style> element in <head>.
// Reads colors from /tmp/qs_colors.json (matugen output) when available,
// falls back to album art extraction via Vibrant.js.

(function () {
    "use strict";

    // ---- Style injection (replaces entire :root block on each update) ----
    // Idempotent: re-running this extension (e.g. after `spicetify refresh -e`)
    // reuses the existing <style> element instead of stacking duplicates.
    var styleEl = document.getElementById("wallpaper-adaptive-styles");
    if (!styleEl) {
        styleEl = document.createElement("style");
        styleEl.id = "wallpaper-adaptive-styles";
        document.head.appendChild(styleEl);
    }

    function injectCSS(vars) {
        var lines = [];
        for (var key in vars) {
            if (!vars.hasOwnProperty(key)) continue;
            lines.push("  --" + key + ": " + vars[key] + ";");
        }
        styleEl.textContent = ":root {\n" + lines.join("\n") + "\n}";
    }

    // ---- Color utilities ----
    function hexToRgb(hex) {
        var bigint = parseInt(hex.replace("#", ""), 16);
        return [(bigint >> 16) & 255, (bigint >> 8) & 255, bigint & 255];
    }

    function rgbToHex(r, g, b) {
        var rgb = (r << 16) | (g << 8) | b;
        return "#" + (0x1000000 + rgb).toString(16).slice(1);
    }

    function isLight(hex) {
        var rgb = hexToRgb(hex);
        var brightness = (rgb[0] * 299 + rgb[1] * 587 + rgb[2] * 114) / 1000;
        return brightness > 128;
    }

    function lightenDarkenColor(hex, percent) {
        var parts = [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
        return "#" + [1, 3, 5].map(function (s) {
            var c = parseInt(hex.substr(s, 2), 16);
            var adjusted = Math.max(0, Math.min(255, Math.round((c * (100 + percent)) / 100)));
            return adjusted.toString(16).padStart(2, "0");
        }).join("");
    }

    function rgbToHsl(r, g, b) {
        r /= 255; g /= 255; b /= 255;
        var max = Math.max(r, g, b), min = Math.min(r, g, b);
        var h, s, l = (max + min) / 2;
        if (max === min) {
            h = s = 0;
        } else {
            var d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            switch (max) {
                case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
                case g: h = ((b - r) / d + 2) / 6; break;
                case b: h = ((r - g) / d + 4) / 6; break;
            }
        }
        return [h, s, l];
    }

    // ---- Map matugen Catppuccin colors → spicetify CSS variables (balanced mode) ----
    function norm(h) {
        if (!h || typeof h !== "string") return null;
        return h.charAt(0) === "#" ? h : "#" + h;
    }

    function applyFromMatugen(mat) {
        if (!mat || typeof mat !== "object") return false;

        var bg = "#1e1e2e", crust = "#11111b", mantle = "#181825";
        var surface0 = "#313244", surface1 = "#45475a";
        var text = "#cdd6f4", subtext1 = "#bac2de";
        var overlay0 = "#6c7086", overlay1 = "#7f849c";
        var accentBlue = "#89b4fa", accentMauve = "#cba6f7", accentGreen = "#a6e3a1";

        if (mat.base && typeof mat.base === "string") {
            bg = norm(mat.base) || bg;
            crust = norm(mat.crust) || crust;
            mantle = norm(mat.mantle) || mantle;
            surface0 = norm(mat.surface0) || surface0;
            surface1 = norm(mat.surface1) || surface1;
            text = norm(mat.text) || text;
            subtext1 = norm(mat.subtext1) || subtext1;
            overlay0 = norm(mat.overlay0) || overlay0;
            overlay1 = norm(mat.overlay1) || overlay1;
            accentBlue = norm(mat.blue) || accentBlue;
            accentMauve = norm(mat.mauve) || accentMauve;
            accentGreen = norm(mat.green) || accentGreen;
        } else if (mat.base16) {
            var b16 = mat.base16;
            crust = "#" + getNested(b16, "base00", "dark", "color");
            mantle = "#" + getNested(b16, "base01", "dark", "color");
            surface0 = "#" + getNested(b16, "base02", "dark", "color");
            overlay0 = "#" + getNested(b16, "base03", "dark", "color");
            subtext1 = "#" + getNested(b16, "base04", "dark", "color");
            text = "#" + getNested(b16, "base05", "dark", "color");
            surface1 = "#" + getNested(b16, "base06", "dark", "color");
            overlay1 = "#" + getNested(b16, "base07", "dark", "color");
            accentBlue = "#" + getNested(b16, "base08", "dark", "color") || "#89b4fa";
            accentMauve = "#" + getNested(b16, "base12", "dark", "color") || "#cba6f7";
            accentGreen = "#" + getNested(b16, "base0A", "dark", "color") || "#a6e3a1";
        } else { return false; }

        var isLightBg = isLight(bg);
        var mainText = text;
        if (!isLightBg && parseInt(text.substr(1, 2), 16) < 80) {
            mainText = lightenDarkenColor(text, 140);
        }

        var darkerAccent = lightenDarkenColor(accentBlue, isLightBg ? 12 : -20);
        var darkestAccent = lightenDarkenColor(accentBlue, isLightBg ? 30 : -40);
        var softHighlight = setLightnessFromHex(accentBlue, isLightBg ? 0.9 : 0.14);

        var vars = {
            "spice-main": bg,
            "spice-sidebar": bg,
            "spice-player": bg,
            "spice-shadow": crust,
            "spice-card": surface1,
            "spice-subtext": subtext1,
            "spice-selected-row": subtext1,
            "spice-main-elevated": surface0,
            "spice-notification": surface0,
            "spice-highlight-elevated": surface0,
            "spice-text": mainText,
            "spice-button": darkestAccent,
            "spice-button-active": darkerAccent,
            "spice-tab-active": softHighlight,
            "spice-button-disabled": softHighlight,
            "spice-highlight": setLightnessFromHex(accentBlue, isLightBg ? 0.9 : 0.1)
        };

        var rgb = hexToRgb(accentBlue);
        vars["colormatrix"] = "url('data:image/svg+xml;utf8," +
            "<svg xmlns=\"http://www.w3.org/2000/svg\">" +
            "<filter id=\"recolor\" color-interpolation-filters=\"sRGB\">" +
            "<feColorMatrix type=\"matrix\" values=\"" +
            "0 0 0 0 " + rgb[0] / 255 + "\n" +
            "0 0 0 0 " + rgb[1] / 255 + "\n" +
            "0 0 0 0 " + rgb[2] / 255 + "\n" +
            "0 0 0 1 0\"/>" +
            "</filter></svg>#recolor')";

        injectCSS(vars);
        return true;
    }

    function getNested(obj, key1, key2, key3) {
        if (!obj || !obj[key1]) return null;
        var v = obj[key1][key2];
        return typeof v === "string" ? v : (v && v.color ? v.color : null);
    }

    function setLightnessFromHex(hex, lightness) {
        var rgb = hexToRgb(hex);
        var hsl = rgbToHsl(rgb[0], rgb[1], rgb[2]);
        hsl[2] = lightness;
        return rgbToHex(hsl[0] * 255, hsl[1] * 255, hsl[2] * 255);
    }

    // ---- Default Catppuccin Mocha colors used when no source is available ----
    function applyDefaults() {
        injectCSS({
            "spice-main": "#1e1e2e",
            "spice-sidebar": "#1e1e2e",
            "spice-player": "#1e1e2e",
            "spice-shadow": "#11111b",
            "spice-card": "#45475a",
            "spice-subtext": "#bac2de",
            "spice-selected-row": "#bac2de",
            "spice-main-elevated": "#313244",
            "spice-notification": "#313244",
            "spice-highlight-elevated": "#313244",
            "spice-text": "#cdd6f4",
            "spice-button": "#74a8fc",
            "spice-button-active": "#5b95f0",
            "spice-tab-active": "#2e2f3d",
            "spice-button-disabled": "#2e2f3d",
            "spice-highlight": "#262731"
        });
    }

    // ---- Wallpaper color source ----
    // Colors arrive via window.__wallpaperColors, set by the companion
    // wallpaper-colors-data.js extension that matugen regenerates on
    // every wallpaper change. Spotify's renderer can't fetch /tmp paths
    // directly (CORS — origin is xpui.app.spotify.com), so we embed.
    function loadWallpaperColors() {
        return Promise.resolve(window.__wallpaperColors || null);
    }

    // ---- Custom Vibrant.js — full implementation inline ----
    function rgbToLab(r, g, b) {
        var rn = r / 255, gn = g / 255, bn = b / 255;
        rn = (rn > 0.04045) ? Math.pow((rn + 0.055) / 1.055, 2.4) : rn / 12.92;
        gn = (gn > 0.04045) ? Math.pow((gn + 0.055) / 1.055, 2.4) : gn / 12.92;
        bn = (bn > 0.04045) ? Math.pow((bn + 0.055) / 1.055, 2.4) : bn / 12.92;
        var x = (rn * 0.4124564 + gn * 0.3575761 + bn * 0.1804375) / 0.95047;
        var y = (rn * 0.2126729 + gn * 0.7151522 + bn * 0.0721750) / 1.00000;
        var z = (rn * 0.0193339 + gn * 0.1191920 + bn * 0.9503041) / 1.08883;
        x = (x > 0.008856) ? Math.pow(x, 1 / 3) : (7.787 * x) + 16 / 116;
        y = (y > 0.008856) ? Math.pow(y, 1 / 3) : (7.787 * y) + 16 / 116;
        z = (z > 0.008856) ? Math.pow(z, 1 / 3) : (7.787 * z) + 16 / 116;
        return [(116 * y) - 16, 13.027 * (x - 0.95047), 13.027 * (z - 0.95844)];
    }

    function labToRgb(l, a, b) {
        var fy = (l + 16) / 116;
        var fx = a / 13.027 + 0.95047;
        var fz = b / 13.027 + 0.95844;
        function inv(v) { return v > Math.pow(0.008856, 1 / 3) ? v * v * v : (v - 16 / 116) / 7.787; }
        var rn = inv(fx), gn = inv(fy), bn = inv(fz);
        rn = rn * 0.4124564 + gn * 0.3575761 + bn * 0.1804375;
        gn = rn * 0.2126729 + gn * 0.7151522 + bn * 0.0721750;
        bn = rn * 0.0193339 + gn * 0.1191920 + bn * 0.9503041;
        function out(v) { return (v > 0.0031308) ? 1.055 * Math.pow(v, 1 / 2.4) - 0.055 : v * 12.92; }
        r = Math.round(out(rn) * 255);
        g = Math.round(out(gn) * 255);
        b = Math.round(out(bn) * 255);
        return [Math.max(0, Math.min(255, r)), Math.max(0, Math.min(255, g)), Math.max(0, Math.min(255, b))];
    }

    function labToHex(l, a, b) {
        var rgb = labToRgb(l, a, b);
        return "#" + (0x1000000 | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]).toString(16).slice(1);
    }

    function luminance(r, g, b) {
        var a = [r, g, b].map(function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
        return a[0] * 0.2126 + a[1] * 0.7152 + a[2] * 0.0722;
    }

    function contrast(rgb1, rgb2) {
        var l1 = luminance(rgb1[0], rgb1[1], rgb1[2]);
        var l2 = luminance(rgb2[0], rgb2[1], rgb2[2]);
        var lighter = Math.max(l1, l2), darker = Math.min(l1, l2);
        return (lighter + 0.05) / (darker + 0.05);
    }

    function saturation(lab) { return Math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]); }

    var HIST_BINS = 32;
    var L_STEP = 100 / HIST_BINS, A_STEP = 256 / HIST_BINS, B_STEP = 256 / HIST_BINS;

    function Vibrant(imgEl) {
        this.img = imgEl;
        this.quantize = arguments[1] || 10;
        this._swatches = null;
    }

    Vibrant.prototype._samplePixels = function () {
        var canvas = document.createElement("canvas");
        var ctx = canvas.getContext("2d");
        var w = Math.min(this.img.naturalWidth, 350);
        var h = Math.round(w * (this.img.naturalHeight / this.img.naturalWidth));
        canvas.width = w; canvas.height = h;
        try { ctx.drawImage(this.img, 0, 0, w, h); } catch (e) { return []; }
        var data = ctx.getImageData(0, 0, w, h).data;
        var pixels = [];
        for (var i = 0; i < data.length; i += 4 * this.quantize) {
            if (i + 3 >= data.length) break;
            pixels.push([data[i], data[i + 1], data[i + 2]]);
        }
        return pixels;
    };

    Vibrant.prototype._buildHistogram = function () {
        var pixels = this._samplePixels();
        var hist = {};
        for (var i = 0; i < pixels.length; i++) {
            var lab = rgbToLab(pixels[i][0], pixels[i][1], pixels[i][2]);
            var li = Math.min(HIST_BINS - 1, Math.max(0, Math.round(lab[0] / L_STEP)));
            var ai = Math.min(HIST_BINS - 1, Math.max(0, Math.round((lab[1] + 128) / A_STEP)));
            var bi = Math.min(HIST_BINS - 1, Math.max(0, Math.round((lab[2] + 128) / B_STEP)));
            var key = li + "_" + ai + "_" + bi;
            if (!hist[key]) hist[key] = { count: 0, labSum: [0, 0, 0], rgbSum: [0, 0, 0] };
            hist[key].count++;
            hist[key].labSum[0] += lab[0]; hist[key].labSum[1] += lab[1]; hist[key].labSum[2] += lab[2];
            hist[key].rgbSum[0] += pixels[i][0]; hist[key].rgbSum[1] += pixels[i][1]; hist[key].rgbSum[2] += pixels[i][2];
        }
        return hist;
    };

    function _binAvg(hist, key) {
        var b = hist[key];
        if (!b || b.count === 0) return null;
        return [b.labSum[0] / b.count, b.labSum[1] / b.count, b.labSum[2] / b.count];
    }

    function _binRgb(hist, key) {
        var b = hist[key];
        if (!b || b.count === 0) return null;
        return [b.rgbSum[0] / b.count, b.rgbSum[1] / b.count, b.rgbSum[2] / b.count];
    }

    function _closest(hist, targetLab) {
        var bestKey = null, bestDist = Infinity;
        for (var key in hist) {
            if (!hist.hasOwnProperty(key)) continue;
            var lab = _binAvg(hist, key);
            if (!lab) continue;
            var d = (lab[0] - targetLab[0]) * (lab[0] - targetLab[0]) +
                    (lab[1] - targetLab[1]) * (lab[1] - targetLab[1]) +
                    (lab[2] - targetLab[2]) * (lab[2] - targetLab[2]);
            if (d < bestDist) { bestDist = d; bestKey = key; }
        }
        return bestKey ? _binRgb(hist, bestKey) : null;
    }

    function Swatch(rgb, lab) { this._rgb = rgb; this._lab = lab; }
    Swatch.prototype.getHex = function () { return labToHex(this._lab[0], this._lab[1], this._lab[2]); };
    Swatch.prototype.getRGB = function () { return this._rgb; };
    Swatch.prototype.getLuminance = function () { return luminance(this._rgb[0], this._rgb[1], this._rgb[2]); };
    Swatch.prototype.getBodytext = function (bgHex) {
        var bgRgb = hexToRgb(bgHex);
        var c = contrast(this._rgb, bgRgb);
        return c >= 3 ? "#ffffff" : "#000000";
    };

    Vibrant.prototype.swatches = function () {
        if (this._swatches) return this._swatches;
        var hist = this._buildHistogram();
        var swatches = {};

        function pick(rangeL, rangeA, rangeB) {
            var bestKey = null, bestCount = 0;
            for (var key in hist) {
                if (!hist.hasOwnProperty(key)) continue;
                var parts = key.split("_").map(Number);
                if (parts[0] < rangeL[0] || parts[0] >= rangeL[1]) continue;
                if (parts[1] < rangeA[0] || parts[1] >= rangeA[1]) continue;
                if (parts[2] < rangeB[0] || parts[2] >= rangeB[1]) continue;
                if (hist[key].count > bestCount) { bestCount = hist[key].count; bestKey = key; }
            }
            return bestKey ? new Swatch(_binRgb(hist, bestKey), _binAvg(hist, bestKey)) : null;
        }

        swatches.Vibrant = pick([0.45, 0.7], [128 - 64 + 1, 128 + 64], [128 - 64 + 1, 128 + 64]);
        swatches.Muted = pick([0.3, 0.75], [0, 128 - 32], [0, 128 - 32]);
        swatches.DarkVibrant = pick([0, 0.35], [128 - 64 + 1, 128 + 64], [128 - 64 + 1, 128 + 64]);
        swatches.LightVibrant = pick([0.65, 1.0], [128 - 64 + 1, 128 + 64], [128 - 64 + 1, 128 + 64]);
        swatches.DarkMuted = pick([0, 0.35], [0, 128 - 32], [0, 128 - 32]);
        swatches.LightMuted = pick([0.65, 1.0], [0, 128 - 32], [0, 128 - 32]);

        var ranges = {
            Vibrant: [60, 128, 128], Muted: [55, 96, 96], DarkVibrant: [20, 128, 128],
            LightVibrant: [85, 128, 128], DarkMuted: [20, 96, 96], LightMuted: [85, 96, 96]
        };
        for (var key in swatches) { if (!swatches.hasOwnProperty(key)) continue;
            if (!swatches[key]) {
                var fallback = _closest(hist, ranges[key] || [50, 128, 128]);
                swatches[key] = new Swatch(fallback || [128, 128, 128], rgbToLab(128, 128, 128));
            }
        }

        this._swatches = swatches;
        return swatches;
    };

    async function applyFromAlbumArt() {
        var imgEl = document.querySelector(".main-image-image.cover-art-image");
        if (!imgEl || !imgEl.src.startsWith("https://i.scdn.co/image")) return false;

        try {
            var img = new Image();
            img.crossOrigin = "anonymous";
            img.src = imgEl.src;
            await new Promise(function (resolve) {
                if (imgEl.complete && imgEl.naturalWidth > 0) { resolve(); return; }
                img.onload = function () { resolve(); };
                img.onerror = function () { resolve(); };
            });
            var vibrantSwatches = new Vibrant(img, 12).swatches();
            if (!vibrantSwatches) return false;

            var mainBg = "#1e1e2e";
            for (var key in vibrantSwatches) {
                if (!vibrantSwatches.hasOwnProperty(key)) continue;
                var computedStyle = document.documentElement.style.getPropertyValue("--spice-main");
                if (computedStyle && isLight(computedStyle)) { mainBg = "#FAFAFA"; break; }
            }

            var textHex = "#1db954";
            for (var i = 0; i < 6; i++) {
                var names = ["Vibrant", "DarkVibrant", "Muted", "LightVibrant", "DarkMuted", "LightMuted"];
                if (vibrantSwatches[names[i]]) { textHex = vibrantSwatches[names[i]].getHex(); break; }
            }

            var isLightBg = mainBg === "#FAFAFA";
            var mainText = lightenDarkenColor(textHex, isLightBg ? -15 : 45);

            var vars = {
                "spice-main": mainBg,
                "spice-sidebar": mainBg,
                "spice-player": mainBg,
                "spice-shadow": "#000000",
                "spice-card": isLightBg ? "#e8e8e8" : "#2a2a2a",
                "spice-subtext": isLightBg ? "#3D3D3D" : "#EAEAEA",
                "spice-selected-row": isLightBg ? "#3D3D3D" : "#EAEAEA",
                "spice-main-elevated": isLightBg ? "#f5f5f5" : "#2a2a2a",
                "spice-notification": isLightBg ? "#e8e8e8" : "#2a2a2a",
                "spice-highlight-elevated": isLightBg ? "#ffffff" : "#3a3a3a",
                "spice-text": mainText,
                "spice-button": lightenDarkenColor(textHex, isLightBg ? 12 : -20),
                "spice-button-active": lightenDarkenColor(textHex, isLightBg ? 30 : -40),
                "spice-tab-active": setLightnessFromHex(textHex, isLightBg ? 0.9 : 0.14),
                "spice-button-disabled": setLightnessFromHex(textHex, isLightBg ? 0.85 : 0.2),
                "spice-highlight": setLightnessFromHex(textHex, isLightBg ? 0.88 : 0.12)
            };

            var rgb = hexToRgb(textHex);
            vars["colormatrix"] = "url('data:image/svg+xml;utf8," +
                "<svg xmlns=\"http://www.w3.org/2000/svg\">" +
                "<filter id=\"recolor\" color-interpolation-filters=\"sRGB\">" +
                "<feColorMatrix type=\"matrix\" values=\"" +
                "0 0 0 0 " + rgb[0] / 255 + "\n" +
                "0 0 0 0 " + rgb[1] / 255 + "\n" +
                "0 0 0 0 " + rgb[2] / 255 + "\n" +
                "0 0 0 1 0\"/>" +
                "</filter></svg>#recolor')";

            injectCSS(vars);
            return true;
        } catch (e) {
            console.error("[wallpaper-adaptive] Vibrant error:", e);
            return false;
        }
    }

    // ---- Main update loop ----
    async function applyColors() {
        var matData = await loadWallpaperColors();
        if (matData && applyFromMatugen(matData)) {
            console.log("[wallpaper-adaptive] Applied wallpaper colors");
            return;
        }

        if (await applyFromAlbumArt()) {
            console.log("[wallpaper-adaptive] Applied album art colors");
            return;
        }

        applyDefaults();
        console.log("[wallpaper-adaptive] No color source available, using defaults");
    }

    // ---- Hook into Spotify song changes too ----
    function waitForElement(els, func, timeout) {
        timeout = timeout || 100;
        var queries = els.map(function (el) { return document.querySelector(el); });
        if (queries.every(function (a) { return a; })) {
            func(queries);
        } else if (timeout > 0) {
            setTimeout(waitForElement, 300, els, func, --timeout);
        }
    }

    async function onSongChange() {
        await applyColors();
    }

    // ---- Startup ----
    function startup() {
        if (!Spicetify.showNotification) {
            setTimeout(startup, 300);
            return;
        }

        Spicetify.Player.addEventListener("songchange", onSongChange);

        applyColors().then(function () {
            var bg = getComputedStyle(document.documentElement).getPropertyValue("--spice-main").trim();
            var src = window.__wallpaperColors ? "wallpaper" : "fallback";
            Spicetify.showNotification("Wallpaper-adaptive: " + src + " " + bg);
        });
    }

    startup();
})();
