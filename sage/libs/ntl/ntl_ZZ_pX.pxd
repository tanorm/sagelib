include "../../ext/cdefs.pxi"

from ntl_ZZ_pX_decl cimport *, ZZ_pX_c, ZZ_pX_Modulus_c
from sage.libs.ntl.ntl_ZZ_pContext cimport ntl_ZZ_pContext_class

cdef class ntl_ZZ_pX:
    cdef ZZ_pX_c x
    cdef ntl_ZZ_pContext_class c
    cdef void setitem_from_int(ntl_ZZ_pX self, long i, int value)
    cdef int getitem_as_int(ntl_ZZ_pX self, long i)
    cdef ntl_ZZ_pX _new(self)

cdef class ntl_ZZ_pX_Modulus:
    cdef ZZ_pX_Modulus_c x
    cdef ntl_ZZ_pX poly
