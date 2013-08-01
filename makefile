# HG changeset patch
# Parent 6e0e87c13987dd1e0c56646ffb0ea574bf6ef800
# User Mihnea Dobrescu-Balaur <mihneadb@gmail.com>
Bug 898142 - xpcshell make target should pass in pluginsPath

diff --git a/testing/testsuite-targets.mk b/testing/testsuite-targets.mk
--- a/testing/testsuite-targets.mk
+++ b/testing/testsuite-targets.mk
@@ -280,16 +280,17 @@ xpcshell-tests:
 	$(PYTHON) -u $(topsrcdir)/config/pythonpath.py \
 	  -I$(DEPTH)/build \
 	  -I$(topsrcdir)/build \
 	  -I$(DEPTH)/_tests/mozbase/mozinfo \
 	  $(topsrcdir)/testing/xpcshell/runxpcshelltests.py \
 	  --manifest=$(DEPTH)/_tests/xpcshell/xpcshell.ini \
 	  --build-info-json=$(DEPTH)/mozinfo.json \
 	  --no-logfiles \
+	  --test-plugin-path="$(DIST)/plugins" \
 	  --tests-root-dir=$(call core_abspath,_tests/xpcshell) \
 	  --testing-modules-dir=$(call core_abspath,_tests/modules) \
 	  --xunit-file=$(call core_abspath,_tests/xpcshell/results.xml) \
 	  --xunit-suite-name=xpcshell \
           $(SYMBOLS_PATH) \
 	  $(TEST_PATH_ARG) $(EXTRA_TEST_ARGS) \
 	  $(LIBXUL_DIST)/bin/xpcshell
 
