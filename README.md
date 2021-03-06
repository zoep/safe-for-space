Closure Conversion is Safe for Space, Supplemental material
-----------------------------------------------------------

This a standalone artifact that contains the Coq formalization of the proof that
closure conversion is correct and safe for space. The code includes the
definitions of the language and logical relation framework presented in the
paper. The transformation and its proof are parts of the CertiCoq certified
compiler for Coq. Here we include only the relevant dependencies.

1. **Compilation Instructions** 

	Dependencies: 

		Coq 8.8.2 

    Specific commits of coq-ext-lib and coq-template-coq that are installed as follows:

    template-coq: 

    download the zip from https://github.com/gmalecha/template-coq/tree/a290e03
    and then make && make install 

    coq-ext-lib:

    download the zip from https://github.com/coq-ext-lib/coq-ext-lib/tree/5dd9cfa 
    and then make && make install 

		
	To compile: 

    	> make -j N  # where N is the number of processors 

	If you are trying to compile with a different version of Coq you may need to
	regenerate the makefile:

    	> coq_makefile -f _CoqProject -o Makefile

2. **Development Description**

	We briefly describe here the contents of all the files in the source code.
	Furthermore, we provide a separate file, called THEOREMS.md, that lists the
	correspondence between the formal definitions and theorems and those
	presented in the paper.

    - cps.v       : definition of the CPS language
    - space_sem.v : Profiling semantics for CPS
    - Ensembles_util.v, map_util.v, functions.v
      set_util.v, List_util.v, tactics.v, hoare.v : General purpose librarIes 
    - ctx.v, identifiers.v, cps_util.v            : CPS-related libraries
    
    - closure_conversion.v      : The definition of the closure conversion as an inductive relation and as a functional program
    - closure_conversion_util.v : Syntactic properties of closure conversion
    
    - heap.v       : Abstract interface (module type) for the heaps used in the semantics
    - heap_defs.v  : Heap-related definitions (well-formedness, reachability, size, etc.)
    - heap_equiv.v : Heap isomorphism definitions and lemmas
    - heap_impl.v  : Concrete heap implementation
    - GC.v         : GC definitions and lemmas 
    - cc_log_rel.v : The definitions of the logical relation and lemmas
    - compat.v     : Compatibility lemmas for the logical relation
    - bounds.v     : Pre- and postcondition definitions and compatibility lemmas
    - invariants.v : Additional environment invariants (for nonlocal variables and function names)
    - closure_conversion_correct.v : Fundamental theorem of the logical relation
    - closure_conversion_corresp.v : Soundness proof of the closure conversion program w.r.t. the inductive definition 
    - toplevel.v   : The top-level theorem for terminating and diverging programs 
    
    - Maps.v, Coqlib.v : part of CompCert's general purpose libraries.


3. **Compiler**

	The sources of the compiler are publicly available [here](https://github.com/PrincetonUniversity/certicoq).
	The safe for space development is in the directory [theories/L6_PCPS/Heap](https://github.com/PrincetonUniversity/certicoq/tree/zoe_safe-for-space-trunk/theories/L6_PCPS/Heap).
   
 
    
    
