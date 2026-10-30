const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const sourcePath = path.join(__dirname, "..", "payload", "modules", "services", "YtdUrl.js");
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "");
const context = {};
vm.runInNewContext(source, context, { filename: sourcePath });

const url = context;

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
