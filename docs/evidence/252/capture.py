import subprocess,time,pathlib,sys
root=pathlib.Path.cwd(); udid=(root/'build/issue252/udid').read_text().strip()
def run(*a): return subprocess.run(a,check=True)
def tap(x,y): run(str(root/'build/issue252/simtouch'),udid,'down',str(x),str(y),'up',str(x),str(y))
def swipe():
 args=[str(root/'build/issue252/simtouch'),udid,'down','0.002','0.4']
 for i in range(1,31): args+=['move',str(.002+i*.03),'0.4']
 args+=['up','.902','.4'];run(*args)
for theme in ['light','dark']:
 run('xcrun','simctl','ui',udid,'appearance',theme)
 for name,y in [('expenses',.397),('balances',.466),('empty',.534),('loan',.603)]:
  run('xcrun','simctl','terminate',udid,'app.settlo')
  run('xcrun','simctl','launch',udid,'app.settlo');time.sleep(3)
  tap(.5,y);time.sleep(2)
  run('xcrun','simctl','io',udid,'screenshot',str(root/f'docs/evidence/252/{sys.argv[1]}-{name}-{theme}.png'))
  if sys.argv[1]=='after':
   swipe();time.sleep(1)
   run('xcrun','simctl','io',udid,'screenshot',str(root/f'build/issue252/swipe-{name}-{theme}.png'))
