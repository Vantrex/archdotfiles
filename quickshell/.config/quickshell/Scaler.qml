import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property real currentWidth: 1920.0
    property real currentHeight: 1080.0
    property real uiScale: 1.0

    property real baseScale: {
        let mw = currentWidth
        let mh = currentHeight
        let us = uiScale
        if (mw <= 0 || mh <= 0) return 1.0
        let rw = mw / 1920.0
        let rh = mh / 1080.0
        let r = Math.min(rw, rh)
        let base = 1.0
        if (r <= 1.0) {
            base = Math.max(0.35, Math.pow(r, 0.85))
        } else {
            base = Math.pow(r, 0.5)
        }
        return base * (us !== undefined ? us : 1.0)
    }
    
    function s(val) { 
        return Math.round(val * baseScale)
    }
}
