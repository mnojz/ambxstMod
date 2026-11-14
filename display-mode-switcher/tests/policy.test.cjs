const {test} = require('node:test');
const assert = require('node:assert/strict');
const L = require('../payload/DisplayLogic.js');
const panel = () => ({name:'eDP-1',id:0,width:1920,height:1080,scale:1.5,x:0,y:0,mirrorOf:'none',availableModes:['1920x1080@60.32Hz']});
const ext = () => ({name:'HDMI-A-1',id:1,width:1920,height:1080,scale:1,x:1280,y:0,mirrorOf:'none',disabled:true});
function fixture(fail=false) {
 const state=[panel(),ext(),{...ext(),name:'DP-2',id:2,disabled:false}]; const calls=[];
 const io={query:async()=>structuredClone(state),delay:async()=>{},set:async s=>{calls.push(s); if(fail && s.disabled===false && s.output==='HDMI-A-1')return; const m=state.find(m=>m.name===s.output);Object.assign(m,s);if(s.mirror!==undefined)m.mirrorOf=s.mirror||'none';if(s.position)[m.x,m.y]=s.position.split('x').map(Number);}};
 return {state,calls,io,c:new L.Controller(io)};
}
test('disabled connected outputs remain discoverable',()=>assert.equal(L.external([panel(),ext()]).length,1));
test('numeric string mirror source',()=>assert.equal(L.mode([panel(),{...ext(),disabled:false,mirrorOf:'0'}],'HDMI-A-1'),1));
test('logical extend geometry',()=>assert.equal(L.mode([panel(),{...ext(),disabled:false}],'HDMI-A-1'),2));
test('destination enabled before other external disabled',async()=>{const f=fixture(); await f.c.apply(2,'HDMI-A-1');assert.equal(f.calls[1].output,'HDMI-A-1');assert.equal(f.calls[f.calls.length-1].output,'DP-2');assert.equal(f.state[1].x,1280);});
test('failed activation never disables laptop',async()=>{const f=fixture(true);await assert.rejects(f.c.apply(3,'HDMI-A-1'));assert.ok(!f.calls.some(s=>s.output==='eDP-1'&&s.disabled));});
test('disconnect aborts before disabling laptop',async()=>{const f=fixture();const set=f.io.set;f.io.set=async s=>{await set(s);if(s.output==='HDMI-A-1')f.state.splice(1,1);};await assert.rejects(f.c.apply(3,'HDMI-A-1'));assert.ok(!f.calls.some(s=>s.output==='eDP-1'&&s.disabled));});
test('stale callbacks cancelled',async()=>{const f=fixture();const q=f.io.query;f.io.query=async()=>{const o=await q();f.c.cancel();return o;};await assert.rejects(f.c.apply(3,'HDMI-A-1'));assert.equal(f.calls.length,0);});
test('mirror to extend clears mirror',async()=>{const f=fixture();f.state[1].disabled=false;f.state[1].mirrorOf='0';await f.c.apply(2,'HDMI-A-1');assert.equal(f.state[1].mirrorOf,'none');});
test('extend to mirror sets source',async()=>{const f=fixture();await f.c.apply(1,'HDMI-A-1');assert.equal(f.state[1].mirrorOf,'eDP-1');});
test('connector injection rejected',()=>assert.throws(()=>L.spec({name:'a";bad()'},{disabled:true})));
test('external-only success enables target before disabling panel',async()=>{const f=fixture();await f.c.apply(3,'HDMI-A-1');const en=f.calls.findIndex(s=>s.output==='HDMI-A-1'&&s.disabled===false);const off=f.calls.findIndex(s=>s.output==='eDP-1'&&s.disabled===true);assert.ok(en>=0&&off>en);});
test('recovery enables internal when no output usable',async()=>{const f=fixture();f.state.forEach(m=>m.disabled=true);await f.c.apply(0,'');assert.ok(L.enabled(f.state[0]));});
test('superseding request cancels in-flight request without destructive step',async()=>{const f=fixture();let resolve;f.io.query=()=>new Promise(r=>resolve=r);const old=f.c.apply(3,'HDMI-A-1');await assert.rejects(f.c.apply(0,''));const snapshot=structuredClone(f.state);resolve(snapshot);f.io.query=async()=>snapshot;await assert.rejects(old);assert.equal(f.calls.length,0);});
