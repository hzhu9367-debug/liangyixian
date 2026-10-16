import {createElement,Camera,Pin,PinOff,Layers,Copy,Archive,Trash2,Undo2,Palette,FileOutput,Check,X,ArrowUp,Upload} from 'lucide';

const api=window.clothesline,role=new URLSearchParams(location.search).get('role')||'line';
const app=document.querySelector('#app');
document.body.className=role;
let state={items:[],pending:[],recent:[],styles:[],mode:'auto'},editId,selectedStyle,queueTab='pending',toastTimer;
const images=new Map();
const paintings=new WeakMap();
const element=(tag,props={},children=[])=>{const el=document.createElement(tag);Object.assign(el,props);for(const child of children)el.append(child);return el;};
const iconButton=(icon,title,handler,extra='')=>{const b=element('button',{className:`icon ${extra}`,title,ariaLabel:title});b.append(createElement(icon));b.onclick=handler;return b;};
const button=(text,handler,icon,cls='')=>{const b=element('button',{textContent:text,className:cls});if(icon)b.prepend(createElement(icon));b.onclick=handler;return b;};
async function call(action,payload={}){const result=await api.invoke(action,payload);if(result?.ok===false){toast(result.error);return false;}return result;}
function toast(text){if(text.startsWith('edit:')){editId=text.slice(5);fillNote();return;}const box=document.querySelector('#toast');box.replaceChildren(element('span',{textContent:text}));if(text.includes('可撤销'))box.append(button('撤销',()=>call('undo'),Undo2));box.hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>box.hidden=true,10000);}
function getImage(src){if(!images.has(src))images.set(src,new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>resolve(image);image.onerror=()=>reject(Error('图片读取失败'));image.src=src;}));return images.get(src);}
function fitImage(ctx,image){const s=Math.min(140/image.width,104/image.height),w=image.width*s,h=image.height*s;ctx.drawImage(image,(140-w)/2,(104-h)/2,w,h);}
function wrapped(ctx,text,width){const lines=[];for(const paragraph of text.split('\n')){let row='';for(const char of paragraph){if(row&&ctx.measureText(row+char).width>width){lines.push(row);row=char;}else row+=char;}lines.push(row);}return lines;}
async function paint(canvas,item,override){const token=Symbol();paintings.set(canvas,token);canvas.width=560;canvas.height=416;const ctx=canvas.getContext('2d');ctx.scale(4,4);const style=override||state.styles.find(s=>s.id===item.style)||state.styles[0];
  try{const image=await getImage(item.type==='image'?`cloth://asset/${item.file}`:style.art);if(paintings.get(canvas)!==token)return;if(item.type==='image'){ctx.fillStyle='#fff';ctx.fillRect(1,1,138,102);ctx.save();ctx.beginPath();ctx.rect(4,4,132,96);ctx.clip();fitImage(ctx,image);ctx.restore();return;}
    fitImage(ctx,image);const [x,y,w,h]=style.rect;let font=style.fontSize,lines;for(;font>=7; font-=.5){ctx.font=`500 ${font}px "Segoe UI", "PingFang SC", sans-serif`;lines=wrapped(ctx,item.text||'',w);if(lines.length*font*1.25<=h)break;}
    ctx.save();ctx.beginPath();ctx.rect(x,y,w,h);ctx.clip();ctx.fillStyle=style.color;ctx.textBaseline='top';ctx.textAlign=style.align;const count=Math.max(1,Math.floor(h/(font*1.25)));if(lines.length>count){lines=lines.slice(0,count);let last=lines.at(-1);while(last&&ctx.measureText(last+'…').width>w)last=last.slice(0,-1);lines[count-1]=last+'…';}
    lines.forEach((text,i)=>ctx.fillText(text,style.align==='left'?x:style.align==='right'?x+w:x+w/2,y+Math.max(0,(h-lines.length*font*1.25)/2)+i*font*1.25));ctx.restore();
  }catch(error){if(paintings.get(canvas)!==token)return;ctx.fillStyle='#777';ctx.font='12px sans-serif';ctx.fillText(error.message,20,45);}
}
function noteCanvas(item,style){const canvas=element('canvas');paint(canvas,item,style);return canvas;}
function tools(){app.replaceChildren();const strip=element('div',{className:'toolstrip'});
  strip.append(iconButton(state.mode==='always'?Pin:PinOff,state.mode==='always'?'始终显示 · 选择模式':'顶部悬停显示 · 选择模式',()=>call('mode-menu')),
    iconButton(Camera,'截取屏幕区域',()=>call('capture')));
  const queue=iconButton(Layers,'待上绳与最近收起',()=>call('queue'),'queued');if(state.pending.length)queue.append(element('span',{className:'badge',textContent:state.pending.length}));strip.append(queue);
  const hammer=element('button',{className:'hammer',title:'新建文字便签',ariaLabel:'新建文字便签'});hammer.append(element('img',{src:'cloth://builtin/hammer.png',alt:''}));hammer.onclick=()=>call('note');app.append(strip,hammer);
}
function renderLine(){app.replaceChildren(element('div',{id:'rope'}));const rack=element('div',{id:'rack'});app.append(rack);
  for(const [index,item]of state.items.entries()){const style=state.styles.find(s=>s.id===item.style);const peg=element('div',{className:`peg${item.pinned?' pinned':''}`,draggable:true,title:item.type==='note'?item.text:'截图',tabIndex:0});
    peg.style.setProperty('--cx',`${(style?.clipX??.5)*100}%`);peg.style.setProperty('--tilt',`${style?.tilt??0}deg`);peg.style.setProperty('--delay',`${-index*.6}s`);const canvas=noteCanvas(item);canvas.style.transform=`translateY(-${(style?.clipY??0)*100}%)`;peg.append(canvas);
    const actions=element('div',{className:'actions'});actions.append(iconButton(Copy,'复制',()=>call('copy',{id:item.id})),iconButton(item.pinned?PinOff:Pin,item.pinned?'取消锁定':'图钉锁定',()=>call('pin',{id:item.id})),iconButton(Archive,'收起，保留文件',()=>call('stow',{id:item.id})),iconButton(Trash2,'移入回收站',()=>call('trash',{id:item.id}),'danger'));if(item.type==='image'){const drag=iconButton(FileOutput,'拖出图片',()=>{});drag.onmousedown=e=>{e.preventDefault();api.drag(item.id);};actions.append(drag);}peg.append(actions);
    peg.ondblclick=()=>item.type==='note'?call('note',{id:item.id}):call('copy',{id:item.id});
    peg.ondragstart=e=>{if(e.target.closest('button')){e.preventDefault();return;}e.dataTransfer.setData('application/x-clothesline',item.id);if(item.type==='note'){e.dataTransfer.setData('text/plain',item.text);e.dataTransfer.effectAllowed='copyMove';}else if(e.altKey){e.preventDefault();api.drag(item.id);}else e.dataTransfer.effectAllowed='copyMove';};
    peg.ondragover=e=>{e.preventDefault();e.stopPropagation();};peg.ondrop=e=>{e.preventDefault();e.stopPropagation();const id=e.dataTransfer.getData('application/x-clothesline');if(id)call('reorder',{id,target:item.id});else dropImages(e);};rack.append(peg);
  }
  rack.ondragover=e=>e.preventDefault();rack.ondrop=dropImages;
}
function dropImages(e){e.preventDefault();const paths=api.paths(e.dataTransfer.files);if(paths.length)call('drop-images',{paths});}
function header(title,extras=[]){return element('header',{},[element('h1',{textContent:title}),element('div',{className:'tabs'},extras)]);}
function activeStyles(){return state.styles.filter(s=>!s.archived);}
function note(){app.replaceChildren(header('文字便签',[iconButton(Palette,'便签工坊',()=>call('workshop'))]));const section=element('section',{className:'editor'});const picker=element('div',{className:'shape-picker',id:'picker'});const text=element('textarea',{id:'note-text',placeholder:'便签文字',ariaLabel:'便签文字',maxLength:20000});text.addEventListener('input',updateNotePreview);
  const preview=element('canvas',{id:'note-preview',className:'note-preview'});section.append(picker,text,preview,element('footer',{},[button('取消',()=>call('close'),X),button('挂上晾衣杆',()=>call('save-note',{id:editId,text:text.value,style:selectedStyle}),Check,'primary')]));app.append(section);fillNote();text.focus();
}
function fillNote(){const text=document.querySelector('#note-text');if(!text)return;const item=state.items.concat(state.pending,state.recent.map(r=>r.item)).find(i=>i.id===editId);if(item){text.value=item.text;selectedStyle=item.style;}selectedStyle ||=activeStyles()[0]?.id;const picker=document.querySelector('#picker');picker.replaceChildren();for(const style of activeStyles()){const b=button('',()=>{selectedStyle=style.id;for(const child of picker.children)child.classList.toggle('selected',child.dataset.id===selectedStyle);updateNotePreview();});b.dataset.id=style.id;b.title=style.name;b.classList.toggle('selected',selectedStyle===style.id);b.append(element('img',{src:style.art,alt:style.name}));picker.append(b);}updateNotePreview();}
function updateNotePreview(){const canvas=document.querySelector('#note-preview');if(canvas)paint(canvas,{type:'note',style:selectedStyle,text:document.querySelector('#note-text').value});}
let workshopStyle;
function workshop(){workshopStyle={name:'我的便签',rect:[30,36,78,46],clipX:.5,clipY:.04,tilt:0,fontSize:13.5,color:'#242025',align:'center'};
  app.replaceChildren(header('便签工坊',[button('上传底图',async()=>{const art=await call('artwork');if(typeof art==='string'){workshopStyle.art=art;drawWorkshop();}},Upload)]));
  const left=element('div'),preview=element('div',{className:'workshop-preview',id:'workshop-preview'}),canvas=element('canvas',{id:'workshop-canvas'}),region=element('div',{className:'text-region',id:'text-region'}),handle=element('span',{className:'resize-handle'}),clip=element('div',{className:'clip-point',id:'clip-point'});region.append(handle);preview.append(canvas,region,clip);left.append(preview);
  const fields=element('div');for(const [key,label,type]of [['name','名称','text'],['color','文字颜色','color'],['fontSize','字号','number'],['tilt','悬挂角度','range'],['clipX','夹子横向位置','range'],['clipY','夹子纵向位置','range']]){
    const input=element('input',{id:`style-${key}`,type,value:workshopStyle[key]});if(key==='tilt'){input.min=-30;input.max=30;input.step=1;}if(key.startsWith('clip')){input.min=0;input.max=1;input.step=.01;}if(key==='fontSize'){input.min=8.5;input.max=22;input.step=.5;}input.oninput=()=>{workshopStyle[key]=type==='text'||type==='color'?input.value:Number(input.value);drawWorkshop();};fields.append(element('label',{},[element('span',{textContent:label}),input]));}
  const align=element('select',{id:'style-align'},['left','center','right'].map((v,i)=>element('option',{value:v,textContent:['左对齐','居中','右对齐'][i],selected:v==='center'})));align.onchange=()=>{workshopStyle.align=align.value;drawWorkshop();};fields.append(element('label',{},[element('span',{textContent:'对齐'}),align]));
  const sample=element('textarea',{id:'sample',value:'今天也要\n好好生活',ariaLabel:'预览文字'});sample.oninput=drawWorkshop;fields.append(sample,element('footer',{},[button('保存样式',async()=>{const id=await call('save-style',workshopStyle);if(typeof id==='string'){workshopStyle.id=id;toast('样式已保存');}},Check,'primary')]));
  const list=element('div',{className:'workshop-list',id:'style-list'});left.append(list);app.append(element('div',{className:'workshop-grid'},[left,fields]));
  region.onpointerdown=e=>{e.preventDefault();e.stopPropagation();region.setPointerCapture(e.pointerId);const start={x:e.clientX,y:e.clientY,rect:[...workshopStyle.rect]},resizing=e.target===handle;region.onpointermove=event=>{const box=preview.getBoundingClientRect(),dx=(event.clientX-start.x)*140/box.width,dy=(event.clientY-start.y)*104/box.height;let[x,y,w,h]=start.rect;if(resizing){w=Math.min(140-x,Math.max(17,w+dx));h=Math.min(104-y,Math.max(13,h+dy));}else{x=Math.max(0,Math.min(140-w,x+dx));y=Math.max(0,Math.min(104-h,y+dy));}workshopStyle.rect=[x,y,w,h];drawWorkshop();};region.onpointerup=()=>region.onpointermove=null;};
  preview.onclick=e=>{if(e.target===canvas){const box=preview.getBoundingClientRect();workshopStyle.clipX=(e.clientX-box.left)/box.width;workshopStyle.clipY=(e.clientY-box.top)/box.height;syncFields();drawWorkshop();}};drawWorkshop();refreshStyleList();
}
function syncFields(){for(const key of ['name','color','fontSize','tilt','clipX','clipY','align']){const field=document.querySelector(`#style-${key}`);if(field)field.value=workshopStyle[key];}}
function drawWorkshop(){const region=document.querySelector('#text-region');if(!region)return;const[x,y,w,h]=workshopStyle.rect;Object.assign(region.style,{left:`${x/140*100}%`,top:`${y/104*100}%`,width:`${w/140*100}%`,height:`${h/104*100}%`});const clip=document.querySelector('#clip-point');clip.style.left=`${workshopStyle.clipX*100}%`;clip.style.top=`${workshopStyle.clipY*100}%`;const canvas=document.querySelector('#workshop-canvas');if(workshopStyle.art)paint(canvas,{type:'note',text:document.querySelector('#sample').value},structuredClone(workshopStyle));else{canvas.width=560;canvas.height=416;}}
function refreshStyleList(){const list=document.querySelector('#style-list');if(!list)return;list.replaceChildren();for(const style of state.styles.filter(s=>!s.builtin&&!s.archived)){list.append(button(style.name,()=>{workshopStyle=structuredClone(style);syncFields();drawWorkshop();}),iconButton(Archive,`移除样式：${style.name}`,()=>{if(confirm(`移除“${style.name}”？已有便签会保留外形。`))call('archive-style',{id:style.id});}));}}
function queue(){app.replaceChildren(header('待上绳与最近收起',['pending','recent'].map((tab,i)=>button(`${['待上绳','最近收起'][i]} ${state[tab].length}`,()=>{queueTab=tab;queue();},null,queueTab===tab?'active':''))));
  const list=element('div',{className:'queue-list'}),entries=state[queueTab];if(!entries.length)list.append(element('div',{className:'empty',textContent:queueTab==='pending'?'没有待上绳内容':'没有最近收起记录'}));
  for(const entry of entries){const item=entry.item||entry,row=element('div',{className:'queue-row'});row.append(noteCanvas(item),element('div',{className:'description',textContent:item.type==='note'?item.text:'截图',title:item.text||''}));
    if(queueTab==='recent')row.append(button('重新挂上',()=>call('restore',{id:item.id}),ArrowUp));
    else if(state.items.length<state.capacity)row.append(button('挂上',()=>call('hang-pending',{id:item.id}),ArrowUp));
    else{const candidates=state.items.filter(i=>!i.pinned),select=element('select',{ariaLabel:'选择要收起的内容'},[element('option',{value:'',textContent:'选择收起项'}),...candidates.map((old,i)=>element('option',{value:old.id,textContent:old.type==='note'?old.text.slice(0,12):`截图 ${i+1}`}))]);row.append(select,button('替换',()=>{if(select.value)call('replace',{id:select.value,next:item.id});else toast(candidates.length?'先选择一张旧内容':'当前全部已锁定');}));}
    list.append(row);
  }app.append(list);
}
function capture(){app.replaceChildren(element('img',{id:'capture-image',alt:''}),element('div',{id:'selection',hidden:true}));let origin;
  app.onpointerdown=e=>{origin={x:e.clientX,y:e.clientY};app.setPointerCapture(e.pointerId);document.querySelector('#selection').hidden=false;};
  app.onpointermove=e=>{if(!origin)return;Object.assign(document.querySelector('#selection').style,{left:`${Math.min(origin.x,e.clientX)}px`,top:`${Math.min(origin.y,e.clientY)}px`,width:`${Math.abs(origin.x-e.clientX)}px`,height:`${Math.abs(origin.y-e.clientY)}px`});};
  app.onpointerup=e=>{if(!origin)return;const rect={x:Math.min(origin.x,e.clientX),y:Math.min(origin.y,e.clientY),width:Math.abs(origin.x-e.clientX),height:Math.abs(origin.y-e.clientY)};origin=null;if(rect.width<3||rect.height<3){document.querySelector('#selection').hidden=true;return;}call('shot',{rect});};
}
function receive(next){state=next;if(role==='line')renderLine();else if(role==='tools')tools();else if(role==='queue')queue();else if(role==='note'){if(!document.querySelector('#note-text'))note();else{const text=document.querySelector('#note-text').value;fillNote();document.querySelector('#note-text').value=text;updateNotePreview();}}else if(role==='workshop'){if(!workshopStyle)workshop();else refreshStyleList();}}
api.state(receive);api.visibility(value=>document.body.classList.toggle('closed',!value));api.notice(toast);api.capture(src=>{document.querySelector('#capture-image').src=src;});
if(role==='capture')capture();
if(role==='line'||role==='tools')document.addEventListener('mousemove',e=>api.pointer(Boolean(e.target.closest('button,.peg,#rack'))));
document.addEventListener('keydown',e=>{if(e.key==='Escape'){call(role==='capture'?'cancel-capture':'close');}if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'&&!e.target.closest('input,textarea')){e.preventDefault();call('undo');}});
call('state').then(receive);
