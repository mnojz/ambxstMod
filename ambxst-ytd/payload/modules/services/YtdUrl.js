.pragma library

// Only real YouTube and YouTube Music links are accepted. QML JS has no URL
// global, so the components are split with a regex instead of URL parsing.

var VIDEO_HOSTS = [
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be",
    "www.youtu.be"
];

var SHORT_HOSTS = [
    "youtu.be",
    "www.youtu.be"
];

var VIDEO_PATH_PREFIXES = ["/shorts/", "/embed/", "/live/", "/v/"];
var ID_PATTERN = /^[A-Za-z0-9_-]{6,}$/;
var URL_PATTERN = /^([a-zA-Z][a-zA-Z0-9+.\-]*):\/\/([^/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$/;
var MOD_PARAMS = ["format", "scope", "playlist"];

function decodeComponent(value) {
    try {
        return decodeURIComponent(String(value).replace(/\+/g, " "));
    } catch (error) {
        return String(value);
    }
}

function parseParams(query) {
    var params = ({});
    var raw = String(query || "").replace(/^\?/, "");
    if (raw === "")
        return params;

    var parts = raw.split("&");
    for (var i = 0; i < parts.length; i++) {
        if (parts[i] === "")
            continue;
        var separator = parts[i].indexOf("=");
        var key = decodeComponent(separator < 0 ? parts[i] : parts[i].slice(0, separator));
        var item = separator < 0 ? "" : decodeComponent(parts[i].slice(separator + 1));
        if (key !== "" && !(key in params))
            params[key] = item;
    }
    return params;
}

// Returns { valid, url, host, videoId, playlistId, hasVideo, hasPlaylist }.
function parse(value) {
    var text = String(value === undefined || value === null ? "" : value).trim();
    var result = {
        valid: false,
        url: text,
        host: "",
        path: "",
        videoId: "",
        playlistId: "",
        hasVideo: false,
        hasPlaylist: false
    };
    if (text === "")
        return result;

    var match = URL_PATTERN.exec(text);
    if (!match)
        return result;

    var scheme = match[1].toLowerCase();
    if (scheme !== "http" && scheme !== "https")
        return result;

    result.host = match[2].split("@").pop().split(":")[0].toLowerCase();
    if (VIDEO_HOSTS.indexOf(result.host) < 0)
        return result;

    result.path = match[3] || "";
    var params = parseParams(match[4]);
    result.playlistId = String(params.list || "");

    if (SHORT_HOSTS.indexOf(result.host) >= 0) {
        var shortId = result.path.replace(/^\/+/, "").split("/")[0];
        if (ID_PATTERN.test(shortId))
            result.videoId = shortId;
    } else if (result.path === "/watch") {
        var watchId = String(params.v || "");
        if (ID_PATTERN.test(watchId))
            result.videoId = watchId;
    } else {
        for (var i = 0; i < VIDEO_PATH_PREFIXES.length; i++) {
            var prefix = VIDEO_PATH_PREFIXES[i];
            if (result.path.indexOf(prefix) === 0) {
                var pathId = result.path.slice(prefix.length).split("/")[0];
                if (ID_PATTERN.test(pathId))
                    result.videoId = pathId;
                break;
            }
        }
    }

    result.hasVideo = result.videoId !== "";
    result.hasPlaylist = result.playlistId !== "";
    result.valid = result.hasVideo || result.hasPlaylist;
    return result;
}

function isValid(value) {
    return parse(value).valid;
}

function hasPlaylist(value) {
    return parse(value).hasPlaylist;
}

// Drops the given query keys while keeping the rest of the URL untouched.
function stripParams(value, keys) {
    var text = String(value === undefined || value === null ? "" : value).trim();
    var match = URL_PATTERN.exec(text);
    if (!match)
        return text;

    var query = String(match[4] || "").replace(/^\?/, "");
    var kept = [];
    if (query !== "") {
        var parts = query.split("&");
        for (var i = 0; i < parts.length; i++) {
            if (parts[i] === "")
                continue;
            var separator = parts[i].indexOf("=");
            var key = decodeComponent(separator < 0 ? parts[i] : parts[i].slice(0, separator));
            if (keys.indexOf(key) >= 0)
                continue;
            kept.push(parts[i]);
        }
    }
    return match[1] + "://" + match[2] + match[3]
        + (kept.length > 0 ? "?" + kept.join("&") : "") + String(match[5] || "");
}

function stripList(value) {
    return stripParams(value, ["list"]);
}

function stripModParams(value) {
    return stripParams(value, MOD_PARAMS);
}

// scope is "single" or "playlist". Single drops the list parameter so only the
// current video is downloaded; playlist keeps it so yt-dlp walks the playlist.
// A playlist-only link has no single video to fall back to, so it is reported
// instead of being rewritten into a link that names no media at all.
function resolve(value, scope) {
    var parsed = parse(value);
    var playlist = String(scope || "single") === "playlist";
    var resolved = {
        valid: parsed.valid,
        reason: parsed.valid ? "" : "invalid",
        hasVideo: parsed.hasVideo,
        hasPlaylist: parsed.hasPlaylist,
        scope: playlist ? "playlist" : "single",
        url: parsed.url
    };
    if (!resolved.valid)
        return resolved;

    if (!playlist && !parsed.hasVideo) {
        resolved.valid = false;
        resolved.reason = "playlist_required";
        return resolved;
    }

    resolved.url = stripModParams(parsed.url);
    if (!playlist && resolved.hasPlaylist)
        resolved.url = stripParams(resolved.url, ["list"]);
    return resolved;
}
