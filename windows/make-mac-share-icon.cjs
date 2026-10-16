const path=require('node:path'),{execFileSync}=require('node:child_process');
const source=path.join(__dirname,'assets','icon.png'),folder=path.join(__dirname,'.cache','mac-share.iconset');
for(const size of [16,32,128,256,512])for(const scale of [1,2])execFileSync('sips',['-z',String(size*scale),String(size*scale),source,'--out',path.join(folder,`icon_${size}x${size}${scale===2?'@2x':''}.png`)],{stdio:'ignore'});
execFileSync('iconutil',['-c','icns',folder,'-o',path.join(__dirname,'.cache','mac-share.icns')],{stdio:'inherit'});
