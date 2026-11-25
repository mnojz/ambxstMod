.pragma library
.import "LockscreenCustomization.js" as Customization

const version = 1;
const fields = {
    clock: ["clockStyle", "clockFont", "clockSize", "clockPosition", "clockFormat",
            "clockX", "clockY", "clockDate", "clockBold", "clockWeekday",
            "clockSeconds", "clockGreeting", "clockDateSize", "clockWeight",
            "clockLetterSpacing", "clockAmPm", "clockTimeRatio", "clockDateRatio", "clockShadow", "clockFrame"],
    media: ["mediaPosition", "mediaScale", "mediaX", "mediaY", "mediaStyle",
            "mediaArtwork", "mediaShadow", "mediaRadius", "mediaThumbnailRatio", "mediaThumbnailRadius", "mediaLayoutOptions", "mediaFrame"],
    login: ["loginPosition", "loginScale", "loginX", "loginY", "loginAvatar", "loginStyle", "loginShadow", "loginArrangement", "loginFrame"],
    visualizer: ["visualizerX", "visualizerY", "visualizerWidth", "visualizerHeight", "visualizerStyle",
                 "visualizerUseShellColors", "visualizerColor", "visualizerShadow"]
};

function valuesFor(widget, settings, defaults) {
    const values = {};
    const appearanceKey = widget + "PartStyles";
    const newKeys = [widget + "Appearance", widget + "Anchor", widget + "Frame", "mediaLayoutOptions", "loginArrangement", appearanceKey];
    for (const key of [...(fields[widget] ?? []), appearanceKey, widget + "Appearance", widget + "Anchor"]) {
        const value = widget === "clock" && key === appearanceKey
            ? Customization.clockPartStyles(settings[key], settings.clockStyle)
            : (settings[key] ?? (newKeys.includes(key) ? defaults[key] : undefined));
        if (typeof value === typeof defaults[key] && (typeof value !== "number" || Number.isFinite(value)))
            values[key] = value;
    }
    return values;
}

function create(widget, name, settings, defaults) {
    return { schemaVersion: version, widget, name, values: valuesFor(widget, settings, defaults) };
}
