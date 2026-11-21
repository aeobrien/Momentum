"""Independent disposable probes for the committed relay repair; no live store."""
import importlib.util,json,multiprocessing,os,sys,tempfile,threading,time,unittest,http.client
from pathlib import Path
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor
SOURCE=Path(__file__).resolve().parents[4]/'relay/momentum_relay.py'
spec=importlib.util.spec_from_file_location('independent_relay',SOURCE);relay=importlib.util.module_from_spec(spec);spec.loader.exec_module(relay)
def body(minute):return json.dumps({'tasks':[{'fixture':minute}],'routines':[],'completionHistory':[],'lastModified':f'2026-10-06T10:{minute:02d}:00Z'}).encode()
def blocked_process(path,entered):
 original=relay.read_snapshot
 def blocked(*args,**kwargs):
  value=original(*args,**kwargs);entered.set();time.sleep(30);return value
 relay.read_snapshot=blocked;relay.store_if_newer(Path(path),body(2))
class IndependentProbes(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='independent-relay-');self.addCleanup(self.temp.cleanup);self.file=Path(self.temp.name)/'snapshot.json';self.file.write_bytes(body(0))
 def test_threads_lock_covers_durable_write_and_atomic_read(self):
  entered=threading.Event();release=threading.Event();started=threading.Event();real=relay.os.fsync
  def fsync(fd):
   if threading.current_thread().name.startswith('old-writer'):
    entered.set();self.assertTrue(release.wait(5))
   return real(fd)
  def newer():started.set();return relay.store_if_newer(self.file,body(2))
  with patch.object(relay.os,'fsync',fsync),ThreadPoolExecutor(1,thread_name_prefix='old-writer') as old,ThreadPoolExecutor(1) as new:
   first=old.submit(relay.store_if_newer,self.file,body(1))
   try:
    self.assertTrue(entered.wait(5));second=new.submit(newer);self.assertTrue(started.wait(5));time.sleep(.1)
    self.assertFalse(second.done());self.assertEqual(relay.read_snapshot(self.file)[0],body(0))
   finally:release.set()
   self.assertTrue(first.result(5)[0]);self.assertTrue(second.result(5)[0])
  self.assertEqual(self.file.read_bytes(),body(2));self.assertFalse(list(self.file.parent.glob('.MomentumData-*')))
 def test_abrupt_process_exit_releases_owned_lock(self):
  ctx=multiprocessing.get_context('spawn');entered=ctx.Event();p=ctx.Process(target=blocked_process,args=(str(self.file),entered));p.start()
  try:
   self.assertTrue(entered.wait(5));self.assertEqual(self.file.read_bytes(),body(0));p.terminate();p.join(5);self.assertFalse(p.is_alive())
   with ThreadPoolExecutor(1) as pool:self.assertTrue(pool.submit(relay.store_if_newer,self.file,body(3)).result(5)[0])
   self.assertEqual(self.file.read_bytes(),body(3))
  finally:
   if p.is_alive():p.kill();p.join(5)
   p.close()
 def test_loopback_error_preservation_retry_stale_and_health(self):
  server=relay.make_server('127.0.0.1',0,self.file);server.daemon_threads=True;t=threading.Thread(target=server.serve_forever,daemon=True);t.start()
  def request(method,path,data=None):
   c=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=4)
   try:c.request(method,path,body=data);r=c.getresponse();return r.status,r.read()
   finally:c.close()
  try:
   with patch.object(relay.os,'replace',side_effect=OSError('synthetic persistence failure')):
    code,data=request('PUT','/momentum/data',body(2));self.assertEqual(code,500);self.assertEqual(json.loads(data),{'error':'snapshot_persistence_failed'});self.assertEqual(self.file.read_bytes(),body(0))
   self.assertFalse(list(self.file.parent.glob('.MomentumData-*')))
   code,data=request('PUT','/data',body(2));self.assertEqual(code,200);self.assertTrue(json.loads(data)['stored'])
   code,data=request('PUT','/data',body(1));self.assertEqual(code,200);self.assertFalse(json.loads(data)['stored'])
   self.assertEqual(request('GET','/momentum/data'),(200,body(2)));self.assertTrue(json.loads(request('GET','/health')[1])['hasData'])
  finally:server.shutdown();server.server_close();t.join(5);self.assertFalse(t.is_alive())
 def test_existing_read_error_preserves_bytes_and_releases_lock(self):
  read=Path.read_bytes
  def fail(path):
   if path==self.file:raise PermissionError('synthetic unreadable file')
   return read(path)
  with patch.object(Path,'read_bytes',fail):
   with self.assertRaises(PermissionError):relay.store_if_newer(self.file,body(2))
  self.assertEqual(self.file.read_bytes(),body(0));self.assertTrue(relay.store_if_newer(self.file,body(2))[0]);self.assertEqual(self.file.read_bytes(),body(2))
if __name__=='__main__':unittest.main()
