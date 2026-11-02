const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { HttpsError } = require('firebase-functions/v2/https');
function setup(overrides = {}) {
  const docs = { 'clinicStaff/staff': {active:true, role:'admin', clinicId:'a'},
    'clinicStaff/target': {active:true,status:'active',clinicId:'a'},
    'clinics/a': {status:'active',allowPatientInvite:true},
    'inneraPatients/p': {clinicId:'a'}, ...overrides };
  const writes=[];
  class Timestamp { constructor(ms){this.ms=ms;} toMillis(){return this.ms;} static fromMillis(ms){return new Timestamp(ms);} }
  docs['inneraInvites/CODE'] = {patientId:'p',clinicId:'a',status:'unused',expiresAt:new Timestamp(Date.now()+60000)};
  function ref(key){return {key,get:async()=>snap(key),update:async(data)=>{writes.push({key,data}); Object.assign(docs[key],data);}};}
  function snap(key){return {exists:!!docs[key],data:()=>docs[key]};}
  const db={collection:(name)=>({add:async data=>writes.push({collection:name,data}),doc:(id)=>({...ref(name+'/'+id),collection:(sub)=>({doc:(id2)=>ref(name+'/'+id+'/'+sub+'/'+id2)})})})};
  const tx={get:async(r)=>snap(r.key),update:(r,data)=>writes.push({key:r.key,data}),set:(r,data)=>writes.push({key:r.key,data}),create:(r,data)=>writes.push({key:r.key,data})};
  db.runTransaction=fn=>fn(tx);
  const admin={firestore:{Timestamp,FieldValue:{serverTimestamp:()=>0}},auth:()=>({updateUser:async(uid,data)=>writes.push({auth:uid,data}),createUser:async()=>({uid:'new'})})};
  function load(file){const exports={}; const module={exports};vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../src/clinic',file),'utf8'),{exports,module,Date,console,require(name){
    if(name==='firebase-functions/v2/https')return {HttpsError,onCall:(_,fn)=>fn};
    if(name==='../config/firebase')return {db,admin};
    if(name==='./authorization')return authorization;
    if(name==='./audit')return audit;
    return require(name);
  }});return module.exports;}
  const authorization=load('authorization.js');
  const audit=load('audit.js');
  return {...load('staff_invites.js'),...audit,...load('staff.js'),authorization,writes,docs};
}
const request={auth:{uid:'staff'},data:{patientId:'p',code:'CODE',staffUid:'target'}};
test('explicit disabled status wins while legacy staff remain supported',()=>{
 const {isStaffActive}=setup().authorization;
 for(const staff of [{active:false,status:'active'},{active:true,status:'inactive'},{active:true,status:'disabled'},{}])assert.equal(isStaffActive(staff),false);
 for(const staff of [{active:true},{status:'active'},{active:true,status:'active'}])assert.equal(isStaffActive(staff),true);
});
test('staff management rejects disabled staff or clinic before writes',async()=>{
 for(const overrides of [{'clinics/a':{status:'inactive'}},{'clinicStaff/staff':{active:false,status:'active',role:'admin',clinicId:'a'}}]){
  for(const name of ['createClinicStaff','disableClinicStaff','enableClinicStaff']){const app=setup(overrides);await assert.rejects(app[name](request),{code:'permission-denied'});assert.equal(app.writes.length,0);}
 }
});
test('disable closes Rules access before Auth disable; enable updates both states',async()=>{
 const app=setup();await app.disableClinicStaff(request);assert.equal(app.writes[0].data.active,false);assert.equal(app.writes[0].data.status,'inactive');assert.equal(app.writes[1].data.disabled,true);
 const start = app.writes.length;
 await app.enableClinicStaff(request);
 const updates = app.writes.slice(start).filter(write => write.auth || write.key === 'clinicStaff/target');
 assert.equal(updates.length, 2);
 assert.equal(updates[0].auth, 'target');
 assert.equal(updates[0].data.disabled, false);
 assert.equal(updates[1].data.active, true);
 assert.equal(updates[1].data.status, 'active');
});

test('an admin cannot disable a member of another clinic', async () => {
  const app = setup({'clinicStaff/target': {active: true, role: 'doctor', clinicId: 'b'}});
  await assert.rejects(app.disableClinicStaff(request), {code: 'permission-denied'});
  assert.equal(app.writes.length, 0);
});

test('staff invite acceptance requires verified email and audit listing requires login', async () => {
  const app = setup();
  await assert.rejects(app.acceptStaffInvite({}), {code: 'unauthenticated'});
  await assert.rejects(app.acceptStaffInvite({auth: {uid: 'staff', token: {}}}), {code: 'failed-precondition'});
  await assert.rejects(app.listClinicAuditLogs({}), {code: 'unauthenticated'});
  assert.equal(app.writes.length, 0);
});
