#
# uCsim  simulator Makefile
#
# (c) Drotos Daniel, Talker Bt. 1997
#

srcdir          = .

top_builddir	= ../../..
top_srcdir	= ../../..

include $(srcdir)/objs.mk
include ../../common.mk


# Compiling entire program or any subproject
# ------------------------------------------
all: $(LEN)

include $(top_srcdir)/src/app.mk

local_install:
	$(INSTALL) $(LEN) $(DESTDIR)$(bindir)/ucsim_i8051$(EXEEXT)
	$(STRIP) $(DESTDIR)$(bindir)/ucsim_i8051$(EXEEXT)
	$(INSTALL) $(LEN) $(DESTDIR)$(bindir)/s51$(EXEEXT)
	$(STRIP) $(DESTDIR)$(bindir)/s51$(EXEEXT)

local_uninstall:
	rm -f $(DESTDIR)$(bindir)/ucsim_i8051$(EXEEXT)
	rm -f $(DESTDIR)$(bindir)/s51$(EXEEXT)


# End of simulator Makefile

# STC12 differential trace binary (appended from Makefile.in)
TRACE_OBJS = stc12_trace.o $(filter-out s51.o,$(OBJECTS))

stc12_trace: $(TRACE_OBJS) $(UCSIM_LIB_PREREQUES)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(TRACE_OBJS) -L$(top_builddir) $(UCSIM_LIBS) -o $@
