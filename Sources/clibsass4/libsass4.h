/* This is hairier than it should be because Swift PM does not let you
   prepend include search paths and so an existing libsass installation
   always wins over a private one.

   These headers have mutual includes in them.  The order here, then,
   is vital to be such that the mutual includes always go backwards to
   files that exist in libsass3:
     sass.h
     sass/base.h
     sass/values.h
     sass/version.h

   Goes away entirely when there is a system libsass4 (or just 'libsass'
   by then)
*/
#include <libsass4/include/sass/base.h>
#include <libsass4/include/sass/enums.h>
#include <libsass4/include/sass/fwdecl.h>
#include <libsass4/include/sass/version.h>
#include <libsass4/include/sass/error.h>
#include <libsass4/include/sass/traces.h>
#include <libsass4/include/sass/values.h>
#include <libsass4/include/sass/import.h>
#include <libsass4/include/sass/importer.h>
#include <libsass4/include/sass/function.h>
#include <libsass4/include/sass/compiler.h>
#include <libsass4/include/sass/variable.h>
