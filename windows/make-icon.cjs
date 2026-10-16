const fs=require('node:fs'),path=require('node:path');
const png=fs.readFileSync(path.join(__dirname,'assets','icon.png'));
const header=Buffer.alloc(22);header.writeUInt16LE(1,2);header.writeUInt16LE(1,4);header.writeUInt16LE(1,10);header.writeUInt16LE(32,12);header.writeUInt32LE(png.length,14);header.writeUInt32LE(22,18);
fs.writeFileSync(path.join(__dirname,'assets','icon.ico'),Buffer.concat([header,png]));
