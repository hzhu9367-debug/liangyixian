const {app,BrowserWindow,Tray,Menu,ipcMain,screen,dialog,clipboard,nativeImage,shell,protocol,net,desktopCapturer}=require('electron');
const fs=require('node:fs');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const {randomUUID}=require('node:crypto');
const chokidar=require('chokidar');
const {StateModel,builtins,normalizeStyle}=require('./model.cjs');

protocol.registerSchemesAsPrivileged([{scheme:'cloth',privileges:{standard:true,secure:true,supportFetchAPI:true}}]);
if(!app.requestSingleInstanceLock()) app.quit();
let model,root,files,lineWindow,toolWindow,tray,watcher,captureWindow,display,timer;
let revealed=false,peekUntil=0,awayAt=0,editorCount=0,quitting=false;
const editors=new Map(),trashBackups=new Map();
const dev=process.argv.includes('--qa');
if(dev) app.setPath('userData',path.join(__dirname,'qa-output','profile'));
const pngFile=name=>path.join(files,name);
const capacity=()=>display.workArea.width>=2200?16:display.workArea.width>=1500?13:12;
const artifactName=/^[a-z0-9-]+\.(png|txt)$/i;
const localFile=item=>{if(!artifactName.test(item.file)) throw Error('无效文件。');return pngFile(item.file);};
function sendState(){const data={...model.view(),capacity:capacity()};for(const win of [lineWindow,toolWindow,...editors.keys()]) if(!win.isDestroyed())win.webContents.send('state',data);updateTray();}
function notice(text){if(!lineWindow.isDestroyed())lineWindow.webContents.send('notice',text);}
function setRevealed(value){revealed=value;lineWindow.webContents.send('visibility',value);if(!value)lineWindow.setIgnoreMouseEvents(true,{forward:true});}
function publish(){sendState();peekUntil=Date.now()+2500;setRevealed(true);}
function moveToDisplay(next){display=next;const r=display.workArea;lineWindow.setBounds({x:r.x,y:r.y,width:r.width,height:240});toolWindow.setBounds({x:r.x+12,y:r.y+5,width:124,height:100});lineWindow.setAlwaysOnTop(true,'screen-saver');toolWindow.setAlwaysOnTop(true,'screen-saver');}
function createWindow(role,options){
  const win=new BrowserWindow({...options,webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,webSecurity:true}});
  win.webContents.setWindowOpenHandler(()=>({action:'deny'}));
  win.webContents.on('will-navigate',event=>event.preventDefault());
  win.loadFile(path.join(__dirname,'index.html'),{query:{role}});
  win.webContents.on('did-finish-load',()=>{win.webContents.send('state',{...model.view(),capacity:capacity()});win.webContents.send('visibility',revealed);});
  return win;
}
function openEditor(role,id){
  const existing=[...editors].find(([,info])=>info.role===role&&info.id===id);
  if(existing){existing[0].show();existing[0].focus();return;}
  const win=createWindow(role,{width:role==='workshop'?980:560,height:role==='workshop'?720:530,minWidth:role==='workshop'?820:460,minHeight:role==='workshop'?620:480,title:role==='workshop'?'便签工坊':role==='queue'?'待上绳与最近收起':'新建文字便签',backgroundColor:'#fafafa',autoHideMenuBar:true});
  editors.set(win,{role,id});editorCount++;
  win.webContents.on('did-finish-load',()=>{if(id)win.webContents.send('notice',`edit:${id}`);});
  win.on('closed',()=>{editors.delete(win);editorCount--;});
}
function setMode(mode){if(!['auto','always'].includes(mode))throw Error('无效显示模式。');model.state.mode=mode;model.persist();peekUntil=0;awayAt=0;setRevealed(mode==='always');sendState();}
function modeMenu(){return [{label:'始终显示',type:'radio',checked:model.state.mode==='always',click:()=>setMode('always')},{label:'顶部悬停显示',type:'radio',checked:model.state.mode==='auto',click:()=>setMode('auto')}];}
function updateTray(){if(!tray)return;tray.setContextMenu(Menu.buildFromTemplate([
  {label:'桌面晾衣杆',enabled:false},{label:'显示模式',submenu:modeMenu()},
  {label:'新建文字便签',click:()=>openEditor('note')},{label:'便签工坊',click:()=>openEditor('workshop')},
  {label:'截取屏幕区域',click:()=>captureScreen()},{label:'挂上剪贴板图片',click:()=>guarded(()=>pasteImage())},
  {label:'导入图片',click:()=>guarded(()=>chooseImages())},{type:'separator'},
  {label:'待上绳与最近收起',click:()=>openEditor('queue')},
  {label:'撤销上一步',enabled:model.undoStack.length>0,click:()=>guarded(()=>undo())},
  {label:'设置截图文件夹',click:()=>guarded(()=>chooseFolder())},{label:'打开保存文件夹',click:()=>shell.openPath(files)},
  {type:'separator'},{label:'退出',click:()=>app.quit()}
 ]));}
async function guarded(fn){try{return await fn();}catch(error){notice(error.message);dialog.showErrorBox('桌面晾衣杆',error.message);return null;}}
function importImage(file){
  if(!/\.(png|jpe?g|webp|bmp)$/i.test(file))throw Error('请选择 PNG、JPG、WebP 或 BMP 图片。');
  if(fs.statSync(file).size>20*1024*1024)throw Error('图片不能超过 20 MB。');
  const image=nativeImage.createFromPath(file);if(image.isEmpty())throw Error('这张图片无法读取。');
  const size=image.getSize();if(size.width*size.height>60000000)throw Error('图片不能超过 6000 万像素。');
  return saveImage(image);
}
function saveImage(image){const size=image.getSize();if(!size.width||!size.height)throw Error('图片为空。');
  const name=`${randomUUID()}.png`;const resized=Math.max(size.width,size.height)>2048?image.resize({width:size.width>=size.height?2048:undefined,height:size.height>size.width?2048:undefined}):image;
  fs.writeFileSync(pngFile(name),resized.toPNG(),{flag:'wx'});return name;
}
function imageItem(file){return {id:randomUUID(),type:'image',file,created:Date.now()};}
function addImage(file){model.add(imageItem(importImage(file)),capacity());publish();}
async function chooseImages(){const result=await dialog.showOpenDialog({properties:['openFile','multiSelections'],filters:[{name:'图片',extensions:['png','jpg','jpeg','webp','bmp']}]});for(const file of result.filePaths)addImage(file);}
function pasteImage(){const image=clipboard.readImage();if(image.isEmpty())throw Error('剪贴板里没有图片。');model.add(imageItem(saveImage(image)),capacity());publish();}
async function chooseFolder(){const result=await dialog.showOpenDialog({properties:['openDirectory'],title:'选择截图文件夹'});if(result.canceled)return;model.state.watchFolder=result.filePaths[0];model.persist();await startWatcher();sendState();}
async function startWatcher(){if(watcher)await watcher.close();const folder=model.state.watchFolder||path.join(app.getPath('pictures'),'Screenshots');
  if(!fs.existsSync(folder))return;
  watcher=chokidar.watch(folder,{ignoreInitial:true,depth:0,awaitWriteFinish:{stabilityThreshold:600,pollInterval:100}});
  watcher.on('add',file=>{if(/\.(png|jpe?g|webp|bmp)$/i.test(file))guarded(()=>addImage(file));});watcher.on('error',error=>notice(`截图监听：${error.message}`));
}
function styleFor(id){return [...builtins,...model.state.styles].find(s=>s.id===id);}
async function deleteItem(item){
  const {response}=await dialog.showMessageBox({type:'warning',buttons:['取消','移入回收站'],defaultId:0,cancelId:0,message:'把这项移入回收站？',detail:'收起会保留文件；这里只删除晾衣杆保存的副本，不删除导入时的原文件。'});
  if(response!==1)return;
  const source=localFile(item),backup=path.join(root,'Undo',`${item.id}-${item.file}`);
  fs.mkdirSync(path.dirname(backup),{recursive:true});fs.copyFileSync(source,backup);await shell.trashItem(source);
  trashBackups.set(item.id,{source,backup});model.remove(item.id);sendState();notice('已移入回收站，可撤销');
}
function undo(){const snapshot=model.undoStack.at(-1);if(!snapshot)return;
  for(const item of [...snapshot.items,...snapshot.pending,...snapshot.recent.map(r=>r.item)]){const info=trashBackups.get(item.id);if(info&&!fs.existsSync(info.source)&&fs.existsSync(info.backup))fs.copyFileSync(info.backup,info.source,fs.constants.COPYFILE_EXCL);}
  model.undo();sendState();setRevealed(true);peekUntil=Date.now()+2500;
}
async function captureScreen(){
  if(captureWindow&&!captureWindow.isDestroyed())return;
  try {
    display=screen.getDisplayNearestPoint(screen.getCursorScreenPoint());lineWindow.hide();toolWindow.hide();
    await new Promise(resolve=>setTimeout(resolve,220));
    const r=display.bounds;const sources=await desktopCapturer.getSources({types:['screen'],thumbnailSize:{width:Math.round(r.width*display.scaleFactor),height:Math.round(r.height*display.scaleFactor)}});
    const source=sources.find(s=>s.display_id===String(display.id))||sources[0];if(!source||source.thumbnail.isEmpty())throw Error('无法读取屏幕。');
    const image=source.thumbnail;
    captureWindow=createWindow('capture',{...r,frame:false,alwaysOnTop:true,skipTaskbar:true,backgroundColor:'#202020',resizable:false});
    editors.set(captureWindow,{role:'capture',image});editorCount++;
    captureWindow.webContents.on('did-finish-load',()=>captureWindow.webContents.send('capture',image.toDataURL()));
    captureWindow.on('closed',()=>{editors.delete(captureWindow);editorCount--;captureWindow=null;lineWindow.showInactive();toolWindow.showInactive();moveToDisplay(display);});
  }catch(error){lineWindow.showInactive();toolWindow.showInactive();notice(error.message);}
}
ipcMain.handle('clothesline',async(event,action,payload={})=>{
  const win=BrowserWindow.fromWebContents(event.sender);if(!win||![lineWindow,toolWindow,...editors.keys()].includes(win))throw Error('无效窗口。');
  try {
    const item=model.find(payload.id);
    switch(action){
      case 'state':return {...model.view(),capacity:capacity()};
      case 'mode':setMode(payload.mode);break;
      case 'mode-menu':Menu.buildFromTemplate(modeMenu()).popup({window:toolWindow});break;
      case 'note':openEditor('note',payload.id);break;
      case 'workshop':openEditor('workshop');break;
      case 'queue':openEditor('queue');break;
      case 'close':if(editors.has(win))win.close();break;
      case 'capture':await captureScreen();break;
      case 'cancel-capture':if(win===captureWindow)win.close();break;
      case 'shot':{
        const info=editors.get(win);if(info?.role!=='capture')throw Error('无效截图窗口。');
        const rect=payload.rect,size=info.image.getSize(),bounds=win.getContentBounds();
        if(!rect||!['x','y','width','height'].every(k=>Number.isFinite(rect[k])))throw Error('无效截图区域。');
        const x=Math.max(0,Math.min(size.width-1,Math.round(rect.x*size.width/bounds.width)));
        const y=Math.max(0,Math.min(size.height-1,Math.round(rect.y*size.height/bounds.height)));
        const width=Math.max(1,Math.min(size.width-x,Math.round(rect.width*size.width/bounds.width)));
        const height=Math.max(1,Math.min(size.height-y,Math.round(rect.height*size.height/bounds.height)));
        model.add(imageItem(saveImage(info.image.crop({x,y,width,height}))),capacity());win.close();publish();break;}
      case 'choose-images':await chooseImages();break;
      case 'drop-images':if(!Array.isArray(payload.paths)||payload.paths.length>100)throw Error('一次最多导入 100 张。');for(const file of payload.paths)if(typeof file==='string')addImage(file);break;
      case 'clipboard':pasteImage();break;
      case 'save-note':{
        const text=String(payload.text||'').trim();if(!text||text.length>20000)throw Error('请输入文字，最多 20000 字。');
        if(!styleFor(payload.style))throw Error('请选择有效外形。');
        if(item){if(item.type!=='note')throw Error('不是文字便签。');fs.writeFileSync(localFile(item),text);item.text=text;item.style=payload.style;model.persist();}
        else {const file=`${randomUUID()}.txt`;fs.writeFileSync(pngFile(file),text,{flag:'wx'});model.add({id:randomUUID(),type:'note',file,text,style:payload.style,created:Date.now()},capacity());}
        publish();if(editors.get(win)?.role==='note')win.close();break;}
      case 'copy':if(!item)throw Error('找不到内容。');if(item.type==='note')clipboard.writeText(item.text);else clipboard.writeImage(nativeImage.createFromPath(localFile(item)));notice('已复制');break;
      case 'pin':model.pin(payload.id);sendState();break;
      case 'stow':model.stow(payload.id);sendState();notice('已收起，可撤销');break;
      case 'trash':if(!item)throw Error('找不到内容。');await deleteItem(item);break;
      case 'replace':model.replace(payload.id,payload.next);sendState();notice('已替换，原文件保留，可撤销');break;
      case 'reorder':model.reorder(payload.id,payload.target);sendState();break;
      case 'restore':model.restore(payload.id,capacity());publish();break;
      case 'hang-pending':model.hangPending(payload.id,capacity());publish();break;
      case 'undo':undo();break;
      case 'artwork':{const result=await dialog.showOpenDialog(win,{properties:['openFile'],filters:[{name:'便签底图',extensions:['png','jpg','jpeg','webp']}]});if(result.canceled)return null;return `cloth://asset/${importImage(result.filePaths[0])}`;}
      case 'save-style':{
        const style=normalizeStyle(payload);const art=new URL(style.art);
        if(art.protocol!=='cloth:'||art.hostname!=='asset'||!artifactName.test(art.pathname.slice(1))||!fs.existsSync(pngFile(art.pathname.slice(1))))throw Error('请先上传底图。');
        const index=model.state.styles.findIndex(s=>s.id===style.id);if(index<0)model.state.styles.push(style);else model.state.styles[index]=style;
        model.persist();sendState();notice('样式已保存');return style.id;}
      case 'archive-style':{const style=model.state.styles.find(s=>s.id===payload.id);if(style){style.archived=true;model.persist();sendState();}break;}
      case 'folder':shell.openPath(files);break;
      case 'watch-folder':await chooseFolder();break;
      case 'quit':app.quit();break;
      default:throw Error('不支持的操作。');
    }
    return {ok:true};
  }catch(error){return {ok:false,error:error.message};}
});
ipcMain.on('pointer',(event,active)=>{for(const win of [lineWindow,toolWindow])if(event.sender===win.webContents)win.setIgnoreMouseEvents(!active,{forward:true});});
ipcMain.on('drag-file',(event,id)=>{if(event.sender!==lineWindow.webContents)return;const item=model.find(id);if(!item)return;
  const icon=item.type==='image'?nativeImage.createFromPath(localFile(item)).resize({width:64}):nativeImage.createFromPath(path.join(__dirname,'assets','tomato.png')).resize({width:64});
  event.sender.startDrag({file:localFile(item),icon});});
app.whenReady().then(()=>{
  root=app.getPath('userData');files=path.join(root,'Files');fs.mkdirSync(files,{recursive:true});model=new StateModel(root);
  protocol.handle('cloth',request=>{const url=new URL(request.url),name=decodeURIComponent(url.pathname.slice(1));
    let file;if(url.hostname==='builtin'&&/^[a-z]+\.png$/.test(name))file=path.join(__dirname,'assets',name);
    else if(url.hostname==='asset'&&artifactName.test(name))file=pngFile(name);
    else return new Response('',{status:404});
    return net.fetch(pathToFileURL(file).href);});
  display=screen.getPrimaryDisplay();
  lineWindow=createWindow('line',{width:display.workArea.width,height:240,transparent:true,frame:false,resizable:false,skipTaskbar:true,focusable:false,hasShadow:false});
  toolWindow=createWindow('tools',{width:124,height:100,transparent:true,frame:false,resizable:false,skipTaskbar:true,focusable:false,hasShadow:false});
  lineWindow.setIgnoreMouseEvents(true,{forward:true});moveToDisplay(display);
  toolWindow.setIgnoreMouseEvents(true,{forward:true});
  if(process.platform==='darwin'){lineWindow.setVisibleOnAllWorkspaces(true,{visibleOnFullScreen:true});toolWindow.setVisibleOnAllWorkspaces(true,{visibleOnFullScreen:true});}
  const trayIcon=nativeImage.createFromPath(path.join(__dirname,'assets','tray.png'));tray=new Tray(trayIcon);tray.setToolTip('桌面晾衣杆');updateTray();tray.on('double-click',()=>setMode(model.state.mode==='auto'?'always':'auto'));
  lineWindow.webContents.on('did-finish-load',()=>setRevealed(model.state.mode==='always'));
  timer=setInterval(()=>{
    if(captureWindow||editorCount)return;
    const mouse=screen.getCursorScreenPoint(),next=screen.getDisplayNearestPoint(mouse),r=next.bounds;
    const top=mouse.y>=r.y&&mouse.y<=r.y+Math.max(6,next.workArea.y-r.y+5);
    if(top){if(next.id!==display.id)moveToDisplay(next);setRevealed(true);awayAt=0;}
    else if(model.state.mode==='always'){if(!revealed)setRevealed(true);}
    else if(revealed&&Date.now()>peekUntil){const bounds=lineWindow.getBounds();const inside=mouse.x>=bounds.x&&mouse.x<bounds.x+bounds.width&&mouse.y>=bounds.y&&mouse.y<bounds.y+bounds.height;
      if(inside)awayAt=0;else if(!awayAt)awayAt=Date.now();else if(Date.now()-awayAt>500){setRevealed(false);awayAt=0;}}
  },80);
  screen.on('display-metrics-changed',()=>moveToDisplay(screen.getDisplayNearestPoint(screen.getCursorScreenPoint())));
  screen.on('display-removed',()=>moveToDisplay(screen.getPrimaryDisplay()));
  startWatcher();
});
app.on('window-all-closed',()=>{});
app.on('second-instance',()=>{if(toolWindow)toolWindow.showInactive();if(lineWindow)setRevealed(true);});
app.on('before-quit',()=>{quitting=true;clearInterval(timer);watcher?.close();});
app.on('web-contents-created',(_event,contents)=>{contents.on('will-attach-webview',event=>event.preventDefault());contents.session.setPermissionRequestHandler((_web, _permission, callback)=>callback(false));});
