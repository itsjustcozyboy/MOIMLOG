class Capture extends AudioWorkletProcessor {
  constructor(options) {
    super(); this.remaining=Math.round((options.processorOptions?.seconds ?? 7200)*sampleRate); this.active=true; this.buffer=new Float32Array(Math.round(sampleRate*15)); this.size=0; this.meterCount=0;
    this.port.onmessage=({data})=>{if(data==='pause'){this.active=false;this.flush();}if(data==='resume')this.active=true;if(data==='stop'){this.active=false;this.flush();this.port.postMessage({stopped:true});}};
  }
  flush(){if(this.size){const samples=this.buffer.slice(0,this.size);this.port.postMessage({samples,rate:sampleRate},[samples.buffer]);this.size=0;}}
  process(inputs){if(this.active&&inputs[0]?.[0]){const input=inputs[0][0];if((this.meterCount+=input.length)>=sampleRate/5){this.meterCount=0;let sum=0;for(const x of input)sum+=x*x;this.port.postMessage({level:Math.sqrt(sum/input.length)});}for(let i=0;i<input.length;i++){this.buffer[this.size++]=input[i];this.remaining--;if(this.size===this.buffer.length)this.flush();if(this.remaining<=0){this.active=false;this.flush();this.port.postMessage({stopped:true});break;}}}return true;}
}
registerProcessor('pcm-capture',Capture);
