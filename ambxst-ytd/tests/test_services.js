const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function loadService(name) {
    const sourcePath = path.join(__dirname, "..", "payload", "modules", "services", name);
    const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "");
    const context = {};
    vm.runInNewContext(source, context, { filename: sourcePath });
    return context;
}

const history = loadService("YtdHistory.js");
const url = loadService("YtdUrl.js");
const formats = ["mp3", "480p", "720p", "1080p", "1440p", "2160p"];
const normalize = (value, limit = 40) => history.normalize(value, formats, "1080p", limit);

test("deduplicates newest entries and retains their first-seen metadata", () => {
    const result = normalize([
        { itemId: "new", title: "New", filename: "/tmp/new.mp4", format: "1080p" },
        { itemId: "old", title: "Old", format: "720p" },
        { itemId: "new", title: "Duplicate", filename: "/tmp/duplicate.mp4" },
        { itemId: "old", title: "Old duplicate" }
    ]);
    assert.equal(result.length, 2);
    assert.equal(result[0].itemId, "new");
    assert.equal(result[0].title, "New");
    assert.equal(result[1].itemId, "old");
});

test("caps entries and sanitizes stored values", () => {
    const input = [];
    for (let i = 0; i < 45; i++) {
        input.push({
            itemId: `item-${i}`,
            title: `Item ${i}`,
            format: i === 0 ? "invalid" : "mp3",
            finishedAt: i + 1
        });
    }
    input.push(null, { title: "Missing identity" });

    const result = normalize(input, 40);
    assert.equal(result.length, 40);
    assert.equal(result[0].itemId, "item-0");
    assert.equal(result[0].format, "1080p");
    assert.equal(result[1].format, "mp3");
    assert.equal(result[0].finishedAt, 1);
});

test("uses filename and URL as identity fallbacks", () => {
    const result = normalize([
        { filename: "/tmp/by-file.mp4", title: "File", format: "720p" },
        { url: "https://youtu.be/id", title: "URL", format: "2160p" }
    ]);
    assert.equal(result.length, 2);
    assert.equal(result[0].filename, "/tmp/by-file.mp4");
    assert.equal(result[1].url, "https://youtu.be/id");
});

test("accepts YouTube and YouTube Music video links", () => {
    for (const good of [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?v=dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?t=30",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "http://www.youtube.com/watch?v=dQw4w9WgXcQ"
    ]) {
        assert.equal(url.isValid(good), true, good);
    }
});

test("accepts playlist links", () => {
    assert.equal(url.isValid("https://www.youtube.com/playlist?list=PLabcdef"), true);
    assert.equal(url.hasPlaylist("https://www.youtube.com/playlist?list=PLabcdef"), true);
});

test("rejects anything that is not a YouTube video or playlist", () => {
    for (const bad of [
        "",
        "   ",
        "not a url",
        "https://example.invalid/video?format=1080p",
        "https://vimeo.com/12345",
        "https://soundcloud.com/track/1",
        "ftp://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/",
        "https://www.youtube.com/watch",
        "https://www.youtube.com/feed/subscriptions",
        "https://www.youtube.com/@SomeChannel",
        "youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ"
    ]) {
        assert.equal(url.isValid(bad), false, bad);
    }
});

test("single scope strips the list parameter", () => {
    const resolved = url.resolve(
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabcdef&t=30", "single"
    );
    assert.equal(resolved.valid, true);
    assert.equal(resolved.scope, "single");
    assert.equal(resolved.hasPlaylist, true);
    assert.equal(resolved.url, "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30");
});

test("playlist scope keeps the list parameter", () => {
    const resolved = url.resolve(
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabcdef", "playlist"
    );
    assert.equal(resolved.valid, true);
    assert.equal(resolved.scope, "playlist");
    assert.equal(resolved.url, "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabcdef");
});

test("mod-only parameters are always removed", () => {
    const resolved = url.resolve(
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=OLAK5&format=mp3&scope=playlist&playlist=1",
        "playlist"
    );
    assert.equal(resolved.url, "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=OLAK5");
});

test("playlist-only link needs the whole playlist option", () => {
    const single = url.resolve("https://www.youtube.com/playlist?list=PLabcdef", "single");
    assert.equal(single.valid, false);
    assert.equal(single.reason, "playlist_required");
    assert.equal(single.hasVideo, false);

    const whole = url.resolve("https://www.youtube.com/playlist?list=PLabcdef", "playlist");
    assert.equal(whole.valid, true);
    assert.equal(whole.url, "https://www.youtube.com/playlist?list=PLabcdef");
});

test("resolve reports invalid links without rewriting them", () => {
    const resolved = url.resolve("https://example.invalid/video", "single");
    assert.equal(resolved.valid, false);
    assert.equal(resolved.hasVideo, false);
    assert.equal(resolved.url, "https://example.invalid/video");
});

test("parse reports the video and playlist ids", () => {
    const parsed = url.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabcdef");
    assert.equal(parsed.videoId, "dQw4w9WgXcQ");
    assert.equal(parsed.playlistId, "PLabcdef");
    assert.equal(parsed.hasVideo, true);
    assert.equal(parsed.hasPlaylist, true);
});
