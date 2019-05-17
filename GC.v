(* Garbage collection definitions for L6. Part of the CertiCoq project.
 * Author: Zoe Paraskevopoulou, 2016
 *)

From Coq Require Import NArith.BinNat Relations.Relations MSets.MSets
         MSets.MSetRBT Lists.List omega.Omega Sets.Ensembles Relations.Relations
         Classes.Morphisms Sorting.Permutation Lists.SetoidPermutation.
From SFS Require Import cps cps_util set_util List_util Ensembles_util functions
     identifiers tactics map_util.
From SFS Require Import heap heap_defs heap_equiv.

From SFS Require Import Coqlib.

Import ListNotations.

Open Scope Ensembles_scope.
Close Scope Z_scope.


Module GC (H : Heap).

  Module Equiv := HeapEquiv H.

  Import H Equiv.Defs.HL Equiv.Defs Equiv.

  (** GC specs **)

  (** Using S as the set of roots, garbage collect H1 *) 
  Definition collect (S : Ensemble loc) (H1 H2 : heap block) : Prop :=
    size_heap H2 <= size_heap H1 /\
    exists β,
      S |- H1 ≃_(β, id) H2 /\ (* locations outside S might be renamed! *)
          injective_subdomain (reach' H1 S) β.
  
  (** [live S H1 H2] iff H2 is the live portion of H1, using S as roots *)
  Definition live (S : Ensemble loc) (H1 H2 : heap block) β : Prop :=
    dom H2 \subset reach' H2 S /\
    S |- H1 ≃_(id, β) H2 /\
    injective_subdomain (reach' H2 S) β.

  Definition live' (S : Ensemble loc) (H1 H2 : heap block) β : Prop :=
    dom H2 \subset reach' H2 (image β S) /\   
    S |- H1 ≃_(β, id) H2 /\
    injective_subdomain (reach' H1 S) β.


  (** * Lemmas about [collect] -- DEPRICATED *)
  
  (** The reachable part of the heap before and after collection are the same *)
  Lemma collect_heap_eq S H1 H2 :
    collect S H1 H2 ->
    exists β,
      S |- H1 ≃_(β, id) H2 /\
          injective_subdomain (reach' H1 S) β.
  Proof.
    firstorder.
  Qed.
  
  Lemma collect_size S H1 H2 :
    collect S H1 H2 ->
    size_heap H2 <= size_heap H1.
  Proof.
    now firstorder.
  Qed.

  
  (** * Lemmas about [live] *)  
  
  Lemma heap_eq_res_approx_l P (k : nat) (H1 H2 : heap block) (v : value) :
    P |- H1 ≡ H2 ->
    reach' H1 (val_loc v) \subset P ->
    res_approx_fuel k (id, (v, H1)) (id, (v, H2)).
  Proof with (now eauto with Ensembles_DB).
    revert v. induction k as [k IHk] using lt_wf_rec1.
    intros v Heq Hsub.
    rewrite res_approx_fuel_eq.
    destruct v as [l|]; simpl; eauto.
    destruct (get l H1) as [b|] eqn:Hget; eauto. split; [ reflexivity |]. 
    destruct b as [c vs1 | v1 v2 | rho1].
    + eexists. split.
      erewrite <- Heq. eassumption. eapply Hsub. eapply reach'_extensive. reflexivity.
      intros.
      eapply Forall2_refl_strong. 
      intros v HIn. eapply IHk; eauto. eapply Included_trans; [| eassumption ].
      simpl. rewrite (reach_unfold H1 [set l]). eapply Included_Union_preserv_r.
      rewrite post_Singleton; try eassumption. eapply reach'_set_monotonic.
      simpl. eapply In_Union_list. eapply in_map. eassumption.
    + do 2 eexists. split.
      rewrite <- Heq. eassumption. eapply Hsub. eapply reach'_extensive.
      reflexivity. 
      intros. split; eapply IHk; eauto.
      eapply Included_trans; [| eassumption ].
      simpl. rewrite (reach_unfold H1 [set l]). eapply Included_Union_preserv_r.
      rewrite post_Singleton; try eassumption. eapply reach'_set_monotonic...
      eapply Included_trans; [| eassumption ].
      simpl. rewrite (reach_unfold H1 [set l]). eapply Included_Union_preserv_r.
      rewrite post_Singleton; try eassumption. eapply reach'_set_monotonic...      
    + eexists. split.
      rewrite <- Heq. eassumption.
      eapply Hsub. eapply reach'_extensive. reflexivity.
      intros. destruct (M.get x rho1) eqn:Hgetx; eauto.
      left. do 2 eexists. split. reflexivity. 
      split. reflexivity.
      intros i Hlt. eapply IHk; eauto.
      eapply Included_trans; [| eassumption ].
      simpl. rewrite (reach_unfold H1 [set l]). eapply Included_Union_preserv_r.
      rewrite post_Singleton; try eassumption. eapply reach'_set_monotonic.
      eapply get_In_env_locs; [| eassumption ]. now constructor. 
  Qed.

  Lemma heap_eq_res_equiv P (H1 H2 : heap block) (v : value) :
    P |- H1 ≡ H2 ->
    reach' H1 (val_loc v) \subset P ->
    (v, H1) ≈_(id, id) (v, H2).
  Proof with (now eauto with Ensembles_DB).
    intros Heq Hsub i; split; eapply heap_eq_res_approx_l; try eassumption.
    symmetry. eassumption.
    eapply Included_trans; [| eassumption ]. 
    rewrite <- reach'_heap_eq. reflexivity.
    eapply heap_eq_antimon; [| eassumption ]. eassumption.
  Qed.

    
  Lemma live_exists S H (_ : ToMSet S) :
    exists H' b, live S H H' b.
  Proof.
    edestruct (restrict_exists _ (reach' H S) H) as [Hr Hres]. tci.
    assert (Hreq := Hres). eapply restrict_heap_eq in Hreq.
  
    eexists Hr, id.

    split; [| split ]. 
    - rewrite restrict_domain; [| | eassumption ]; tci.
      rewrite reach'_heap_eq; [| eassumption ].
      eapply Included_Intersection_r.
    - intros x Hin. eapply heap_eq_res_equiv; try eassumption.
      simpl. eapply reach'_set_monotonic. eapply Singleton_Included. eassumption.
    - clear. now firstorder.
  Qed. 

  Lemma live_exists' S H (_ : ToMSet S) :
    exists H' b, live' S H H' b.
  Proof.
    edestruct (restrict_exists _ (reach' H S) H) as [Hr Hres]. tci.
    assert (Hreq := Hres). eapply restrict_heap_eq in Hreq.
    
    eexists Hr, id.

    split; [| split ]. 
    - rewrite restrict_domain; [| | eassumption ]; tci.
      rewrite reach'_heap_eq; [| eassumption ].
      rewrite image_id. eapply Included_Intersection_r.
    - intros x Hin. eapply heap_eq_res_equiv; try eassumption.
      simpl. eapply reach'_set_monotonic. eapply Singleton_Included. eassumption.
    - clear. now firstorder.
  Qed.
    
  Lemma Proper_live S1 S2 (HS1 : ToMSet S1) (HS2 : ToMSet S2) H1 H2 b1 :
    S1 <--> S2 ->
    live S1 H1 H2 b1 ->
    live S2 H1 H2 b1 .
  Proof.
    intros Heq Hl; unfold live in *. rewrite <- !Heq at 1. 
    eassumption.
  Qed.


  Lemma live_live'_inv S b  H1 H2 :
    live S H1 H2 b ->
    exists b', live' (image b S) H1 H2 b' /\ inverse_subdomain (reach' H2 S) b b'.
  Abort.

  Lemma live'_live_inv S { _ : ToMSet S} b H1 H2 :
    live' S H1 H2 b ->
    exists b', live (image b S) H1 H2 b' /\ inverse_subdomain (reach' H1 S) b b'.
  Proof.
    intros [Hl1 [Hl2 Hl3]].
    edestruct inverse_exists as [b' [Hinv Hinj']]; [| eassumption | ].
    now tci.
    eexists b'. split; [| eassumption ].
    split; [| split ].
    + eassumption.
    + eapply heap_equiv_inverse_subdomain; eassumption. 
    + rewrite <- heap_equiv_reach_eq. eassumption. eassumption.
  Qed.
  
  
  Instance Proper_live' : Proper (Same_set _ ==> eq ==> eq ==> eq ==> iff) live'. 
  Proof. 
    intros s1 s2 Hseq x1 x2 Hxeq y1 y2 Hyeq z1 z2 Hzeq; subst.
    unfold live'. rewrite !Hseq. reflexivity.
  Qed.

  Instance Proper_livei : Proper (Same_set _ ==> eq ==> eq ==> eq ==> iff) live.
  Proof. 
    intros s1 s2 Hseq x1 x2 Hxeq y1 y2 Hyeq z1 z2 Hzeq; subst.
    unfold live. rewrite !Hseq. reflexivity.
  Qed.

  
  Lemma live_deterministic S (_ : set_util.ToMSet S) H1 H2 H2' b b' :
    live' S H1 H2 b ->
    live' S H1 H2' b' ->
    (exists b1, image b S |- H2 ≃_(b1, id) H2' /\
           injective_subdomain (reach' H2 (image b S)) b1).
  Proof.
    intros Hl1 Hl2.
    edestruct (live'_live_inv S b H1 H2) as [d [Hld [Heq1 Heq2]]].
    eassumption.
    revert Hl2 Hld .
    intros [Hl1' [Hl2' Hl3]] [Hl1'' [Hl2'' Hl3']].
    eexists (compose b' d).
    split. eapply heap_equiv_compose_l.
    eapply heap_equiv_symm. eassumption.
    eapply heap_equiv_antimon; [  eapply Hl2' | ].
    rewrite <- image_compose, image_f_eq_subdomain.
    rewrite image_id. reflexivity.
    eapply f_eq_subdomain_antimon; [| eassumption ]. 
    eapply reach'_extensive.

    eapply heap_equiv_symm in Hl2''. eapply heap_equiv_reach_eq in Hl2''. 
    eapply injective_subdomain_compose. eassumption.
    eapply injective_subdomain_Proper_Same_set. eassumption.
    reflexivity. rewrite <- image_compose.
    eapply injective_subdomain_antimon. eassumption.
    rewrite image_f_eq_subdomain;
      [| eapply f_eq_subdomain_antimon ].
    rewrite image_id. reflexivity.
    reflexivity.
    eapply f_eq_subdomain_antimon; [| eassumption ].
    eapply reach'_extensive. 
  Qed.

  Lemma res_equiv_subst_val (S : Ensemble var) (b1 b2 : loc -> loc) (H1 H2 : heap block)
        (v1 v2 : value):
    (v1, H1) ≈_( b1, b2) (v2, H2) ->
    subst_val b1 v1 = subst_val b2 v2. 
  Proof.
    intros Heq. rewrite res_equiv_eq in Heq.
    destruct v1; destruct v2; try contradiction.
    - simpl. f_equal. eapply res_equiv_locs_eq. exact (Empty_set _).
      rewrite res_equiv_eq. eassumption.
    - simpl. inv Heq. reflexivity. 
  Qed. 

  (** Aux relation for showing the size lemmas *)

  Definition subst_block_rel b1 b2 (bl1 bl2 : block) : Prop :=
    match bl1, bl2 with
      | Constr c vs1, Constr c' vs2 => Forall2 (fun v1 v2 => subst_val b2 v2 = subst_val b1 v1)
                                              vs1 vs2
      | Clos v1 v2, Clos v1' v2' => subst_val b1 v1 = subst_val b2 v1' /\
                                   subst_val b1 v2 = subst_val b2 v2'
      | Env rho1, Env rho2 => key_set rho1 <--> key_set rho2
      | _, _ => False
    end. 
    
  Lemma block_equiv_subst_block b1 b2 H1 H2 bl1 bl2 :
    block_equiv ((b1, H1), bl1) ((b2, H2), bl2) ->
    subst_block_rel b1 b2 bl1 bl2.
  Proof.
    intros Hb. 
    destruct bl1 as [c1 vs1 | v1 v2 | rho1 ];
      destruct bl2 as [c2 vs2 | v1' v2' | rho2 ]; try contradiction.
    - destruct Hb as [Heq1 Hall]. subst. simpl.
      eapply Forall2_monotonic; [| eassumption ].
      simpl. intros v1 v2 Heq.
      symmetry.
      eapply res_equiv_subst_val. exact (Empty_set _). eassumption. 
    - destruct Hb as [Hb Hb2]. simpl. split.
      eapply res_equiv_subst_val. exact (Empty_set _). eassumption. 
      eapply res_equiv_subst_val. exact (Empty_set _). eassumption. 
    - simpl in Hb.
      eapply heap_env_equiv_key_set. 
      eassumption. 
  Qed.
  
      
  Lemma heap_elements_filter_PermutationA S {Hs : ToMSet S} (R : relation block) {_ : PreOrder R} H1 H2 b1 :
    S |- H1 ≃_(b1, id) H2 ->
    injective_subdomain S b1 ->
    (forall bl1 bl2, block_equiv (b1, H1, bl1) (id, H2, bl2) -> R bl1 bl2) -> 

    PermutationA
      (fun p1 p2 => let '(l1, bl1) := p1 in let '(l2, bl2) := p2 in
                 R bl1 bl2)
      (heap_elements_filter S H1)
      (heap_elements_filter (image b1 S) H2).
  Proof with (now eauto with Ensembles_DB).
    intros Heq Hinj Hr.
    pose (P := fun S => forall {Hs : ToMSet S},
                       S |- H1 ≃_(b1, id) H2 ->
                       injective_subdomain S b1 ->
                       PermutationA
                         (fun p1 p2 : loc * block =>
                            let '(_, bl1) := p1 in let '(_, bl2) := p2 in R bl1 bl2)
                         (heap_elements_filter S H1) (heap_elements_filter (image b1 S) H2)).
    assert (Hs' := Hs). revert Hs Heq Hinj. 
    eapply Ensemble_ind with (P := P).
    - intros S1 S2 Heq. unfold P; split.
      
      intros Hp1 Hs Hseq Hinj.  
      erewrite <- !(heap_elements_filter_set_Equal _ S1 S2); [| eassumption ].
      erewrite <- !(heap_elements_filter_set_Equal _ (image b1 S1) (image b1 S2)); [| ].
      rewrite <- !Heq in *. eapply Hp1; try eassumption. rewrite Heq. reflexivity. 

      intros Hp1 Hs Hseq Hinj.  
      erewrite !(heap_elements_filter_set_Equal _ S1 S2); [| eassumption ].
      erewrite !(heap_elements_filter_set_Equal _ (image b1 S1) (image b1 S2)); [| ].
      rewrite !Heq in *. eapply Hp1; try eassumption. rewrite Heq. reflexivity. 
      
    - intros He Heq Hinj.
      erewrite heap_elements_filter_Empty_set. 
      erewrite heap_elements_filter_set_Equal; [| rewrite image_Empty_set; reflexivity ]. 
      erewrite heap_elements_filter_Empty_set.
      now constructor. 
    - unfold P. intros l S0 Hs0 Hnin IH HS Heq Hinj.
      
      assert (Hres : (Loc l, H1) ≈_(b1, id) (Loc (b1 l), H2)). 
      { eapply Heq. now left. }

      assert (Hpre : PreOrder
                       (fun p1 p2 : loc * block =>
                          let '(_, bl1) := p1 in let '(_, bl2) := p2 in R bl1 bl2)). 
      { constructor.
        - intros [l1 bl1]. reflexivity.
        - intros [l1 bl1] [l2 bl2] [l3 bl3]. eapply transitivity. }

      rewrite res_equiv_eq in Hres. destruct Hres as [_ Hres]. 
      
      destruct (get l H1) eqn:Hget1; destruct (get (b1 l) H2) eqn:Hget2; try contradiction. 
      
      + eapply PermutationA_respects_Permutation_l; [ eassumption |
                                                    | symmetry; eapply heap_elements_filter_add; eassumption ].
        
        erewrite heap_elements_filter_set_Equal with (S1 := image b1 (l |: S0))
                                                       (S2 := (b1 l) |: image b1 S0).
        
        eapply PermutationA_respects_Permutation_r; [ eassumption |
                                                    | symmetry; eapply heap_elements_filter_add; try eassumption ].

        eapply permA_skip. now eauto. 
        
        eapply IH. eapply heap_equiv_antimon. eassumption. now eauto with Ensembles_DB. 

        eapply injective_subdomain_antimon; [ eassumption | ]...

        eapply injective_subdomain_Union_not_In_image in Hinj; [| eapply Disjoint_Singleton_l; eassumption ].  

        intros Hc. eapply Hinj. constructor; eauto. rewrite image_Singleton. reflexivity.

        rewrite image_Union, image_Singleton. reflexivity.

      + eapply PermutationA_respects_Permutation_l; [ eassumption |
                                                    | symmetry; eapply heap_elements_filter_add_not_In; eassumption ].
        erewrite heap_elements_filter_set_Equal with
        (S1 := image b1 (l |: S0))
        (S2 := (b1 l) |: image b1 S0).
        
        eapply PermutationA_respects_Permutation_r; [ eassumption |
                                                    | symmetry; eapply heap_elements_filter_add_not_In;
                                                      try eassumption ].

        eapply IH. eapply heap_equiv_antimon. eassumption. now eauto with Ensembles_DB.
        
        eapply injective_subdomain_antimon; [ eassumption | ]...

        eapply injective_subdomain_Union_not_In_image in Hinj; [| eapply Disjoint_Singleton_l; eassumption ].  

        intros Hc. eapply Hinj. constructor; eauto. rewrite image_Singleton. reflexivity.
        
        rewrite image_Union, image_Singleton. reflexivity.
    - tci.

      Grab Existential Variables.

      eapply ToMSet_Same_set. eassumption. tci. 
      eapply ToMSet_Same_set. symmetry. eassumption. tci. 
  Qed.

  Lemma block_equiv_size_val b bl1 bl2 H1 H2 :
    block_equiv (b, H1, bl1) (id, H2, bl2) ->
    size_val bl1 = size_val bl2.
  Proof. 
    intros Hbl. eapply block_equiv_subst_block in Hbl.
    destruct bl1; destruct bl2; try contradiction.
    - simpl in *. f_equal. eapply Forall2_length. eassumption.
    - reflexivity.
    - simpl in Hbl. simpl.
      unfold size_env. rewrite !PS.cardinal_spec.
      do 2 f_equal. eapply elements_eq.
      eapply Same_set_From_set. rewrite <- !mset_eq. eassumption. 
  Qed.

  Lemma heap_equiv_size_reachable S {_ : ToMSet S} H1 H2 b1 :
    reach' H1 S |- H1 ≃_(b1, id) H2 ->
    injective_subdomain (reach' H1 S) b1 ->
    size_reachable S H1 = size_reachable (image b1 S) H2. 
  Proof.
    intros Heq Hinj. unfold size_reachable, size_with_measure_filter.
    erewrite heap_elements_filter_set_Equal with (S1 := reach' H2 (image b1 S))
                                                 (S2 := image b1 (reach' H1 S)). 
    - eapply fold_permutationA; [ | | eapply heap_elements_filter_PermutationA; eauto;
                                      [| intros bl1 bl2 Hbl; eapply block_equiv_size_val; eassumption ]].
      + intros [x1 x2] [y1 y2] z. firstorder.
      + intros z [x1 x2] [y1 y2] Heqf. firstorder.
      + constructor.
        intros x1. reflexivity.
        intros x1 x2 x3 Hr1 Hr2; congruence.
    - symmetry. eapply heap_equiv_reach_eq.
      eapply heap_equiv_antimon. eassumption.
      now eapply reach'_extensive. 
  Qed.
  
  Corollary heap_env_equiv_reach_size e  H1 H2 rho1 rho2 b1 :
    occurs_free e |- (H1, rho1) ⩪_( b1, id) (H2, rho2) ->
    injective_subdomain (reach' H1 (env_locs rho1 (occurs_free e))) b1 ->
    reach_size H1 rho1 e = reach_size H2 rho2 e. 
  Proof.
    intros Heq Hinj. unfold reach_size.
    erewrite size_reachable_same_set with (S1 := (env_locs rho2 (occurs_free e)))
                                          (S2 := image b1 (env_locs rho1 (occurs_free e))). 
    eapply heap_equiv_size_reachable.
    eapply heap_equiv_reach.
    eapply heap_env_approx_heap_equiv_r. eassumption.
    eassumption. 

    eapply heap_env_equiv_image_post_n with (n := 0) in Heq. 
    simpl in Heq. rewrite image_id in Heq. symmetry. eassumption. 
  Qed.       

  Lemma heap_equiv_preserves_closed S β1 H1 H2 :
    S |- H1 ≃_(β1, id) H2 ->
    closed (reach' H1 S) H1 ->
    closed (reach' H2 (image β1 S)) H2.
  Proof.
    intros Heq Hwf l2 [n [_ Hin]].
    assert (Hin2 := Hin). 
    eapply heap_equiv_post_n_eq in Hin; [| eassumption ].
    edestruct Hin as [l1 [Heq' Hin']]. subst.

    edestruct Hwf as [b1 [Hget1 Hr1]].
    now eexists; split; eauto.

    eapply heap_equiv_post_n in Heq. eapply Heq in Heq'.
    rewrite res_equiv_eq in Heq'. destruct Heq' as [_ Heq'].
    unfold id in *. rewrite Hget1 in Heq'. 
    edestruct (get (β1 l1) H2) as [b2 |] eqn:Hget2; try contradiction.
    eexists; split; eauto.
    intros x Hinx. eexists (1 + n). split. now constructor.
    simpl. do 2 eexists; split; eauto. 
  Qed.

  Lemma GC_dom S H1 H2 b :
    live' S H1 H2 b ->
    closed (reach' H1 S) H1 ->
    dom H2 <--> reach' H2 (image b S).  
  Proof. 
    intros [Hsub [Heq Hinj]] Hcl.
    split. eassumption.
    
    eapply in_dom_closed. eapply heap_equiv_preserves_closed.
    eassumption. eassumption.
  Qed.
 
  
  Lemma GC_dom_subset S H1 H2 b :
    live' S H1 H2 b ->
    dom H2 \subset reach' H2 (image b S).  
  Proof. 
    intros [Hsub [Heq Hinj]].
    eassumption.
  Qed.


  (** Size after GC *)
   
  Lemma live_size_with_measure S {_ : ToMSet S} H1 H2 b f : 
    live' S H1 H2 b ->
    (forall bl1 bl2, block_equiv (b, H1, bl1) (id, H2, bl2) -> f bl1 = f bl2) ->
    size_with_measure f H2 = size_with_measure_filter f (reach' H1 S) H1.
  Proof.
    intros Hl Heq.
    rewrite size_with_measure_filter_dom.
    assert (Hl' := Hl). destruct Hl as [Hdom [Hheq Hinj]]. 
    
    erewrite <- size_with_measure_filter_weaken with (S := reach' H2 (image b S));
      [| eassumption ].

    erewrite size_with_measure_Same_set with (S := reach' H2 (image b S))
                                               (S' := image b (reach' H1 S)). 
    - eapply fold_permutationA with (R := fun p1 p2 : loc * block =>
                                            let '(_, bl1) := p1 in let '(_, bl2) := p2 in f bl1 = f bl2).
    + intros [x1 x2] [y1 y2] z. firstorder.
    + intros z [x1 x2] [y1 y2] Heqf. firstorder.
    + eapply PermutationA_symm.
      now intros [x1 y1] [x2 y2]; eauto. 
      eapply heap_elements_filter_PermutationA; try eassumption.
      
      constructor; eauto. intros x1 x2 x3; congruence.

      eapply heap_equiv_reach. eassumption.
      
    - symmetry. eapply heap_equiv_reach_eq. eassumption. 
  Qed. 

  Lemma live_max_with_measure S {_ : ToMSet S} H1 H2 b f :
    live' S H1 H2 b ->
    (forall bl1 bl2, block_equiv (b, H1, bl1) (id, H2, bl2) -> f bl1 = f bl2) ->
    max_with_measure f H2 = max_with_measure_filter f (reach' H1 S) H1.
  Proof.
    intros Hl Heq.
    rewrite max_with_measure_filter_dom.
    assert (Hl' := Hl). destruct Hl as [Hdom [Hheq Hinj]]. 
    
    erewrite <- max_with_measure_filter_weaken with (S := reach' H2 (image b S));
      [| eassumption ].

    erewrite max_with_measure_Same_set with (S := reach' H2 (image b S))
                                               (S' := image b (reach' H1 S)). 
    - eapply fold_permutationA with (R := fun p1 p2 : loc * block =>
                                            let '(_, bl1) := p1 in let '(_, bl2) := p2 in f bl1 = f bl2).
      + intros [x1 x2] [y1 y2] z.
        rewrite <- !Max.max_assoc. f_equal. rewrite Max.max_comm. reflexivity.
      + intros z [x1 x2] [y1 y2] Heqf. simpl. rewrite Heqf. reflexivity.
      + eapply PermutationA_symm.
        now intros [x1 y1] [x2 y2]; eauto. 
        eapply heap_elements_filter_PermutationA; try eassumption.
        
        constructor; eauto. intros x1 x2 x3; congruence.

        eapply heap_equiv_reach. eassumption.
        
    - symmetry. eapply heap_equiv_reach_eq. eassumption. 
  Qed. 

  
  Lemma live_size_with_measure_leq S {_ : ToMSet S} H1 H2 b f :
    live' S H1 H2 b ->
    (forall bl1 bl2, block_equiv (b, H1, bl1) (id, H2, bl2) -> f bl1 = f bl2) ->
    size_with_measure f H2 <= size_with_measure f H1.
  Proof.
    intros Hl Heq. erewrite live_size_with_measure; [| eassumption | eassumption ].
    rewrite HL.size_with_measure_filter_dom.
    eapply HL.size_with_measure_filter_dom_sup. 
  Qed.


  Lemma live_max_with_measure_leq S {_ : ToMSet S} H1 H2 b f :
    live' S H1 H2 b ->
    (forall bl1 bl2, block_equiv (b, H1, bl1) (id, H2, bl2) -> f bl1 = f bl2) ->
    max_with_measure f H2 <= max_with_measure f H1.
  Proof.
    intros Hl Heq. erewrite live_max_with_measure; [| eassumption | eassumption ].
    rewrite HL.max_with_measure_filter_dom.
    eapply HL.max_with_measure_filter_dom_sup. 
  Qed.


End GC.
