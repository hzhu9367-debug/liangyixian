const {contextBridge,ipcRenderer,webUtils}=require('electron');
contextBridge.exposeInMainWorld('clothesline', {
  invoke:(action,payload)=>ipcRenderer.invoke('clothesline',action,payload),
  state:callback=>{ipcRenderer.on('state',(_event,data)=>callback(data));},
  visibility:callback=>{ipcRenderer.on('visibility',(_event,value)=>callback(value));},
  notice:callback=>{ipcRenderer.on('notice',(_event,value)=>callback(value));},
  capture:callback=>{ipcRenderer.on('capture',(_event,value)=>callback(value));},
  pointer:active=>ipcRenderer.send('pointer',Boolean(active)),
  paths:files=>Array.from(files).map(file=>webUtils.getPathForFile(file)).filter(Boolean),
  drag:id=>ipcRenderer.send('drag-file',id)
});
