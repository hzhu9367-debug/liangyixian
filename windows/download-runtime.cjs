const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{execFile}=require('node:child_process'),{promisify}=require('node:util');
const run=promisify(execFile),checksums=require('./node_modules/electron/checksums.json');
async function download(platform,size){
  const tool=toolsets[platform];
  const name=tool?.name||`electron-v44.7.2-${platform}.zip`,url=tool?.url||`https://cdn.npmmirror.com/binaries/electron/44.7.2/${name}`;
  const folder=path.join(__dirname,'.cache','segments',platform);fs.mkdirSync(folder,{recursive:true});
  const chunkSize=1024*1024,count=Math.ceil(size/chunkSize);let cursor=0,done=0;
  async function worker(){while(cursor<count){const index=cursor++,start=index*chunkSize,end=Math.min(size-1,start+chunkSize-1),file=path.join(folder,String(index));
    let length=fs.existsSync(file)?fs.statSync(file).size:0,attempts=0;
    while(length<end-start+1){
      if(attempts++>=12)throw Error(`Download stalled at chunk ${index}`);
      const tail=`${file}.tail`;
      if(fs.existsSync(tail))fs.unlinkSync(tail);
      const source=tool?url:`https://github.com/electron/electron/releases/download/v44.7.2/${name}`;
      try{await run('curl',['-sS','--http1.1','-L','--fail','--connect-timeout','10','--max-time','45','--range',`${start+length}-${end}`,'-o',tail,source]);}
      catch(error){if(![7,28,35,52,56].includes(error.code))throw error;}
      if(!fs.existsSync(tail))continue;
      const bytes=fs.readFileSync(tail);if(bytes.length>end-start+1-length)throw Error('Invalid range response');
      fs.appendFileSync(file,bytes);length+=bytes.length;
    }
    if(fs.statSync(file).size!==end-start+1)throw Error(`Invalid range response ${index}`);
    done++;if(done%10===0||done===count)console.log(`${platform}: ${done}/${count} chunks`);
  }}
  await Promise.all(Array.from({length:8},worker));
  const temporary=path.join(__dirname,'.cache',`${name}.complete`),output=fs.openSync(temporary,'w'),hash=crypto.createHash('sha256');
  try{for(let i=0;i<count;i++){const chunk=fs.readFileSync(path.join(folder,String(i)));hash.update(chunk);fs.writeSync(output,chunk);}}finally{fs.closeSync(output);}
  if(hash.digest('hex')!==(tool?.checksum||checksums[name]))throw Error('Official SHA256 checksum mismatch');
  fs.renameSync(temporary,path.join(__dirname,'.cache',name));console.log(`${name}: official SHA256 verified`);
}
const toolsets={
  nsis:{name:'nsis-bundle-3.12.tar.gz',url:'https://github.com/electron-userland/electron-builder-binaries/releases/download/nsis%401.2.1/nsis-bundle-3.12.tar.gz',checksum:'56997fdefe25e7928a1a68b4583d08b240b66cf660234053b20131a74cc082f4'},
  sevenzip:{name:'7zip-darwin-arm64.tar.gz',url:'https://github.com/electron-userland/electron-builder-binaries/releases/download/7zip%401.0.0/7zip-darwin-arm64.tar.gz',checksum:'496a341abe210aae1a25bc202ee97f6de6c76a3dc80f91d96616be05502d72c1'}
};
const sizes={'win32-x64':157867015,'darwin-arm64':130455620,nsis:4337619,sevenzip:2599879};const platform=process.argv[2];
if(!sizes[platform])throw Error('Unknown platform');download(platform,sizes[platform]).catch(error=>{console.error(error);process.exitCode=1;});
