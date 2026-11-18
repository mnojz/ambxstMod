import QtQuick
Item {
    id: h
    width: 100; height: 100
    Component { id: comp; FarewellQuote {} }
    Component.onCompleted: {
        const xhr = new XMLHttpRequest(); xhr.open("GET", Qt.resolvedUrl("quotes.json"), false); xhr.send();
        const quotes = JSON.parse(xhr.responseText);
        const sizes = [[3440,1440],[5120,1440],[3840,2160],[2560,1440],[1920,1080],[1504,1003],[1366,768],[1280,720],[1024,600],[800,480],[640,360],[1080,1920],[1440,2560],[720,1280]];
        const fonts = ["Roboto Condensed", "", "DejaVu Sans", "DejaVu Sans Mono"];
        let bad = 0;
        for (const f of fonts) for (const sz of sizes) {
            let minPx = 1e9, shrunk = 0, worst = "";
            for (let i = 0; i < quotes.length; i++) {
                const o = comp.createObject(h, { width: sz[0], height: sz[1], quote: quotes[i].text, fontFamily: f, reveal: 1 });
                const custom = (i === quotes.length - 1);
                const ok = o.quoteLineCount === 1 && o.quoteContentWidth <= o.lineWidth + 0.5 && (custom || !o.quoteTruncated);
                if (!ok) { bad++; console.log("FAIL", f, sz, o.quoteLineCount, o.quoteContentWidth, o.lineWidth, o.quoteTruncated, quotes[i].text.slice(0, 40)); }
                if (!custom) { if (o.fittedPixelSize < minPx) { minPx = o.fittedPixelSize; worst = quotes[i].text.slice(0, 30); } if (o.fittedPixelSize < o.basePixelSize - 0.5) shrunk++; }
                else if (f === "Roboto Condensed") console.log("  custom 215-char line @", sz[0] + "x" + sz[1], "->", o.fittedPixelSize + "px", "lines", o.quoteLineCount, "elided", o.quoteTruncated);
                o.destroy();
            }
            console.log((f || "(default font)"), sz[0] + "x" + sz[1], "base", Math.max(14, Math.round(Math.min(sz[1] * 0.026, sz[0] * 0.03))) + "px", "smallest builtin", minPx + "px", "shrunk", shrunk + "/" + (quotes.length - 1), "[" + worst + "]");
        }
        console.log(bad === 0 ? "ALL ONE LINE, NONE ELIDED" : ("FAILURES: " + bad));
        Qt.quit();
    }
}
