const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

const builtins = [
  ['tote', '黄色手提袋', [41,32,58,42], '#242025', .66, -.18],
  ['paperbag', '牛皮纸袋', [54,32,50,52], '#242025'],
  ['clock', '蓝色时钟', [40,36,60,36], '#242025'],
  ['screwdriver', '螺丝刀', [48,14,44,38], '#242025', .5, .12],
  ['house', '房子', [36,36,72,39], '#242025'],
  ['apple', '苹果', [34,33,70,41], '#f7efd1'],
  ['tomato', '番茄', [32,54,76,35], '#f7efd1'],
  ['bear', '小熊', [32,54,76,35], '#f7efd1'],
  ['dino', '小恐龙', [18,62,104,30], '#27472d'],
  ['monster', '小怪兽', [18,62,104,30], '#623f70']
].map(([id,name,rect,color,clipX=.5,tilt=0]) => ({id,name,rect,color,clipX,clipY:0,tilt:tilt*100,fontSize:13.5,align:'center',builtin:true,art:`cloth://builtin/${id}.png`}));

function normalizeStyle(input) {
  const bound = (v,lo,hi,fallback) => Math.min(hi,Math.max(lo,Number.isFinite(Number(v))?Number(v):fallback));
  let [x,y,w,h] = Array.isArray(input.rect) ? input.rect : [30,36,78,46];
  w=bound(w,17,140,78); h=bound(h,13,104,46); x=bound(x,0,140-w,30); y=bound(y,0,104-h,36);
  return {id: /^style-[\w-]+$/.test(input.id) ? input.id : `style-${randomUUID()}`,
    name:String(input.name || '我的便签').trim().slice(0,40) || '我的便签',
    art:input.art, rect:[x,y,w,h], clipX:bound(input.clipX,0,1,.5),clipY:bound(input.clipY,0,1,.06),
    tilt:bound(input.tilt,-30,30,0),fontSize:bound(input.fontSize,8.5,22,13.5),
    align:['left','center','right'].includes(input.align)?input.align:'center',
    color:/^#[0-9a-f]{6}$/i.test(input.color)?input.color:'#242025',archived:false};
}

class StateModel {
  constructor(folder) {
    this.folder=folder; this.file=path.join(folder,'state.json'); this.undoStack=[];
    fs.mkdirSync(folder,{recursive:true});
    const empty={items:[],pending:[],recent:[],styles:[],mode:'auto',watchFolder:''};
    try {
      const loaded=JSON.parse(fs.readFileSync(this.file,'utf8'));
      this.state={...empty,...loaded};
      for(const key of ['items','pending','recent','styles']) if(!Array.isArray(this.state[key])) this.state[key]=[];
      if(!['always','auto'].includes(this.state.mode)) this.state.mode='auto';
    } catch { this.state=empty; }
    this.pruneRecent();
  }
  persist() {
    const temporary=path.join(this.folder,`state-${randomUUID()}.tmp`);
    fs.writeFileSync(temporary,JSON.stringify(this.state),{flag:'wx'});
    fs.renameSync(temporary,this.file);
  }
  snapshot() { return structuredClone({items:this.state.items,pending:this.state.pending,recent:this.state.recent}); }
  change(action) {
    const previous=this.snapshot();
    try { const result=action(); this.pruneRecent(); this.persist(); this.undoStack.push(previous); this.undoStack=this.undoStack.slice(-30); return result; }
    catch(error) { Object.assign(this.state,previous); throw error; }
  }
  pruneRecent() { this.state.recent=this.state.recent.filter(r=>Date.now()-r.time<7*86400000).slice(0,20); }
  add(item,capacity) { this.change(()=> { (this.state.items.length<capacity ? this.state.items : this.state.pending).push({...item,pinned:false}); }); }
  find(id) { return [...this.state.items,...this.state.pending,...this.state.recent.map(r=>r.item)].find(i=>i.id===id); }
  stow(id) {
    this.change(()=> {
      let list=this.state.items; let index=list.findIndex(i=>i.id===id);
      if(index<0) {list=this.state.pending; index=list.findIndex(i=>i.id===id);}
      if(index<0) throw new Error('找不到这张便签。');
      const [item]=list.splice(index,1); this.state.recent.unshift({item,index,time:Date.now()});
    });
  }
  remove(id) { this.change(()=> { this.state.items=this.state.items.filter(i=>i.id!==id); this.state.pending=this.state.pending.filter(i=>i.id!==id); this.state.recent=this.state.recent.filter(r=>r.item.id!==id); }); }
  pin(id) { const item=this.find(id); if(!item) throw new Error('找不到这张便签。'); item.pinned=!item.pinned; try{this.persist();}catch(error){item.pinned=!item.pinned;throw error;} }
  replace(oldId,newId) {
    const oldIndex=this.state.items.findIndex(i=>i.id===oldId), nextIndex=this.state.pending.findIndex(i=>i.id===newId);
    if(oldIndex<0 || nextIndex<0) throw new Error('找不到待替换内容。');
    if(this.state.items[oldIndex].pinned) throw new Error('请先取消图钉锁定。');
    this.change(()=> { const old=this.state.items[oldIndex]; const [next]=this.state.pending.splice(nextIndex,1);
      this.state.items[oldIndex]=next; this.state.recent.unshift({item:old,index:oldIndex,time:Date.now()}); });
  }
  reorder(id,targetId) {
    if(id===targetId) return;
    this.change(()=> {const index=this.state.items.findIndex(i=>i.id===id); if(index<0) throw new Error('找不到这张便签。');
      const [item]=this.state.items.splice(index,1); const target=this.state.items.findIndex(i=>i.id===targetId);
      this.state.items.splice(target<0?this.state.items.length:target,0,item);});
  }
  restore(id,capacity) {
    const index=this.state.recent.findIndex(r=>r.item.id===id);
    if(index<0) throw new Error('找不到收起记录。');
    this.change(()=> {const [record]=this.state.recent.splice(index,1); if(this.state.items.length<capacity)
      this.state.items.splice(Math.min(record.index,this.state.items.length),0,record.item);
      else this.state.pending.push(record.item);});
  }
  hangPending(id,capacity) {
    if(this.state.items.length>=capacity) throw new Error('请先收起一张，或选择替换。');
    this.change(()=> { const index=this.state.pending.findIndex(i=>i.id===id);if(index<0) throw new Error('找不到待上绳内容。');
      this.state.items.push(this.state.pending.splice(index,1)[0]); });
  }
  undo() { const state=this.undoStack.at(-1);if(!state) return false; const before=this.snapshot();Object.assign(this.state,structuredClone(state));
    try{this.persist();this.undoStack.pop();return true;}catch(error){Object.assign(this.state,before);throw error;} }
  view() { return {...this.state,styles:[...builtins,...this.state.styles],canUndo:this.undoStack.length>0}; }
}
module.exports={StateModel,builtins,normalizeStyle};
