.pragma library

function normalize(value, formats, defaultFormat, limit) {
    var normalized = [];
    var seen = ({});
    if (!Array.isArray(value))
        return normalized;

    for (var i = 0; i < value.length && normalized.length < limit; i++) {
        var candidate = value[i];
        if (!candidate || typeof candidate !== "object")
            continue;

        var requestedFormat = String(candidate.format || "").trim().toLowerCase();
        var item = {
            itemId: String(candidate.itemId || ""),
            title: String(candidate.title || ""),
            url: String(candidate.url || ""),
            filename: String(candidate.filename || ""),
            format: formats.indexOf(requestedFormat) >= 0 ? requestedFormat : defaultFormat,
            thumbnail: String(candidate.thumbnail || ""),
            finishedAt: Number(candidate.finishedAt || 0)
        };
        var key = item.itemId || item.filename || item.url;
        if (item.title === "" || key === "" || seen[key])
            continue;
        seen[key] = true;
        normalized.push(item);
    }
    return normalized;
}
