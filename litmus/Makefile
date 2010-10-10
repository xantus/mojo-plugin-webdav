# litmus Makefile.  Generated from Makefile.in by configure.
SHELL = /bin/bash

# Installation directories
prefix = /usr/local
exec_prefix = ${prefix}
libexecdir = ${exec_prefix}/libexec
bindir = ${exec_prefix}/bin
datadir = ${datarootdir}
datarootdir = ${prefix}/share

# Toolchain settings
CC = gcc
CFLAGS = -g -O2 -I$(top_srcdir)/lib/neon
CPPFLAGS = -DHAVE_CONFIG_H  -D_LARGEFILE64_SOURCE -DNE_LFS  -I${top_builddir} -I$(top_srcdir)/lib -I$(top_srcdir)/src -I$(top_srcdir)/test-common

LDFLAGS = 
LIBS = -Llib/neon -lneon  -Wl,-Bsymbolic-functions -lgssapi_krb5 -lkrb5 -lk5crypto -lcom_err -lexpat 
# expat may be in LIBOBJS, so must come after $(LIBS) (which has -lneon)
ALL_LIBS = -L. -ltest $(LIBS) $(LIBOBJS)

top_builddir = .
top_srcdir = .



AR = /usr/bin/ar
RANLIB = /usr/bin/ranlib

LIBOBJS = 
TESTOBJS = src/common.o test-common/child.o test-common/tests.o
HDRS = src/common.h test-common/tests.h config.h

TESTS = basic copymove props locks http
HTDOCS = foo

URL = http://`hostname`/dav/
CREDS = `whoami` `whoami`
DIR = .
OPTS = 

INSTALL_PROGRAM = ${INSTALL}
INSTALL_DATA = ${INSTALL} -m 644
INSTALL = /usr/bin/install -c

# Fixme; use $(LIBOBJS) here instead. not happy on many non-GNU makes
# though; not sure why.
ODEPS = subdirs libtest.a 

all: $(TESTS)
	@echo
	@echo "  Now run:"
	@echo ""
	@echo '     make URL=http://dav.server/path/ check'
	@echo ' or  make URL=http://dav.server/path/ CREDS="uname passwd" check'
	@echo ""

litmus: litmus.in
	@./config.status $@

check: $(TESTS) litmus
	@test -d "$(DIR)" || mkdir "$(DIR)"
	@rm -f $(DIR)/debug.log $(DIR)/child.log
	@if test "$(DIR)" != "."; then echo "TESTS FOR $(DIR) ---"; fi
	@cd $(DIR) && TESTROOT="$(top_builddir)" HTDOCS="$(top_srcdir)/htdocs" \
	 $(top_builddir)/litmus $(OPTS) $(URL) $(CREDS)

install: $(TESTS) litmus 
	$(INSTALL) -d $(DESTDIR)$(bindir)
	$(INSTALL) -d $(DESTDIR)$(libexecdir)/litmus
	$(INSTALL) -d $(DESTDIR)$(datadir)/litmus/htdocs
	$(INSTALL_PROGRAM) $(top_builddir)/litmus $(DESTDIR)$(bindir)/litmus
	for t in $(TESTS); do \
	  $(INSTALL_PROGRAM) $(top_builddir)/$$t $(DESTDIR)$(libexecdir)/litmus/$$t; done
	for d in $(HTDOCS); do \
	  $(INSTALL_DATA) $(top_srcdir)/htdocs/$$d $(DESTDIR)$(datadir)/litmus/htdocs/$d; done

props: src/props.o $(ODEPS)
	$(CC) $(LDFLAGS) -o $@ src/props.o $(ALL_LIBS)

basic: src/basic.o $(ODEPS)
	$(CC) $(LDFLAGS) -o $@ src/basic.o $(ALL_LIBS)

copymove: src/copymove.o $(ODEPS)
	$(CC) $(LDFLAGS) -o $@ src/copymove.o $(ALL_LIBS)

locks: src/locks.o $(ODEPS)
	$(CC) $(LDFLAGS) -o $@ src/locks.o $(ALL_LIBS)

http: src/http.o $(ODEPS)
	$(CC) $(LDFLAGS) -o $@ src/http.o $(ALL_LIBS)

largefile: src/largefile.o $(ODEPS)
	$(CC) $(LDFLAGS) -o $@ src/largefile.o $(ALL_LIBS)

subdirs:
	@cd lib/neon && $(MAKE)

libtest.a: $(TESTOBJS)
	$(AR) cru $@ $(TESTOBJS)
	$(RANLIB) $@

clean:	
	@cd lib/neon && $(MAKE) clean
	rm -f */*.o $(TESTS) largefile libtest.a *~ debug.log child.log

distclean: clean
	@cd lib/neon && $(MAKE) distclean
	rm Makefile litmus config.log config.h config.status

.c.o:
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

Makefile: $(top_srcdir)/Makefile.in
	./config.status Makefile

src/basic.o: src/basic.c $(HDRS)
src/common.o: src/common.c $(HDRS)
src/copymove.o: src/copymove.c $(HDRS)
src/locks.o: src/locks.c $(HDRS)
src/props.o: src/props.c $(HDRS)
src/http.o: src/http.c $(HDRS)
src/largefile.o: src/largefile.c $(HDRS)
