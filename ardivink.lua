oasis = require("oasis")
darcs = require("darcs")
ci = require("ci")
dist = require("dist")

ci.init()
oasis.init()
darcs.init()

ci.prependenv("PATH", "/usr/opt/godi/bin")
ci.prependenv("PATH", "/usr/opt/godi/sbin")
ci.putenv("OUNIT_OUTPUT_HTML_DIR", dist.make_filename("ounit-log.html"))
ci.putenv("OUNIT_OUTPUT_JUNIT_FILE", dist.make_filename("junit.xml"))
ci.putenv("OUNIT_OUTPUT_FILE", dist.make_filename("ounit-log.txt"))

oasis.std_process("--enable-tests")
darcs.create_tag(oasis.package_version())

-- Create documentation package.
ci.exec("make", "doc-dev-dist")
