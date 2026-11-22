.pragma library

const version = 1;
const fields = {
    clock: ["clockStyle", "clockFont", "clockSize", "clockPosition", "clockFormat",
            "clockX", "clockY", "clockDate", "clockBold", "clockWeekday",
            "clockSeconds", "clockGreeting", "clockDateSize", "clockWeight",
            "clockLetterSpacing", "clockAmPm", "clockTimeRatio", "clockDateRatio", "clockShadow"],
    media: ["mediaPosition", "mediaScale", "mediaX", "mediaY", "mediaStyle",
            "mediaArtwork", "mediaShadow", "mediaRadius", "mediaThumbnailRatio", "mediaThumbnailRadius"],
    login: ["loginPosition", "loginScale", "loginX", "loginY", "loginAvatar", "loginStyle", "loginShadow"]
};

function valuesFor(widget, settings, defaults) {
    const values = {};
    for (const key of fields[widget] ?? []) {
        const value = settings[key];
        if (typeof value === typeof defaults[key] && (typeof value !== "number" || Number.isFinite(value)))
            values[key] = value;
    }
    return values;
}

function create(widget, name, settings, defaults) {
    return { schemaVersion: version, widget, name, values: valuesFor(widget, settings, defaults) };
}
