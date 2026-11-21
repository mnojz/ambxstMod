.pragma library

function fit(width, height, availableWidth, availableHeight, requestedScale, padding = 32) {
    return Math.min(requestedScale, Math.max(1, availableWidth - padding) / Math.max(1, width),
                    Math.max(1, availableHeight - padding) / Math.max(1, height));
}

function offset(alignment, available, size, edgeMargin = 32) {
    const space = Math.max(0, available - size);
    const margin = Math.min(edgeMargin, space / 2);
    if (alignment === "left" || alignment === "top")
        return margin;
    if (alignment === "right" || alignment === "bottom")
        return space - margin;
    return space / 2;
}

function localUrl(value) {
    return typeof value === "string" && value.startsWith("file:///") ? value : "";
}

function fileUrl(path) {
    if (typeof path !== "string")
        return "";
    if (path.startsWith("/"))
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    return localUrl(path);
}

function alignmentGuides(length, siblings, horizontal) {
    const margin = Math.min(32, length / 2);
    const guides = [0, margin, length / 2, length - margin, length];
    for (const sibling of siblings) {
        const origin = horizontal ? sibling.x : sibling.y;
        const size = (horizontal ? sibling.width : sibling.height) * sibling.scale;
        guides.push(origin, origin + size / 2, origin + size);
    }
    return guides;
}

function snap(position, offsets, guides, minimum, maximum, threshold = 12) {
    let best = { position, guide: -1, distance: threshold + 1 };
    for (const guide of guides) {
        for (const offset of offsets) {
            const candidate = guide - offset;
            const distance = Math.abs(candidate - position);
            if (candidate >= minimum && candidate <= maximum && distance <= threshold && distance < best.distance)
                best = { position: candidate, guide, distance };
        }
    }
    return best;
}
