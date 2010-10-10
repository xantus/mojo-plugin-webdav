#
# neon source directory Makefile
# 
# Use the NEON_NORMAL_BUILD or NEON_LIBTOOL_BUILD autoconf 
# macros to set up this Makefile correctly.
#

SHELL = /bin/bash

# Installation paths
prefix = /usr/local
exec_prefix = ${prefix}
libdir = ${exec_prefix}/lib

# Build paths

top_builddir = ../..
top_srcdir = ../..

# Toolchain settings.
CC = gcc
AR = /usr/bin/ar
RANLIB = /usr/bin/ranlib
LIBTOOL = @LIBTOOL@

# Flags
CPPFLAGS = -DHAVE_CONFIG_H  -D_LARGEFILE64_SOURCE -DNE_LFS  -I${top_builddir} -I$(top_srcdir)/lib
CFLAGS = -g -O2 -I$(top_srcdir)/lib/neon
LDFLAGS = 
NEON_LINK_FLAGS = 
# Note: don't substitute  in here; during a bundled
# build of this directory,  may include -lneon.
LIBS = -Llib/neon -lneon  -Wl,-Bsymbolic-functions -lgssapi_krb5 -lkrb5 -lk5crypto -lcom_err -lexpat 

COMPILE = $(CC) $(CPPFLAGS) $(CFLAGS)
LINK = $(LIBTOOL) --quiet --mode=link $(CC) -no-undefined $(LDFLAGS)

NEON_BASEOBJS = ne_request.o ne_session.o 	    \
	ne_basic.o  ne_string.o 		    \
	ne_uri.o ne_dates.o ne_alloc.o  \
	ne_md5.o ne_utils.o    \
	ne_socket.o ne_auth.o 			    \
	ne_redirect.o ne_compress.o		    \
	ne_i18n.o ne_pkcs11.o

NEON_DAVOBJS = $(NEON_BASEOBJS) \
	ne_207.o ne_xml.o \
	ne_props.o ne_locks.o \
	ne_xmlreq.o

OBJECTS =  $(NEON_DAVOBJS)  ne_stubssl.o

.SUFFIXES:
.SUFFIXES: .c .lo .o

NEON_TARGET = libneon.a

# Thanks to gettext for this neat trick.
all: all-yes

all-yes: $(NEON_TARGET)
all-no:
	@echo "Bundled neon build not being used."

.c.lo:
	$(LIBTOOL) --quiet --mode=compile $(COMPILE) -c $< -o $@
.c.o:
	$(COMPILE) -c $< -o $@

libneon.la: $(OBJECTS)
	$(LINK) -rpath $(libdir) $(NEON_LINK_FLAGS) -o $@ $(OBJECTS) $(LIBS)

libneon.a: $(OBJECTS)
	@rm -f $@
	$(AR) cru $@ $(OBJECTS)
	$(RANLIB) $@

clean:
	rm -f $(NEON_TARGET) *.o *.lo *.bbg *.bb *.gc*
	rm -rf .libs

c++.c:
	find . -name ne_\*.h -print | sed 's/.*/#include "&"/;/ne_priv/d' > $@
	echo "int main(void) {}" >> $@

check-c++: c++.c
	c++ -I. c++.c

check-incl:
	@for f in ne_*.h; do \
	 echo Checking $$f...; \
	 echo "#include \"$$f\"" > checkincl.c; \
	 $(COMPILE) -c checkincl.c -o checkincl.o || exit 1; done

# Update generated dependencies below; requires cc -MM as in gcc.
update-deps:
	for f in `echo $(OBJECTS) | sed 's/\\.o/.c/g'`; do \
	  $(CC) $(CPPFLAGS) -MM -c $$f; \
	done | sed 's, \.\./, $$(top_builddir)/,g;s, /[^ ]*.h,,g;/^  .$$/d;s/\.o: /.@NEON''_OBJEXT@: /' > new-deps
	sed '/[-]--CUT---/q' Makefile.in > Makefile.new
	cat Makefile.new new-deps > Makefile.in
	rm new-deps Makefile.new

#### ---CUT--- DO NOT REMOVE THIS LINE.  Generated dependencies follow.  ####
ne_request.o: ne_request.c $(top_builddir)/config.h ne_internal.h ne_defs.h ne_alloc.h \
  ne_request.h ne_utils.h ne_string.h ne_session.h ne_ssl.h ne_uri.h \
  ne_socket.h ne_private.h ne_pkcs11.h
ne_session.o: ne_session.c $(top_builddir)/config.h ne_session.h ne_ssl.h ne_defs.h \
  ne_uri.h ne_socket.h ne_alloc.h ne_utils.h ne_internal.h ne_string.h \
  ne_dates.h ne_private.h ne_request.h ne_pkcs11.h
ne_basic.o: ne_basic.c $(top_builddir)/config.h ne_request.h ne_utils.h ne_defs.h \
  ne_string.h ne_alloc.h ne_session.h ne_ssl.h ne_uri.h ne_socket.h \
  ne_basic.h ne_207.h ne_xml.h ne_locks.h ne_dates.h ne_internal.h
ne_string.o: ne_string.c $(top_builddir)/config.h ne_alloc.h ne_defs.h ne_string.h
ne_uri.o: ne_uri.c $(top_builddir)/config.h ne_string.h ne_defs.h ne_alloc.h ne_uri.h
ne_dates.o: ne_dates.c $(top_builddir)/config.h ne_alloc.h ne_defs.h ne_dates.h \
  ne_string.h
ne_alloc.o: ne_alloc.c $(top_builddir)/config.h ne_alloc.h ne_defs.h
ne_md5.o: ne_md5.c $(top_builddir)/config.h ne_md5.h ne_defs.h ne_string.h ne_alloc.h
ne_utils.o: ne_utils.c $(top_builddir)/config.h ne_utils.h ne_defs.h ne_string.h \
  ne_alloc.h ne_dates.h
ne_socket.o: ne_socket.c $(top_builddir)/config.h ne_privssl.h ne_ssl.h ne_defs.h \
  ne_socket.h ne_internal.h ne_utils.h ne_string.h ne_alloc.h ne_sspi.h
ne_auth.o: ne_auth.c $(top_builddir)/config.h ne_md5.h ne_defs.h ne_dates.h \
  ne_request.h ne_utils.h ne_string.h ne_alloc.h ne_session.h ne_ssl.h \
  ne_uri.h ne_socket.h ne_auth.h ne_internal.h
ne_redirect.o: ne_redirect.c $(top_builddir)/config.h ne_session.h ne_ssl.h ne_defs.h \
  ne_uri.h ne_socket.h ne_request.h ne_utils.h ne_string.h ne_alloc.h \
  ne_redirect.h ne_internal.h
ne_compress.o: ne_compress.c $(top_builddir)/config.h ne_request.h ne_utils.h \
  ne_defs.h ne_string.h ne_alloc.h ne_session.h ne_ssl.h ne_uri.h \
  ne_socket.h ne_compress.h ne_internal.h
ne_i18n.o: ne_i18n.c $(top_builddir)/config.h ne_i18n.h ne_defs.h
ne_pkcs11.o: ne_pkcs11.c $(top_builddir)/config.h ne_pkcs11.h ne_defs.h ne_session.h \
  ne_ssl.h ne_uri.h ne_socket.h
ne_207.o: ne_207.c $(top_builddir)/config.h ne_alloc.h ne_defs.h ne_utils.h ne_xml.h \
  ne_207.h ne_request.h ne_string.h ne_session.h ne_ssl.h ne_uri.h \
  ne_socket.h ne_basic.h ne_internal.h
ne_xml.o: ne_xml.c $(top_builddir)/config.h ne_internal.h ne_defs.h ne_alloc.h \
  ne_xml.h ne_utils.h ne_string.h
ne_props.o: ne_props.c $(top_builddir)/config.h ne_alloc.h ne_defs.h ne_xml.h \
  ne_props.h ne_request.h ne_utils.h ne_string.h ne_session.h ne_ssl.h \
  ne_uri.h ne_socket.h ne_207.h ne_basic.h ne_locks.h ne_internal.h
ne_locks.o: ne_locks.c $(top_builddir)/config.h ne_alloc.h ne_defs.h ne_request.h \
  ne_utils.h ne_string.h ne_session.h ne_ssl.h ne_uri.h ne_socket.h \
  ne_xml.h ne_locks.h ne_basic.h ne_props.h ne_207.h ne_internal.h \
  ne_xmlreq.h
ne_xmlreq.o: ne_xmlreq.c $(top_builddir)/config.h ne_internal.h ne_defs.h ne_xmlreq.h \
  ne_request.h ne_utils.h ne_string.h ne_alloc.h ne_session.h ne_ssl.h \
  ne_uri.h ne_socket.h ne_xml.h ne_basic.h
ne_acl.o: ne_acl.c $(top_builddir)/config.h ne_request.h ne_utils.h ne_defs.h \
  ne_string.h ne_alloc.h ne_session.h ne_ssl.h ne_uri.h ne_socket.h \
  ne_locks.h ne_acl.h ne_xml.h
ne_openssl.o: ne_openssl.c $(top_builddir)/config.h ne_ssl.h ne_defs.h ne_string.h \
  ne_alloc.h ne_session.h ne_uri.h ne_socket.h ne_internal.h ne_private.h \
  ne_request.h ne_utils.h ne_pkcs11.h ne_privssl.h
