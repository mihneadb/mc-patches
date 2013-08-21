# HG changeset patch
# Parent 1d6bf2bd4003d23f9f726d85d2e75f83d26eae2a
# User Mihnea Dobrescu-Balaur <mihneadb@gmail.com>
Bug 907455 - Enhance the xpcshell harness to provide per test resource usage data

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
@@ -451,16 +452,41 @@ class XPCShellTestThread(Thread):
 
             startTime = time.time()
             proc = self.launchProcess(completeCmd,
                 stdout=self.pStdout, stderr=self.pStderr, env=self.env, cwd=test_dir)
 
             if self.interactive:
                 self.log.info("TEST-INFO | %s | Process ID: %d" % (name, proc.pid))
 
+            # get process data (if available)
+            if HAVE_PSUTIL:
+                attrs = [
+                    'get_cpu_percent',
+                    'get_cpu_times',
+                    'get_ext_memory_info',
+                ]
+                # psutil does not support this on OS X :(
+                if mozinfo.os != 'mac':
+                    attrs.append('get_io_counters')
+
+                data = proc.as_dict(attrs=attrs, ad_value=None)
+                # convert psutil's own format to dicts
+                for k in data:
+                    if data[k] and '_asdict' in dir(data[k]):
+                        data[k] = data[k]._asdict()
+
+                # get test file path relative to $SRC_DIR
+                path = 'xpcshell'.join(name.split('xpcshell')[1:])
+                test_file = str(path[1:])
+                data['test_file'] = test_file
+
+                json_str = json.dumps(data, sort_keys=True, indent=4)
+                self.log.info("TEST-INFO | %s | Resource usage:\n%s" % (name, json_str))
+
             stdout, stderr = self.communicate(proc)
 
             if self.interactive:
                 # Not sure what else to do here...
                 self.keep_going = True
                 return
 
             if testTimer:
