From SFS Require Import cps cps_util set_util identifiers ctx Ensembles_util
     List_util functions tactics map_util.

From SFS Require Import heap heap_defs 
     cc_log_rel compat closure_conversion closure_conversion_util GC.

From Coq Require Import ZArith.Znumtheory Arith Arith.Wf_nat Relations.Relations
                        Lists.List MSets.MSets MSets.MSetRBT Numbers.BinNums
                        NArith.BinNat PArith.BinPos Sets.Ensembles Omega Permutation.

Require Import SFS.Maps.

Import ListNotations.

Open Scope ctx_scope.
Open Scope fun_scope.
Close Scope Z_scope.



Module Size (H : Heap).

  Module Util := CCUtil H.
  
  Import H Util.C.LR.Sem Util.C.LR.Sem.GC Util.C.LR.Sem.GC.Equiv
         Util.C.LR.Sem.GC.Equiv.Defs Util.C.LR.Sem.GC
         Util.C.LR Util.C Util.



  (** * Size of CPS terms and heaps, needed to express the upper bound on the execution cost of certain transformations *)


  (** The extra cost incurred by closure conversion when evaluating *)
  Fixpoint cost_space_exp (e : exp) : nat :=
    match e with
      | Econstr x _ ys e => 1 + length ys + cost_space_exp e
      | Ecase x l =>
        (fix sizeOf_l l :=
               match l with
                 | [] => 0
                 | (t, e) :: l => max (cost_space_exp e) (sizeOf_l l)
               end) l
      | Eproj x _ _ y e => cost_space_exp e
      | Efun B e => max
                     (1 + PS.cardinal (fundefs_fv B) + (* env *)
                      3 * (numOf_fundefs B) + (* closures *)
                      cost_space_exp e)
                     (1 + PS.cardinal (fundefs_fv B) + cost_space_funs B)
      | Eapp x _ ys => 0
      | Eprim x _ ys e => cost_space_exp e
      | Ehalt x => 0
    end
  with cost_space_funs (f : fundefs) : nat :=
         match f with
         | Fcons _ _ _ e B =>
           max (cost_space_exp e) (cost_space_funs B) 
         | Fnil => 0
         end.

  Definition cost_value (c : fundefs -> nat) (v : value) : nat :=
    match v with
    | Loc _ => 0
    | FunPtr B _ => c B
    end.

  Definition cost_block (c : fundefs -> nat) (b : block) : nat :=
    match b with
    | Constr _ vs => 0
    | Clos v1 rho => cost_value c v1
    | Env rho => 0
    end.

  (** The maximum cost of evaluating any function in the heap *)
  Definition cost_heap (c : fundefs -> nat) (H : heap block) :=
    max_with_measure (cost_block c) H.


  Definition cost_env_app_exp_out (e : exp) : nat :=
    match e with
    | Econstr x _ ys e => 3 * length ys
    | Ecase x l => 3
    | Eproj x _ _ y e => 3
    | Efun B e => 1 + 4 * PS.cardinal (fundefs_fv B)
    | Eapp x _ ys => 3 + 3 * length ys
    | Eprim x _ ys e => 3 * length ys
    | Ehalt x => 3
    end.

  
  Definition cost_space_heap H1 := cost_heap (fun B => cost_space_funs B + (1 + PS.cardinal (fundefs_fv B))) H1.


  (** * PostCondition *)

  Definition Ktime := 7.
  
  (** Enforces that the resource consumption of the target is within certain bounds *)
  Definition Post
             (k : nat) (* This varies locally in the proof *)
             (A : nat) (* Size at entry *)
             (δ : nat) (* local delta *) 
             (* (Funs : Ensemble var) *)
             (* `{ToMSet Funs} *)
             (p1 p2 : heap block * env * exp * nat * nat) :=
    match p1, p2 with
      | (H1, rho1, e1, c1, m1), (H2, rho2, e2, c2, m2) =>
        (* time bound *)
        c1 <= c2 + k <= Ktime * c1 /\
        (* memory bound *)
        m2 <= max (A + cost_space_exp e1 + δ) (m1 + max (cost_space_exp e1) (cost_space_heap H1))
    end.

  Definition Post_weak (* essentially, Post <--> Post_weak for our semantics *)
             (k : nat) (* This varies locally in the proof *)
             (A : nat) (* Size at entry *)
             (δ : nat) (* local delta *) 
             (* (Funs : Ensemble var) *)
             (* `{ToMSet Funs} *)
             (p1 p2 : heap block * env * exp * nat * nat) :=
    match p1, p2 with
    | (H1, rho1, e1, c1, m1), (H2, rho2, e2, c2, m2) =>
      (* time bound *)
      (cost e1 <= c1 -> c1 <= c2 + k <= Ktime * c1) /\
      (* memory bound *)
      m2 <=  max (A + cost_space_exp e1 + δ) (m1 + max (cost_space_exp e1) (cost_space_heap H1))
    end.


  Definition PostG
             (size_heap size_env : nat)
             (p1 p2 : heap block * env * exp * nat * nat) :=
    match p1, p2 with
      | (H1, rho1, e1, c1, m1), (H2, rho2, e2, c2, m2) =>
        Post 0 size_heap size_env p1 p2 
    end.

  
  (** * Precondition *)
  
  (** Enforces that the initial heaps have related sizes *)  
  Definition Pre
             (Funs : Ensemble var)
             `{ToMSet Funs} A δ
             (p1 p2 : heap block * env * exp) :=
    let funs := 3 * PS.cardinal (@mset Funs _) in
    match p1, p2 with
      | (H1, rho1, e1), (H2, rho2, e2) =>
        (* Sizes of the initial heaps *)
        size_heap H2 + funs (* not yet projected funs *)
        <=  A + δ (* initial delta of heaps *)
    end.

  Definition PreG
             (Funs : Ensemble var)
             `{ToMSet Funs} (size_heap size_env : nat) 
             (p1 p2 : heap block * env * exp) :=
    let funs := 3 * PS.cardinal (@mset Funs _) in
    match p1, p2 with
    | (H1, rho1, e1), (H2, rho2, e2) =>
      Pre Funs size_heap size_env p1 p2 
    end.


 
  Lemma cost_heap_block_get H1 c l b :
    get l H1 = Some b ->
    cost_block c b <= cost_heap c H1. 
  Proof.
    eapply HL.max_with_measure_get.
  Qed.
  
  Lemma cost_heap_alloc H1 H1' c l b :
    alloc b H1 = (l, H1') ->
    cost_heap c H1' = max (cost_block c b) (cost_heap c H1).
  Proof.
    intros Hal. unfold cost_heap.
    erewrite (HL.max_with_measure_alloc _ _ _ _ H1'); eauto.
    rewrite Max.max_comm. eapply Nat.max_compat; omega.
  Qed.

  Lemma cost_space_heap_alloc H1 H1' l b :
    alloc b H1 = (l, H1') ->
    cost_space_heap H1' = max (cost_block (fun B => cost_space_funs B + (1 + PS.cardinal (fundefs_fv B))) b)
                              (cost_space_heap H1).
  Proof.
    intros. eapply cost_heap_alloc. eassumption.
  Qed.

  Lemma cost_heap_def_closures H1 H1' rho1 rho1' c B B0 rho :
    def_closures B B0 rho1 H1 rho = (H1', rho1') ->
    cost_heap c H1' = match B with
                        | Fnil => cost_heap c H1
                        |  _ => max (c B0) (cost_heap c H1)
                      end.
  Proof.
    revert H1' rho1'. induction B; intros H1' rho1' Hclo.
    - simpl in Hclo.
      destruct (def_closures B B0 rho1 H1 rho) as [H2 rho2] eqn:Hclo'.
      destruct (alloc (Clos (FunPtr B0 v) rho) H2) as [l' rho3] eqn:Hal. inv Hclo.
      erewrite cost_heap_alloc; [| eassumption ].
      simpl. destruct B.
      + erewrite (IHB H2); [| reflexivity ].
        rewrite Max.max_assoc, Max.max_idempotent. reflexivity.
      + erewrite (IHB H2); reflexivity.
    - inv Hclo; eauto.
  Qed.

  Lemma cost_space_heap_def_closures H1 H1' rho1 rho1' B B0 rho :
    def_closures B B0 rho1 H1 rho = (H1', rho1') ->
    cost_space_heap H1' = match B with
                          | Fnil => cost_space_heap H1
                          |  _ => max (cost_space_funs B0 + (1 + PS.cardinal (fundefs_fv B0))) (cost_space_heap H1)
                        end.
  Proof.
    eapply cost_heap_def_closures. 
  Qed.     

  Lemma cost_space_heap_def_closures_cons H1 H1' rho1 rho1' B B0 rho :
    B <> Fnil ->
    def_closures B B0 rho1 H1 rho = (H1', rho1') ->
    cost_space_heap H1' = max (cost_space_funs B0 + (1 + PS.cardinal (fundefs_fv B0))) (cost_space_heap H1).
  Proof.
    intros. erewrite cost_space_heap_def_closures; [| eassumption ].
    destruct B. reflexivity.
    congruence.
  Qed.
  
  Lemma cardinal_name_in_fundefs B :
    unique_functions B ->
    PS.cardinal (@mset (name_in_fundefs B) _) = numOf_fundefs B.
  Proof.
    intros Hun. induction B.
    - inv Hun.
      simpl.
      rewrite Proper_carinal.  Focus 2.
      eapply Same_set_From_set. 
      rewrite <- (@mset_eq (v |: name_in_fundefs B)) at 1.
      rewrite FromSet_union. eapply Same_set_Union_compat.
      eapply ToMSet_Singleton.
      eapply ToMSet_name_in_fundefs.
      rewrite <- PS_cardinal_union. erewrite PS_cardinal_singleton.
      now rewrite <- IHB; eauto.
      rewrite <- mset_eq. reflexivity. 
      eapply FromSet_disjoint. rewrite <- !mset_eq...
      eapply Disjoint_Singleton_l. eassumption. 
    - simpl. 
      rewrite PS.cardinal_spec. erewrite Same_set_FromList_length' with (l2 := []).
      reflexivity. eapply NoDupA_NoDup. eapply PS.elements_spec2w.
      now constructor. 
      rewrite <- FromSet_elements. rewrite <- mset_eq, FromList_nil. reflexivity. 
  Qed.


  Lemma cost_env_app_exp_out_le_cost e :
    cost_env_app_exp_out e <= 4 * (cost e).
  Proof.
    induction e; simpl; omega.
  Qed.  

  Lemma fun_in_fundefs_cost_space_fundefs Funs {Hf : ToMSet Funs} B f tau xs e: 
    fun_in_fundefs B (f, tau, xs, e) ->
    cost_space_exp e <= cost_space_funs B.
  Proof. 
    induction B; intros Hin; inv Hin.
    - simpl. inv H.
      eapply Nat.le_max_l.
    - eapply le_trans. eapply IHB. eassumption.
      simpl. eapply Nat.le_max_r.
  Qed.

  (** * Compat lemmas *)
 
  Lemma PostBase e1 e2 k
        (Funs : Ensemble var) { _ : ToMSet Funs} A δ δ' :
    k <= cost_env_app_exp_out e1 ->
    δ' <= δ + cost_space_exp e1 ->
    InvCostBase (Post k A δ) (Pre Funs A δ') e1 e2.
  Proof.
    unfold InvCostBase, Post, Pre.
    intros Hleq Hleq' H1' H2' rho1' rho2' c Hs Hc.
    unfold Ktime. split.
    + split. omega. 
      eapply plus_le_compat. omega.
      eapply le_trans. eassumption. 
      eapply le_trans. eapply cost_env_app_exp_out_le_cost.
      omega. 
    + eapply le_trans. eapply le_plus_l.
      eapply le_trans. eassumption.
      eapply le_trans; [| now eapply Nat.le_max_l]. omega.
  Qed.

  Lemma PostBase_weak e1 e2 k
        (Funs : Ensemble var) { _ : ToMSet Funs} A δ δ' :
    k <= cost_env_app_exp_out e1 ->
    δ' <= δ + cost_space_exp e1 ->
    InvCostBase (Post_weak k A δ) (Pre Funs A δ') e1 e2.
  Proof.
    unfold InvCostBase, Post_weak, Pre.
    intros Hleq Hleq' H1' H2' rho1' rho2' c Hs Hc.
    unfold Ktime. split.
    + intros Hw. split. omega. 
      eapply plus_le_compat. omega.
      eapply le_trans. eassumption. 
      eapply le_trans. eapply cost_env_app_exp_out_le_cost.
      omega. 
    + eapply le_trans. eapply le_plus_l.
      eapply le_trans. eassumption.
      eapply le_trans; [| now eapply Nat.le_max_l]. omega.
  Qed.

  Lemma PostTimeOut_weak e1 e2 k
        (Funs : Ensemble var) { _ : ToMSet Funs} A δ δ' :
    k <= cost_env_app_exp_out e1 ->
    δ' <= δ + cost_space_exp e1 ->
    InvCostTimeOut (Post_weak k A δ) (Pre Funs A δ') e1 e2.
  Proof.
    unfold InvCostBase, Post_weak, Pre.
    intros Hleq Hleq' H1' H2' rho1' rho2' c Hs Hc.
    unfold Ktime. split.
    + intros Hyp. omega.
    + eapply le_trans. eapply le_plus_l.
      eapply le_trans. eassumption.
      eapply le_trans; [| now eapply Nat.le_max_l]. omega.
  Qed.
  
  Lemma PostTimeOut e1 e2
        (Funs : Ensemble var) { _ : ToMSet Funs} A δ δ' :
    δ' <= δ + cost_space_exp e1 ->
    InvCostTimeOut (Post 0 A δ) (Pre Funs A δ') e1 e2.
  Proof.
    unfold InvCostBase, Post, Pre.
    intros Hleq H1' H2' rho1' rho2' c Hs Hc.
    unfold Ktime. split.
    + omega.
    + eapply le_trans. eapply le_plus_l.
      eapply le_trans. eassumption.
      eapply le_trans; [| now eapply Nat.le_max_l]. omega.
  Qed.
  
  Lemma PostTimeOut' e1 e2 l
        (Funs : Ensemble var) { _ : ToMSet Funs} A δ :
    l <=  3 * PS.cardinal mset -> 
    InvCostTimeOut' (Post 0 A δ) (Pre Funs A δ) l e1 e2.
  Proof.
    unfold InvCostTimeOut', Post, Pre.
    intros Hleq H1' H2' rho1' rho2' c m Hs Hc Hleq'.
    unfold Ktime. split.
    + omega.
    + eapply le_trans. eassumption.
      eapply le_trans. eapply plus_le_compat_l. eassumption.
      eapply le_trans. eassumption.
      eapply le_trans; [| now eapply Nat.le_max_l]. omega.
  Qed.
    

  Lemma PostTimeOut'_weak e1 e2 l k
        (Funs : Ensemble var) { _ : ToMSet Funs} A δ :
    l <= cost_space_exp e1 ->
    k <= cost_env_app_exp_out e1 ->
    InvCostTimeOut' (Post_weak k A δ) (Pre Funs A δ) l e1 e2.
  Proof.
    unfold InvCostTimeOut', Post_weak, Pre.
    intros Hleq Hleq2 H1' H2' rho1' rho2' c m Hs Hc Hleq'.
    unfold Ktime. split.
    + omega.
    + eapply le_trans. eassumption.
      eapply le_trans. eapply plus_le_compat_l. eassumption.
      eapply le_trans with (m := A + δ  + cost_space_exp e1). omega. 
      eapply le_trans; [| now eapply Nat.le_max_l]. omega.
  Qed.
    

  Lemma PostBaseFuns e1 e2 k
        (Funs : Ensemble var) { _ : ToMSet Funs} A δ δ' B1 B2:
    S (PS.cardinal (fundefs_fv B1)) <= k <= cost_env_app_exp_out (Efun B1 e1) ->
    δ' <= δ + cost_space_exp (Efun B1 e1) ->
    InvCostTimeOut_Funs (Post_weak k A δ) (Pre Funs A δ') B1 e1 B2 e2.
  Proof.
    unfold InvCostTimeOut_Funs, Post_weak, Pre.
    intros [Hleq1 Hleq2] Hleq' H1' H2' rho1' rho2' c Hs.
    unfold Ktime. split.
    + intros Hyp. simpl in *. omega.
    + eapply le_trans. eapply le_plus_l.
      eapply le_trans. eassumption.
      eapply le_trans; [| now eapply Nat.le_max_l]. omega.
  Qed.

 
  Lemma PostAppCompat i j IP P Funs {Hf : ToMSet Funs}
        b H1 H2 rho1 rho2 f1 t xs1 f2 xs2 f2' Γ k A δ :
    Forall2 (fun y1 y2 => cc_approx_var_env i j IP P b H1 rho1 H2 rho2 y1 y2) (f1 :: xs1) (f2 :: xs2) -> 
    k <= (cost_env_app_exp_out (Eapp f1 t xs1)) ->
    ~ Γ \in FromList xs2 ->
    ~ f2' \in FromList xs2 ->
    IInvAppCompat Util.clo_tag PostG
                  (Post k A δ) (Pre Funs A δ)
                  H1 H2 rho1 rho2 f1 t xs1 f2 xs2 f2' Γ.
  Proof.
    unfold IInvAppCompat, Pre, Post, PostG. 
    intros Hall Hk Hnin1 Hnin2 _ H1' H1'' H2' Hgc2 env_loc
           rhoc1 rhoc2 rhoc3 rho1' rho2' rho2''
           b1 b2 B1 f1' ct1 xs1' e1 l1 vs1 B
           f3 c ct2 xs2' e2 l2 env_loc2 vs2 c1 c2 m1 m2 d3
           Heq1 Hinj1 Heq2 Hinj2
           [[Hc1 Hc2] Hm1] Hh1
           Hgetf1 Hgetl1 Hgetecl Hfind1 Hgetxs1 Hclo Hset1
           Hgetf2 Hgetxs2 Hset2 Hgetl2 Hfind2 Gc2. 
    assert (Hlen := Forall2_length _ _ _ Hall). inversion Hlen as [Hlen'].    
    { rewrite <- !plus_n_O in *. split.
      - split.
        + simpl. omega.
        + unfold Ktime in *. eapply le_trans. 
          rewrite <- !plus_assoc. eapply plus_le_compat_r. eassumption.
          simpl in *. omega. 
      - eapply Max.max_lub.
          
        + simpl. eapply le_trans. eassumption.
          eapply le_trans; [| eapply Max.le_max_r ].
          
          eapply Max.max_lub.
          * eapply le_trans. eapply plus_le_compat_r.
            eapply plus_le_compat_r. eassumption.
            rewrite <- plus_assoc. eapply plus_le_compat.
            now eapply Max.le_max_r.
            eapply le_trans; [| eapply HL.max_with_measure_get; now apply Hgetl1 ].
            simpl. eapply plus_le_compat_r.
            eapply fun_in_fundefs_cost_space_fundefs; eauto.
            eapply find_def_correct. eassumption.
          * eapply plus_le_compat. 
            now eapply Max.le_max_r.
            eapply Max.max_lub.
            
            eapply le_trans; [| eapply HL.max_with_measure_get; now apply Hgetl1 ].
            simpl.
            eapply le_trans. eapply fun_in_fundefs_cost_space_fundefs; eauto.
            eapply find_def_correct. eassumption.
            omega.
            erewrite (cost_space_heap_def_closures_cons H1' H1''); [| | eassumption ].
            eapply Max.max_lub.
            eapply le_trans; [| eapply HL.max_with_measure_get; now apply Hgetl1 ].
            reflexivity. reflexivity.
            intros Hc; inv Hc. now inv Hfind1. 
      
        + eapply le_trans. eapply le_trans; [| eapply Hh1 ]. omega.
          eapply Max.le_max_l. }
  Qed.
  
  Lemma PostConstrCompat i j IP P k
        b H1 H2 rho1 rho2 x c ys1 ys2 e1 e2 A δ :
    k <= cost_env_app_exp_out (Econstr x c ys1 e1) ->
    Forall2 (cc_approx_var_env i j IP P b H1 rho1 H2 rho2) ys1 ys2 ->
    InvCtxCompat (Post_weak k A δ)
                 (Post 0 A (δ + (1 + length ys1)))
                 (Econstr_c x c ys1 Hole_c) (Econstr_c x c ys2 Hole_c) e1 e2.
  Proof with (now eauto with Ensembles_DB).
    unfold InvCtxCompat, Post.
    intros Hleqk Hall H1' H2' H1'' H2'' rho1' rho2' rho1'' rho2'' c1 c2 c1' c2'
           m1 m2 [[Hc1 Hc2] Hm] Hleq Hctx1 Hctx2.
    assert (Hlen := Forall2_length _ _ _ Hall). 
    inv Hctx1. inv Hctx2. inv H13. inv H16.
    rewrite !plus_O_n in *. simpl cost_ctx in *.
    rewrite !Hlen in *.
    split. 
    - intros Hleq1. split.
      + rewrite !(plus_comm _ (S (length _))). rewrite <- !plus_assoc.
        assert (Hleq' : c1 <= c2) by omega.
        simpl. omega.
      + simpl in *. omega.        
    - rewrite <- !plus_n_O in *. eapply le_trans. eassumption.
      erewrite cost_space_heap_alloc; [| eassumption ]. 
      eapply Nat.max_le_compat. simpl. omega.
      simpl cost_block. eapply plus_le_compat.
      now eapply Max.le_max_r.
      rewrite Nat_as_OT.max_0_l.
      eapply Nat.max_le_compat_r. simpl. omega.
  Qed.       
  
  Lemma PreConstrCompat i j A δ IP P
        (Funs Funs' : Ensemble var) {Hf : ToMSet Funs} {Hf' : ToMSet Funs'}
        b H1 H2 rho1 rho2 x c ys1 ys2 e1 e2 :
    Forall2 (fun y1 y2 => cc_approx_var_env i j IP P b H1 rho1 H2 rho2 y1 y2) ys1 ys2 ->
    Funs' \subset Funs ->
    IInvCtxCompat (Pre Funs A δ) (Pre Funs' A (δ + (1 + length ys1)))
                  (Econstr_c x c ys1 Hole_c) (Econstr_c x c ys2 Hole_c) e1 e2.
  Proof with (now eauto with Ensembles_DB). 
    unfold IInvCtxCompat, Pre.
    intros Hall Hsub H1' H2' H1'' H2'' rho1' rho2' rho1'' rho2'' c1' c2'
           Hm Hctx1 Hctx2.
    inv Hctx1. inv Hctx2. inv H13. inv H16.
    
    unfold size_heap in *.
    erewrite HL.size_with_measure_alloc; [| reflexivity | eassumption ].

    unfold reach_size, size_reachable in *.
    assert (Hsubleq : 3 * PS.cardinal (@mset Funs' _) <= 3 * PS.cardinal (@mset Funs _)).
    { eapply mult_le_compat_l. eapply PS_elements_subset. eassumption. }

    rewrite <- plus_assoc. rewrite (plus_comm (size_val _)). rewrite plus_assoc. 

    eapply le_trans. eapply plus_le_compat_r. 
    eapply le_trans; [| now apply Hm]. omega. simpl.

    eapply Forall2_length in Hall.
    eapply (@getlist_length_eq value) in H11; try eassumption.
    eapply (@getlist_length_eq value) in H14; try eassumption.
    replace (@length var ys1) with (@length M.elt ys1) in *. 
    rewrite <- H14, Hall. rewrite !plus_assoc. reflexivity. reflexivity.
  Qed.
  

  Lemma PostProjCompat k x c y1 y2 e1 e2 n A δ :
    k <= (cost_env_app_exp_out (Eproj x c n y1 e1)) ->
    InvCtxCompat (Post_weak k A δ)
                 (Post 0 A δ)
                 (Eproj_c x c n y1 Hole_c) (Eproj_c x c n y2 Hole_c) e1 e2.
  Proof with (now eauto with Ensembles_DB).
    unfold InvCtxCompat, Post.
    intros Hleqk H1' H2' H1'' H2'' rho1' rho2' rho1'' rho2'' c1 c2 c1' c2'
           m1 m2 [[Hc1 Hc2] Hm] Hleq Hctx1 Hctx2.
    inv Hctx1. inv Hctx2. inv H17. inv H13.
    split; rewrite <- !plus_n_O in *.
    - intros Hleq'; simpl in *; omega.
    - eapply le_trans. eassumption.
      eapply Nat.max_le_compat. simpl. omega.
      simpl cost_block. eapply plus_le_compat.
      now eapply Max.le_max_r.
      eapply Nat.max_le_compat_r. simpl. omega.
  Qed.
  
  Lemma PreProjCompat x1 x2 c n y1 y2 e1 e2 A δ
        (Funs : Ensemble var) {Hf : ToMSet Funs} (Funs' : Ensemble var) {Hf' : ToMSet Funs'} :
    Funs' \subset Funs -> 
    IInvCtxCompat (Pre Funs A δ) (Pre Funs' A δ)
                  (Eproj_c x1 c n y1 Hole_c) (Eproj_c x2 c n y2 Hole_c) e1 e2.
  Proof with (now eauto with Ensembles_DB).
    unfold IInvCtxCompat, Pre.
    intros Hsub H1' H2' H1'' H2'' rho1' rho2' rho1'' rho2'' c1' c2'
           Hm1 Hctx1 Hctx2.
    inv Hctx1. inv Hctx2. inv H13. inv H17.  
    eapply le_trans; [| now apply Hm1 ]. eapply plus_le_compat_l.
    eapply mult_le_compat_l. eapply PS_elements_subset. eassumption. 
  Qed.
  
  Lemma cost_space_exp_case_In x1 c1 e1 P1 :
    List.In (c1, e1) P1 ->
    cost_space_exp e1 <= cost_space_exp (Ecase x1 P1).
  Proof.
    induction P1; intros Hin.
    - now inv Hin.
    - inv Hin.
      + simpl. eapply Nat.le_max_l.
      + eapply le_trans. eapply IHP1. eassumption.
        destruct a. simpl. eapply Max.le_max_r.
  Qed.
  
  Lemma PostCaseCompat k x1 x2 P1 P2 A δ :
    k <= (cost_env_app_exp_out (Ecase x1 P1)) ->
    InvCaseCompat (Post_weak k A δ)
                  (fun e1 e2 => Post 0 A δ) x1 x2 P1 P2.
  Proof with (now eauto with Ensembles_DB).
    unfold InvCaseCompat, Post.
    intros Hleqk H1' H2' rho1' rho2' m1 m2
           c1 c2 c e1 tc1 e2 tc2 Hin1 Hin2 Hleq1 [[Hc1 Hc2] Hm].
    split; rewrite <- !plus_n_O in *.
    - simpl in *; omega.
    - eapply le_trans. eassumption. 
      eapply Nat.max_le_compat.
      eapply plus_le_compat_r. eapply plus_le_compat_l. 
      eapply cost_space_exp_case_In. eassumption.
      eapply plus_le_compat.
      now eapply Max.le_max_r.
      eapply Nat.max_le_compat_r.
      eapply cost_space_exp_case_In. eassumption.
  Qed.
  
  Lemma PreCaseCompat A δ x1 x2 P1 P2 
        (Funs : Ensemble var) {Hf : ToMSet Funs} (Funs' : exp -> Ensemble var)
        {HFe : forall e, ToMSet (Funs' e)} :
    (forall c e, List.In (c, e) P1 -> Funs' e \subset Funs) -> 
    IInvCaseCompat (Pre Funs A δ) (fun e1 e2  => Pre (Funs' e1) A δ) x1 x2 P1 P2.
  Proof with (now eauto with Ensembles_DB).
    unfold IInvCtxCompat, Pre.
    intros Hsub H1'  rho1' H2' rho2 c1 c2 e1 e2 Hin1 Hin2 hleq.
    eapply le_trans; [| eassumption ]. eapply plus_le_compat_l.
    eapply mult_le_compat_l.
    eapply PS_elements_subset. eapply Hsub. eassumption.
  Qed.
  
  
  Lemma PostFunsCompat B1 B2 e1 e2 k m A δ δ' :
    1 + PS.cardinal (fundefs_fv B1) + m <= k -> 
    k <= cost_env_app_exp_out (Efun B1 e1) + m ->
    δ' <= (1 + (PS.cardinal (@mset (occurs_free_fundefs B1) _)) + 3 * numOf_fundefs B1) + δ ->
    InvCtxCompat (Post_weak k A δ)
                 (Post m A δ') (Efun1_c B1 Hole_c) (Efun1_c B2 Hole_c) e1 e2.
  Proof with (now eauto with Ensembles_DB).
    unfold InvCtxCompat, Post, Post_weak.
    intros Hleq0 Hleq Hleq' H1' H2' H1'' H2'' rho1' rho2' rho1'' rho2'' c1 c2 c1' c2'
           m1 m2 [[Hc1 Hc2] Hm] Hleq1 Hctx1 Hctx2.
    inv Hctx1. inv Hctx2. inv H4. inv H9. inv H10.
    rewrite !plus_O_n. simpl cost_ctx.
    split.
    - simpl in *. omega.
    - eapply le_trans. eassumption.
      simpl cost_space_exp; simpl reach_size. 
      eapply Nat.max_le_compat.
      + rewrite <- !plus_assoc. 
        eapply plus_le_compat_l.
        eapply le_trans. eapply plus_le_compat_l. eassumption.
        rewrite  !plus_assoc. eapply plus_le_compat_r.
        eapply le_trans; [| eapply Peano.le_n_S; eapply Max.le_max_l ].
        assert (Heq : PS.cardinal (fundefs_fv B1) =
                      (PS.cardinal (@mset (occurs_free_fundefs B1) _))).
        { rewrite !PS.cardinal_spec. eapply Same_set_FromList_length'.
          eapply NoDupA_NoDup. eapply PS.elements_spec2w.
          eapply NoDupA_NoDup. eapply PS.elements_spec2w. rewrite <- !FromSet_elements.
          rewrite <- !mset_eq at 1.
          rewrite <- fundefs_fv_correct. reflexivity. }
        rewrite Heq. omega. 
      + eapply plus_le_compat. 
        now eapply Max.le_max_r.
        erewrite (cost_space_heap_def_closures H' H1''); [| eassumption ].
        erewrite (cost_space_heap_alloc H1' H'); [| eassumption ].      
      destruct B1.
        * rewrite !Nat.max_assoc. eapply Nat.max_le_compat_r.
          
          eapply Max.max_lub. eapply Max.max_lub.
          
          eapply le_trans; [| eapply Peano.le_n_S; eapply Max.le_max_l ].
          omega.
          
          eapply le_trans; [| eapply Peano.le_n_S; eapply Max.le_max_r ].
          omega.
          
          simpl. omega. 
          
        * rewrite !Nat.max_assoc. eapply Nat.max_le_compat_r.
          
          eapply Max.max_lub.
          eapply le_trans; [| eapply Peano.le_n_S; eapply Max.le_max_l ].
          omega.
          
          simpl. omega. 
  Qed.



  Lemma PreSubsetCompat (Funs : Ensemble var) {Hf : ToMSet Funs}
        (Funs' : Ensemble var) {Hf' : ToMSet Funs'}
        A d H1 rho1 e1 H2 rho2 e2  :
    Pre Funs A d (H1, rho1, e1) (H2, rho2, e2) ->
    Funs' \subset Funs -> 
    Pre Funs' A d  (H1, rho1, e1) (H2, rho2, e2). 
  Proof. 
    unfold Pre. intros Hpre Hleq.
    assert (Hsubleq : 3 * PS.cardinal (@mset Funs' _) <= 3 * PS.cardinal (@mset Funs _)).
    { eapply mult_le_compat_l. eapply PS_elements_subset. eassumption. }
    omega.
  Qed.
  
  Lemma PreFunsCompat
        (Scope : Ensemble var) {Hs : ToMSet Scope} 
        (* (Scope' : Ensemble var) {Hs' : ToMSet Scope'}  *)
        (Funs : Ensemble var) {Hf : ToMSet Funs}
        (* (Funs' : Ensemble var) {Hf' : ToMSet Funs'} *)
        (S : Ensemble var) {Hst : ToMSet S}
        (S' : Ensemble var) {Hst' : ToMSet S'}
        B1 B2 e1 e2 A δ:
    Funs :&: S' \subset Funs :&: S ->
    Disjoint _ (name_in_fundefs B1) (Scope :|: Funs) ->
    unique_functions B1 ->
    IInvCtxCompat_Funs (Pre (Funs :&: S \\ Scope) A δ)
                       (Pre ((name_in_fundefs B1 :|: Funs) :&: S'  \\ (Scope \\ name_in_fundefs B1)) A
                            (δ + 3 * numOf_fundefs B1)) B1 B2 e1 e2.
  Proof with (now eauto with Ensembles_DB).
    unfold IInvCtxCompat.
    intros Hsub Hdis Hun H1' H2' H1'' H2'' rho1' rho2' rho1'' rho2'' c1' c2'
           Hm Hbin Hctx1 Hctx2.
    
    eapply PreSubsetCompat with (Funs := name_in_fundefs B1 :|: (Funs :&: S \\ Scope)); eauto with Ensembles_DB.
     
 
    inv Hctx1. inv Hctx2. inv H9. inv H10.
     
    unfold Pre in *.  
    rewrite Proper_carinal. Focus 2.
    eapply Same_set_From_set.
    rewrite <- (@mset_eq (name_in_fundefs B1 :|: (Funs :&: S \\ Scope))) at 1.
    rewrite FromSet_union. eapply Same_set_Union_compat.
    eapply ToMSet_name_in_fundefs.
    rewrite <- (@mset_eq (Funs :&: S \\ Scope)) at 1.
    reflexivity. tci.
    
    rewrite <- PS_cardinal_union, Nat_as_OT.mul_add_distr_l. 

    rewrite (plus_comm (3 * _)), plus_assoc. eapply le_trans.
    eapply plus_le_compat_r. eassumption. 
    
    assert (Heq' : 3 * PS.cardinal (@mset (name_in_fundefs B1) (ToMSet_name_in_fundefs B1)) =
                   3 * numOf_fundefs B1).
    { f_equal. eapply cardinal_name_in_fundefs. eassumption. } 
     omega. 
    
    eapply FromSet_disjoint. rewrite <- !mset_eq.
    eapply Disjoint_Included_r; [| eassumption ].
    eapply Included_trans. eapply Setminus_Included.
    eapply Included_trans. eapply Ensembles_util.Included_Intersection_l.
    now eauto with Ensembles_DB.
    eapply Included_trans. 
    eapply Included_Setminus_compat.
    rewrite Intersection_Union_distr. eapply Included_Union_compat.
    eapply Included_Intersection_l. reflexivity. 
    reflexivity.
    rewrite  Setminus_Union_distr... 
  Qed.
   
  
  Lemma project_var_ToMSet Scope1 Scope2 `{ToMSet Scope1} Funs1 Funs2
        fenv c Γ FVs y C1 :
    project_var Util.clo_tag Scope1 Funs1 fenv c Γ FVs y C1 Scope2 Funs2 ->
    ToMSet Scope2.
  Proof.
    intros Hvar.
    assert (Hd1 := H).  eapply Decidable_ToMSet in Hd1. 
    destruct Hd1 as [Hdec1]. 
    destruct (Hdec1 y).
    - assert (Scope1 <--> Scope2).
      { inv Hvar; eauto; try reflexivity.
        now exfalso; eauto. now exfalso; eauto. }
      eapply ToMSet_Same_set; eassumption.
    - assert (y |: Scope1 <--> Scope2).
      { inv Hvar; try reflexivity.
        exfalso; eauto. }
      eapply ToMSet_Same_set; try eassumption.
      eauto with typeclass_instances.
  Qed.

  Lemma project_var_ToMSet_Funs Scope1 `{ToMSet Scope1} Scope2 Funs1 Funs2 `{ToMSet Funs1}
        fenv c Γ FVs y C1 :
    project_var Util.clo_tag Scope1 Funs1 fenv c Γ FVs y C1 Scope2 Funs2 ->
    ToMSet Funs2.
  Proof.
    intros Hvar.
    assert (Hd1 := H). eapply Decidable_ToMSet in Hd1. 
    destruct Hd1 as [Hdec1]. 
    destruct (Hdec1 y).
    - assert (Funs1 <--> Funs2).
      { inv Hvar; eauto; try reflexivity.
        now exfalso; eauto. }
      tci.
    - destruct (@Dec _ Funs1 _ y).
      + assert (Funs1 \\ [set y] <--> Funs2).
        { inv Hvar; try reflexivity.
          exfalso; eauto. exfalso; eauto. }
        eapply ToMSet_Same_set; try eassumption.
        tci.
      + assert (Funs1 <--> Funs2).
        { inv Hvar; try reflexivity.
          exfalso; eauto. }
        eapply ToMSet_Same_set; try eassumption.
  Qed.   

  Lemma project_var_cost_alloc_eq Scope Scope'
        Funs `{ToMSet Funs}
        Funs' `{ToMSet Funs'}
        fenv c Γ FVs x C1 :
    project_var Util.clo_tag Scope Funs fenv c Γ FVs x C1 Scope' Funs' ->
    cost_alloc_ctx_CC C1 = 3 * PS.cardinal (@mset (Funs \\ Funs') _).
  Proof.
    intros Hvar; inv Hvar; eauto.
    - rewrite (Proper_carinal _ PS.empty).
      reflexivity.
      eapply Same_set_From_set. 
      rewrite <- mset_eq, Setminus_Same_set_Empty_set.
      rewrite FromSet_empty. reflexivity.
    - simpl cost_ctx_full. erewrite PS_cardinal_singleton. 
      reflexivity.
      rewrite <- mset_eq. 
      split. eapply Included_trans.
      eapply Setminus_Setminus_Included. tci.
      rewrite Setminus_Same_set_Empty_set, Union_Empty_set_neut_l...
      reflexivity...
      eapply Singleton_Included. constructor; eauto.
      intros Hc. inv Hc. eauto.
    - rewrite PS_cardinal_empty_l. reflexivity. 
      rewrite <- mset_eq. rewrite Setminus_Same_set_Empty_set. reflexivity. 
  Qed.
  

  Lemma project_vars_cost_alloc_eq Scope `{ToMSet Scope} Scope'
        Funs `{ToMSet Funs}
        Funs' `{ToMSet Funs'}
        fenv c Γ FVs xs C1 :
    project_vars Util.clo_tag Scope Funs fenv c Γ FVs xs C1 Scope' Funs' ->
    cost_alloc_ctx_CC C1 = 3 * PS.cardinal (@mset (Funs \\ Funs') _).
  Proof with (now eauto with Ensembles_DB).
    intros Hvar; induction Hvar; eauto.
    - rewrite PS_cardinal_empty_l. reflexivity. 
      rewrite <- mset_eq, Setminus_Same_set_Empty_set.
      reflexivity.
    - assert (Hvar' := H2); assert (Hvar'' := H2).
      eapply (project_var_ToMSet_Funs Scope1 Scope2 Funs1 Funs2) in  Hvar''; eauto. 
      rewrite cost_alloc_ctx_CC_comp_ctx_f. 
      eapply (@project_var_cost_alloc_eq Scope1 Scope2 Funs1 _  Funs2 _) in H2.
      rewrite H2. erewrite IHHvar; eauto.
      rewrite <- Nat.mul_add_distr_l.
      eapply Nat_as_OT.mul_cancel_l. omega.
      rewrite PS_cardinal_union.
      eapply Proper_carinal.
      eapply Same_set_From_set. setoid_rewrite <- mset_eq.
      rewrite FromSet_union.
      do 2 setoid_rewrite <- mset_eq at 1.
      rewrite Union_commut. erewrite Setminus_compose; tci.
      reflexivity. eapply project_vars_Funs_l. eassumption.
      eapply project_var_Funs_l. eassumption.
      eapply FromSet_disjoint.
      do 2 setoid_rewrite <- mset_eq at 1.
      eapply Disjoint_Setminus_l... tci.
      eapply project_var_ToMSet in Hvar'; tci.
  Qed.

    Lemma project_var_cost_eq'
        Scope Scope'  Funs Funs' fenv
        c Γ FVs x C1 :
    project_var Util.clo_tag Scope Funs fenv c Γ FVs x C1 Scope' Funs' ->
    cost_ctx_full_cc C1 <= 3.
  Proof with (now eauto with Ensembles_DB).
    intros Hvar; inv Hvar; eauto.
  Qed.

  Lemma project_vars_cost_eq'
        Scope Scope'  Funs Funs' fenv
        c Γ FVs xs C1 :
    project_vars Util.clo_tag Scope Funs fenv c Γ FVs xs C1 Scope' Funs' ->
    cost_ctx_full_cc C1 <= 3 * length xs.
  Proof with (now eauto with Ensembles_DB).
    intros Hvar; induction Hvar; eauto.
    rewrite cost_ctx_full_cc_ctx_comp_ctx_f. simpl.
    eapply le_trans. eapply plus_le_compat.
    eapply project_var_cost_eq'. eassumption. eassumption.
    omega.
  Qed.


  Lemma project_var_cost_eq
        Scope {_ : ToMSet Scope} Scope' {_ : ToMSet Scope'} Funs `{ToMSet Funs}
        Funs' `{ToMSet Funs'} fenv
        c Γ FVs x C1 :
    project_var Util.clo_tag Scope Funs fenv c Γ FVs x C1 Scope' Funs' ->
    cost_ctx_full C1 = 3 * PS.cardinal (@mset (Funs \\ Funs') _) +
                       PS.cardinal (@mset ((FromList FVs \\ Funs) :&: (Scope' \\ Scope)) _).
  Proof with (now eauto with Ensembles_DB).
    intros Hvar; inv Hvar; eauto.
    - rewrite !PS_cardinal_empty_l.
      reflexivity.
      rewrite <- mset_eq, Setminus_Same_set_Empty_set, Intersection_Empty_set_abs_r.
      reflexivity.
      rewrite <- mset_eq, Setminus_Same_set_Empty_set.
      reflexivity.
    - simpl cost_ctx_full.

      erewrite PS_cardinal_singleton. 
      erewrite PS_cardinal_empty_l. omega.
      rewrite <- mset_eq. 
      rewrite Setminus_Union_distr, (Setminus_Disjoint [set x]).
      rewrite Setminus_Same_set_Empty_set, Union_Empty_set_neut_r.
      rewrite Intersection_Disjoint.
      reflexivity.
      eapply Disjoint_Singleton_r. intros Hc; inv Hc; eauto.
      eapply Disjoint_Singleton_l. eassumption. 

      rewrite <- mset_eq.
      split. eapply Included_trans. eapply Setminus_Setminus_Included; tci...
      now eauto with Ensembles_DB. 
      
      eapply Singleton_Included. constructor; eauto.
      intros Hc. inv Hc; eauto. 
    - rewrite PS_cardinal_empty_l.
      erewrite PS_cardinal_singleton.
      simpl. reflexivity.
      + rewrite <- mset_eq.
        rewrite Setminus_Union_distr, (Setminus_Disjoint [set x]).
        rewrite Setminus_Same_set_Empty_set, Union_Empty_set_neut_r.
        rewrite Intersection_commut, Intersection_Same_set.
        reflexivity.
        eapply Singleton_Included.
        constructor. eapply nthN_In. eassumption.
        eassumption.
        eapply Disjoint_Singleton_l. eassumption.
      + rewrite <- mset_eq.
        rewrite Setminus_Same_set_Empty_set. reflexivity. 
  Qed.


  Lemma project_vars_cost_eq
        Scope `{ToMSet Scope} Scope' `{ToMSet Scope'} Funs `{ToMSet Funs}
        Funs' `{ToMSet Funs'}
        fenv c Γ FVs xs C1 :
    project_vars Util.clo_tag Scope Funs fenv c Γ FVs xs C1 Scope' Funs' ->
    cost_ctx_full C1 = 3 * PS.cardinal (@mset (Funs \\ Funs') _) +
                       PS.cardinal (@mset ((FromList FVs \\ Funs) :&: (Scope' \\ Scope)) _).
  Proof with (now eauto with Ensembles_DB).
    intros Hvar; induction Hvar; eauto.
    - rewrite !PS_cardinal_empty_l.

      reflexivity.
      rewrite <- mset_eq, Setminus_Same_set_Empty_set, Intersection_Empty_set_abs_r.
      reflexivity.
      rewrite <- mset_eq, Setminus_Same_set_Empty_set.
      reflexivity.
    - assert (Hvar' := H3). assert (Hvar'' := H3).
      assert (Hvar''' := H3).
      eapply project_var_ToMSet_Funs in Hvar''; eauto. 
      eapply project_var_ToMSet in Hvar'; eauto. 
      rewrite cost_ctx_full_ctx_comp_ctx_f. 
      eapply (@project_var_cost_eq Scope1 H Scope2 Hvar' Funs1 _ Funs2) in H3.
      rewrite H3. erewrite IHHvar; eauto.
      rewrite <- !plus_assoc, (plus_assoc _  (3 * _)), (plus_comm _ (3 * _)).
      rewrite !plus_assoc. 
      rewrite <- Nat.mul_add_distr_l.
      rewrite <- plus_assoc. eapply f_equal2_plus. 
      + eapply Nat_as_OT.mul_cancel_l. omega.
        rewrite PS_cardinal_union. 
        eapply Proper_carinal.  
        eapply Same_set_From_set. setoid_rewrite <- mset_eq.
        rewrite FromSet_union.
        do 2 setoid_rewrite <- mset_eq at 1.
        rewrite Union_commut, Setminus_compose. now eauto with typeclass_instances. 
        tci. eapply project_vars_Funs_l. eassumption.
        eapply project_var_Funs_l. eassumption.
        eapply FromSet_disjoint.
        do 2 setoid_rewrite <- mset_eq at 1.
        eapply Disjoint_Setminus_l...
      + rewrite PS_cardinal_union. 
        eapply Proper_carinal.  
        eapply Same_set_From_set. setoid_rewrite <- mset_eq.
        rewrite FromSet_union.
        do 2 setoid_rewrite <- mset_eq at 1.
        rewrite !(Intersection_commut _ (FromList FVs \\ _)).
        assert (Hvar1 := Hvar'''). eapply project_var_Scope_Funs_eq in Hvar'''. 
        rewrite Hvar'''.
        assert (Hseq : (Scope3 \\ Scope2) :&: (FromList FVs \\ (Funs1 \\ (Scope2 \\ Scope1))) <-->
                                          (Scope3 \\ Scope2) :&: (FromList FVs \\ Funs1)).
        { rewrite Intersection_commut. rewrite Intersection_Setmius_Setminus_Disjoint.
          rewrite Intersection_commut. reflexivity. 
          now eauto with Ensembles_DB. }

        rewrite Hseq.
        rewrite <- Intersection_Union_distr.
        eapply Same_set_Intersection_compat; [| reflexivity ].
        eapply Setminus_compose. now eauto with typeclass_instances.
        eapply project_var_Scope_l. eassumption.
        eapply project_vars_Scope_l. eassumption.
        eapply FromSet_disjoint.
        do 2 setoid_rewrite <- mset_eq at 1.
        eapply Disjoint_Included_l.  eapply Included_Intersection_compat.
        eapply Included_Setminus_compat. reflexivity. eapply project_var_Funs_l. eassumption.
        reflexivity. eapply Disjoint_Intersection_r.
        eapply Disjoint_Setminus_r...

        Grab Existential Variables. tci. 
  Qed.          
  

  Lemma project_var_Scope_Funs_subset Scope Scope' Funs Funs'
        fenv c Γ FVs xs C1 :
    project_var Util.clo_tag Scope Funs fenv c Γ FVs xs C1 Scope' Funs' ->
    Funs \\ Funs' \subset Scope' \\ Scope. 
  Proof.
    intros Hvar. inv Hvar.
    now eauto with Ensembles_DB.
    rewrite Setminus_Union_distr.
    eapply Included_Union_preserv_l.
    rewrite (Setminus_Disjoint [set xs]).
    eapply Setminus_Included_Included_Union.
    rewrite Union_Setminus_Included.
    now eauto with Ensembles_DB. tci. reflexivity. 
    eapply Disjoint_Singleton_l. eassumption. 

    now eauto with Ensembles_DB. 
  Qed.

  Lemma project_vars_Scope_Funs_subset
        Scope Scope' {_ : ToMSet Scope}
        Funs {_ : ToMSet Funs} Funs'
        fenv c Γ FVs xs C1 :
    project_vars Util.clo_tag Scope Funs fenv c Γ FVs xs C1 Scope' Funs' ->
    Funs \\ Funs' \subset Scope' \\ Scope. 
  Proof.
    intros Hvar. induction Hvar.

    now eauto with Ensembles_DB.

    rewrite <- Setminus_compose; [| | eapply project_vars_Funs_l; eassumption
                                 | eapply project_var_Funs_l; eassumption ]; tci. 
    rewrite <- Setminus_compose with (s3 := Scope3);
      [| | eapply project_var_Scope_l; eassumption
       | eapply project_vars_Scope_l; eassumption ]; tci. 

    rewrite (Union_commut (Scope2 \\ _)). 
    eapply Included_Union_compat.
    eapply IHHvar; tci.

    eapply project_var_ToMSet; [| eassumption ]; eauto.
    eapply project_var_ToMSet_Funs; [ | | eassumption ]; eauto.
    
    eapply project_var_Scope_Funs_subset. 
    eassumption.

    eapply Decidable_ToMSet. 
    eapply project_var_ToMSet; [| eassumption ]; eauto.
    eapply Decidable_ToMSet. 
    eapply project_var_ToMSet_Funs; [| | eassumption ]; eauto.
    
  Qed.
  
  Lemma PreCtxCompat_var_r C e1 e2 A δ
        Scope Scope' {_ : ToMSet Scope} {_ : ToMSet Scope'}
        Funs {_ : ToMSet Funs} Funs' {_ : ToMSet Funs'} S {_ : ToMSet S} 
        fenv c Γ FVs x :
    project_var Util.clo_tag Scope Funs fenv c Γ FVs x C Scope' Funs' ->
    x \in S ->
    IInvCtxCompat_r (Pre (Funs :&: S \\ Scope) A δ) (Pre (Funs' :&: S \\ Scope') A δ) C e1 e2.
  Proof.
    intros Hvar Hin.
    unfold IInvCtxCompat_r, Pre.
    intros H1' H2' H2'' rho1' rho2' rho2'' c1' Hm Hctx.
    erewrite (ctx_to_heap_env_CC_size_heap _ _ _ H2' H2''); [| eassumption ].
    erewrite (project_var_cost_alloc_eq Scope Scope' Funs Funs'); [| eassumption ].
    eapply le_trans with (m := size_heap H2' + (3 * PS.cardinal (@mset (Funs \\ Funs') _) +
                                                3 * PS.cardinal (@mset (Funs' :&: S \\ Scope') _))).
    omega.
     
    rewrite <- Nat.mul_add_distr_l.
    rewrite PS_cardinal_union. eapply le_trans; [| eassumption ].
    
    eapply plus_le_compat_l.
    eapply mult_le_compat_l.
    
    rewrite !PS.cardinal_spec. eapply Same_set_FromList_length.
    eapply NoDupA_NoDup. eapply PS.elements_spec2w.

    rewrite <- !FromSet_elements, !FromSet_union. rewrite <- !mset_eq.
    
    eapply Union_Included.

    eapply Included_Setminus.
    eapply Disjoint_Included_l. 
    eapply project_var_Scope_Funs_subset. eassumption.
    now eauto with Ensembles_DB.
    intros z Hc. inv Hc.  constructor. eassumption. 
    eapply project_var_Funs in H; try eassumption.
    inv H. inv H1; eauto. now exfalso; eauto.


    eapply Included_Setminus_compat.
    eapply Included_Intersection_compat. 
    eapply project_var_Funs_l; eassumption.
    reflexivity.
    eapply project_var_Scope_l; eassumption. 

    eapply FromSet_disjoint. rewrite <- !mset_eq...

    eapply Disjoint_Setminus_l.
    eapply Setminus_Included_Included_Union.
    eapply Included_trans. eapply Included_Intersection_l. 
    now eauto with Ensembles_DB. 
  Qed.

  Lemma PreCtxCompat_ctx_to_heap_env (C : exp_ctx) (e1 e2 : exp) A δ δ'
        Funs {_ : ToMSet Funs} Funs' {_ : ToMSet Funs'} :
    Funs' \subset Funs ->
    δ + cost_alloc_ctx_CC C <= δ' ->
    IInvCtxCompat_r (Pre Funs A δ) (Pre Funs' A δ') C e1 e2.
  Proof.
    intros Hsub Hleq.
    unfold IInvCtxCompat_r, Pre.
    intros H1' H2' H2'' rho1' rho2' rho2'' c1' Hm Hctx.
    erewrite (ctx_to_heap_env_CC_size_heap _ _ _ H2' H2''); [| eassumption ].
    assert (Hsubleq : 3 * PS.cardinal (@mset Funs' _) <= 3 * PS.cardinal (@mset Funs _)).
    { eapply mult_le_compat_l. eapply PS_elements_subset. eassumption. }
    omega.
  Qed.
  
  Lemma PostCtxCompat_ctx_r
        C e1 e2 k m A δ :
    cost_ctx_full_cc C + m = k ->
    InvCtxCompat_r (Post m A δ)
                   (Post_weak k A δ) C e1 e2.
  Proof. 
    unfold InvCtxCompat_r, Post.
    intros Hleq H1' H2' H2'' rho1' rho2' rho2'' c' c1 c2 m1 m2 
           Hcost Hleq1 Hctx'.
    edestruct Hcost as [[Hs1 Hs2] Hm]. eassumption. 
    assert (Hcost' := ctx_to_heap_env_CC_cost _ _ _ _ _ _ Hctx'). subst. 
    omega.
  Qed.
  
  Lemma PostCtxCompat_ctx_r_weak
        C e1 e2 k m A δ :
    cost_ctx_full_cc C + m = k ->
    InvCtxCompat_r (Post_weak m A δ)
                   (Post_weak k A δ) C e1 e2.
  Proof. 
    unfold InvCtxCompat_r, Post_weak.
    intros Hleq H1' H2' H2'' rho1' rho2' rho2'' c' c1 c2 m1 m2 
           Hcost Hleq1 Hctx'.
    edestruct Hcost as [[Hs1 Hs2] Hm]. eassumption. 
    assert (Hcost' := ctx_to_heap_env_CC_cost _ _ _ _ _ _ Hctx'). subst. 
    omega.
  Qed.


  Lemma PostCtxCompat_ctx_r_weak'
        C e1 e2 k m A δ :
    cost_ctx_full_cc C + m = k ->
    InvCtxCompat_r_strong (Post_weak m A δ)
                   (Post_weak k A δ) C e1 e2.
  Proof. 
    unfold InvCtxCompat_r, Post_weak.
    intros Hew H1' H2' H2'' rho1' rho2' rho2'' c' c1 c2 m1 m2 
           Hcost Hctx'. split; try omega.
    intros Hw.
    edestruct Hcost as [[Hs1 Hs2] Hm]. eassumption. 
    assert (Hcost' := ctx_to_heap_env_CC_cost _ _ _ _ _ _ Hctx'). subst. 
    omega.
  Qed.
  
  Lemma PreCtxCompat_vars_r
        Scope {Hs : ToMSet Scope} Scope' {Hs' : ToMSet Scope'} Funs {Hf : ToMSet Funs}
        S {HS : ToMSet S}
        Funs' {Hf' : ToMSet Funs'} fenv
        C e1 e2 c Γ FVs x A δ :
    FromList x \subset S ->
    project_vars Util.clo_tag Scope Funs fenv c Γ FVs x C Scope' Funs' ->
    IInvCtxCompat_r (Pre (Funs :&: S \\ Scope) A δ) (Pre (Funs' :&: S \\ Scope') A δ) C e1 e2.
  Proof.
    intros Hsub Hvar.
    unfold IInvCtxCompat_r, Pre.
    intros H1' H2' H2'' rho1' rho2' rho2'' k Hm Hctx. subst. eauto. 
    assert (Hcost := ctx_to_heap_env_CC_cost _ _ _ _ _ _ Hctx).
    subst.  
    assert (Heq := project_vars_cost_eq _ _ _ _ _ _ _ _ _ _ Hvar).  
    erewrite (ctx_to_heap_env_CC_size_heap _ _ _ H2' H2''); [| eassumption ].
    erewrite (project_vars_cost_alloc_eq Scope Scope' Funs Funs'); [| eassumption ].
    eapply le_trans; [| eassumption ].
    
    eapply le_trans with (m := size_heap H2' +
                               (3 * PS.cardinal (@mset (Funs \\ Funs') _) +
                                3 * PS.cardinal (@mset (Funs' :&: S \\ Scope') _))). 
    omega. 
    rewrite  <- Nat.mul_add_distr_l.
    rewrite PS_cardinal_union.

    eapply plus_le_compat_l. 
    eapply mult_le_compat_l.
    rewrite !PS.cardinal_spec. eapply Same_set_FromList_length.
    eapply NoDupA_NoDup. eapply PS.elements_spec2w.
    
    rewrite <- !FromSet_elements, !FromSet_union. rewrite <- !mset_eq.

    eapply Union_Included.

    eapply Included_Setminus.
    eapply Disjoint_Included_l. 
    eapply project_vars_Scope_Funs_subset; [| | eassumption]; tci.
    now eauto with Ensembles_DB.
    intros z Hc. inv Hc.  constructor. eassumption. 
    eapply project_vars_Funs in H; try eassumption.
    inv H. eapply Hsub. eassumption. now exfalso; eauto.

    eapply Included_Setminus_compat.
    eapply Included_Intersection_compat. 
    eapply project_vars_Funs_l; eassumption.
    reflexivity.
    eapply project_vars_Scope_l; eassumption. 

    eapply FromSet_disjoint. rewrite <- !mset_eq...

    eapply Disjoint_Setminus_l.
    eapply Setminus_Included_Included_Union.
    eapply Included_trans. eapply Included_Intersection_l. 
    now eauto with Ensembles_DB. 
  Qed.
  
  Lemma PostCtxCompat_vars_r
       Scope {Hs : ToMSet Scope} Scope' {Hs' : ToMSet Scope'} Funs {Hf : ToMSet Funs}
       Funs' {Hf' : ToMSet Funs'} fenv
       C e1 e2 c Γ FVs x k m A δ :
   project_vars Util.clo_tag Scope Funs fenv c Γ FVs x C Scope' Funs' ->
   cost_ctx_full_cc C + m = k ->
   InvCtxCompat_r (Post m A δ)
                  (Post_weak k A δ) C e1 e2.
   Proof.
    unfold InvCtxCompat_r, Post.
    intros Hvar Hleq H1' H2' H2'' rho1' rho2' rho2'' c' c1 c2 m1 m2 
           Hc Hleq2 Hctx'.
    edestruct Hc as  [[Hs1 Hs2] Hm]; eauto. 
    assert (Hcost := ctx_to_heap_env_CC_cost _ _ _ _ _ _ Hctx').
    assert (Heq := project_vars_cost_eq _ _ _ _ _ _ _ _ _ _ Hvar). subst.
    assert (Hcost := ctx_to_heap_env_CC_cost _ _ _ _ _ _ Hctx').
    subst.  
    unfold Post in *. omega.
   Qed.
   
   Lemma PostCtxCompat_vars_r'
         Scope {Hs : ToMSet Scope} Scope' {Hs' : ToMSet Scope'} Funs {Hf : ToMSet Funs}
         Funs' {Hf' : ToMSet Funs'} fenv
         C e1 e2 c Γ FVs x k m A δ :
     project_vars Util.clo_tag Scope Funs fenv c Γ FVs x C Scope' Funs' ->
     cost_ctx_full_cc C + m = k ->
     InvCtxCompat_r (Post m A δ)
                    (Post k A δ) C e1 e2.
   Proof.
     unfold InvCtxCompat_r, Post.
     intros Hvar Hleq H1' H2' H2'' rho1' rho2' rho2'' c' c1 c2 m1 m2 
            Hc Hleq2 Hctx'.
     edestruct Hc as  [[Hs1 Hs2] Hm]; eauto. 
     assert (Hcost := ctx_to_heap_env_CC_cost _ _ _ _ _ _ Hctx').
     assert (Heq := project_vars_cost_eq _ _ _ _ _ _ _ _ _ _ Hvar). subst.
     assert (Hcost := ctx_to_heap_env_CC_cost _ _ _ _ _ _ Hctx').
     subst.  
     unfold Post in *. omega.
   Qed.
  
  Lemma size_reachable_leq S1 `{HS1 : ToMSet S1}  S2 `{HS2 : ToMSet S2}
        H1 H2 k GIP GP b :
    (forall j, S1 |- H1 ≼ ^ (k ; j ; GIP ; GP ; b ) H2) ->
    S2 <--> image b S1 ->
    size_with_measure_filter size_val S2 H2 <= size_with_measure_filter size_val S1 H1.
  Proof with (now eauto with Ensembles_DB).
    assert (HS1' := HS1).
    revert HS1 S2 HS2.
    set (P := (fun S1 => 
                 forall (HS1 : ToMSet S1) (S2 : Ensemble positive) (HS2 : ToMSet S2),
                   (forall j, S1 |- H1 ≼ ^ (k ; j ; GIP ; GP ; b ) H2) ->
                   S2 <--> image b S1 ->
                   size_with_measure_filter size_val S2 H2 <=
                   size_with_measure_filter size_val S1 H1)). 
    assert (HP : Proper (Same_set var ==> iff) P).
    { intros S1' S2' Hseq. unfold P.
      split; intros.
      
      assert (HMS1' : ToMSet S1').
      { eapply ToMSet_Same_set. symmetry. eassumption. eassumption. }
       
      erewrite <- !(@HL.size_with_measure_Same_set _ _ _ _ _ _ _ Hseq).
      eapply H; try eassumption; repeat setoid_rewrite Hseq at 1; try eassumption.
      
      assert (HMS2' : ToMSet S2').
      { eapply ToMSet_Same_set; eassumption. }
      
      erewrite !(@HL.size_with_measure_Same_set _ _ _ _ _ _ _ Hseq).
      eapply H; try eassumption; repeat setoid_rewrite <- Hseq at 1; try eassumption. }
    eapply (@Ensemble_ind P HP); [| | eassumption ].
    - intros HS1 S2 HS2 Hcc Heq1.
      rewrite !HL.size_with_measure_filter_Empty_set.
      rewrite image_Empty_set in Heq1.
      erewrite (@HL.size_with_measure_Same_set _ _ _ _ _ _ _ Heq1).
      rewrite HL.size_with_measure_filter_Empty_set. omega.
    - intros x S1' HS Hnin IHS HS1 S2 HS2 Hheap Heq1.
      rewrite !image_Union, !image_Singleton in Heq1.
      
      assert (Hseq : S2 <--> b x |: (S2 \\ [set b x])).
      { eapply Union_Setminus_Same_set; tci.
        rewrite Heq1... }
       
      erewrite (HL.size_with_measure_Same_set _ S2 (b x |: (S2 \\ [set b x])));
        try eassumption.
      assert (Hyp : size_with_measure_filter size_val (S2 \\ [set b x]) H2 <=
                    size_with_measure_filter size_val S1' H1).
      { destruct (@Dec _ (image b S1') _ (b x)).
        - eapply le_trans. eapply HL.size_with_measure_filter_monotonic.
          eapply Setminus_Included.
          eapply IHS. 
          intros j. eapply cc_approx_heap_antimon; [| eapply Hheap ]...
          rewrite Heq1. rewrite Union_Same_set.
          reflexivity. 
          eapply Singleton_Included. eassumption.
        - eapply IHS. 
          intros j. eapply cc_approx_heap_antimon; [| eapply Hheap ]...
          rewrite Heq1. rewrite Setminus_Union_distr. 
          rewrite Setminus_Same_set_Empty_set, Union_Empty_set_neut_l.
          rewrite Setminus_Disjoint. reflexivity. 
          eapply Disjoint_Singleton_r. eassumption.
      }
      erewrite !HL.size_with_measure_filter_Union. 

      assert (Hyp' : size_with_measure_filter size_val [set b x] H2 <=
                     size_with_measure_filter size_val [set x] H1).
      { erewrite !HL.size_with_measure_Same_set with (S' := x |: Empty_set _) (H := H1);
        [| now eauto with Ensembles_DB ].
        erewrite !HL.size_with_measure_Same_set with (S' := (b x) |: Empty_set _) (H := H2);
          [| now eauto with Ensembles_DB ].
            
        edestruct (Hheap 1) as [Hcc | Henv]. now left.
        - destruct Hcc as [_ Hcc].
          destruct (get x H1) as [ [c vs1 | [fs |] [el|] | env] | ] eqn:Hgetl1; try contradiction.
          + destruct (get (b x) H2 ) as [ [c' vss | fs' [el |] | env'] | ] eqn:Hgetl2; try contradiction.
            
            erewrite HL.size_with_measure_filter_add_In;
              [| intros Hc; now inv Hc | eassumption ]. simpl.
            erewrite HL.size_with_measure_filter_add_In;
              [| intros Hc; now inv Hc | eassumption ] . simpl.
            destruct Hcc as [_ Hcc]. specialize (Hcc 0Nat.lt_0_1). 
            rewrite !HL.size_with_measure_filter_Empty_set. eapply Forall2_length in Hcc.
            omega.
          + destruct ( get (b x) H2 ) as [ [ c' [ | [lf |] [| [lenv |] [|]  ]] | | ] | ] eqn:Hgetl2; try contradiction.
            erewrite HL.size_with_measure_filter_add_In;
              [| intros Hc; now inv Hc | eassumption ]. simpl.
            erewrite HL.size_with_measure_filter_add_In;
              [| intros Hc; now inv Hc | eassumption ]. simpl.
            rewrite !HL.size_with_measure_filter_Empty_set. omega.
        - edestruct Henv as [_ [rho1 [c1 [vs1 [FVs [Hkey [Hnd [Hget1 [Hget2 Hall]]]]]]]]]. 
          erewrite HL.size_with_measure_filter_add_In;
            [| intros Hc; now inv Hc | eassumption ]. simpl.
          erewrite HL.size_with_measure_filter_add_In;
            [| intros Hc; now inv Hc | eassumption ]. simpl.
          rewrite !HL.size_with_measure_filter_Empty_set.
          rewrite <- !plus_n_O. eapply Peano.le_n_S.
          unfold size_env. rewrite PS.cardinal_spec.
          eapply Forall2_length in Hall. 
          rewrite <- Hall.
          eapply Same_set_FromList_length. eassumption.
          rewrite <- FromSet_elements, <- mset_eq.
          eapply Hkey. } 

      omega.
      
      
      eapply Disjoint_Singleton_l. eassumption. 
      eapply Disjoint_Setminus_r. reflexivity.

  Qed.
  

  Lemma cardinal_env_locs S {HS : ToMSet S} rho :
    (forall x, x \in S -> exists l, M.get x rho = Some (Loc l) /\ ~ l \in (env_locs rho (S \\ [set x]))) ->
    PS.cardinal (@mset S _) <= PS.cardinal (@mset (env_locs rho S) _).
  Proof with (now eauto with Ensembles_DB).
    assert (HS' := HS).
    revert HS.
    set (P := fun S1 => 
                forall (HS1 : ToMSet S1),
                  (forall x : positive, In positive S1 x ->
                  exists l, M.get x rho = Some (Loc l) /\ ~ l \in (env_locs rho (S1 \\ [set x]))) ->
                  PS.cardinal (@mset S1 _) <= PS.cardinal (@mset (env_locs rho S1) _)).
    assert (HP : Proper (Same_set var ==> iff) P).
    { intros S1' S2' Hseq. unfold P.
      split; intros. 
      eapply le_trans. eapply (PS_elements_subset S2' S1'). eapply Hseq.
      eapply le_trans; [| eapply (PS_elements_subset (env_locs _ S1') (env_locs _ S2')) ].
      eapply H. setoid_rewrite Hseq. eassumption. eapply env_locs_monotonic. eapply Hseq.

      eapply le_trans. eapply (PS_elements_subset S1' S2'). eapply Hseq.
      eapply le_trans; [| eapply (PS_elements_subset (env_locs _ S2') (env_locs _ S1')) ].
      eapply H. setoid_rewrite <- Hseq. eassumption. eapply env_locs_monotonic. eapply Hseq. }
    
    eapply (@Ensemble_ind P HP); [| | eassumption ]; unfold P; [ intros HS Hyp | intros x S1 HS1 ].
    
    - rewrite !PS_cardinal_empty_l. reflexivity.
      rewrite <- mset_eq. eapply env_locs_Empty_set.
      rewrite <- mset_eq. reflexivity.

    - intros Hnin IH Hun Hyp.
      rewrite Proper_carinal. 
      Focus 2.
      eapply Same_set_From_set. 
      rewrite <- (@mset_eq (x |: S1)) at 1.
      rewrite FromSet_union. eapply Same_set_Union_compat.
      eapply ToMSet_Singleton. eapply HS1.

      edestruct Hyp as [l [Hgetx Hgf]]. now left. 
      
      eapply le_trans; [| eapply PS_elements_subset with (S1 := l |: (env_locs rho S1)) ]. 
      
      erewrite Proper_carinal with (x := (@mset (l |: (env_locs rho S1)) _ )).
      Focus 2.
      eapply Same_set_From_set. 
      rewrite <- (@mset_eq (l |: _)) at 1.
      rewrite FromSet_union. eapply Same_set_Union_compat.
      eapply ToMSet_Singleton. eapply ToMSet_env_locs.
      
      rewrite <- !PS_cardinal_union.
      erewrite !(PS_cardinal_singleton (@mset [set x] _)).
      erewrite !(PS_cardinal_singleton (@mset [set l] _)).
      
      eapply plus_le_compat_l. eapply le_trans. eapply IH.
      intros. edestruct Hyp as [l1 [Hget Hf]]. right. eassumption.
      eexists; split; eauto. intros H1. eapply Hf. 
      eapply env_locs_monotonic; [| eassumption ]... reflexivity.
      
      rewrite <- mset_eq. reflexivity.
      rewrite <- mset_eq. reflexivity.

      eapply FromSet_disjoint. rewrite <- !mset_eq. 
      eapply Disjoint_Singleton_l. intros Hc. eapply Hgf.
      eapply env_locs_monotonic; [| eassumption ]...
      
      eapply FromSet_disjoint. rewrite <- !mset_eq. 
      eapply Disjoint_Singleton_l. eassumption.

      rewrite env_locs_Union, env_locs_Singleton; eauto. reflexivity. 

      Grab Existential Variables.
      eapply ToMSet_Same_set; eassumption.
      eapply ToMSet_Same_set. symmetry. eassumption. eassumption. 
  Qed.

  Lemma def_closures_env_locs S B B0 H rho H' rho' v x :
    S \subset name_in_fundefs B ->
    x \in S ->
    def_closures B B0 rho H v = (H', rho') ->
    exists l, M.get x rho' = Some (Loc l) /\
    ~ l \in env_locs rho' (S \\ [set x]).
  Proof with (now eauto with Ensembles_DB).
    revert S H' rho'.
    induction B; intros S H' rho' Hin1 Hin2 Hdef.
    - simpl in Hdef.
      destruct (def_closures B B0 rho H v) as [H2 rho2] eqn:Hclo'.
      destruct (alloc (Clos (FunPtr B0 v0) v) H2) as [l' H3] eqn:Hal.
      inv Hdef.

      destruct (var_dec x v0); subst.
      + rewrite M.gss. eexists; split; eauto. intros Hc.
        rewrite env_locs_set_not_In in Hc; [| intros Hc'; inv Hc'; now eauto ].
        eapply env_locs_monotonic in Hc.
        eapply def_closures_env_locs_in_dom with (S := Empty_set _) in Hc; try eassumption.
        eapply HL.alloc_not_In_dom. eassumption. eassumption.

        rewrite env_locs_Empty_set...
        rewrite Union_Empty_set_neut_l.
        eapply Setminus_Included_Included_Union. eapply Included_trans. eassumption.
        simpl...
      + setoid_rewrite M.gso; eauto.
        edestruct IHB  with (S := S \\ [set v0]) as [l0 [Hget0 Hsub0]].
        
        eapply Setminus_Included_Included_Union. eapply Included_trans. eassumption.
        simpl...

        constructor; eauto. intros Hc'; inv Hc'; now eauto.
        reflexivity.

        eexists. split; eauto.
        
        intros Hc. eapply env_locs_set_Inlcuded' in Hc. inv Hc.
        * inv H0. eapply HL.alloc_not_In_dom. eassumption.
          eapply def_closures_env_locs_in_dom with (S := Empty_set _); try eassumption.
          
          rewrite env_locs_Empty_set... 

          eapply get_In_env_locs; try eassumption; [| reflexivity ].
          right. eapply Hin1 in Hin2. inv Hin2. inv H0; contradiction.
          eassumption.
        * rewrite @Setminus_Union in *. rewrite Union_commut in H0; eauto.
    - eapply Hin1 in Hin2. inv Hin2. 
  Qed. 

      
  Lemma size_with_measure_filter_def_closures
        S {HS : ToMSet S} g H1 H1' rho1 rho1' B B0 rho f
        (Hyp : forall B v f rho, g (Clos (FunPtr B v) rho) = g (Clos (FunPtr B f) rho)) : 
    unique_functions B ->
    S \subset env_locs rho1' (name_in_fundefs B) ->
    def_closures B B0 rho1 H1 rho = (H1', rho1') ->
    size_with_measure_filter g S H1' = (g (Clos (FunPtr B0 f) rho)) * (PS.cardinal (@mset S _)).
  Proof.
    revert S HS H1 H1' rho1'.
    induction B; intros S HS H1 H1' rho1' Hun Hin Hclo.
    - simpl in Hclo.
      destruct (def_closures B B0 rho1 H1 rho) as [H2 rho2] eqn:Hclo'.
      destruct (alloc (Clos (FunPtr B0 v) rho) H2) as [l' H3] eqn:Hal.
      
      inv Hun. inv Hclo.

      destruct (@Dec _ S _ l').
      + assert (Hseq : S <--> l' |: (S \\ [set l'])). 
        { rewrite Union_Setminus_Included. rewrite Union_Same_set. reflexivity.
          eapply Singleton_Included; eauto. tci.
          eapply Singleton_Included; eauto. }

        erewrite (@HL.size_with_measure_Same_set _ _ _ _ _ _ _ Hseq).
        erewrite HL.size_with_measure_filter_add_In; [| | eapply gas; eauto ].   

        rewrite Proper_carinal. Focus 2.
        eapply Same_set_From_set with (s2 := @mset (l' |: (S \\ [set l'])) _).
        do 2 rewrite <- mset_eq. eassumption.

        rewrite Proper_carinal. Focus 2.
        eapply Same_set_From_set. 
        rewrite <- (@mset_eq (l' |: (S \\ [set l']))) at 1.
        rewrite FromSet_union. eapply Same_set_Union_compat.
        eapply ToMSet_Singleton.
        eapply ToMSet_Setminus.
        
        rewrite <- PS_cardinal_union.
        simpl. rewrite Nat.mul_add_distr_l.
        eapply f_equal2_plus.
        
        rewrite <- (Nat.mul_1_r (g _)). erewrite (Hyp B0 v f).
        f_equal. erewrite PS_cardinal_singleton. reflexivity.
        
        replace 1 with (length [l']) by reflexivity.
        rewrite <- mset_eq. 
        repeat normalize_sets. reflexivity.
        
        erewrite HL.size_with_measure_filter_alloc_in; [| reflexivity | eassumption | ]. 
        eapply IHB; try eassumption.
        
        eapply Setminus_Included_Included_Union. eapply Included_trans. eassumption.

        eapply Included_trans. eapply env_locs_set_Inlcuded'. simpl.
        rewrite Union_commut. eapply Included_Union_compat; [| reflexivity ]. 
        eapply env_locs_monotonic. now eauto with Ensembles_DB.

        intros Hc; inv Hc; eauto. 
        eapply FromSet_disjoint.  rewrite <- !mset_eq. 
        eapply Disjoint_Singleton_l. 
        intros Hc; inv Hc; eauto. 
        intros Hc; inv Hc; eauto. 
      + erewrite HL.size_with_measure_filter_alloc_in; [| reflexivity | eassumption | eassumption ]. 
        eapply IHB; try eassumption.

        rewrite <- (Setminus_Disjoint S [set l']); tci. 
        eapply Setminus_Included_Included_Union.
        eapply Included_trans. eassumption.
        eapply Included_trans. eapply env_locs_set_Inlcuded'. simpl.
        rewrite Union_commut. eapply Included_Union_compat; [| reflexivity ]. 
        eapply env_locs_monotonic. now eauto with Ensembles_DB.
        
        eapply Disjoint_Singleton_r. eassumption. 
    - inv Hclo. simpl. 
      rewrite PS_cardinal_empty_l. rewrite <- mult_n_O.
      erewrite (HL.size_with_measure_Same_set _ S (Empty_set _)).
      rewrite HL.size_with_measure_filter_Empty_set. reflexivity.
      rewrite env_locs_Empty_set in Hin. now eauto with Ensembles_DB. 
      rewrite <- @mset_eq.
      rewrite env_locs_Empty_set in Hin. now eauto with Ensembles_DB. 
  Qed.

    
  Lemma GC_pre 
        (H1 H1' H2 Hgc2: heap block)
        env_loc1 env_loc2
        (rho_clo rho_clo1 rho_clo2 rho2 rho2' : env)
        (B1 B2 : fundefs) (f1 f2 : var) (ct1 ct2 : cTag)
        (xs1 xs2 : list var) (e1 e2 : exp) c
        (vs1 vs2 : list value) 
        fls d
        Scope {Hs : ToMSet Scope} β k : (* existentials *) 
        
        get env_loc1 H1 = Some (Env rho_clo) ->
        find_def f1 B1 = Some (ct1, xs1, e1) ->
        def_closures B1 B1 rho_clo H1 (Loc env_loc1) = (H1', rho_clo1) ->
        setlist xs1 vs1 rho_clo1 = Some rho_clo2 ->
        
        Some rho2' =
        setlist xs2 (Loc env_loc2 :: vs2) (def_funs B2 B2 (M.empty value)) ->
        find_def f2 B2 = Some (ct2, xs2, e2) ->
        live' ((env_locs rho2') (occurs_free e2)) H2 Hgc2 d ->

        get env_loc2 H2 = Some (Constr c fls) ->
        length fls = PS.cardinal (fundefs_fv B1) ->
        
        (forall j, Scope |- H1 ≼ ^ ( k ; j ; PreG ; PostG ; β ) H2) ->

        Disjoint M.elt (name_in_fundefs B1 :&: occurs_free e1) (FromList xs1) ->
        unique_functions B1 ->

        (** To show size relation  **)

        (* Scope <--> vs :&: FVs *)
        Scope :|: (* reachable from xs or FVs of post name :&: FV(e1) *)
        env_locs rho_clo2 (name_in_fundefs B1 :&: occurs_free e1) (* closures *) \subset
        reach' H1' ((env_locs rho_clo2) (occurs_free e1)) ->
        
        reach' H2 ((env_locs rho2') (occurs_free e2)) \subset
        env_loc2 |: image β Scope  (* reachable from xs or Γ *) ->
        
        PreG (name_in_fundefs B1 :&: occurs_free e1)
             (reach_size H1' rho_clo2 e1)
             (1 + PS.cardinal (fundefs_fv B1))
             (H1', rho_clo2, e1) (Hgc2, subst_env d rho2', e2).
  Proof with (now eauto with Ensembles_DB).
    intros Hgetenv1 Hfd1 Hst1 Hl1 Hs2 Hdf2 Hl2 Hget Hlen Hreach Hdis Hun Heq1 Heq2. 
    unfold PreG, Pre.
    unfold reach_size, size_reachable, size_heap.
    assert (Hdis' : Disjoint loc Scope
                             (env_locs rho_clo2 (name_in_fundefs B1 :&: occurs_free e1))). 
    { eapply Disjoint_Included_r.
      rewrite <- env_locs_setlist_Disjoint; try eassumption.
      eapply env_locs_monotonic. eapply Included_Intersection_l.
      eapply Disjoint_Included_l; [| eapply Disjoint_sym; eapply def_closures_env_locs_Disjoint ; eassumption ].
      eapply cc_approx_heap_dom1 with (j := 0). eapply Hreach. }
    
    
    assert (Hseq : (env_loc2 |: image β Scope) <--> (env_loc2 |: (image β Scope \\ [set env_loc2]))). 
    { rewrite Union_Setminus_Included. reflexivity. tci. reflexivity. }
 
    assert (Hsize : size_with_measure_filter size_val (reach' H2 (env_locs rho2' (occurs_free e2))) H2
                    + 3 * PS.cardinal (@mset (name_in_fundefs B1 :&: occurs_free e1) _) <=
                    size_with_measure_filter size_val (reach' H1' (env_locs rho_clo2 (occurs_free e1))) H1'
                    + (1 + PS.cardinal (fundefs_fv B1))).
    { eapply le_trans. 
      eapply plus_le_compat_r. 
      eapply (@HL.size_with_measure_filter_monotonic _ _ _ _ _ _ ) in Heq2. eassumption.
      assert (Heq1' := Heq1). 
      eapply (@HL.size_with_measure_filter_monotonic _ _ _ _ _ _ ) in Heq1; tci.  
      eapply le_trans; [| eapply plus_le_compat_r; eassumption ]. 
      
      erewrite !HL.size_with_measure_filter_Union with (S1 := Scope). 
      (* Closure env size *)
      assert (Hsize1 : size_with_measure_filter size_val (env_loc2 |: image β Scope) H2 <=
                       1 + PS.cardinal (fundefs_fv B1)
                       + size_with_measure_filter size_val (image β Scope) H2). 
      { erewrite (HL.size_with_measure_Same_set _ _ _ _ _ Hseq).
        erewrite HL.size_with_measure_filter_add_In; try eassumption.
        eapply plus_le_compat. simpl. omega.
        eapply HL.size_with_measure_filter_monotonic. now eauto with Ensembles_DB.
        intros Hc; inv Hc. eauto. } 
      (* reachable part *)
      assert (Hsize2 : size_with_measure_filter size_val (image β Scope) H2 <=
                       size_with_measure_filter size_val Scope H1).
      { eapply size_reachable_leq. eassumption. reflexivity. }
      
      assert (Hlem : forall f, size_with_measure_filter f Scope H1 = size_with_measure_filter f Scope H1'). 
      { intros f. eapply HL.size_with_measure_filter_subheap_eq.
        now eapply def_funs_subheap; eauto. 
        eapply cc_approx_heap_dom1 with (j := 0). now eauto.  }
      
      rewrite <- !Hlem.
      (* def_closure *)
      assert (Hclos : 3 * PS.cardinal (@mset (name_in_fundefs B1 :&: occurs_free e1) _) <=
                      size_with_measure_filter size_val (env_locs rho_clo2 (name_in_fundefs B1 :&: occurs_free e1)) H1').
      { erewrite size_with_measure_filter_def_closures with (f := f1); try eassumption.
        simpl size_val. eapply mult_le_compat_l.
         
        eapply cardinal_env_locs. intros.
        setoid_rewrite <- env_locs_setlist_Disjoint; try eassumption.
        setoid_rewrite <- setlist_not_In; try eassumption. eapply def_closures_env_locs; try eassumption.

        eapply Included_Intersection_l.
        intros Hc. eapply Hdis. now constructor; eauto.
        eapply Disjoint_Included_l ; [| eassumption ]... 

        intros. reflexivity.

        rewrite <- env_locs_setlist_Disjoint; try eassumption.
        eapply env_locs_monotonic. now eapply Included_Intersection_l. }
      (* lemma size_with_measure_filter def_closures *)
      omega. eassumption. }
    assert (Hl1' := Hl1). 
    eapply live_size_with_measure in Hl2.
    rewrite Hl2. now eapply Hsize. 
    intros. eapply block_equiv_size_val. eassumption. 
  Qed.   

End Size.
