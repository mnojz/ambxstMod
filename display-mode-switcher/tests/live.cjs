// Safe opt-in compositor smoke test: never requests external-only.
const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const exec = promisify(execFile);
const L = require('../payload/DisplayLogic.js');
const hypr = async (...args) => (await exec('/usr/bin/hyprctl', args)).stdout;
const delay = ms => new Promise(r => setTimeout(r,ms));
(async () => {
 const name='DM-SMOKE';
 try {
  await hypr('output','create','headless',name); await delay(1000);
  const io={query:async()=>JSON.parse(await hypr('monitors','all','-j')),set:s=>hypr('eval',L.lua(s)),delay};
  const c=new L.Controller(io);
  for(const choice of [2,1,2,0,2]) {
   await c.apply(choice,name);
   console.log('Verified mode',choice);
  }
 } finally { await hypr('output','remove',name); }
})().catch(e=>{console.error(e);process.exitCode=1;});
