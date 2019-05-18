In this file we provide pointers to the source code for the definitions and
theorems stated in the paper.

- Section 3

  file: cps.c 

  CPS language definition (fig. 3): exp, line 71
  
  The main difference with the language presented at the paper is that this
  calculus supports mutual recursive function definitions  

  file: heap_defs.v

  heap reachability : reach', line 140
  heap size: size_heap, line 213
  reachable size: size_reachable, line 2636

- Section 4

  file: heap_equiv.v

  value equivalence: res_equiv, line 73
  environment equivalence: heap_env_equiv, line 95
  heap equivalence: heap_env_equiv, line 95
  
- Section 5

  file: space_sem.v

  source big-step semantics (fig. 4): big_step, line 146
  target big-step semantics (fug. 5): big_step_GC_cc, line 254

  file: GC.v

  garbage collection specification: live', line 44

- Section 6

  file: closure_conversion.v

  free variable judgment (fig 6): project_var and project_vars, line 14 and 77
  closure conversion definition (fig 7): Closure_conversion, line 102
  functional implementation of closure conversion: closure_conversion_top, line 461

  file: closure_conversion_corresp.v

  soundness of the implementation w.r.t. the relational definition: closure_conversion_top_sound, line 1395
  
- Section 7

  file: cc_log_rel.v

  expression relation : cc_approx_exp, line 66
  value relation (fig. 8) : cc_approx_val', line 207
  closure environment relation : cc_approx_clos, line 90
  environment relation : cc_approx_env_P, line 496

  file: compat.v

  Theorem 7.6 (projection compatibility lemma): cc_approx_exp_proj_compat, line 697


- Section 8

  file: bounds.v (Subsections 8.1, 8.2 (concrete time and space bounds))

  cost_exp^space : line 35  cost_space_exp
  pre- and postconditions : lines 99 - 162

  file: closure_conversion_correct.v

  Theorem 8.1 (Correctness of Closure Conversion): Closure_conversion_correct, line 1135

  Apart from the premises shown in the paper the theorem also makes assumptions
  about the uniqueness of identifiers, that are left implicit in the paper.

  It also assumes that the functions defined it the shame block are "truly"
  recursive. Without this assumption space safety cannot be proved since sharing
  environments between functions defined in the same scope is not generally safe
  for space. This does not show up in the paper as we use a calculus that does
  not support mutual induction.

  file: toplevel.v

  Corollary 8.2 (Correctness of Closure Conversion, top-level, termination): closure_conversion_correct_top, line 134


- Corollary 8.3 (Correctness of Closure Conversion, top-level, divergence): closure_conversion_correct_div, line 202