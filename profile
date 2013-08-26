# HG changeset patch
# Parent 17143a9a0d838ced69fa159d8b12c7ecfcc5d8c4
# User Mihnea Dobrescu-Balaur <mihneadb@gmail.com>
Bug 907455 - Enhance the xpcshell harness to provide per test resource usage data

diff --git a/testing/xpcshell/head.js b/testing/xpcshell/head.js
--- a/testing/xpcshell/head.js
+++ b/testing/xpcshell/head.js
@@ -402,16 +402,42 @@ function _execute_test() {
           todo_checks: _todoChecks});
   } else {
     // ToDo: switch to TEST-UNEXPECTED-FAIL when all tests have been updated. (Bug 496443)
     _log("test_info",
          {_message: "TEST-INFO | (xpcshell/head.js) | No (+ " + _falsePassedChecks +
                     ") checks actually run\n",
          source_file: _TEST_FILE});
   }
+  if (typeof _RESOURCE_PORT != "undefined") {
+    dump("~~~~~~~~~~ " + _RESOURCE_PORT + "\n");
+    let transportService = Components.classes["@mozilla.org/network/socket-transport-service;1"]
+      .getService(Components.interfaces.nsISocketTransportService);
+    let transport = transportService.createTransport(null, 0, "localhost", _RESOURCE_PORT, null);
+    let outputStream = transport.openOutputStream(1, 0, 0);
+    let inputStream = transport.openInputStream(1, 0, 0);
+    const nsIScriptableInputStream = Components.interfaces.nsIScriptableInputStream;
+    var factory = Components.classes["@mozilla.org/scriptableinputstream;1"];
+    let sis = factory.createInstance(nsIScriptableInputStream);
+    sis.init(inputStream);
+
+    // tell harness we are ready
+    let message = "RDY";
+    outputStream.write(message, message.length);
+    outputStream.close();
+
+    // wait for ACK from the harness
+
+    // this blocks so we wait here
+    //let msg = sis.readBytes(512);
+    dump("READ..\n");
+
+    inputStream.close();
+  }
+
 }
 
 /**
  * Loads files.
  *
  * @param aFiles Array of files to load.
  */
 function _load_files(aFiles) {
@@ -875,20 +901,20 @@ function do_test_pending(aName) {
        {_message: "TEST-INFO | (xpcshell/head.js) | test" +
                   (aName ? " " + aName : "") +
                   " pending (" + _tests_pending + ")\n"});
 }
 
 function do_test_finished(aName) {
   _log("test_finish",
        {_message: "TEST-INFO | (xpcshell/head.js) | test" +
-                  (aName ? " " + aName : "") +
-                  " finished (" + _tests_pending + ")\n"});
-  if (--_tests_pending == 0)
-    _do_quit();
+         (aName ? " " + aName : "") +
+         " finished (" + _tests_pending + ")\n"});
+       if (--_tests_pending == 0)
+         _do_quit();
 }
 
 function do_get_file(path, allowNonexistent) {
   try {
     let lf = Components.classes["@mozilla.org/file/directory_service;1"]
       .getService(Components.interfaces.nsIProperties)
       .get("CurWorkD", Components.interfaces.nsILocalFile);
 
diff --git a/testing/xpcshell/mach_commands.py b/testing/xpcshell/mach_commands.py
--- a/testing/xpcshell/mach_commands.py
+++ b/testing/xpcshell/mach_commands.py
@@ -48,29 +48,30 @@ class XPCShellRunner(MozbuildObject):
         manifest = os.path.join(self.topobjdir, '_tests', 'xpcshell',
             'xpcshell.ini')
 
         return self._run_xpcshell_harness(manifest=manifest, **kwargs)
 
     def run_test(self, test_file, interactive=False,
                  keep_going=False, sequential=False, shuffle=False,
                  debugger=None, debuggerArgs=None, debuggerInteractive=None,
-                 rerun_failures=False):
+                 rerun_failures=False, resource_usage=None):
         """Runs an individual xpcshell test."""
         # TODO Bug 794506 remove once mach integrates with virtualenv.
         build_path = os.path.join(self.topobjdir, 'build')
         if build_path not in sys.path:
             sys.path.append(build_path)
 
         if test_file == 'all':
             self.run_suite(interactive=interactive,
                            keep_going=keep_going, shuffle=shuffle, sequential=sequential,
                            debugger=debugger, debuggerArgs=debuggerArgs,
                            debuggerInteractive=debuggerInteractive,
-                           rerun_failures=rerun_failures)
+                           rerun_failures=rerun_failures,
+                           resource_usage=resource_usage)
             return
 
         path_arg = self._wrap_path_argument(test_file)
 
         test_obj_dir = os.path.join(self.topobjdir, '_tests', 'xpcshell',
             path_arg.relpath())
         if os.path.isfile(test_obj_dir):
             test_obj_dir = mozpack.path.dirname(test_obj_dir)
@@ -91,29 +92,30 @@ class XPCShellRunner(MozbuildObject):
             'interactive': interactive,
             'keep_going': keep_going,
             'shuffle': shuffle,
             'sequential': sequential,
             'test_dirs': xpcshell_dirs,
             'debugger': debugger,
             'debuggerArgs': debuggerArgs,
             'debuggerInteractive': debuggerInteractive,
-            'rerun_failures': rerun_failures
+            'rerun_failures': rerun_failures,
+            'resource_usage': resource_usage,
         }
 
         if os.path.isfile(path_arg.srcdir_path()):
             args['test_path'] = mozpack.path.basename(path_arg.srcdir_path())
 
         return self._run_xpcshell_harness(**args)
 
     def _run_xpcshell_harness(self, test_dirs=None, manifest=None,
                               test_path=None, shuffle=False, interactive=False,
                               keep_going=False, sequential=False,
                               debugger=None, debuggerArgs=None, debuggerInteractive=None,
-                              rerun_failures=False):
+                              rerun_failures=False, resource_usage=None):
 
         # Obtain a reference to the xpcshell test runner.
         import runxpcshelltests
 
         dummy_log = StringIO()
         xpcshell = runxpcshelltests.XPCShellTests(log=dummy_log)
         self.log_manager.enable_unstructured()
 
@@ -127,16 +129,17 @@ class XPCShellRunner(MozbuildObject):
             'xpcshell': os.path.join(self.bindir, 'xpcshell'),
             'mozInfo': os.path.join(self.topobjdir, 'mozinfo.json'),
             'symbolsPath': os.path.join(self.distdir, 'crashreporter-symbols'),
             'interactive': interactive,
             'keepGoing': keep_going,
             'logfiles': False,
             'sequential': sequential,
             'shuffle': shuffle,
+            'resource_usage': resource_usage,
             'testsRootDir': tests_dir,
             'testingModulesDir': modules_dir,
             'profileName': 'firefox',
             'verbose': test_path is not None,
             'xunitFilename': os.path.join(self.statedir, 'xpchsell.xunit.xml'),
             'xunitName': 'xpcshell',
             'pluginsPath': os.path.join(self.distdir, 'plugins'),
             'debugger': debugger,
@@ -218,16 +221,18 @@ class MachCommands(MachCommandBase):
     @CommandArgument('--keep-going', '-k', action='store_true',
         help='Continue running tests after a SIGINT is received.')
     @CommandArgument('--sequential', action='store_true',
         help='Run the tests sequentially.')
     @CommandArgument('--shuffle', '-s', action='store_true',
         help='Randomize the execution order of tests.')
     @CommandArgument('--rerun-failures', action='store_true',
         help='Reruns failures from last time.')
+    @CommandArgument('--resource-usage', default=None, dest='resource_usage',
+        help='Path for dumping JSON data of resources used.')
     def run_xpcshell_test(self, **params):
         # We should probably have a utility function to ensure the tree is
         # ready to run tests. Until then, we just create the state dir (in
         # case the tree wasn't built with mach).
         self._ensure_state_subdir_exists('.')
 
         xpcshell = self._spawn(XPCShellRunner)
 
diff --git a/testing/xpcshell/runxpcshelltests.py b/testing/xpcshell/runxpcshelltests.py
--- a/testing/xpcshell/runxpcshelltests.py
+++ b/testing/xpcshell/runxpcshelltests.py
@@ -83,17 +83,18 @@ def parse_json(j):
 gotSIGINT = False
 def markGotSIGINT(signum, stackFrame):
     global gotSIGINT
     gotSIGINT = True
 
 class XPCShellTestThread(Thread):
     def __init__(self, test_object, event, cleanup_dir_list, tests_root_dir=None,
             app_dir_key=None, interactive=False, verbose=False, pStdout=None,
-            pStderr=None, keep_going=False, log=None, **kwargs):
+            pStderr=None, keep_going=False, log=None, resource_logs=None,
+            **kwargs):
         Thread.__init__(self)
         self.daemon = True
 
         self.test_object = test_object
         self.cleanup_dir_list = cleanup_dir_list
 
         self.appPath = kwargs.get('appPath')
         self.xrePath = kwargs.get('xrePath')
@@ -116,16 +117,18 @@ class XPCShellTestThread(Thread):
         self.tests_root_dir = tests_root_dir
         self.app_dir_key = app_dir_key
         self.interactive = interactive
         self.verbose = verbose
         self.pStdout = pStdout
         self.pStderr = pStderr
         self.keep_going = keep_going
         self.log = log
+        self.resource_data = None
+        self.resource_logs = resource_logs
 
         # only one of these will be set to 1. adding them to the totals in
         # the harness
         self.passCount = 0
         self.todoCount = 0
         self.failCount = 0
 
         self.output_lines = []
@@ -176,21 +179,74 @@ class XPCShellTestThread(Thread):
 
     def getReturnCode(self, proc):
         """
           Simple wrapper to get the return code for a given process.
           On a remote system we overload this to work with the remote process management.
         """
         return proc.returncode
 
+    def recordResourceUsage(self, proc):
+        # get process data (if available)
+        if HAVE_PSUTIL and self.resource_logs is not None:
+            # wait for the process to be done
+            conn, addr = self.sock.accept()
+            # wait for a msg from the process saying "I'm done"
+            data = conn.recv(4096)
+
+            # record the actual data
+            attrs = [
+                'get_cpu_percent',
+                'get_cpu_times',
+                'get_ext_memory_info',
+            ]
+            # psutil does not support this on OS X :(
+            if mozinfo.os != 'mac':
+                attrs.append('get_io_counters')
+
+            data = proc.as_dict(attrs=attrs, ad_value=None)
+
+            # tell xpcshell to carry on
+            #import time; time.sleep(1)
+            conn.sendall("ACK")
+            conn.close()
+            self.sock.close()
+
+            # process the captured data
+            # convert psutil's own format to dicts
+            for k in data:
+                if data[k] and '_asdict' in dir(data[k]):
+                    data[k] = data[k]._asdict()
+
+            # get test file path relative to $SRC_DIR
+            full_path = self.test_object['path']
+            if 'xpcshell' in full_path:
+                path = 'xpcshell'.join(full_path.split('xpcshell')[1:])
+            else:
+                path = full_path
+            test_file = str(path[1:])
+            data['test_file'] = test_file
+
+            self.resource_data = data
+            if self.resource_logs is not None:
+                self.resource_logs.append(self.resource_data)
+
+    def logResourceUsage(self):
+        if not self.resource_data:
+            return
+        json_str = json.dumps(self.resource_data, sort_keys=True, indent=4)
+        full_path = self.test_object['path']
+        self.log.info("TEST-INFO | %s | Resource usage:\n%s" % (full_path, json_str))
+
     def communicate(self, proc):
         """
           Simple wrapper to communicate with a process.
           On a remote system, this is overloaded to handle remote process communication.
         """
+        self.recordResourceUsage(proc)
         return proc.communicate()
 
     def launchProcess(self, cmd, stdout, stderr, env, cwd):
         """
           Simple wrapper to launch a process.
           On a remote system, this is more complex and we need to overload this function.
         """
         if HAVE_PSUTIL:
@@ -301,16 +357,23 @@ class XPCShellTestThread(Thread):
                     raise Exception('%s file is not a file: %s' % (kind, path))
 
                 yield path
 
         return (list(sanitize_list(test_object['head'], 'head')),
                 list(sanitize_list(test_object['tail'], 'tail')))
 
     def buildXpcsCmd(self, testdir):
+        self.sock = None
+        if self.resource_logs is not None and HAVE_PSUTIL:
+            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
+            self.sock.bind(('localhost', 0))
+            self.resource_port = self.sock.getsockname()[1]
+            print "PORT >>>>> ", self.resource_port
+            self.sock.listen(1)
         """
           Load the root head.js file as the first file in our test path, before other head, test, and tail files.
           On a remote system, we overload this to add additional command line arguments, so this gets overloaded.
         """
         # - NOTE: if you rename/add any of the constants set here, update
         #   do_load_child_test_harness() in head.js
         if not self.appPath:
             self.appPath = self.xrePath
@@ -319,18 +382,20 @@ class XPCShellTestThread(Thread):
             self.xpcshell,
             '-g', self.xrePath,
             '-a', self.appPath,
             '-r', self.httpdManifest,
             '-m',
             '-n',
             '-s',
             '-e', 'const _HTTPD_JS_PATH = "%s";' % self.httpdJSPath,
-            '-e', 'const _HEAD_JS_PATH = "%s";' % self.headJSPath
+            '-e', 'const _HEAD_JS_PATH = "%s";' % self.headJSPath,
         ]
+        if self.resource_logs is not None and HAVE_PSUTIL:
+            self.xpcsCmd.extend(['-e', 'const _RESOURCE_PORT = %d;' % self.resource_port])
 
         if self.testingModulesDir:
             # Escape backslashes in string literal.
             sanitized = self.testingModulesDir.replace('\\', '\\\\')
             self.xpcsCmd.extend([
                 '-e',
                 'const _TESTING_MODULES_DIR = "%s";' % sanitized
             ])
@@ -582,20 +647,24 @@ class XPCShellTestThread(Thread):
                         for k, v in self.test_object.items():
                             f.write('%s = %s\n' % (k, v))
 
             else:
                 now = time.time()
                 timeTaken = (now - startTime) * 1000
                 self.xunit_result["time"] = now - startTime
 
+                if self.resource_logs is not None:
+                    self.resource_data["duration"] = timeTaken
+
                 with LOG_MUTEX:
                     self.log.info("TEST-%s | %s | test passed (time: %.3fms)" % ("PASS" if expected else "KNOWN-FAIL", name, timeTaken))
                     if self.verbose:
                         self.log_output(self.output_lines)
+                    self.logResourceUsage()
 
                 self.xunit_result["passed"] = True
 
                 if expected:
                     self.passCount = 1
                 else:
                     self.todoCount = 1
                     self.xunit_result["todo"] = True
@@ -1066,17 +1135,17 @@ class XPCShellTests(object):
                  manifest=None, testdirs=None, testPath=None, mobileArgs=None,
                  interactive=False, verbose=False, keepGoing=False, logfiles=True,
                  thisChunk=1, totalChunks=1, debugger=None,
                  debuggerArgs=None, debuggerInteractive=False,
                  profileName=None, mozInfo=None, sequential=False, shuffle=False,
                  testsRootDir=None, xunitFilename=None, xunitName=None,
                  testingModulesDir=None, autolog=False, pluginsPath=None,
                  testClass=XPCShellTestThread, failureManifest=None,
-                 **otherOptions):
+                 resource_usage=None, **otherOptions):
         """Run xpcshell tests.
 
         |xpcshell|, is the xpcshell executable to use to run the tests.
         |xrePath|, if provided, is the path to the XRE to use.
         |appPath|, if provided, is the path to an application directory.
         |symbolsPath|, if provided is the path to a directory containing
           breakpad symbols for processing crashes in tests.
         |manifest|, if provided, is a file containing a list of
@@ -1212,16 +1281,17 @@ class XPCShellTests(object):
         if self.singleFile:
             self.sequential = True
 
         if shuffle:
             random.shuffle(self.alltests)
 
         self.xunitResults = []
         self.cleanup_dir_list = []
+        self.resource_logs = [] if resource_usage else None
 
         kwargs = {
             'appPath': self.appPath,
             'xrePath': self.xrePath,
             'testingModulesDir': self.testingModulesDir,
             'debuggerInfo': self.debuggerInfo,
             'pluginsPath': self.pluginsPath,
             'httpdManifest': self.httpdManifest,
@@ -1264,17 +1334,18 @@ class XPCShellTests(object):
                 continue
 
             self.testCount += 1
 
             test = testClass(test_object, self.event, self.cleanup_dir_list,
                     tests_root_dir=testsRootDir, app_dir_key=appDirKey,
                     interactive=interactive, verbose=verbose, pStdout=pStdout,
                     pStderr=pStderr, keep_going=keepGoing, log=self.log,
-                    mobileArgs=mobileArgs, **kwargs)
+                    mobileArgs=mobileArgs, resource_logs=self.resource_logs,
+                    **kwargs)
             if 'run-sequentially' in test_object or self.sequential:
                 sequential_tests.append(test)
             else:
                 tests_queue.append(test)
 
         if self.sequential:
             self.log.info("INFO | Running tests sequentially.")
         else:
@@ -1330,16 +1401,17 @@ class XPCShellTests(object):
                 if not keep_going:
                     self.log.error("TEST-UNEXPECTED-FAIL | Received SIGINT (control-C), so stopped run. " \
                                    "(Use --keep-going to keep running tests after killing one with SIGINT)")
                     break
                 test.start()
                 test.join()
                 # did the test encounter any exception?
                 if test.exception:
+                    print test.traceback
                     raise test.exception
                 keep_going = test.keep_going
                 self.addTestResults(test)
 
         # restore default SIGINT behaviour
         signal.signal(signal.SIGINT, signal.SIG_DFL)
 
         self.shutdownNode()
@@ -1363,16 +1435,20 @@ class XPCShellTests(object):
             self.log.error("TEST-UNEXPECTED-FAIL | runxpcshelltests.py | No tests run. Did you pass an invalid --test-path?")
             self.failCount = 1
 
         self.log.info("INFO | Result summary:")
         self.log.info("INFO | Passed: %d" % self.passCount)
         self.log.info("INFO | Failed: %d" % self.failCount)
         self.log.info("INFO | Todo: %d" % self.todoCount)
 
+        if resource_usage:
+            with open(os.path.expanduser(resource_usage), 'w') as f:
+                json.dump(self.resource_logs, f, sort_keys=True, indent=4)
+
         if autolog:
             self.post_to_autolog(self.xunitResults, xunitName)
 
         if xunitFilename is not None:
             self.writeXunitResults(filename=xunitFilename, results=self.xunitResults,
                                    name=xunitName)
 
         if gotSIGINT and not keepGoing:
@@ -1439,16 +1515,19 @@ class XPCShellOptions(OptionParser):
                         type = "string", dest="profileName", default=None,
                         help="name of application profile being tested")
         self.add_option("--build-info-json",
                         type = "string", dest="mozInfo", default=None,
                         help="path to a mozinfo.json including information about the build configuration. defaults to looking for mozinfo.json next to the script.")
         self.add_option("--shuffle",
                         action="store_true", dest="shuffle", default=False,
                         help="Execute tests in random order")
+        self.add_option("--resource-usage",
+                        type="string", dest="resource_usage", default=None,
+                        help="Where to save JSON data of per test used resources.")
         self.add_option("--xunit-file", dest="xunitFilename",
                         help="path to file where xUnit results will be written.")
         self.add_option("--xunit-suite-name", dest="xunitName",
                         help="name to record for this xUnit test suite. Many "
                              "tools expect Java class notation, e.g. "
                              "dom.basic.foo")
         self.add_option("--failure-manifest", dest="failureManifest",
                         action="store",
