#*****************************************************************************
#       Copyright (C) 2005 William Stein <wstein@gmail.com>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#
#    This code is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    General Public License for more details.
#
#  The full text of the GPL is available at:
#
#                  http://www.gnu.org/licenses/
#*****************************************************************************

include "../../ext/interrupt.pxi"
include "../../ext/stdsage.pxi"
include 'misc.pxi'
include 'decl.pxi'

ZZ_pEContextDict = {}

from sage.libs.ntl.ntl_ZZ_pX cimport ntl_ZZ_pX
from sage.libs.ntl.ntl_ZZ_pContext import ntl_ZZ_pContext
from sage.libs.ntl.ntl_ZZ cimport ntl_ZZ

cdef class ntl_ZZ_pEContext_class:
    def __init__(self, ntl_ZZ_pX f):
        """
        EXAMPLES:
            # You can construct contexts manually.
            sage: c=ntl.ZZ_pEContext(ntl.ZZ_pX([4,1,6],25))
            sage: n1=c.ZZ_pE([10,17,12])
            sage: n1
            [2 15]

            # or You can construct contexts implicitly.
            sage: n2=ntl.ZZ_pE(12, ntl.ZZ_pX([1,1,1],7))
            sage: n2
            [5]
            sage: n2+n1  # Mismatched moduli:  It will go BOOM!
            Traceback (most recent call last):
            ...
            ValueError: You can not perform arithmetic with elements of different moduli.
        """
        pass
        
    def __cinit__(self, ntl_ZZ_pX f):
        self.pc = f.c
        self.pc.restore_c()
        ZZ_pEContext_construct_ZZ_pX(&self.x, &f.x)
        ZZ_pEContextDict[(repr(f),repr(f.c.p))] = self
        self.f = f

    def __dealloc__(self):
        ZZ_pEContext_destruct(&self.x)

    def __reduce__(self):
        """
        sage: c=ntl.ZZ_pEContext(ntl.ZZ_pX([1,1,1],7))
        sage: loads(dumps(c)) is c
        True
        """
        return ntl_ZZ_pEContext, (self.f,)

    def __repr__(self):
        """
        Returns a string representation of self.

        EXAMPLES:
        sage: c = ntl.ZZ_pEContext(ntl.ZZ_pX([1,1,1], 7)); c
        NTL modulus [1 1 1] (mod 7)
        """
        return "NTL modulus %s (mod %s)"%(self.f, self.pc.p)

    def get_pc(self):
        """
        Returns the ZZ_pContext contained within self.

        EXAMPLES:
        sage: c = ntl.ZZ_pEContext(ntl.ZZ_pX([1,1,1], 7)); c
        NTL modulus [1 1 1] (mod 7)
        sage: c.get_pc()
        NTL modulus 7
        """
        return self.pc

    def polynomial(self):
        """
        Returns the ZZ_pX polynomial defining self.

        EXAMPLES:
        sage: c = ntl.ZZ_pEContext(ntl.ZZ_pX([1,1,1], 7))
        sage: c.polynomial()
        [1 1 1]
        """
        return self.f

    def restore(self):
        """
        Manually sets the global NTL modulus to be self.

        This should be done automatically by all of the NTL wrapper classes.

        CRUCIAL: If you are writing your own classes that use ZZ_p_c, ZZ_pX_c, ZZ_pE_c, ZZ_pEX_c
        then you MUST restore the context before calling off to NTL for anything.  If the context has been
        switched by other code then behavior of operations is undefined.  See the NTL documentation for
        more details (or the wrappers in sage.libs.ntl)
        """
        self.restore_c()

    cdef void restore_c(self):
        """
        Sets the global NTL modulus to be self.

        CRUCIAL: If you are writing your own classes that use ZZ_p_c, ZZ_pX_c, ZZ_pE_c, ZZ_pEX_c
        then you MUST restore the context before calling off to NTL for anything.  If the context has been
        switched by other code then behavior of operations is undefined.  See the NTL documentation for
        more details (or the wrappers in sage.libs.ntl)
        """
        self.pc.restore_c()
        ZZ_pEContext_restore(&self.x)

    #def ZZ_pX(self,v = None):
    #    from ntl_ZZ_pX import ntl_ZZ_pX
    #    return ntl_ZZ_pX(v,modulus=self)

    def ZZ_pE(self,v = None):
        """
        Returns a ZZ_pE object with modulus self out of the data v.

        EXAMPLES:
        sage: c = ntl.ZZ_pEContext(ntl.ZZ_pX([1,1,1], 7))
        sage: c.ZZ_pE([4,3])
        [4 3]
        """        
        from ntl_ZZ_pE import ntl_ZZ_pE
        return ntl_ZZ_pE(v,modulus=self)

    def ZZ_pEX(self, v = None):
        """
        Returns a ZZ_pE object with modulus self out of the data v.

        EXAMPLES:
        sage: c = ntl.ZZ_pEContext(ntl.ZZ_pX([1,1,1], 7))
        sage: c.ZZ_pEX([4,3])
        [[4] [3]]
        """        
        from ntl_ZZ_pEX import ntl_ZZ_pEX
        return ntl_ZZ_pEX(v, modulus=self)
        
def ntl_ZZ_pEContext( ntl_ZZ_pX f):
    """
    Creates an ntl_ZZ_pEContext.

    Such an object must be created before any ZZ_pE or ZZ_pEX objects can be used.

    The context handling should be taken care of by the wrapper classes.
    EXAMPLES:
    sage: c = ntl.ZZ_pEContext(ntl.ZZ_pX([1,1,1], 7)); c
    NTL modulus [1 1 1] (mod 7)
    """
    try:
        return ZZ_pEContextDict[repr(f), repr(f.c.p)]
    except KeyError:
        # Creating the following object caches it.
        return ntl_ZZ_pEContext_class(f)
