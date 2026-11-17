// Presentation only: the original output remains available in the raw view.
function cleanOutput(output) {
    return output
        .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
        .replace(/\x1b\][^\x07\x1b]*(?:\x1b)?$/g, "")
        // A retained log may start halfway through a sudo OSC session record.
        .replace(/[a-f0-9]{16,};user=[^\r\n\x07\x1b]*(?:\x07|\x1b\\|$)/gi, "")
        .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "");
}

function parse(output, transaction) {
    transaction = transaction || {};
    const entries = [];
    const positions = {};
    let group = "Preparing";
    let syncing = false;
    let planned = 0;
    let downloaded = {};
    const alreadyInstalled = {};
    let downloadTotal = 0;
    let downloadCompleted = 0;
    let batch = 0;
    const repositoryNames = {core: true, extra: true, multilib: true, "chaotic-aur": true};
    function add(kind, title, detail, key, measurement) {
        const row = Object.assign({kind: kind, title: title, detail: detail || "", group: group, count: 1, progress: -1, progressLabel: ""}, measurement || {});
        const identity = key ? group + ":" + key : "";
        if (identity && positions[identity] !== undefined) {
            entries[positions[identity]] = row;
            return;
        }
        const previous = entries[entries.length - 1];
        if (!key && previous && previous.group === group && previous.kind === kind && previous.title === title && previous.detail === row.detail) {
            previous.count++;
            return;
        }
        if (identity)
            positions[identity] = entries.length;
        entries.push(row);
    }
    const name = transaction.name || "package";
    const operation = transaction.operation;
    if (operation) {
        group = "";
        const title = operation === "remove" ? "Removing " + name : operation === "upgrade" ? "Synchronizing all packages" : operation === "bootstrap" ? "Installing " + (transaction.helper || "AUR helper") : "Installing " + name;
        add("start", title, "");
        group = "Preparing";
    }
    function completeDependencies(detail) {
        group = "Installing";
        add("progress", "Dependencies", detail, "satisfied:" + batch, {progress: 1, progressLabel: "Already installed"});
    }
    function dependencyDownload() {
        const completed = Math.max(downloadCompleted, Object.keys(downloaded).length);
        const total = downloadTotal || planned;
        add("progress", "Dependencies", "Downloading", "download-total:" + batch, {
            progress: total ? Math.min(1, completed / total) : -1,
            progressLabel: total ? Math.min(completed, total) + "/" + total : completed ? completed + " downloaded" : ""
        });
    }
    const lines = cleanOutput(output).split(/\r\n?|\n/);
    // Only database synchronization output can introduce repository names.
    let scanningRepositories = false;
    for (const raw of lines) {
        if (/synchronizing package databases/i.test(raw)) scanningRepositories = true;
        if (/retrieving packages|starting full system upgrade|resolving dependencies/i.test(raw)) scanningRepositories = false;
        const repo = raw.trim().match(/^(\S+)\s+(is up to date|.*?\b(?:KiB|MiB|GiB)\b.*\d+%)/i);
        if (repo && (scanningRepositories || /is up to date/i.test(repo[2])))
            repositoryNames[repo[1]] = true;
    }
    for (const raw of lines) {
        const text = raw.trim();
        if (!text || /^[\s#=\-─━░▒▓█\/\\|]+$/.test(text))
            continue;
        const clean = text.replace(/^(?:::|==>+|->)\s*/, "");
        const lower = clean.toLowerCase();
        if (/^(?:(?:all|runtime|build|make|check|package)\s+)*dependencies\s+(?:(?:are|already|have been)\s+)*(?:installed|satisfied|up.to.date)[.!]?$/i.test(clean)) {
            completeDependencies("Dependencies are already satisfied");
            continue;
        }
        const skipped = clean.match(/^(?:warning:\s*)?(\S+)\s+is up to date\s*--\s*skipping[.!]?$/i);
        if (skipped) {
            group = "Installing";
            alreadyInstalled[skipped[1]] = true;
            const count = Object.keys(alreadyInstalled).length;
            add("progress", "Dependencies", "Already installed", "already-installed", {progress: 1, progressLabel: count + "/" + count});
            continue;
        }
        // Keep diagnostics before filtering progress or compiler chatter.
        if (/^(?:error|fatal|exception|traceback)\b|\b(?:error|fatal):|\b(?:failed|failure|not found|could not)\b|no aur package found/i.test(clean)) {
            add("error", clean.replace(/^(?:error|fatal):\s*/i, ""), "");
            continue;
        }
        if (/\b(?:warning|warn):|\bdeprecated\b/i.test(clean)) {
            add("warning", clean.replace(/^(?:warning|warn):\s*/i, ""), "");
            continue;
        }
        // These are answered by --noconfirm; real interactive prompts stay in the main UI.
        if (/\[[YyNn]\/[YyNn]\]|^(?:y|n|yes|no)$/i.test(clean) || /^(?:Proceed with (?:installation|removal|download)|Do you want to (?:continue|proceed)|Continue building|Enter a selection|Packages to (?:cleanBuild|exclude)|Diffs to show)\b/i.test(clean))
            continue;
        // AUR helper build-file/diff selection menus are handled automatically.
        if (/^\d+\s+[^\s()]+(?:\s+\((?:Installed|Not Installed|Build Files Exist|Build Files Do Not Exist)\))+\s*$/i.test(clean) || /^\[(?:N|A|Ab)\](?:one|ll|ort)\b/i.test(clean) || /^\s*(?:\[I\]nstalled|\[No\]tInstalled|or\s+\(1 2 3,)/i.test(clean))
            continue;
        if (/synchronizing package databases/.test(lower))
            syncing = true;
        else if (/retrieving packages|processing package changes|starting full system upgrade|resolving dependencies|starting build|making package/.test(lower))
            syncing = false;
        if (/retrieving packages/.test(lower)) {
            batch++;
            downloaded = {};
            downloadTotal = downloadCompleted = 0;
        }
        if (repositoryNames[clean] || /^(?:core|extra|multilib)-(?:testing|staging)$/.test(clean))
            continue;
        const plan = clean.match(/^(?:Packages|Remove)\s*\((\d+)\)/i);
        if (plan) {
            planned = Number(plan[1]);
            continue;
        }
        // Wrapped package-plan lines are terminal detail, not activity events.
        if (/^\s+/.test(raw) && /(?:^|\s)[a-zA-Z0-9@_+.:-]+-\d[^\s]*(?:\s|$)/.test(clean) && !/\b(?:KiB|MiB|GiB|installing|upgrading|removing)\b|%/.test(clean))
            continue;
        if (/retrieving packages|downloading|retrieving sources|receiving objects|cloning into/.test(lower))
            group = "Downloading";
        else if (/starting build|making package|compiling|building |entering fakeroot|creating package|compressing package/.test(lower))
            group = "Building";
        else if (/running post-transaction|cleaning up|cleaning build|finalizing/.test(lower))
            group = "Finalizing";
        else if (/processing package changes|\b(?:installing|upgrading|reinstalling|removing)\s+/.test(lower))
            group = "Installing";
        else if (/synchronizing package|resolving dependencies|looking for conflicting|starting full system upgrade|searching aur|querying aur|checking.*updates/.test(lower))
            group = "Preparing";

        const progress = clean.match(/^\((\d+)\/(\d+)\)\s*(installing|upgrading|reinstalling|removing)\s+(\S+)/i);
        if (progress) {
            group = "Installing";
            const percent = clean.match(/(\d+(?:\.\d+)?)%/);
            const current = Number(progress[1]), total = Number(progress[2]);
            const completed = percent && Number(percent[1]) >= 100 ? current : Math.max(0, current - 1);
            const key = group + ":install-total:" + batch;
            const previous = positions[key] !== undefined ? entries[positions[key]] : null;
            const fraction = Math.max(previous ? previous.progress : 0, total ? completed / total : 0);
            add("progress", "Dependencies", progress[3].toLowerCase() === "removing" ? "Removing" : "Installing", "install-total:" + batch, {
                progress: Math.min(1, fraction),
                progressLabel: Math.round(fraction * total) + "/" + total
            });
            continue;
        }
        const total = clean.match(/^Total\s*\((\d+)\/(\d+)\)/i);
        if (total) {
            group = "Downloading";
            downloadTotal = Number(total[2]);
            downloadCompleted = Math.max(downloadCompleted, Number(total[1]));
            dependencyDownload();
            continue;
        }
        const percentages = clean.match(/\d+(?:\.\d+)?%/g);
        const percent = percentages ? Math.min(100, Number(percentages[percentages.length - 1].slice(0, -1))) : -1;
        const transfer = clean.match(/^(\S+)\s+.*\b(?:B|KiB|MiB|GiB)\b/);
        const archive = clean.match(/^(?:Downloading\s+)?['"]?([^\s'"]+?(?:\.pkg\.tar\.(?:zst|xz|gz)|\.tar\.(?:gz|xz|bz2|zst)))['"]?/i);
        if (transfer || archive) {
            const name = archive ? archive[1] : transfer[1];
            if (!archive && (syncing || repositoryNames[name] || /\.(?:db|files)$/.test(name))) {
                const key = "repository:" + name;
                const previous = positions[group + ":" + key] !== undefined ? entries[positions[group + ":" + key]] : null;
                const fraction = Math.max(previous ? previous.progress : -1, percent >= 0 ? percent / 100 : -1);
                add("progress", name.replace(/\.(?:db|files)$/, ""), "Synchronizing repository", key, {
                    progress: fraction,
                    progressLabel: fraction >= 0 ? Math.round(fraction * 100) + "%" : ""
                });
            } else {
                group = "Downloading";
                if (percent >= 100)
                    downloaded[name] = true;
                dependencyDownload();
            }
            continue;
        }
        if (syncing && repositoryNames[clean.split(/\s+/)[0]] && !/is up to date/i.test(clean))
            continue;
        // Bare file names and package-plan continuations are not useful events.
        if (group === "Downloading" && /^(?:\S+\.pkg\.tar\.(?:zst|xz|gz)|[a-zA-Z0-9@_+.:-]+-\d[^\s]*)$/.test(clean))
            continue;
        // Collapse repeated verification bars without carrying terminal artwork over.
        const check = clean.match(/^(?:\(\d+\/\d+\)\s*)?(checking .+?|loading package files)(?:\s*\[.*|\s+\d+%|$)/i);
        if (check) {
            add("note", check[1].replace(/\.{3}$/, ""), "", "check:" + check[1]);
            continue;
        }
        if (/\b(successfully|completed|finished|up.to.date|nothing to do)\b/i.test(clean)) {
            add("success", clean, "");
            continue;
        }
        if (group === "Building" && /^(?:\[\s*\d+(?:%|\/\d+)|(?:cc|gcc|g\+\+|c\+\+|clang\+\+|clang|rustc|ccache|libtool|make\[\d+\])(?:\s|:|$)|\s*(?:CC|CXX|LINK|AR)\s)/.test(clean)) {
            const key = group + ":compiler";
            const old = positions[key] !== undefined ? entries[positions[key]] : null;
            const count = old ? old.count + 1 : 1;
            add("build", "Compiling sources", count + " build output lines · available in Raw", "compiler");
            entries[positions[key]].count = count;
            continue;
        }
        // A redraw without a package identity belongs in the status strip/raw view.
        if (/^(?:\d+(?:\.\d+)?%|\[.*\]\s*\d+%|remote: (?:Counting|Compressing|Enumerating)|Receiving objects:|Resolving deltas:)/i.test(clean))
            continue;
        const readable = clean.replace(/\s*\[[#=\->\s]+\]\s*\d+%.*$/, "").replace(/\.{3}$/, "");
        add(/^\s*[$+]\s/.test(text) ? "command" : "note", readable, "");
    }
    if (transaction.state === "done") {
        // Confirmed success closes any terminal bars whose final redraw was omitted.
        for (const row of entries) {
            if (row.kind === "progress") {
                row.progress = 1;
                const ratio = row.progressLabel.match(/^\d+\/(\d+)$/);
                row.progressLabel = ratio ? ratio[1] + "/" + ratio[1] : row.progressLabel === "Already installed" ? row.progressLabel : "100%";
            }
        }
        group = "";
        add("done", "Done", operation === "remove" ? name + " removed successfully." : operation === "upgrade" ? "All packages synchronized successfully." : operation === "bootstrap" ? "AUR helper installed successfully." : name + " installed successfully.");
    } else if (transaction.state === "failed" || transaction.state === "cancelled") {
        group = "";
        add(transaction.state === "failed" ? "error" : "note", transaction.state === "failed" ? "Operation failed" : "Cancelled", transaction.message || "");
    }
    return entries;
}
