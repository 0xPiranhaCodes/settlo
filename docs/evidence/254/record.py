import subprocess,time,sys,pathlib
udid=pathlib.Path(sys.argv[3] if len(sys.argv)>3 else '/tmp/settings254-udid').read_text().strip()
prefix=sys.argv[1]; theme=sys.argv[2]
def cmd(*args): return subprocess.run(args,check=True)
def tap(x,y): cmd('/tmp/settings254-simtouch',udid,'down',str(x),str(y),'up',str(x),str(y))
def drag(x,y,to):
 args=['/tmp/settings254-simtouch',udid,'down',str(x),str(y)]
 for i in range(1,31): args += ['move',str(x),str(y+(to-y)*i/30)]
 args += ['up',str(x),str(to)];cmd(*args)
cmd('xcrun','simctl','ui',udid,'appearance',theme)
time.sleep(2)
record=subprocess.Popen(['xcrun','simctl','io',udid,'recordVideo','--codec=h264','--force',prefix+'.mp4'])
time.sleep(1);tap(.5,.5);time.sleep(2)
cmd('xcrun','simctl','io',udid,'screenshot',prefix+'-top.png')
drag(.5,.8,.35);time.sleep(2)
cmd('xcrun','simctl','io',udid,'screenshot',prefix+'-scrolled.png')
drag(.5,.14,.25);time.sleep(2)
cmd('xcrun','simctl','io',udid,'screenshot',prefix+'-header-drag.png')
drag(.5,.3,.8);time.sleep(2);drag(.5,.2,.8);time.sleep(2)
record.send_signal(2)
if record.wait() != 0: raise RuntimeError('Recording failed')
