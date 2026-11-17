const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const parser = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../overlays/modules/widgets/parcel/ActivityParser.js'), 'utf8'), parser);

let rows = parser.parse('Packages (20) foo-1.0 bar-2.0\n:: Retrieving packages...\rTotal (1/20) 5%\rTotal (2/20) 10%\rfoo-1.0.pkg.tar.zst 45%\rfoo-1.0.pkg.tar.zst 100%\n');
assert.equal(rows.filter(row => row.kind === 'progress').length, 1);
assert.equal(rows.find(row => row.kind === 'progress').progressLabel, '2/20');
assert.equal(rows.find(row => row.kind === 'progress').progress, 0.1);
assert.equal(rows.filter(row => row.kind === 'package').length, 0);
assert.ok(!rows.some(row => /foo|bar/.test(row.title)));
assert.ok(rows.every(row => row.group === 'Downloading'));

rows = parser.parse('==> Starting build()...\n[1/3] Building CXX object example.o\n[2/3] Building CXX object error.o\nwarning: deprecated option\ngcc -c main.c\nmain.c:3: error: missing symbol <x> & y\n-> No AUR package found for openssl-3 (required by: python312)\n');
assert.equal(rows.filter(row => row.kind === 'build').length, 1);
assert.equal(rows.find(row => row.kind === 'build').count, 3);
assert.equal(rows.filter(row => row.kind === 'warning').length, 1);
assert.equal(rows.filter(row => row.kind === 'error').length, 2);
assert.ok(rows.find(row => row.kind === 'error').title.includes('<x> & y'));
assert.equal(rows.find(row => row.kind === 'build').group, 'Building');

rows = parser.parse(':: Processing package changes...\n(1/2) installing foo [####] 50%\r(1/2) installing foo [####] 100%\n(2/2) upgrading bar [####] 100%\n:: Running post-transaction hooks...\n(1/1) Updating icon cache...\n');
assert.equal(rows.filter(row => row.kind === 'progress').length, 1);
assert.equal(rows.find(row => row.kind === 'progress').progressLabel, '2/2');
assert.equal(rows.find(row => row.kind === 'progress').progress, 1);
assert.ok(!rows.some(row => /foo|bar/.test(row.title)));
assert.equal(rows.at(-1).group, 'Finalizing');
assert.ok(!rows.some(row => row.title.includes('[####]')));

rows = parser.parse('\u001b[31merror: failed to fetch package\u001b[0m\nwarning: optional dependency unavailable\nwarning: optional dependency unavailable\nUnrecognized output is still kept\n');
assert.equal(rows[0].kind, 'error');
assert.equal(rows[1].count, 2);
assert.equal(rows[2].title, 'Unrecognized output is still kept');
assert.equal(parser.parse('').length, 0);
// Real sudo metadata, including a log buffer that starts inside its payload.
const payload = 'ed94bd68c8f3414111c5c75;user=manoj;hostname=archlinux;machineid=abc;bootid=def;pid=323140;pidfdid=340751;comm=sudo;targetuser=root;type=session';
for (const metadata of ['\x1b]3008;start=' + payload + '\x1b\\', payload + '\x1b\\']) {
    rows = parser.parse(metadata + ':: Synchronizing package databases\n');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].title, 'Synchronizing package databases');
}
assert.equal(parser.cleanOutput('\x1b]3008;start=' + payload), '');

rows = parser.parse(':: Synchronizing package databases\ncore\nextra\nmultilib\nchaotic-aur\ncore is up to date\nextra is up to date\rchaotic-aur 15.5 KiB 19.7 KiB/s 00:33 [-Co  o  o] 2%.\rchaotic-aur 30.0 KiB 20.0 KiB/s 00:20 [-Co o] 40%\n');
assert.equal(rows.filter(row => row.kind === 'success').length, 2);
let bar = rows.find(row => row.title === 'chaotic-aur');
assert.equal(rows.filter(row => row.title === 'chaotic-aur').length, 1);
assert.equal(bar.progressLabel, '40%');
assert.equal(bar.progress, 0.4);
assert.equal(bar.kind, 'progress');
assert.ok(!rows.some(row => /KiB|Co |user=|^core$|^extra$|^multilib$/.test(row.title)));

// Custom repository names and byte units; package bars without archive suffixes.
rows = parser.parse(':: Synchronizing package databases\nmyrepo\rmyrepo 100 B 1 KiB/s 00:00 [###] 100%\nPackages (300) a-1 b-1\n    dependency-1.0 other-2.0\n:: Retrieving packages...\rdependency-1.0 100 KiB 10 KiB/s 00:02 [###] 100%\rTotal (230/300) 10%\rTotal (229/300) 9%\n');
bar = rows.find(row => row.title === 'Dependencies');
assert.equal(bar.progressLabel, '230/300');
assert.equal(bar.progress, 230 / 300);
assert.equal(rows.filter(row => row.title === 'Dependencies').length, 1);
assert.equal(rows.filter(row => row.title === 'myrepo').length, 1);
assert.ok(!rows.some(row => /dependency-1|other-2/.test(row.title)));

// Without an aggregate counter, count completed files, never their fast percentages.
rows = parser.parse('Packages (3) a-1 b-1 c-1\n:: Retrieving packages...\ra-1.pkg.tar.zst 100%\rb-1.pkg.tar.zst 20%\rb-1.pkg.tar.zst 100%\ra-1.pkg.tar.zst 100%\n');
bar = rows.find(row => row.title === 'Dependencies');
assert.equal(bar.progressLabel, '2/3');
assert.equal(bar.progress, 2/3);
// Routine auto-answered prompts are not activity; real warnings/errors survive.
rows = parser.parse(':: Proceed with installation? [Y/n]\ny\nDo you want to continue? [y/N]\nyes\nwarning: unexpected dependency conflict\nerror: could not proceed\n');
assert.equal(rows.length, 2);
assert.equal(rows[0].kind, 'warning');
assert.equal(rows[1].kind, 'error');

rows = parser.parse('==> All dependencies are already installed.\n');
assert.equal(rows[0].title, 'Dependencies');
assert.equal(rows[0].progress, 1);
assert.equal(rows[0].progressLabel, 'Already installed');
rows = parser.parse('warning: foo-1.0 is up to date -- skipping\nwarning: bar-2.0 is up to date -- skipping\n');
assert.equal(rows.length, 1);
assert.equal(rows[0].progress, 1);
assert.equal(rows[0].progressLabel, '2/2');
assert.ok(!rows[0].detail.includes('foo'));

const operation = {operation:'install',name:'firefox',state:'running'};
rows = parser.parse('Total (2/5) 40%\n', operation);
assert.equal(rows[0].kind, 'start');
assert.equal(rows[0].title, 'Installing firefox');
assert.ok(!rows.some(row=>row.kind==='done'));
rows = parser.parse('Total (2/5) 40%\n', {...operation,state:'done'});
assert.equal(rows.at(-1).kind,'done');
assert.equal(rows.at(-1).title,'Done');
assert.equal(rows.find(row=>row.kind==='progress').progress,1);
assert.equal(rows.find(row=>row.kind==='progress').progressLabel,'5/5');
for (const state of ['failed','cancelled']) {
    rows = parser.parse('Total (2/5) 40%\n', {...operation,state,message:'Stopped'});
    assert.ok(!rows.some(row=>row.kind==='done'));
    assert.equal(rows.find(row=>row.kind==='progress').progress,0.4);
    assert.equal(rows.at(-1).detail,'Stopped');
}
rows = parser.parse('', {operation:'remove',name:'firefox',state:'done'});
assert.equal(rows[0].title,'Removing firefox');
assert.equal(rows.at(-1).detail,'firefox removed successfully.');
rows = parser.parse('1 audacity4-bin (Installed) (Build Files Exist)\n2 example-bin (Build Files Exist)\n[N]one [A]ll [Ab]ort [I]nstalled [No]tInstalled or (1 2 3, 1-3, ^4)\n[I]nstalled [No]tInstalled\nwarning: build files unavailable\nerror: failed to build audacity4-bin\n');
assert.equal(rows.length, 2);
assert.equal(rows[0].kind, 'warning');
assert.equal(rows[1].kind, 'error');
assert.equal(parser.parse('', {operation:'install',name:'firefox',state:'running',hideStart:true}).length,0);
rows = parser.parse('', {operation:'install',name:'firefox',state:'done',hideStart:true});
assert.equal(rows.length,1);
assert.equal(rows[0].kind,'done');
assert.equal(rows[0].detail,'firefox installed successfully.');
console.log('Activity parser checks passed');
