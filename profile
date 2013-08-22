# HG changeset patch
# Parent c8c9bd74cc405ed706ff153fb2170418bcbc7ebc
# User Mihnea Dobrescu-Balaur <mihneadb@gmail.com>
Bug 907455 - Enhance the xpcshell harness to provide per test resource usage data

diff --git a/testing/xpcshell/mach_commands.py b/testing/xpcshell/mach_commands.py
--- a/testing/xpcshell/mach_commands.py
+++ b/testing/xpcshell/mach_commands.py
@@ -40,17 +40,17 @@ class XPCShellRunner(MozbuildObject):
     """Run xpcshell tests."""
     def run_suite(self, **kwargs):
         manifest = os.path.join(self.topobjdir, '_tests', 'xpcshell',
             'xpcshell.ini')
 
         return self._run_xpcshell_harness(manifest=manifest, **kwargs)
 
     def run_test(self, test_file, debug=False, interactive=False,
-        keep_going=False, sequential=False, shuffle=False):
+        keep_going=False, sequential=False, shuffle=False, resource_usage=None):
         """Runs an individual xpcshell test."""
         # TODO Bug 794506 remove once mach integrates with virtualenv.
         build_path = os.path.join(self.topobjdir, 'build')
         if build_path not in sys.path:
             sys.path.append(build_path)
 
         if test_file == 'all':
             self.run_suite(debug=debug, interactive=interactive,
@@ -78,26 +78,27 @@ class XPCShellRunner(MozbuildObject):
 
         args = {
             'debug': debug,
             'interactive': interactive,
             'keep_going': keep_going,
             'shuffle': shuffle,
             'sequential': sequential,
             'test_dirs': xpcshell_dirs,
+            'resource_usage': resource_usage,
         }
 
         if os.path.isfile(path_arg.srcdir_path()):
             args['test_path'] = mozpack.path.basename(path_arg.srcdir_path())
 
         return self._run_xpcshell_harness(**args)
 
     def _run_xpcshell_harness(self, test_dirs=None, manifest=None,
         test_path=None, debug=False, shuffle=False, interactive=False,
-        keep_going=False, sequential=False):
+        keep_going=False, sequential=False, resource_usage=None):
 
         # Obtain a reference to the xpcshell test runner.
         import runxpcshelltests
 
         dummy_log = StringIO()
         xpcshell = runxpcshelltests.XPCShellTests(log=dummy_log)
         self.log_manager.enable_unstructured()
 
@@ -108,16 +109,17 @@ class XPCShellRunner(MozbuildObject):
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
         }
@@ -169,16 +171,18 @@ class MachCommands(MachCommandBase):
     @CommandArgument('--interactive', '-i', action='store_true',
         help='Open an xpcshell prompt before running tests.')
     @CommandArgument('--keep-going', '-k', action='store_true',
         help='Continue running tests after a SIGINT is received.')
     @CommandArgument('--sequential', action='store_true',
         help='Run the tests sequentially.')
     @CommandArgument('--shuffle', '-s', action='store_true',
         help='Randomize the execution order of tests.')
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
@@ -1,15 +1,16 @@
 #!/usr/bin/env python
 #
 # This Source Code Form is subject to the terms of the Mozilla Public
 # License, v. 2.0. If a copy of the MPL was not distributed with this
 # file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 import copy
+import json
 import re, sys, os, os.path, logging, shutil, math, time, traceback
 import xml.dom.minidom
 from collections import deque
 from distutils import dir_util
 from glob import glob
 from multiprocessing import cpu_count
 from optparse import OptionParser
 from subprocess import Popen, PIPE, STDOUT
@@ -66,17 +67,18 @@ def parse_json(j):
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
@@ -98,16 +100,18 @@ class XPCShellTestThread(Thread):
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
 
         # event from main thread to signal work done
@@ -155,21 +159,60 @@ class XPCShellTestThread(Thread):
 
     def getReturnCode(self, proc):
         """
           Simple wrapper to get the return code for a given process.
           On a remote system we overload this to work with the remote process management.
         """
         return proc.returncode
 
+    def recordResourceUsage(self, proc):
+        # get process data (if available)
+        if HAVE_PSUTIL:
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
@@ -496,20 +539,23 @@ class XPCShellTestThread(Thread):
                   "message": message,
                   "text": stdout
                 }
             else:
                 now = time.time()
                 timeTaken = (now - startTime) * 1000
                 self.xunit_result["time"] = now - startTime
 
+                self.resource_data["duration"] = timeTaken
+
                 with LOG_MUTEX:
                     self.log.info("TEST-%s | %s | test passed (time: %.3fms)" % ("PASS" if expected else "KNOWN-FAIL", name, timeTaken))
                     if self.verbose:
                         self.print_stdout(stdout)
+                    self.logResourceUsage()
 
                 self.xunit_result["passed"] = True
 
                 if expected:
                     self.passCount = 1
                 else:
                     self.todoCount = 1
                     self.xunit_result["todo"] = True
@@ -977,17 +1023,17 @@ class XPCShellTests(object):
     def runTests(self, xpcshell, xrePath=None, appPath=None, symbolsPath=None,
                  manifest=None, testdirs=None, testPath=None, mobileArgs=None,
                  interactive=False, verbose=False, keepGoing=False, logfiles=True,
                  thisChunk=1, totalChunks=1, debugger=None,
                  debuggerArgs=None, debuggerInteractive=False,
                  profileName=None, mozInfo=None, sequential=False, shuffle=False,
                  testsRootDir=None, xunitFilename=None, xunitName=None,
                  testingModulesDir=None, autolog=False, pluginsPath=None,
-                 testClass=XPCShellTestThread, **otherOptions):
+                 testClass=XPCShellTestThread, resource_usage=None, **otherOptions):
         """Run xpcshell tests.
 
         |xpcshell|, is the xpcshell executable to use to run the tests.
         |xrePath|, if provided, is the path to the XRE to use.
         |appPath|, if provided, is the path to an application directory.
         |symbolsPath|, if provided is the path to a directory containing
           breakpad symbols for processing crashes in tests.
         |manifest|, if provided, is a file containing a list of
@@ -1121,16 +1167,17 @@ class XPCShellTests(object):
 
         self.buildTestList()
 
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
@@ -1172,17 +1219,18 @@ class XPCShellTests(object):
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
 
         if sequential:
             self.log.info("INFO | Running tests sequentially.")
         else:
@@ -1271,16 +1319,20 @@ class XPCShellTests(object):
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
@@ -1347,16 +1399,19 @@ class XPCShellOptions(OptionParser):
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
 
 def main():
