"""Reproduce an older concurrent upload replacing a newer synthetic snapshot."""
import importlib.util, json, tempfile, threading
from pathlib import Path
source=Path('/Users/aidan/Dev/Momentum/relay/momentum_relay.py')
spec=importlib.util.spec_from_file_location('momentum_relay_audit',source)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def snapshot(stamp):
 return json.dumps({'tasks':[], 'routines':[], 'completionHistory':[], 'lastModified':stamp, 'lastModifiedBy':'app'}).encode()
older=snapshot('2026-10-06T10:01:00Z'); newer=snapshot('2026-10-06T10:02:00Z')
with tempfile.TemporaryDirectory(prefix='momentum-audit-') as tmp:
 path=Path(tmp)/'snapshot.json';path.write_bytes(snapshot('2026-10-06T10:00:00Z'))
 read_done=threading.Event();release=threading.Event(); original=m.read_snapshot; failures=[]; outcomes=[]
 def read_with_barrier(p):
  result=original(p)
  if threading.current_thread().name=='older-upload':
   read_done.set()
   if not release.wait(5): raise RuntimeError('test barrier expired')
  return result
 m.read_snapshot=read_with_barrier
 def older_upload():
  try:outcomes.append(m.store_if_newer(path,older)[0])
  except BaseException as e:failures.append(repr(e))
 thread=threading.Thread(target=older_upload,name='older-upload');thread.start()
 try:
  assert read_done.wait(5),'older upload did not reach comparison'
  assert m.store_if_newer(path,newer)[0]
  assert path.read_bytes()==newer,'newer upload not stored'
 finally:
  release.set();thread.join(5)
 assert not thread.is_alive() and not failures,failures
 assert outcomes==[True] and path.read_bytes()==older,'original concurrency defect not reproduced'
 print(json.dumps({'defect_reproduced':True,'older_upload_replaced_newer':True,'real_records_accessed':False,'network_used':False,'scope':'actual store_if_newer with controlled concurrent read timing'}))
