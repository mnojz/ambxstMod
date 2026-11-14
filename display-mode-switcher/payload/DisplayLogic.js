// Pure policy and asynchronous transaction engine. Also loaded directly by Node tests.
function internal(outputs) { return outputs.find(m => /^(eDP|LVDS|DSI)[-0-9]/i.test(m.name)); }
function enabled(m) { return !!m && m.disabled !== true && m.width > 0 && m.height > 0; }
function external(outputs) { return outputs.filter(m => !/^(eDP|LVDS|DSI)[-0-9]/i.test(m.name)); }
function mirrored(m, source) { return !!m && !!source && (String(m.mirrorOf) === source.name || String(m.mirrorOf) === String(source.id)); }
function mode(outputs, target) {
    const i = internal(outputs), e = outputs.find(m => m.name === target);
    const others = external(outputs).filter(enabled);
    if (enabled(i) && !others.length) return 0;
    if (!enabled(i) && enabled(e) && others.length === 1) return 3;
    if (enabled(i) && enabled(e) && others.length === 1) {
        if (mirrored(e, i)) return 1;
        const w = ((i.transform || 0) % 2 ? i.height : i.width) / (i.scale || 1);
        if ((!e.mirrorOf || e.mirrorOf === 'none') && Math.abs(e.x - i.x - w) < 2 && e.y === i.y) return 2;
    }
    return -1;
}
function safeName(s) { if (!/^[A-Za-z0-9_.:-]+$/.test(s)) throw Error('Invalid connector'); return s; }
function spec(m, changes) {
    const s = {output: safeName(m.name)};
    // Partial monitor specs preserve unrelated rules in the installed Lua API.
    Object.assign(s, changes);
    if (changes.disabled === false && !enabled(m)) {
        const candidate = m.width > 0 && m.refreshRate > 0 ? `${m.width}x${m.height}@${m.refreshRate}` : (m.availableModes || [])[0];
        if (candidate && !/^\d+x\d+@[\d.]+(?:Hz)?$/.test(candidate)) throw Error('Invalid mode');
        s.mode = candidate ? candidate.replace(/Hz$/, '') : 'preferred';
        s.scale = m.scale > 0 ? m.scale : 1;
        s.transform = m.transform || 0;
    }
    return s;
}
function lua(s) {
    return 'hl.monitor({' + Object.keys(s).map(k => k + '=' + (typeof s[k] === 'string' ? JSON.stringify(s[k]) : String(s[k]))).join(',') + '})';
}
function Controller(io) {
    this.io = io; this.serial = 0; this.busy = false;
}
Controller.prototype.cancel = function() { ++this.serial; };
Controller.prototype.apply = function(choice, target) {
    this.cancel();
    if (this.busy) return Promise.reject(Error('Display change in progress; try again shortly'));
    const self = this, ticket = this.serial, io = this.io;
    this.busy = true;
    function fresh() { return io.query().then(o => {
        if (ticket !== self.serial) throw Error('Display request cancelled');
        return o;
    }); }
    function change(s, predicate) {
        function check(n) { return fresh().then(o => {
            if (predicate(o)) return o;
            if (!n) throw Error('Display did not reach requested state');
            return io.delay(150).then(() => check(n-1));
        }); }
        return fresh().then(() => io.set(s)).then(() => check(20));
    }
    let panelName, panelPosition;
    return fresh().then(o => {
        const i = internal(o); panelName = i && i.name; panelPosition = i ? `${i.x || 0}x${i.y || 0}` : '0x0';
        if (!i) throw Error('No internal panel identified');
        if (choice !== 0 && !external(o).some(m => m.name === target)) throw Error('Selected external display disconnected');
        return choice === 3 ? o : change(spec(i, {disabled:false, mirror:'', position:`${i.x || 0}x${i.y || 0}`}), a => enabled(internal(a)));
    }).then(o => {
        if (choice === 0) return o;
        const i = internal(o), e = o.find(m => m.name === target);
        if (!e) throw Error('Selected external display disconnected');
        const width = ((i.transform || 0) % 2 ? i.height : i.width) / (i.scale || 1);
        return change(spec(e, {disabled:false, mirror:choice === 1 ? i.name : '', position:choice === 2 ? `${Math.round(i.x + width)}x${i.y}` : `${e.x || 0}x${e.y || 0}`}), a => {
            const dest = a.find(m => m.name === target);
            return enabled(dest) && (choice === 1 ? mirrored(dest, internal(a)) : (!dest.mirrorOf || dest.mirrorOf === 'none'));
        });
    }).then(o => {
        if (choice !== 2) return o;
        return change({output:panelName,position:panelPosition}, a => {
            const i = internal(a); return i && `${i.x}x${i.y}` === panelPosition;
        }).then(a => {
            const i = internal(a);
            const width = ((i.transform || 0) % 2 ? i.height : i.width) / (i.scale || 1);
            return change({output:target,position:`${Math.round(i.x + width)}x${i.y}`}, b => mode(b.filter(m => !external(b).includes(m) || m.name === target), target) === 2);
        });
    }).then(o => {
        const victims = o.filter(m => (choice === 3 && m.name === panelName) || (external(o).includes(m) && (choice === 0 || m.name !== target)));
        return victims.reduce((chain, victim) => chain.then(() => fresh()).then(a => {
            const destination = choice === 0 ? internal(a) : a.find(m => m.name === target);
            if (!enabled(destination)) throw Error('Destination disconnected; keeping remaining displays');
            const live = a.find(m => m.name === victim.name);
            return enabled(live) ? change({output:safeName(live.name), disabled:true}, b => !enabled(b.find(m => m.name === live.name))) : a;
        }), Promise.resolve(o));
    }).then(() => fresh()).then(o => {
        if (mode(o, target) !== choice) throw Error('Resulting arrangement differs from request');
        return o;
    }).catch(error => io.query().then(o => {
        const i = internal(o);
        return i && !o.some(enabled) ? io.set(spec(i, {disabled:false, mirror:''})) : null;
    }).then(() => { throw error; })).then(o => { self.busy = false; return o; }, error => { self.busy = false; throw error; });
};
if (typeof module !== 'undefined') module.exports = {internal, external, enabled, mirrored, mode, spec, lua, Controller};
