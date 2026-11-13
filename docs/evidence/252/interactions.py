import subprocess,time,pathlib,signal
root=pathlib.Path.cwd();udid=(root/'build/issue252/udid').read_text().strip()
def run(*args):subprocess.run(args,check=True)
def touch(*args):run(str(root/'build/issue252/simtouch'),udid,*map(str,args))
def tap(x,y):touch('down',x,y,'up',x,y)
for theme in ['light','dark']:
 run('xcrun','simctl','ui',udid,'appearance',theme);time.sleep(1)
 tap(.5,.397);time.sleep(1)
 # Tap near the bottom edge of the 44pt native target (y=103 of 874).
 tap(.17,103/874);time.sleep(1)
 run('xcrun','simctl','io',udid,'screenshot',str(root/f'docs/evidence/252/tap-bottom-{theme}.png'))
 tap(.5,.397);time.sleep(1)
 args=['down',.002,.4]
 for i in range(1,31):args+=['move',.002+i*.03,.4]
 args+=['up',.902,.4];touch(*args);time.sleep(1)
