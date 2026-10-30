const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const sourcePath = path.join(__dirname, "..", "payload", "modules", "services", "YtdHistory.js");
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "");
const context = {};
vm.runInNewContext(source, context, { filename: sourcePath });

const formats = ["mp3", "480p", "720p", "1080p", "1440p", "2160p"];
const normalize = (value, limit = 40) => context.normalize(value, formats, "1080p", limit);

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
