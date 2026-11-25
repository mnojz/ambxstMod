.pragma library

const parts = {
    clock: [["hours", "Hours", true], ["minutes", "Minutes", true],
            ["suffix", "Seconds and AM/PM", true], ["date", "Date", true],
            ["greeting", "Greeting", true], ["dial", "Orbit dial", false]],
    media: [["art", "Album art", false], ["title", "Track title", true],
            ["artist", "Artist", true], ["controls", "Playback controls", false]],
    login: [["avatar", "Profile picture", false], ["password", "Password field", true],
            ["title", "Sign-in title", true]],
    visualizer: [["graph", "Spectrum", false]]
};
function read(value) {
    try {
        const data = JSON.parse(value);
        return data && typeof data === "object" && !Array.isArray(data) ? data : {};
    } catch (error) {
        return {};
    }
}

function part(styles, key) {
    const value = styles[key];
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function editPart(styles, key, property, value) {
    const next = Object.assign({}, styles);
    const style = Object.assign({}, part(next, key));
    if (!property) {
        delete next[key];
    } else {
        if (value === undefined)
            delete style[property];
        else
            style[property] = value;
        if (Object.keys(style).length > 0)
            next[key] = style;
        else
            delete next[key];
    }

    // Identical styles compare equal even when their controls were changed in a different order.
    const sorted = {};
    for (const name of Object.keys(next).sort()) {
        const entry = part(next, name);
        sorted[name] = {};
        for (const field of Object.keys(entry).sort())
            sorted[name][field] = entry[field];
    }
    return JSON.stringify(sorted);
}

function clockPartStyles(value, clockStyle) {
    if (clockStyle === "offset") {
        const styles = read(value);
        // The previous Ambxst preset serialized its default as a legacy offset.
        if (part(styles, "minutes").yPercent === 72)
            return editPart(styles, "minutes", "yPercent", undefined);
    }
    return value ?? "{}";
}

function clockPartPosition(style, key, clockStyle, axis, start, room, scale) {
    const position = style[axis + "Position"];
    if (Number.isFinite(position))
        return Math.max(-100, Math.min(100, position));
    if (room <= 0)
        return 0;

    let origin = start;
    const oldPercent = style[axis + "Percent"];
    if (Number.isFinite(oldPercent)) {
        if (axis === "y" && key === "minutes" && clockStyle === "offset") {
            if (oldPercent !== 72)
                origin = room * Math.max(0, oldPercent) / 100;
        } else {
            origin += oldPercent * (oldPercent < 0 ? origin : room - origin) / 100;
        }
    }
    origin += legacyOffset(style, axis, scale);
    return Math.max(-100, Math.min(100, (origin / room * 2 - 1) * 100));
}

function placeClockPart(percent, available, size) {
    return Math.max(0, available - size) * (percent + 100) / 200;
}

function clockPartLayout(parts, width, height, style, scale) {
    const extents = { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity };
    const placements = {};
    for (const item of parts) {
        const xPosition = clockPartPosition(item.partStyle, item.partKey, style, "x", item.naturalX, width - item.width, scale);
        const yPosition = clockPartPosition(item.partStyle, item.partKey, style, "y", item.naturalY, height - item.height, scale);
        const left = placeClockPart(xPosition, width, item.width);
        const top = placeClockPart(yPosition, height, item.height);
        extents.left = Math.min(extents.left, left);
        extents.top = Math.min(extents.top, top);
        extents.right = Math.max(extents.right, left + item.width);
        extents.bottom = Math.max(extents.bottom, top + item.height);
        placements[item.partKey] = { xPosition, yPosition };
    }
    // Use the intrinsic preset span to measure spread, then place against the fitted box.
    // This keeps both the frame and center-relative percentages stable during edits.
    const fittedWidth = parts.length ? Math.max(1, extents.right - extents.left) : 1;
    const fittedHeight = parts.length ? Math.max(1, extents.bottom - extents.top) : 1;
    for (const item of parts) {
        const placement = placements[item.partKey];
        placement.x = placeClockPart(placement.xPosition, fittedWidth, item.width);
        placement.y = placeClockPart(placement.yPosition, fittedHeight, item.height);
    }
    return { width: fittedWidth, height: fittedHeight, placements };
}

function editClockPosition(styles, key, axis, percent, presetPercent) {
    const withoutPixels = read(editPart(styles, key, axis, undefined));
    const withoutLegacy = read(editPart(withoutPixels, key, axis + "Percent", undefined));
    return editPart(withoutLegacy, key, axis + "Position", percent === presetPercent ? undefined : percent);
}

function snapClockPosition(percent) {
    if (Math.abs(percent) <= 4)
        return 0;
    return Math.abs(percent) >= 97 ? Math.sign(percent) * 100 : percent;
}

function color(style, fallback, colors) {
    const choice = style.color;
    if (typeof choice !== "string")
        return fallback;
    if (/^#[0-9a-f]{6}$/i.test(choice))
        return Qt.color(choice);
    return colors.availableColorNames.includes(choice) ? colors[choice] : fallback;
}

function scale(style) {
    return Number.isFinite(style.scale) ? Math.max(0.65, Math.min(1.5, style.scale / 100)) : 1;
}

function legacyOffset(style, axis, scale) {
    const distance = style[axis];
    return Number.isFinite(distance) ? Math.max(-60, Math.min(60, distance)) * scale : 0;
}

function partPosition(axis, item, widget) {
    const horizontal = axis === "x";
    const dimension = horizontal ? "width" : "height";
    let start = 0;
    for (let current = item; current && current !== widget; current = current.parent)
        start += current[axis];
    return { start, end: widget[dimension] - item[dimension] - start };
}

function partOffset(style, axis, scale, item, widget) {
    const percent = style[axis + "Percent"];
    const savedOffset = legacyOffset(style, axis, scale);
    if (!widget || !Number.isFinite(percent))
        return savedOffset;
    const reach = partPosition(axis, item, widget);
    return savedOffset + Math.max(-100, Math.min(100, percent)) / 100 * (percent < 0 ? reach.start : reach.end);
}

function frameSize(value, naturalWidth, naturalHeight) {
    return Qt.size(Number.isFinite(value.width) && value.width > 0 ? value.width : naturalWidth,
                   Number.isFinite(value.height) && value.height > 0 ? value.height : naturalHeight);
}

function editOption(options, key, value) {
    const next = Object.assign({}, options);
    if (value === undefined)
        delete next[key];
    else
        next[key] = value;
    const ordered = {};
    for (const name of Object.keys(next).sort())
        ordered[name] = next[name];
    return JSON.stringify(ordered);
}

function targetWidget(target) {
    return target === "avatar" ? "login" : target;
}

function canAnchor(settings, widget, target) {
    const visited = [widget];
    let next = targetWidget(target);
    while (Object.prototype.hasOwnProperty.call(parts, next)) {
        if (visited.includes(next))
            return false;
        visited.push(next);
        next = targetWidget(read(settings[next + "Anchor"]).target);
    }
    return next === "screen" || !next;
}

function place(anchor, target, size, screen, designScale) {
    const gap = Number.isFinite(anchor.gap) ? Math.max(0, Math.min(160, anchor.gap)) * designScale : 0;
    const alignment = typeof anchor.alignment === "string" ? anchor.alignment : "";
    let x = target.x + (target.width - size.width) / 2;
    let y = target.y + (target.height - size.height) / 2;

    if (alignment === "before")
        x = target.x - size.width - gap;
    else if (alignment === "after")
        x = target.x + target.width + gap;
    else if (alignment?.endsWith("left"))
        x = target.x + gap;
    else if (alignment?.endsWith("right"))
        x = target.x + target.width - size.width - gap;

    if (alignment === "above")
        y = target.y - size.height - gap;
    else if (alignment === "below")
        y = target.y + target.height + gap;
    else if (alignment?.startsWith("top"))
        y = target.y + gap;
    else if (alignment?.startsWith("bottom"))
        y = target.y + target.height - size.height - gap;

    return Qt.rect(Math.max(0, Math.min(screen.width - size.width, x)),
                   Math.max(0, Math.min(screen.height - size.height, y)), size.width, size.height);
}
