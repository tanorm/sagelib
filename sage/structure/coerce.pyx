#*****************************************************************************
#       Copyright (C) 2007 Robert Bradshaw <robertwb@math.washington.edu>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#
#                  http://www.gnu.org/licenses/
#*****************************************************************************


include "../ext/stdsage.pxi"
include "../ext/python_tuple.pxi"
include "coerce.pxi"

import operator
import re
import time

import sage.categories.morphism

cdef class CoercionModel_original(CoercionModel):
    """
    This is the original coercion model, as of SAGE 2.6 (2007-06-02)
    """
    
    cdef canonical_coercion_c(self, x, y):
        cdef int i
        xp = parent_c(x)
        yp = parent_c(y)
        if xp is yp:
            return x, y

        if PY_IS_NUMERIC(x):
            try:
                x = yp(x)
            except TypeError:
                y = x.__class__(y)
                return x, y
            # Calling this every time incurs overhead -- however, if a mistake
            # gets through then one can get infinite loops in C code hence core
            # dumps.  And users define _coerce_ and __call__ for rings, which
            # can easily have bugs in it, i.e., not really make the element
            # have the correct parent.  Thus this check is *crucial*.
            return _verify_canonical_coercion_c(x,y)
        
        elif PY_IS_NUMERIC(y):
            try:
                y = xp(y)
            except TypeError:
                x = y.__class__(x)
                return x, y            
            return _verify_canonical_coercion_c(x,y)

        try:
            if xp.has_coerce_map_from(yp):
                y = (<Parent>xp)._coerce_c(y)
                return _verify_canonical_coercion_c(x,y)
        except AttributeError:
            pass
        try:
            if yp.has_coerce_map_from(xp):
                x = (<Parent>yp)._coerce_c(x)
                return _verify_canonical_coercion_c(x,y)
        except AttributeError:
            pass
        raise TypeError, "no common canonical parent for objects with parents: '%s' and '%s'"%(xp, yp)

    cdef canonical_base_coercion_c(self, Element x, Element y):
        if not have_same_base(x, y):
            if (<Parent> x._parent._base).has_coerce_map_from_c(y._parent._base):
                # coerce all elements of y to the base ring of x
                y = y.base_extend_c(x._parent._base)
            elif (<Parent> y._parent._base).has_coerce_map_from_c(x._parent._base):
                # coerce x to have elements in the base ring of y
                x = x.base_extend_c(y._parent._base)
        return x,y

    def canonical_base_coercion(self, x, y):
        try:
            xb = x.base_ring()
        except AttributeError:
            #raise TypeError, "unable to find base ring for %s (parent: %s)"%(x,x.parent())
            raise TypeError, "unable to find base ring"
        try:
            yb = y.base_ring()
        except AttributeError:
            raise TypeError, "unable to find base ring"
            #raise TypeError, "unable to find base ring for %s (parent: %s)"%(y,y.parent())
        try:
            b = self.canonical_coercion_c(xb(0),yb(0))[0].parent()
        except TypeError:
            raise TypeError, "unable to find base ring"
            #raise TypeError, "unable to find a common base ring for %s (base ring: %s) and %s (base ring %s)"%(x,xb,y,yb)
        return x.change_ring(b), y.change_ring(b)


    cdef bin_op_c(self, x, y, op):
        """
        Compute x op y, where coercion of x and y works according to
        SAGE's coercion rules.
        """
        # Try canonical element coercion.
        try:
            x1, y1 = self.canonical_coercion_c(x, y)
            return op(x1,y1)        
        except TypeError, msg:
            # print msg  # this can be useful for debugging.
            if not op is operator.mul:
                raise TypeError, arith_error_message(x,y,op)

        # If the op is multiplication, then some other algebra multiplications
        # may be defined
        
        # 2. Try scalar multiplication.
        # No way to multiply x and y using the ``coerce into a canonical
        # parent'' rule.
        # The next rule to try is scalar multiplication by coercing
        # into the base ring.
        cdef bint x_is_modelt, y_is_modelt

        y_is_modelt = PY_TYPE_CHECK(y, ModuleElement)
        if y_is_modelt:
            # First try to coerce x into the base ring of y if y is an element.
            try:
                R = (<ModuleElement> y)._parent._base 
                if R is None:
                    raise RuntimeError, "base of '%s' must be set to a ring (but it is None)!"%((<ModuleElement> y)._parent)
                x = (<Parent>R)._coerce_c(x)
                return (<ModuleElement> y)._rmul_c(x)     # the product x * y
            except TypeError, msg:
                pass

        x_is_modelt = PY_TYPE_CHECK(x, ModuleElement)
        if x_is_modelt:
            # That did not work.  Try to coerce y into the base ring of x.
            try:
                R = (<ModuleElement> x)._parent._base 
                if R is None:
                    raise RuntimeError, "base of '%s' must be set to a ring (but it is None)!"%((<ModuleElement> x)._parent)            
                y = (<Parent> R)._coerce_c(y)
                return (<ModuleElement> x)._lmul_c(y)    # the product x * y
            except TypeError:
                pass

        if y_is_modelt and x_is_modelt:
            # 3. Both canonical coercion failed, but both are module elements.
            # Try base extending the right object by the parent of the left

            ## TODO -- WORRY -- only unambiguous if one succeeds!
            if  PY_TYPE_CHECK(x, RingElement):
                try:
                    return x * y.base_extend((<RingElement>x)._parent)
                except (TypeError, AttributeError), msg:
                    pass
            # Also try to base extending the left object by the parent of the right
            if  PY_TYPE_CHECK(y, RingElement):
                try:
                    return y * x.base_extend((<Element>y)._parent)
                except (TypeError, AttributeError), msg:
                    pass

        # 4. Try _l_action or _r_action.
        # Test to see if an _r_action or _l_action is
        # defined on either side.
        try:
            return x._l_action(y)
        except (AttributeError, TypeError):    
            pass
        try:
            return y._r_action(x)
        except (AttributeError, TypeError):
            pass
            
        raise TypeError, arith_error_message(x,y,op)
        

# just so we can detect these fast to avoid action-searching
cdef op_add, op_sub
from operator import add as op_add, sub as op_sub

cdef class CoercionModel_cache_maps(CoercionModel_original):
    """
    See also sage.categories.pushout
    
    EXAMPLES:
        sage: f = ZZ['t','x'].0 + QQ['x'].0 + CyclotomicField(13).gen(); f
        t + x + zeta13
        sage: f.parent()
        Polynomial Ring in t, x over Cyclotomic Field of order 13 and degree 12
        sage: ZZ['x','y'].0 + ~Frac(QQ['y']).0
        (x*y + 1)/y
        sage: MatrixSpace(ZZ['x'], 2, 2)(2) + ~Frac(QQ['x']).0
        [(2*x + 1)/x           0]
        [          0 (2*x + 1)/x]
        sage: f = ZZ['x,y,z'].0 + QQ['w,x,z,a'].0; f
        w + x
        sage: f.parent()
        Polynomial Ring in w, x, y, z, a over Rational Field
        sage: ZZ['x,y,z'].0 + ZZ['w,x,z,a'].1
        2*x
        
    AUTHOR: 
        -- Robert Bradshaw
    """

    def __init__(self):
        # This MUST be a mapping of tuples, where each 
        # tuple contains at least two elements that are either
        # None or of type Morphism. 
        self._coercion_maps = {}
        # This MUST be a mapping of actions. 
        self._action_maps = {}
        
    cdef bin_op_c(self, x, y, op):
        
        if (op is not op_add) and (op is not op_sub):
            # Actions take preference over common-parent coercions.
            xp = parent_c(x)
            yp = parent_c(y)
            if xp is yp:
                return op(x,y)
            action = self.get_action_c(xp, yp, op)
            if action is not None:
                return (<Action>action)._call_c(x, y)
        
        try:
            xy = self.canonical_coercion_c(x,y)
            return op(<object>PyTuple_GET_ITEM(xy, 0), <object>PyTuple_GET_ITEM(xy, 1))
        except TypeError:
#            raise
            pass

        if op is operator.mul:
                
            # elements may also act on non-elements
            # (e.g. sequences or parents)
            try:
                return x._l_action(y)
            except (AttributeError, TypeError):    
                pass
            try:
                return y._r_action(x)
            except (AttributeError, TypeError):
                pass
        
        raise TypeError, arith_error_message(x,y,op)


        
    cdef canonical_coercion_c(self, x, y):
        xp = parent_c(x)
        yp = parent_c(y)
        if xp is yp:
            return x,y
            
        cdef Element x_elt, y_elt
        coercions = self.coercion_maps_c(xp, yp)
        if coercions is not None:
            x_map, y_map = coercions
            if x_map is not None:
                x_elt = (<Morphism>x_map)._call_c(x)
            else:
                x_elt = x
            if y_map is not None:
                y_elt = (<Morphism>y_map)._call_c(y)
            else:
                y_elt = y
            if x_elt._parent is y_elt._parent:
                # We must verify this as otherwise we are prone to 
                # getting into an infinite loop in c, and the above
                # morphisms may be written by (imperfect) users. 
                return x_elt,y_elt
            elif x_elt._parent == y_elt._parent:
                # TODO: Non-uniqueness of parents strikes again! 
                # print parent_c(x_elt), " is not ", parent_c(y_elt)
                y_elt = parent_c(x_elt)(y_elt)
                if x_elt._parent is y_elt._parent:
                    return x_elt,y_elt
            self._coercion_error(x, x_map, x_elt, y, y_map, y_elt)
        
        # Now handle the native python + sage object cases
        # that were not taken care of above. 
        elif PY_IS_NUMERIC(x):
            try:
                x = yp(x)
                if PY_TYPE_CHECK(yp, type): return x,y
            except TypeError:
                y = x.__class__(y)
                return x, y
            return _verify_canonical_coercion_c(x,y)

        elif PY_IS_NUMERIC(y):
            try:
                y = xp(y)
                if PY_TYPE_CHECK(xp, type): return x,y
            except TypeError:
                x = y.__class__(x)
                return x, y            
            return _verify_canonical_coercion_c(x,y)
            
        raise TypeError, "no common canonical parent for objects with parents: '%s' and '%s'"%(xp, yp)
        

    def _coercion_error(self, x, x_map, x_elt, y, y_map, y_elt):
        raise RuntimeError, """There is a bug in the coercion code in SAGE.
Both x (=%r) and y (=%r) are supposed to have identical parents but they don't.
In fact, x has parent '%s'
whereas y has parent '%s'

Original elements %r (parent %s) and %r (parent %s) and morphisms
%s %r
%s %r"""%( x_elt, y_elt, parent_c(x_elt), parent_c(y_elt),
            x, parent_c(x), y, parent_c(y),
            type(x_map), x_map, type(y_map), y_map)
    
    def coercion_maps(self, R, S):
        return self.coercion_maps_c(R, S)
    
    cdef coercion_maps_c(self, R, S):
        try:
            return self._coercion_maps[R,S]
        except KeyError:
            homs = self.discover_coercion_c(R, S)
            if homs is not None:
                self._coercion_maps[R,S] = homs
                self._coercion_maps[S,R] = (homs[1], homs[0])
            else:
                self._coercion_maps[R,S] = self._coercion_maps[S,R] = None
            return homs
    
    def get_action(self, R, S, op):
        return self.get_action_c(R, S, op)
    
    cdef get_action_c(self, R, S, op):
        try:
            return self._action_maps[R,S,op]
        except KeyError:
            action = self.discover_action_c(R, S, op)
            self._action_maps[R,S,op] = action
            return action
    
    cdef discover_coercion_c(self, R, S):
        from sage.categories.homset import Hom
        if R is S:
            return None, None
            
        # See if there is a natural coercion from R to S
        if PY_TYPE_CHECK(R, Parent):
            mor = (<Parent>R).coerce_map_from_c(S)
            if mor is not None:
                return None, mor

        # See if there is a natural coercion from S to R
        if PY_TYPE_CHECK(S, Parent):
            mor = (<Parent>S).coerce_map_from_c(R)
            if mor is not None:
                return mor, None
        
        # Try base extending
        if PY_TYPE_CHECK(R, Parent) and PY_TYPE_CHECK(S, Parent):
            from sage.categories.pushout import pushout
            try:
                Z = pushout(R, S)
                from sage.categories.homset import Hom
                # Can I trust always __call__() to do the right thing in this case? 
                return sage.categories.morphism.CallMorphism(Hom(R, Z)), sage.categories.morphism.CallMorphism(Hom(S, Z))
            except:
                pass

        return None
        
    
    cdef discover_action_c(self, R, S, op):

        if PY_TYPE_CHECK(S, Parent):
            action = (<Parent>S).get_action_c(R, op, False)
            if action is not None:
#                print "found", action
                return action
    
        if PY_TYPE_CHECK(R, Parent):
            action = (<Parent>R).get_action_c(S, op, True)
            if action is not None:
#                print "found", action
                return action
        
        if op is operator.div:
            # Division on right is the same acting on right by inverse, if it is so defined. 
            # To return such an action, we need to verify that it would be an action for the mul
            # operator, but the action must be over a parent containing inverse elements. 
            from sage.rings.ring import is_Ring
            if is_Ring(S):
                try:
                    K = S.fraction_field()
                except TypeError:
                    K = None
            else:
                K = S
                
            if K is not None:            
                if PY_TYPE_CHECK(S, Parent) and (<Parent>S).get_action_c(R, operator.mul, False) is not None:
                    action = (<Parent>K).get_action_c(R, operator.mul, False)
                    if action is not None and action.actor() is K:
                        try:
                            return ~action
                        except TypeError:
                            pass
                            
                if PY_TYPE_CHECK(R, Parent) and (<Parent>R).get_action_c(S, operator.mul, True) is not None:
                    action = (<Parent>R).get_action_c(K, operator.mul, True)
                    if action is not None and action.actor() is K:
                        try:
                            return ~action
                        except TypeError:
                            pass
                            
    

cdef class CoercionModel_profile(CoercionModel_cache_maps):
    """
    This is a subclass of CoercionModel_cache_maps that can be used
    to inspect and profile implicit coercions. 

    EXAMPLE: 
        sage: from sage.structure.coerce import CoercionModel_profile
        sage: from sage.structure.element import set_coercion_model
        sage: coerce = CoercionModel_profile()
        sage: set_coercion_model(coerce)
        sage: 2 + 1/2
        5/2
        sage: coerce.profile() # random timings
        1    0.00015    Integer Ring    -->    Rational Field    Rational Field
        
    This shows that one coercion was performed, from $\Z$ to $\Q$ (with the result in $\Q$)
    and it took 0.00015 seconds. 
    
        sage: R.<x> = ZZ[]
        sage: coerce.flush()
        sage: 1/2 * x + .5
        0.500000000000000*x + 0.500000000000000
        sage: coerce.profile()    # random timings
        1    0.00279    *    Rational Field    A->    Univariate Polynomial Ring in x over Integer Ring    Univariate Polynomial Ring in x over Rational Field
        1    0.00135         Univariate Polynomial Ring in x over Rational Field    <->    Real Field with 53 bits of precision    Univariate Polynomial Ring in x over Real Field with 53 bits of precision
        10   0.00013         <type 'int'>    -->    Rational Field    Rational Field
        6    0.00011         <type 'int'>    -->    Real Field with 53 bits of precision    Real Field with 53 bits of precision
        
    We can read of this data that the most expensive operation was the creation 
    of the action of $\Q$ on $\Z[x]$ (whose result lies in $\Q[x]$. This has
    been cached as illistrated below. 
    
        sage: coerce.flush()
        sage: z = 1/2 * x + .5
        sage: coerce.profile()     # more random timings
        1    0.00020         Univariate Polynomial Ring in x over Rational Field    <->    Real Field with 53 bits of precision    Univariate Polynomial Ring in x over Real Field with 53 bits of precision
        5    0.00005         <type 'int'>    -->    Rational Field    Rational Field
        1    0.00004    *    Rational Field    A->    Univariate Polynomial Ring in x over Integer Ring    Univariate Polynomial Ring in x over Rational Field
        

    NOTE: 
       - profiles are indexable and sliceable. 
       - they also have a nice latex view (with much less verbose ring descriptors), use the show(...) command. 
    
    """
    def __init__(self, timer=time.time):
        CoercionModel_cache_maps.__init__(self)
        self.profiling_info = {}
        self.timer = timer
    
    
    cdef get_action_c(self, xp, yp, op):
        time = self.timer()
        action = CoercionModel_cache_maps.get_action_c(self, xp, yp, op)
        time = self.timer() - time
        if action is not None:
            self._log_time(xp, yp, op, time, action)
        return action
        
    cdef canonical_coercion_c(self, x, y):
        time = self.timer()
        xy = CoercionModel_cache_maps.canonical_coercion_c(self, x, y)
        time = self.timer() - time
        self._log_time(parent_c(x), parent_c(y), 'coerce', time, parent_c(xy[0]))
        return xy
            
    cdef void _log_time(self, xp, yp, op, time, data):
        if op == "coerce":
            # consolidate symmetric cases
            if data is xp:
                xp,yp = yp,xp
            if data is not yp and xp > yp:
                xp,yp = yp,xp
                
        try:
            timing = self.profiling_info[xp, yp, op]
        except KeyError:
            timing = [0, 0, time, data]
            self.profiling_info[xp, yp, op] = timing
        timing[0] += 1
        timing[1] += time
    
    def flush(self):
        self.profiling_info = {}

    def profile(self, filter=None):
            
        output = []
        import re
        for key, timing in self.profiling_info.iteritems():
            xp, yp, op = key
            explain, resp = self.analyze_bin_op(xp, yp, op, timing[3])
            if filter is not None:
                if not xp in filter and not yp in filter and not resp in filter:
                    continue
                    
            item = CoercionProfileItem(xp=xp, yp=yp, op=op, total_time=timing[1], count=timing[0], discover_time=timing[2], explain=explain, resp=resp)
            output.append(item)
        
        output.sort(reverse=True)
        return CoercionProfile(output)
                    
        
    def analyze_bin_op(self, xp, yp, op, data):
        if isinstance(data, Action):
            if data.actor() == xp:  
                explain = "Act on left"
            else:
                explain = "Act on right"
            resp = data.domain()
        else:
            resp = data
            if resp is xp:
                explain = "Coerce left"
            elif resp is yp:
                explain = "Coerce right"
            else:
                explain = "Coerce both"
        return explain, resp


class CoercionProfile:
    
    def __init__(self, data):
        self.data = data
        
    def __getitem__(self, ix):
        return CoercionProfile([self.data[ix]])

    def __getslice__(self, start, end):
        return CoercionProfile(self.data[start:end])

    def _latex_(self):
        return r"""
        \begin{array}{rr|l|ccccc}
        %s
        \end{array}
        """ % "\\\\\n".join([row._latex_() for row in self.data])
        
    def __repr__(self):
        return "\n".join([repr(row) for row in self.data])
        
            
class CoercionProfileItem:

    def __init__(self, **kwds):
        self.__dict__.update(kwds)
    
    def __cmp__(self, other):
        return cmp(self.total_time, other.total_time)
        
    def _latex_(self):
        return "&".join([str(self.count), 
                         "%01.5f"%self.total_time, 
                         self.op_name(self.op), 
                         self.pretty_print_parent(self.xp), 
                         self.latex_arrow(self.explain),
                         self.pretty_print_parent(self.yp), 
                         "|",
                         self.pretty_print_parent(self.resp)])
                         
    def __repr__(self):
        return "\t".join([str(self.count), 
                          "%01.5f"%self.total_time, 
                          self.op_name(self.op), 
                          str(self.xp), 
                          self.text_arrow(self.explain),
                          str(self.yp),
                          str(self.resp)])
        
    def latex_arrow(self, explain):
        if explain == "Coerce left":
            return "\\leftarrow"
        elif explain == "Coerce right":
            return "\\rightarrow"
        elif explain == "Coerce both":
            return "\\leftrightarrow"
        elif explain == "Act on left":
            return "\\nearrow"
        elif explain == "Act on right":
            return "\\nwarrow"
        else:
            return "\\text{%s}" % explain
            
    def text_arrow(self, explain):
        if explain == "Coerce left":
            return "<--"
        elif explain == "Coerce right":
            return "-->"
        elif explain == "Coerce both":
            return "<->"
        elif explain == "Act on left":
            return "A->"
        elif explain == "Act on right":
            return "<-A"
        else:
            return explain
            
    def op_name(self, op):
        if op == "coerce":
            return " "
        try:
            return D[op.__name__]
        except AttributeError:
            return str(op)
        except KeyError:
            return op.__name__
            
    def pretty_print_parent(self, p):
        # Full text names can be really long, but latex doesn't have all the info
        # Perhaps there should be another method and/or a difference between str/repr
        # for parents. 
        if isinstance(p, type):
            return "\\text{%s}" % re.sub(r"<.*'(.*)'>", r"\1", str(p))
        
        # special cases
        from sage.rings.all import RDF, RQDF, CDF
        if p == RDF:
            return "RDF"
        elif p == RQDF:
            return "RQDF"
        elif p == CDF:
            return "CDF"
            
        try:
            s = p._latex_()
        except AttributeError:
            s = str(p)
        try:
            prec = p.precision()
            s += " \\text{(%s)}"%prec
        except AttributeError:
            pass
            
        # try to non-distructively shorten latex
        if len(s) > 50:
            real_len = len(re.sub(r"(\\[a-zA-Z]+)|[{}]", "", s))
            if real_len > 50:
                s = re.sub(r"([0-9]{,3})[0-9]{5,}([0-9])", "\\1...\\2", s)
                real_len = len(re.sub(r"(\\[a-zA-Z]+)|[{}]", "", s))
                if real_len > 50:
                    s = re.sub(r"([^\\]\b[^{}\\]{5,7})[^{}\\]{5,}([^{}\\]{3,})", "\\1...\\2", " "+s)

        return s            



from sage.structure.element cimport Element # workaround SageX bug

cdef class LAction(Action):
    """Action calls _l_action of the actor."""
    def __init__(self, G, S):
        Action.__init__(self, G, S, True, operator.mul)
    cdef Element _call_c_impl(self, Element g, Element a):
        return g._l_action(a)  # a * g

cdef class RAction(Action):
    """Action calls _r_action of the actor."""
    def __init__(self, G, S):
        Action.__init__(self, G, S, False, operator.mul)
    cdef Element _call_c_impl(self, Element a, Element g):
        return g._r_action(a)  # g * a

cdef class LeftModuleAction(Action):
    def __init__(self, G, S):
        # Objects are implemented with the assumption that
        # _rmul_ is given an element of the basering
        if G is not S.base() and S.base() is not S:
            # first we try the easy case of coercing G to the basering of S
            self.connecting = S.base().coerce_map_from(G)
            if self.connecting is None:
                # otherwise, we try and find a base extension
                from sage.categories.pushout import pushout
                # this may raise a type error, which we propagate
                self.extended_base = pushout(G, S)
                # make sure the pushout actually gave correct a base extension of S
                if self.extended_base.base() != pushout(G, S.base()):
                    raise TypeError, "Actor must be coercable into base."
                else:
                    self.connecting = self.extended_base.base().coerce_map_from(G)
                
        # TODO: detect this better
        # if this is bad it will raise a type error in the subsequent lines, which we propagate
        cdef RingElement g = G._an_element()
        cdef ModuleElement a = S._an_element()
        res = self._call_c(g, a)
        
        if parent_c(res) is not S and parent_c(res) is not self.extended_base:
            raise TypeError
            
        Action.__init__(self, G, S, True, operator.mul)

    cdef Element _call_c_impl(self, Element g, Element a):
        if self.connecting is not None:
            g = self.connecting._call_c(g)
        if self.extended_base is not None:
            a = self.extended_base(a)
        return (<ModuleElement>a)._rmul_c(g)  # a * g
        
    def _repr_name_(self):
        return "scalar multiplication"

    def codomain(self):
        if self.extended_base is not None:
            return self.extended_base
        return self.S

        
cdef class RightModuleAction(Action):
    def __init__(self, G, S):
        # Objects are implemented with the assumption that
        # _lmul_ is given an element of the basering
        if G is not S.base() and S.base() is not S:
            # first we try the easy case of coercing G to the basering of S
            self.connecting = S.base().coerce_map_from(G)
            if self.connecting is None:
                # otherwise, we try and find a base extension
                from sage.categories.pushout import pushout
                # this may raise a type error, which we propagate
                self.extended_base = pushout(G, S)
                # make sure the pushout actually gave correct a base extension of S
                if self.extended_base.base() != pushout(G, S.base()):
                    raise TypeError, "Actor must be coercable into base."
                else:
                    self.connecting = self.extended_base.base().coerce_map_from(G)

        # TODO: detect this better
        # if this is bad it will raise a type error in the subsequent lines, which we propagate
        cdef RingElement g = G._an_element()
        cdef ModuleElement a = S._an_element()
        res = self._call_c(a, g)

        if parent_c(res) is not S and parent_c(res) is not self.extended_base:
            raise TypeError
            
        Action.__init__(self, G, S, False, operator.mul)
        
    cdef Element _call_c_impl(self, Element a, Element g):
        if self.connecting is not None:
            g = self.connecting._call_c(g)
        if self.extended_base is not None:
            a = self.extended_base(a)
        return (<ModuleElement>a)._lmul_c(g)  # a * g
        
    def _repr_name_(self):
        return "scalar multiplication"
        
    def codomain(self):
        if self.extended_base is not None:
            return self.extended_base
        return self.S

