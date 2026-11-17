// Presentation only: the original output remains available in the raw view.
function cleanOutput(output) {
    return output
        .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
        .replace(/\x1b\][^\x07\x1b]*(?:\x1b)?$/g, "")
        // A retained log may start halfway through a sudo OSC session record.
        .replace(/[a-f0-9]{16,};user=[^\r\n\x07\x1b]*(?:\x07|\x1b\\|$)/gi, "")
        .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
        // Character-set selection, e.g. ncurses resetting to ASCII with ESC(B.
        .replace(/\x1b[ -/]+[0-~]/g, "")
        .replace(/\x1b[ -/]*$/g, "");
}

function parse(output, transaction) {
    transaction = transaction || {};
    const operation = transaction.operation;
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
    let buildLines = 0;
    let buildStatus = "Preparing build";
    const repositoryNames = {core: true, extra: true, multilib: true, "chaotic-aur": true};
    function add(kind, title, detail, key, measurement) {
        const row = Object.assign({kind: kind, title: title, detail: detail || "", group: group, count: 1, progress: -1, progressLabel: "", action: operation === "remove" ? "remove" : operation === "upgrade" ? "upgrade" : operation ? "install" : ""}, measurement || {});
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
    if (operation && !transaction.hideStart) {
        group = "";
        const title = operation === "remove" ? "Removing " + name : operation === "upgrade" ? "Synchronizing all packages" : operation === "bootstrap" ? "Installing " + (transaction.helper || "AUR helper") : "Installing " + name;
        add("start", title, "");
        group = "Preparing";
    }
    function completeDependencies(detail) {
        group = operation === "upgrade" ? "Upgrading" : "Installing";
        add("progress", "Dependencies", detail, "satisfied:" + batch, {progress: 1, progressLabel: "Already installed"});
    }
    function dependencyDownload() {
        const completed = Math.max(downloadCompleted, Object.keys(downloaded).length);
        const total = downloadTotal || planned;
        add("progress", operation === "upgrade" ? "Update packages" : "Dependencies", operation === "upgrade" ? "Downloading updates" : "Downloading", "download-total:" + batch, {
            progress: total ? Math.min(1, completed / total) : -1,
            progressLabel: total ? Math.min(completed, total) + "/" + total : completed ? completed + " downloaded" : ""
        });
    }
    function recordBuild(line) {
        buildLines++;
        if (/^\s*(?:cc|gcc|g\+\+|c\+\+|clang\+\+|clang|rustc|ccache|libtool|make(?:\[\d+\])?)(?:\s|:|$)|^\s*\[\s*\d+(?:%|\/\d+)/i.test(line))
            buildStatus = "Compiling sources";
        else if (/starting build|compiling|building /i.test(line)) buildStatus = "Compiling sources";
        else if (/retrieving sources|downloading|receiving objects|cloning into/i.test(line)) buildStatus = "Retrieving build sources";
        else if (/validating|verifying.*source/i.test(line)) buildStatus = "Verifying build sources";
        else if (/extracting|patching|starting prepare/i.test(line)) buildStatus = "Preparing build sources";
        else if (/creating package|compressing package|starting package|entering fakeroot/i.test(line)) buildStatus = "Packaging build";
        add("build", "Build", buildStatus, "build", {progress: -1, progressLabel: buildLines + " lines"});
        entries[positions["Building:build"]].count = buildLines;
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
            if (operation === "remove")
                add("note", "Dependency check complete", "");
            else
                completeDependencies("Dependencies are already satisfied");
            continue;
        }
        const skipped = clean.match(/^(?:warning:\s*)?(\S+)\s+is up to date\s*--\s*skipping[.!]?$/i);
        if (skipped && operation !== "remove") {
            group = operation === "upgrade" ? "Upgrading" : "Installing";
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
        // Transaction size summaries describe disk usage, not a transfer.
        if (/^(?:Total (?:Download|Installed|Removed) Size|Net Upgrade Size)\s*:/i.test(clean))
            continue;
        const plan = clean.match(/^(?:Packages|Remove)\s*\((\d+)\)/i);
        if (plan) {
            planned = Number(plan[1]);
            continue;
        }
        // Wrapped package-plan lines are terminal detail, not activity events.
        if (/^\s+/.test(raw) && /(?:^|\s)[a-zA-Z0-9@_+.:-]+-\d[^\s]*(?:\s|$)/.test(clean) && !/\b(?:KiB|MiB|GiB|installing|upgrading|removing)\b|%/.test(clean))
            continue;
        if (/starting (?:build|prepare|package)\(|making package|compiling|building |entering fakeroot|creating package|compressing package|(?:retrieving|validating|extracting) sources|patching/.test(lower) || /^(?:\[\s*\d+(?:%|\/\d+)|(?:cc|gcc|g\+\+|c\+\+|clang\+\+|clang|rustc|ccache|libtool|make\[\d+\])(?:\s|:|$))/.test(clean))
            group = "Building";
        else if (group !== "Building" && /retrieving packages|downloading|receiving objects|cloning into/.test(lower))
            group = "Downloading";
        else if (/running post-transaction/.test(lower) || group !== "Building" && /cleaning up|cleaning build|finalizing/.test(lower))
            group = "Finalizing";
        else if (/^processing package changes|^\(\d+\/\d+\)\s*(?:installing|upgrading|reinstalling|removing)\s+/.test(lower) || group !== "Building" && /^(?:installing|upgrading|reinstalling|removing)\s+/.test(lower))
            group = operation === "remove" || /\bremoving\s/.test(lower) ? "Removing" : operation === "upgrade" || /\bupgrading\s/.test(lower) ? "Upgrading" : "Installing";
        else if (group !== "Building" && /synchronizing package|resolving dependencies|looking for conflicting|starting full system upgrade|searching aur|querying aur|checking.*updates/.test(lower))
            group = "Preparing";

        if (group === "Building") {
            recordBuild(clean);
            continue;
        }

        const progress = clean.match(/^\((\d+)\/(\d+)\)\s*(installing|upgrading|reinstalling|removing)\s+(\S+)/i);
        if (progress) {
            const verb = progress[3].toLowerCase();
            const removing = verb === "removing";
            const upgrading = verb === "upgrading";
            group = removing ? "Removing" : operation === "upgrade" ? "Upgrading" : "Installing";
            const percent = clean.match(/(\d+(?:\.\d+)?)%/);
            const current = Number(progress[1]), total = Number(progress[2]);
            const completed = percent && Number(percent[1]) >= 100 ? current : Math.max(0, current - 1);
            const key = group + ":install-total:" + batch;
            const previous = positions[key] !== undefined ? entries[positions[key]] : null;
            const fraction = Math.max(previous ? previous.progress : 0, total ? completed / total : 0);
            add("progress", removing || upgrading || operation === "upgrade" ? "Packages" : "Dependencies", removing ? "Removing packages" : upgrading ? "Updating packages" : operation === "upgrade" ? "Installing new packages" : verb === "reinstalling" ? "Reinstalling" : "Installing", "install-total:" + batch, {
                action: removing ? "remove" : upgrading || operation === "upgrade" ? "upgrade" : "install",
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
        const transferLine = clean.match(/^(\S+)\s+\d+(?:\.\d+)?\s*(?:B|KiB|MiB|GiB)\b/);
        const transfer = transferLine && (percent >= 0 || /\b(?:B|KiB|MiB|GiB)\/s\b|\b\d{1,2}:\d{2}\b/.test(clean)) ? transferLine : null;
        const archiveLine = clean.match(/^(?:Downloading\s+)?['"]?([^\s'"]+?(?:\.pkg\.tar\.(?:zst|xz|gz)|\.tar\.(?:gz|xz|bz2|zst)))['"]?/i);
        const archive = archiveLine && (percent >= 0 || /^Downloading\s+/i.test(clean)) ? archiveLine : null;
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
        // A redraw without a package identity belongs in the status strip/raw view.
        if (/^(?:\d+(?:\.\d+)?%|\[.*\]\s*\d+%|remote: (?:Counting|Compressing|Enumerating)|Receiving objects:|Resolving deltas:)/i.test(clean))
            continue;
        const readable = clean.replace(/\s*\[[#=\->\s]+\]\s*\d+%.*$/, "").replace(/\.{3}$/, "");
        add(/^\s*[$+]\s/.test(text) ? "command" : "note", readable, "");
    }
    if (["done", "failed", "cancelled"].includes(transaction.state) && positions["Building:build"] !== undefined) {
        const build = entries[positions["Building:build"]];
        build.progress = transaction.state === "done" ? 1 : 0;
        build.progressLabel = transaction.state === "done" ? "Complete" : transaction.state === "cancelled" ? "Cancelled" : "Failed";
        build.detail = buildLines + " build output lines in Raw";
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
        add("done", operation === "remove" ? "Removed" : operation === "upgrade" ? "Updated" : "Installed", operation === "remove" ? name + " removed successfully." : operation === "upgrade" ? "All packages synchronized successfully." : operation === "bootstrap" ? "AUR helper installed successfully." : name + " installed successfully.");
    } else if (transaction.state === "failed" || transaction.state === "cancelled") {
        group = "";
        add(transaction.state === "failed" ? "error" : "note", transaction.state === "failed" ? operation === "remove" ? "Removal failed" : operation === "upgrade" ? "Update failed" : "Operation failed" : "Cancelled", transaction.message || "");
    }
    return entries;
}
