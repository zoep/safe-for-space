(* Heap definitions for L6 intermediate language. Part of the CertiCoq project.
 * Author: Zoe Paraskevopoulou, 2016
 *)

From Coq Require Import NArith.BinNat Relations.Relations MSets.MSets
         MSets.MSetRBT Lists.List omega.Omega Sets.Ensembles Relations.Relations
         Classes.Morphisms.
From SFS Require Import cps cps_util List_util Ensembles_util functions
        identifiers tactics set_util map_util.
From SFS Require Import heap.
From SFS Require Import Coqlib.

Import ListNotations.

Open Scope Ensembles_scope.
Close Scope Z_scope.

Create HintDb Heap_sets_DB.

Ltac solve_sets := eauto with Ensembles_DB Heap_sets_DB typeclass_instances. 

Module HeapDefs (H : Heap) .

  Module HL := HeapLemmas H.

  Import H HL.
  
  (** * Heap definitions *)

  (** A value is a location or a function pointer offset *)
  Inductive value : Type :=
  | Loc : loc -> value
  | FunPtr : fundefs -> var -> value.

  
  Definition env : Type := M.t value.
  
  (** A block in the heap *)
  Inductive block :=
  (* A constructed value *)
  | Constr : cTag -> list value -> block
  (* A closure pair -- Only used in pre-closure conversion semantics *)
  | Clos : value -> value -> block
  (* Env -- heap allocated to account for environment sharing between mutually rec. functions *)
  | Env : env -> block.
  

  (** The result of evaluation *)
  Definition res : Type := value * heap block.
  
  Inductive ans : Type :=
  | Res : res -> ans
  | OOT : ans (* out of time *).


  (** * Location sets  *)
  
  Definition val_loc (v : value) : Ensemble loc :=
    match v with
      | Loc l => [set l]
      | FunPtr _ _ => Empty_set _
    end.

  Definition val_loc_set (v : value) : PS.t :=
    match v with
      | Loc l => PS.singleton l 
      | FunPtr _ _ => PS.empty
    end.
  
  Definition env_locs (rho : env) (S : Ensemble var) : Ensemble loc :=
    \bigcup_(x in S) (match M.get x rho with
                        | Some v => val_loc v
                        | None => Empty_set _
                      end).
  
  Definition env_locs_set (rho : env) (s : PS.t) : PS.t :=
    PS.fold (fun x s' =>
               match M.get x rho with
                 | Some (Loc l) => PS.add l s'
                 | Some (FunPtr _ _) | None  => s'
               end)
            s PS.empty.

  Fixpoint env_locs_set_full (rho : M.t value) : PS.t :=
    match rho with
      | M.Leaf => PS.empty
      | M.Node t1 (Some (Loc l)) t2 =>
        PS.add l (PS.union (env_locs_set_full t1) (env_locs_set_full t2))
      | M.Node t1 _ t2 =>
        PS.union (env_locs_set_full t1) (env_locs_set_full t2)
    end.
  
  
  (** The locations that appear on a block *)
  Definition locs (v : block) : Ensemble loc :=
    match v with
      | Constr t ls => Union_list (map val_loc ls)
      | Clos v1 v2 => val_loc v1 :|: val_loc v2
      | Env rho => env_locs rho (Full_set _)
    end.
  
  Fixpoint to_locs (vs : list value) : list loc :=
    match vs with
      | [] => []
      | (Loc l) :: vs => l :: (to_locs vs)
      | (FunPtr _ _) :: vs => to_locs vs
    end.
  
  (** The locations that appear on a block *)
  Definition locs_set (v : block) : PS.t :=
    match v with
      | Constr t ls => union_list PS.empty (to_locs ls)
      | Clos v1 v2 => PS.union (val_loc_set v1) (val_loc_set v2)
      | Env rho => env_locs_set_full rho
    end.
  
  (** The locations that are pointed by the locations in S *)
  Definition post (H : heap block) (S : Ensemble loc) :=
    [ set l : loc | exists l' v, l' \in S /\ get l' H = Some v /\ l \in locs v].  


  (** Computational definition of [post] *)  
  Definition post_set (H : heap block) (s : PS.t) :=
    PS.fold (fun l r =>
               match get l H with
                 | Some v => PS.union (locs_set v) r
                 | None => r
               end)
            s PS.empty.

  (** Least fixed point *)
  Definition lfp {A} (f : Ensemble A -> Ensemble A) :=
    \bigcup_( n : nat ) ((f ^ n) (Empty_set A)).
  
  (** Least fixed point characterization of heap reachability. *)
  Definition reach (H : heap block) (Si : Ensemble loc) : Ensemble loc :=
    lfp (fun S => Union _ Si (post H S)).
  
  (** Alternative characterization of heap reachability. *)
  Definition reach' (H : heap block) (Si : Ensemble loc) : Ensemble loc :=
    \bigcup_(n : nat) (((post H) ^ n) (Si)).


  Definition reach_res (r : res) : Ensemble loc :=
    let '(v, H) := r in reach' H (val_loc v).

  Definition reach_ans (a : ans) : Ensemble loc :=
    match a with
      | Res r => reach_res r
      | _ => Empty_set _
    end.

  Definition reach_var_env (S : Ensemble var) (rho : env) (H : heap block) : Ensemble loc :=
    reach' H (env_locs rho S). 
  

  (** N-reachability. *)
  Definition reach_n (H : heap block) (n : nat) (Si : Ensemble loc) : Ensemble loc :=
    \bigcup_(m in (fun m => m <= n)) (((post H) ^ m) (Si)).
  

  
  Fixpoint dfs (roots visited : PS.t) (H : heap block) (size : nat) : PS.t :=
    match size with
      | 0 => PS.union roots visited
      | S n =>
        match PS.cardinal roots with
          | 0 => visited
          | S c => 
            let roots' := post_set H roots in (* compute the new set of roots *)
            let visited' := PS.union visited roots in (* mark roots as visited *)
            dfs (PS.diff roots' visited') visited' H n
        end
    end.

  (** Computational definition of reachable location *)
  Definition reach_set (H : heap block) (s : PS.t) : PS.t :=
    dfs s PS.empty H (size H).

  
  (** Reachability paths *) 
  Inductive path (H : heap block) : list loc -> loc -> nat -> Prop :=
  | Path_Singl :
      forall ld,
        path H [] ld 0
  | Path_Multi :
      forall l ls ld n b,
        path H ls l n ->
        ~ List.In l ls ->
        get l H = Some b ->
        ld \in locs b ->
        path H (l :: ls) ld (S n).

  (* The two definitions should be equivalent. *)
  Lemma reach_equiv H Si :
    reach H Si <--> reach' H Si.
  Proof.
  Abort.

  Definition size_env {a} (rho : M.t a) : nat :=
    PS.cardinal (@mset (key_set rho) _).

  (** Size of heap blocks *)
  Definition size_val (v : block) : nat :=
    match v with
      | Constr t ls => (* The size of the constructor representation *)
        1 + length ls
      | Clos _ _ => 3
      | Env rho => 1 + size_env rho
    end.
  
  (** Size of the heap *)
  Definition size_heap (H : heap block) : nat :=
    size_with_measure size_val H.



  (** * Wel-formedness definitions *)
  
  (** A heap is well-formed if there are not dangling pointers in the stored values *)
  Definition well_formed (S : Ensemble loc) (H : heap block) :=
    forall l v, l \in S -> get l H = Some v -> locs v \subset dom H.
  
  (** Well-formedness lifted to the environments. NOT USED *)
  Definition well_formed_env (S: Ensemble var) (H : heap block) (rho : env):=
    env_locs rho S \subset dom H.
  
  (** A heap is closed in S if the locations of its image on S remain in S *)
  Definition closed (S : Ensemble loc) (H : heap block) : Prop :=
    forall l, l \in S -> exists v, get l H = Some v /\ locs v \subset S.

  (** * Functions used in the semantics *)

  (** Add a block of function definitions in the heap and the environment *)
  Fixpoint def_closures (B B0: fundefs) (rho : env) (H : heap block) (cenv : value) {struct B}
  : heap block * env :=
    match B with
      | Fcons f _ _ _ B' =>
        let '(H', rho') := def_closures B' B0 rho H cenv in
        (* construct the closure *)
        let clo := Clos (FunPtr B0 f) cenv in
        (* add it to heap *)
        let '(l, H'') := alloc clo H' in
        (* extend the environment *)
        (H'', M.set f (Loc l) rho') 
      | Fnil => (H, rho)
    end.
  
  Fixpoint def_funs (B B0 : fundefs) rho :=
    match B with
      | Fcons f _ _ _ B =>
        M.set f (FunPtr B0 f) (def_funs B B0 rho)
      | Fnil => rho
    end.
  
  
  (** * Location renaming *)

  Definition subst_val b (v : value) : value :=
    match v with
      | Loc l => Loc (b l)
      | FunPtr _ _ => v
    end.
  
  Definition subst_env b rho := M.map (fun _ => subst_val b) rho.

  Definition subst_block f b : block :=
    match b with
      | Constr c vs => Constr c (map (subst_val f) vs)
      | Clos v1 v2 => Clos (subst_val f v1) (subst_val f v2)
      | Env rho => Env (subst_env f rho)
    end.


  (** * Restriction of environments *)

  Definition restrict_env (s : PS.t) (rho : env) : env :=
    filter (fun i _ => PS.mem i s) rho.
  
  (** [rho'] is the restriction of [rho] in [S] *)
  Definition Restrict_env (S : Ensemble var) (rho rho' : env) : Prop :=
    (forall x, x \in S -> M.get x rho = M.get x rho') /\
    sub_map rho' rho /\ key_set rho' \subset S.


  (** * Lemmas about [post] and [reach'] *)
  

  (** Set monotonicity lemmas *)
    
  Lemma post_set_monotonic S1 S2 H :
    S1 \subset S2 ->
    post H S1 \subset post H S2.
  Proof.
    unfold post. intros Hsub l [l' [v [Hin [Hget Hin']]]].
    exists l', v. split; eauto.
  Qed.

  Lemma post_n_set_monotonic n (H : heap block) (S1 S2 : Ensemble loc) :
    S1 \subset S2 -> (post H ^ n) S1 \subset (post H ^ n) S2.
  Proof.
    induction n; simpl; eauto with Ensembles_DB.
    intros Hsub. eapply Included_trans.
    eapply post_set_monotonic. now eauto.
    reflexivity.
  Qed.

  Lemma reach'_set_monotonic H S1 S2 :
    S1 \subset S2 ->
    reach' H S1 \subset reach' H S2.
  Proof.
    intros Hsub; intros x [i [_ Hin]]. 
    exists i. split. constructor. eapply app_monotonic.
    + intros. now eapply post_set_monotonic.
    + eassumption.
    + eassumption.
  Qed.

  Hint Resolve post_set_monotonic
       post_n_set_monotonic
       reach'_set_monotonic : Heap_sets_DB.  

  
  (** Heap monotonicity lemmas *)

  Lemma post_heap_monotonic H1 H2 S :
    H1 ⊑ H2 ->
    post H1 S \subset post H2 S.
  Proof.
    unfold post. intros Hsub l [l' [v [Hin [Hget Hin']]]].
    exists l', v. split; eauto.
  Qed.
  
  Lemma post_n_heap_monotonic n (H1 H2 : heap block) (S : Ensemble loc) :
    H1 ⊑ H2 -> (post H1 ^ n) S \subset (post H2 ^ n) S.
  Proof.
    induction n; simpl; eauto with Ensembles_DB.
    intros Hsub. eapply Included_trans.
    eapply post_set_monotonic. now eauto.
    now eapply post_heap_monotonic.
  Qed.
  
  Lemma reach'_heap_monotonic (H1 H2 : heap block) (S : Ensemble loc) :
    H1 ⊑ H2 -> reach' H1 S \subset reach' H2 S.
  Proof.
    intros Hsub l [n [HT Hp]]. exists n; split; eauto.
    eapply post_n_heap_monotonic; eauto.
  Qed.
  
  (** [reach'] is extensive *)
  Lemma reach'_extensive H S :
    S \subset reach' H S.
  Proof.
    intros x Hin. exists 0; split; eauto.
    now constructor.
  Qed.

  (** [reach'] includes [post] *)
  Lemma Included_post_reach' H S :
    (post H S) \subset reach' H S.
  Proof.
    intros x Hin. exists 1; split; eauto.
    now constructor.
  Qed.

  Lemma Included_post_n_reach' (H : heap block) (S : Ensemble loc) (n : nat) :
    (post H ^ n) S \subset reach' H S.
  Proof.
    intros l Hp. eexists; eauto. split; eauto. constructor.
  Qed.

  Hint Immediate reach'_extensive
       Included_post_reach'
       Included_post_n_reach' : Heap_sets_DB.
  
  Lemma reach_unfold H S :
    (reach' H S) <--> (Union _ S (reach' H (post H S))).
  Proof.
    split; intros x.
    - intros [i [_ Hin]]. 
      destruct i.
      + eauto.
      + right. exists i. split. now constructor.
        replace ((post H ^ i) (post H S))
        with (((post H ^ i) ∘ (post H ^ 1)) S) by eauto.
        rewrite <- app_plus. rewrite plus_comm. eassumption.
    - intros Hin. destruct Hin as [ x Hin | x [i [_ Hin]]].
      + now eapply reach'_extensive.
      + exists (i+1). split. now constructor.
          rewrite app_plus. eassumption.
  Qed.

  (** reach is a post fixed point of post. Post is monotonic so
      it is also a fixed point *)
  Lemma reach'_post_fixed_point H S :
    post H (reach' H S) \subset reach' H S.
  Proof.
    unfold post, reach'; simpl; intros x [l [v [[i [_ Hin]] Hin']]].
    exists (i + 1). split. now constructor.
    rewrite plus_comm, app_plus.
    exists l, v. split; eauto.
  Qed.
  
  Lemma reach'_post_fixed_point_n n H S :
    (post H ^ n) (reach' H S) \subset reach' H S.
  Proof.
    induction n. 
    - reflexivity.
    - replace (Datatypes.S n) with (n + 1). rewrite app_plus.
      eapply Included_trans.
      eapply app_monotonic. now intros; eapply post_set_monotonic.
      now apply reach'_post_fixed_point. eassumption.
      omega.
  Qed. 
  
  (** [reach'] is idempotent *)
  Lemma reach'_idempotent H S :
    reach' H S <--> reach' H (reach' H S).
  Proof.
    unfold reach'. split; intros x Hin.
    - exists 0. split. now constructor.
      simpl. eassumption.
    - rewrite <- bigcup_merge.
      destruct Hin as [m [_ Hin]].
      apply reach'_post_fixed_point_n in Hin.
      exists 0. split; eauto. now constructor.
  Qed.

  Lemma reach_spec H S S' :
    S \subset S' ->
    S' \subset reach' H S ->
    reach' H S <--> reach' H S'.
  Proof.
    intros Hsub1 Hsub2. split.
    - eapply reach'_set_monotonic. eassumption.
    - rewrite (reach'_idempotent H S).
      apply reach'_set_monotonic. eassumption.
  Qed.
  
  (** Proper instances and the like *)

  Instance Proper_post : Proper (eq ==> Same_set loc ==> Same_set loc) post.
  Proof.
    intros x1 x2 Heq S1 S2 Heq'; subst; split; intros z [l [v [Hin [Hget Hin']]]].
    repeat eexists; eauto; now rewrite <- Heq'; eauto.
    repeat eexists; eauto; now rewrite Heq'; eauto.
  Qed.

  Lemma proper_post_n H n S1 S2 :
    S1 <--> S2 ->
    ((post H) ^ n) S1 <--> ((post H) ^ n) S2.
  Proof.
    induction n; eauto; intros Heq; simpl.
    rewrite IHn; eauto. reflexivity.
  Qed.

  Instance Proper_reach' : Proper (eq ==> Same_set _ ==> Same_set _) reach'.
  Proof.
    intros H1 H2 heq S1 S2 Hseq; subst; split; intros x [n [Hn Hin]].
    - eexists; split; eauto. eapply proper_post_n; eauto.
      now symmetry.
    - eexists; split; eauto. eapply proper_post_n; eauto.
  Qed.
  
  Lemma post_heap_eq S H1 H2 :
    S |- H1 ≡ H2 ->
    post H1 S <--> post H2 S.
  Proof.
    intros Heq; split; intros x [l [v [Hin [Hget Hin']]]].
    repeat eexists; eauto; now rewrite <- Heq; eauto.
    repeat eexists; eauto; now rewrite Heq; eauto.
  Qed.

  Lemma post_n_heap_eq n P H1 H2 :
    reach' H1 P |- H1 ≡ H2 ->
    (post H1 ^ n) P <--> (post H2 ^ n) P.
  Proof.
    induction n; intros Heq; try reflexivity.
    simpl. rewrite IHn; solve_sets. apply post_heap_eq.
    rewrite <- IHn.
    eapply heap_eq_antimon; [| eassumption ]. eapply Included_post_n_reach'.
    eassumption.
  Qed.
  
  Lemma post_n_heap_eq' n P H1 H2 :
    reach' H2 P |- H1 ≡ H2 ->
    (post H1 ^ n) P <--> (post H2 ^ n) P.
  Proof.
    induction n; intros Heq; try reflexivity.
    simpl. rewrite IHn; eauto. apply post_heap_eq.
    eapply heap_eq_antimon; eauto. eapply Included_post_n_reach'.
  Qed.
  
  Lemma reach'_heap_eq P H1 H2 :
    reach' H1 P |- H1 ≡ H2 ->
    reach' H1 P <--> reach' H2 P.
  Proof.
    intros Heq; split; intros l [n [HT Hp]]; eexists; split; eauto;
    try now eapply post_n_heap_eq; eauto.
    eapply post_n_heap_eq'; eauto.
    symmetry ; eauto.
  Qed.  
  
  Lemma reach'_post S H : 
    reach' H S <--> reach' H (S :|: (post H S)).
  Proof.
    rewrite <- reach_spec with (S' := Union loc S (post H S)).
    reflexivity.
    now eauto with Ensembles_DB.
    apply Union_Included. now apply reach'_extensive.
    now apply Included_post_reach'.
  Qed.
  
  (** Set lemmas *)
  
  Lemma post_Empty_set :
    forall (H : heap block), post H (Empty_set _) <--> Empty_set _.
  Proof.
    intros H.
    unfold post. split; intros l H1; try now inv H1.
    destruct H1 as [l' [b [Hin _]]]. inv Hin.
  Qed.

  Lemma post_Union H S1 S2 :
    post H (Union _ S1 S2) <--> Union _ (post H S1) (post H S2).
  Proof with now eauto with Ensembles_DB.
    split; intros l Hp.
    - destruct Hp as [l' [v [Hin [Hget Hin']]]].
      inv Hin; [left | right ]; repeat eexists; eauto.
    - destruct Hp as [ Hp | Hp ];
      eapply post_set_monotonic; eauto...
  Qed.

  Lemma post_Singleton (H1 : heap block) (l : loc) (b : block) :
    get l H1 = Some b ->
    post H1 [set l] <--> locs b.
  Proof.
    intros Hget; split; intros l1.
    - intros [l2 [b2 [Hin [Hget' Hin']]]]. inv Hin.
      rewrite Hget in Hget'. inv Hget'; eauto.
    - intros Hin. repeat eexists; eassumption.
  Qed.

  Lemma post_Singleton_None (H1 : heap block) (l : loc) :
    get l H1 = None -> post H1 [set l] <--> Empty_set _.
  Proof. 
    intros Hget; split; intros l1.
    - intros [l2 [b2 [Hin [Hget' Hin']]]]. inv Hin.
      rewrite Hget in Hget'. inv Hget'; eauto.
    - intros Hin. inv Hin.
  Qed.


  Lemma post_n_Empty_set n H :
    (post H ^ n) (Empty_set _) <--> Empty_set _.
  Proof.
    induction n; try reflexivity.
    simpl. rewrite IHn. rewrite post_Empty_set.
    reflexivity.
  Qed.

  Lemma post_n_Singleton_None H n l :
    get l H = None ->
    (post H ^ S n) [set l] <--> Empty_set _.
  Proof.
    intros Hnone. induction n.
    - simpl. rewrite post_Singleton_None. reflexivity. eassumption.
    - simpl. rewrite IHn. rewrite post_Empty_set. reflexivity.
  Qed.

  Lemma post_n_Union n H S1 S2 :
    (post H ^ n) (Union _ S1 S2) <--> Union _ ((post H ^ n) S1) ((post H ^ n) S2).
  Proof with now eauto with Ensembles_DB.
     induction n;  try now firstorder.
     simpl. rewrite IHn, post_Union. reflexivity.
  Qed.

  Lemma reach'_Empty_set H :
    reach' H (Empty_set positive) <--> Empty_set _.
  Proof.
    split; [| now firstorder ].
    intros x [n [_ Hin]].
    revert x Hin. induction n; intros x Hin. simpl in Hin.
    inv Hin. 
    destruct Hin as [y [v [Hin [Hget Hin']]]].
    eapply IHn in Hin. inv Hin.
  Qed.

  
  Lemma reach'_Union H S1 S2 :
    reach' H (S1 :|: S2) <--> (reach' H S1) :|: (reach' H S2).
  Proof.
    split; intros l Hp.
    - destruct Hp as [n [HT Hp]].
       eapply post_n_Union in Hp. destruct Hp as [Hp | Hp ].
       now left; firstorder. now right; firstorder.
    - destruct Hp as [ l [n [HT Hp]] | l [n [HT Hp]] ];
      repeat eexists; eauto; eapply post_n_Union; eauto.
  Qed.


  Lemma post_size_H_O S H :
    size H = 0 ->
    post H S <--> Empty_set _.
  Proof.
    intros Heq.
    split; intros x.
    - intros [y [v [Hin [Hget Hin']]]].
      unfold size in Heq. eapply length_zero_iff_nil in Heq.
      eapply heap_elements_complete in Hget.
      rewrite Heq in Hget. inv Hget.
    - intros Hin; inv Hin.
  Qed.

  Lemma reach_size_H_O S H :
    size H = 0 ->
    reach' H S <--> S.
  Proof.
    rewrite reach_unfold. intros Heq.
    rewrite post_size_H_O; eauto. 
    rewrite reach'_Empty_set.
    rewrite Union_Empty_set_neut_r.
    reflexivity.
  Qed.


  (** Disjointedness lemmas *)

  Lemma post_Disjoint S H :
    Disjoint _ S (dom H) ->
    post H S <--> Empty_set _.
  Proof.
    intros Hd; split; eauto with Ensembles_DB.
    intros l [l' [v [Hin [Hget _]]]].
    exfalso. eapply Hd. constructor; eauto.
    eexists; eauto.
  Qed.

  Lemma post_n_Disjoint n S H :
    Disjoint _ S (dom H) ->
    (post H ^ n) S \subset S.
  Proof with now eauto with Ensembles_DB.
    revert S; induction n; intros S Hd; eauto with Ensembles_DB.
    replace (Datatypes.S n) with (n + 1) by omega.
    rewrite app_plus. simpl. unfold compose.
    eapply Included_trans. eapply proper_post_n.
    rewrite post_Disjoint; eauto. reflexivity.
    eapply Included_trans; [ eapply IHn | ]...
  Qed.
  
  Lemma reach'_Disjoint S H :
    Disjoint _ S (dom H) ->
    reach' H S <--> S.
  Proof.
    split.
    - intros l [n [_ Hp]]. eapply post_n_Disjoint; eauto.
    - apply reach'_extensive.
  Qed.
  
  (** allocation lemmas *)
  
  Lemma post_alloc S H v l H'  :
    alloc v H = (l, H') ->
    post H' S \subset (Union _ (post H S) (locs v)).
  Proof.
    intros Ha l' Hp.
    destruct Hp as [l2 [v' [Hin2 [Hget Hin1]]]].
    destruct (loc_dec l l2); subst; eauto.
    + repeat eexists; eauto. erewrite gas in Hget; eauto.
      inv Hget. eauto.
    + left; repeat eexists; eauto. erewrite <-gao; eauto.
  Qed.

  Lemma post_alloc' H v l H'  :
    alloc v H = (l, H') ->
    post H' [set l] \subset locs v.
  Proof.
    intros Ha l' Hp.
    destruct Hp as [l2 [v' [Hin2 [Hget Hin1]]]].
    inv Hin2.
    repeat eexists; eauto. erewrite gas in Hget; eauto.
    inv Hget. eauto.
  Qed.
  
  Lemma post_n_alloc n S H v l H'  :
    alloc v H = (l, H') ->
    locs v \subset reach' H S ->
    (post H' ^ n) S \subset reach' H S.
  Proof.
    revert S.
    induction n; intros S Ha Hin; simpl.
    - eapply reach'_extensive.
    - eapply Included_trans. eapply post_set_monotonic.
      now eauto. eapply Included_trans. now eapply post_alloc; eauto.
      eapply Union_Included. now eapply reach'_post_fixed_point_n with (n := 1).
      eapply Included_trans; eauto. reflexivity.
  Qed.
  
  Lemma reach'_alloc S H v l H'  :
    alloc v H = (l, H') ->
    locs v \subset reach' H S ->
    reach' H' S <--> reach' H S.
  Proof.
    intros Ha Hin.
    split.
    - intros l' [n [_ Hp]]. eapply post_n_alloc; eauto.
    - eapply reach'_heap_monotonic. now eapply alloc_subheap; eauto.
  Qed.   

  (** * Lemmas about [path] *)

  Lemma path_NoDup H ls ld n : 
    path H ls ld n -> NoDup ls.
  Proof.
    intros Hp; induction Hp; constructor; eauto.
  Qed.

  Lemma path_length H ls ld n :
    path H ls ld n -> length ls = n.
  Proof.
    intros Hp; induction Hp; eauto.
    simpl. congruence.
  Qed.

  Lemma path_heap_elements H ls ld n :
    path H ls ld n ->
    Subperm ls (map fst (heap_elements H)).
  Proof.
    intros Hp; induction Hp.
    - eexists; split; [| reflexivity ].
      eapply Sublist_nil.
    - destruct IHHp as [elems [Hsub Hperm]].
      eapply heap_elements_complete in H1.
      eapply in_map with (f := fst) in H1.
      eapply Permutation.Permutation_in in H1; [| symmetry ; eassumption ].
      edestruct in_split as [l1 [l2 Heq]]; eauto.
      rewrite Heq in *. simpl in *.
      eexists (l :: l1 ++ l2).
      split.
      + eapply sublist_skip. eapply Sublist_cons_app; eauto.
      + eapply Permutation.Permutation_trans; try eassumption.
        eapply Permutation.Permutation_cons_app. reflexivity.
  Qed.

  Lemma path_post_n H l ls ld n :
    path H (ls ++ [l]) ld n ->
    ld \in ((post H ^ n) [set l]).
  Proof.
    revert n ld; induction ls; intros n ld Hp; inv Hp.
    - simpl. inv H2. repeat eexists; eauto.
    - do 2 eexists. split.
      + eapply IHls. eassumption.
      + split; eauto.
  Qed.

  Lemma path_prev H l1 l2 l l' m:
    path H (l1 ++ l :: l2) l' m ->
    path H l2 l (length l2) /\ ~ List.In l l2.
  Proof.
    revert l' m; induction l1; simpl; intros l' m Hpath; inv Hpath.
    - erewrite <- path_length in H2; eauto.
    - eapply IHl1. simpl. eassumption.
  Qed.

  Lemma post_path_n (S : Ensemble loc) H ld n :
    ld \in (post H ^ (1 + n)) S ->
    exists l ls m, l \in S /\ m <= (1 + n) /\ path H (ls ++ [l]) ld m.
  Proof.
    revert ld; induction n; intros ld Hpost.
    - destruct Hpost as [l' [v [Hin1 [Hget Hin2]]]]. simpl in *.
      exists l', [], 1. repeat split; eauto. simpl.
      econstructor. now constructor.
      now intros Hc; inv Hc. eassumption. eassumption.
    - destruct Hpost as [l' [v [Hin1 [Hget Hpost]]]].
      eapply IHn in Hin1. edestruct Hin1 as [l'' [ls [m [Hin [Hleq Hpath]]]]].
      destruct (in_dec loc_dec l' (ls ++ [l''])) as [Hinl | Hninl].
      + edestruct in_split as [ll [lr Happ]]; try eassumption.
        destruct (destruct_last lr) as [| [lr' [r Heq]]]; subst.
        * simpl in Happ. assert (l' = l'') by (eapply app_snoc; eauto). subst.
          eexists l'', [], 1. repeat split; eauto. omega.
          simpl. econstructor; eauto. now constructor.
        * assert (l'' = r).
          { replace (ll ++ l' :: lr' ++ [r]) with ((ll ++ l' :: lr') ++ [r]) in Happ
              by (rewrite <- app_assoc; reflexivity).
            eapply app_snoc; eauto. }
          subst. rewrite Happ in Hpath.
          erewrite <- path_length with (n := m) in Hleq, Hpath; eauto.
          eapply path_prev in Hpath; destruct Hpath as [Hpath Hnin].
          exists r, (l' :: lr'), (length (l' :: lr' ++ [r])).
          repeat split; eauto. 
          simpl. rewrite !app_length.
          repeat (simpl in Hleq; rewrite !app_length in Hleq).
          simpl in *. omega. 
          simpl. econstructor; eauto. 
      + eexists l'', (l' :: ls), (1 + m). 
        split; eauto. split. omega.
        econstructor; eauto.
  Qed.

  Lemma post_exists_Singleton S H l :
    post H S l ->
    exists l', l' \in S /\ post H [set l'] l.
  Proof.
    intros [l' [v [Hin Hp]]]. eexists; split; eauto.
    eexists. eexists. split; eauto.
  Qed.

  Lemma post_n_exists_Singleton S1 H n l :
    (post H ^ n) S1 l ->
    exists l', l' \in S1 /\ (post H ^ n) [set l'] l.
  Proof.
    revert l S1. induction n; intros l S1.
    - simpl. intros. eexists; split; eauto. reflexivity.
    - intros Hp.
      simpl in *. eapply post_exists_Singleton in Hp.
      destruct Hp as [l' [Hin Hp]].
      eapply IHn in Hin. destruct Hin as [l'' [Hinl'' Hp'']].
      eexists. split; eauto.
      destruct Hp as [l1 [b1 [Heq [Hget Hin]]]]. inv Heq.
      eexists. eexists. split; eauto.
  Qed.


  (** * Lemmas about [reach_n] *)

  Lemma reach_0 S H :
    reach_n H 0 S <--> S.
  Proof.  
    split.
    - intros x [y [H1 H2]].
      destruct y; try omega. eauto.
    - intros y Hin. eexists 0. split; eauto.
  Qed.

  Lemma reach_S_n S H m :
    reach_n H (m + 1) S <--> reach_n H m S :|: (post H ^ (m + 1)) S.
  Proof.
    split.
    + intros x Hin. destruct Hin as [k [Hleq Hin]].
      destruct (Nat.eq_dec k (m + 1)); subst.
      * now right.
      * left. eexists. split; [| eassumption ]. omega.
    + intros x Hin. destruct Hin as [ x Hin | x Hin].
      * destruct Hin as [k [Hleq Hin]].
        eexists. split; [| eassumption ]. omega.
      * eexists. split; [| eassumption ]. omega.
  Qed.

  Lemma reach_n_in_reach (H : heap block) (n : nat) (S : Ensemble loc): 
    reach_n H n S \subset reach' H S.
  Proof.
    intros x [n' [_ Hin]]. eexists; split; eauto. constructor.
  Qed.

  (** [reach_n] is extensive *)
  Lemma reach_n_extensive H n S :
    S \subset reach_n H n S.
  Proof.
    intros x Hin. exists 0; split; eauto.
    omega.
  Qed.

  Lemma reach_n_unfold H n S :
    (reach_n H (1 + n) S) <--> (Union _ S (reach_n H n (post H S))).
  Proof.
    split; intros x.
    - intros [i [Hleq Hin]]. 
      destruct i.
      + eauto.
      + right. exists i. split. omega.
        replace ((post H ^ i) (post H S))
        with (((post H ^ i) ∘ (post H ^ 1)) S) by eauto.
        rewrite <- app_plus. rewrite plus_comm. eassumption.
    - intros Hin. destruct Hin as [ x Hin | x [i [Hleq Hin]]].
      + now eapply reach_n_extensive.
      + exists (i+1). split. omega.
        rewrite app_plus. eassumption.
  Qed.

  Lemma reach_n_Empty_set n H :
    reach_n H n (Empty_set _) <--> Empty_set _.
  Proof.
    split; intros x Hin; try now inv Hin.
    destruct Hin as [m [Hin1 Hin2]].
    eapply post_n_Empty_set in Hin2. inv Hin2.
  Qed.

  Lemma reach_n_Union (H : heap block) (S1 S2 : Ensemble loc) (n : nat) : 
    reach_n H n (S1 :|: S2) <--> reach_n H n S1 :|: reach_n H n S2.
  Proof.
    induction n.
    - rewrite !reach_0. reflexivity.
    - replace (S n) with (n + 1) by omega. rewrite !reach_S_n.
      rewrite post_n_Union, IHn.
      rewrite <- !Union_assoc.
      eapply Same_set_Union_compat. reflexivity.
      rewrite !Union_assoc.
      eapply Same_set_Union_compat; [| reflexivity].
      rewrite Union_commut. reflexivity.
  Qed.

  Instance Proper_reach_n : Proper (eq ==> eq ==> Same_set _ ==> Same_set _) reach_n.
  Proof.
    intros H1 H2 heq S1 S2 Hseq; subst; split; intros z [n [Hn Hin]].
    - eexists; split; eauto. eapply proper_post_n; eauto.
      now symmetry.
    - eexists; split; eauto. eapply proper_post_n; eauto.
  Qed.
  
  Lemma reach_n_monotonic S H m n :
    m <= n ->
    reach_n H m S \subset reach_n H n S.
  Proof. 
    revert n S. induction m; intros n S Hleq.
    - rewrite reach_0. eapply reach_n_extensive.
    - destruct n. omega.
      rewrite !reach_n_unfold.
      eapply Included_Union_compat. reflexivity.
      eapply IHm. omega.
  Qed.

  Lemma reach_n_fixed_point_aux S H m :
    (post H ^ (m + 1)) S \subset (reach_n H m S) ->
    reach_n H (m + 1) S <--> reach_n H m S.  
  Proof.
    intros Hsub. 
    split.
    - intros x Hin. destruct Hin as [k [Hleq Hin]].
      edestruct le_lt_eq_dec as [Hlt | Heq]; eauto.
      + eexists k.
        split. omega.
        repeat eexists; try eassumption.
      + subst. eapply Hsub.
        eassumption.
    - eapply reach_n_monotonic. omega.
  Qed.
  
  Lemma post_fixed_aux S H m n :
    (post H ^ (m + 1)) S \subset reach_n H m S ->
    (post H ^ (n + m + 1)) S \subset reach_n H m S.  
  Proof.
    revert m S. induction n; eauto; intros m S Hsub.
    simpl.
    intros x [y [b [Hin1 [Hget Hin2]]]]. 
    eapply IHn in Hin1; [| eassumption ].
    destruct Hin1 as [k [Hleq Hin]].
    edestruct le_lt_eq_dec as [Hlt | Heq]; eauto.
    - eexists (1 + k).
      split. omega.
      repeat eexists; try eassumption.
    - subst. eapply Hsub.
      replace (m + 1) with (1 + m) by omega.
      simpl. eexists. repeat eexists; try eassumption.
  Qed.

  Lemma post_fixed S H m n :
    (post H ^ (m + 1)) S \subset reach_n H m S ->
    n >= m ->
    (post H ^ n) S \subset reach_n H m S.  
  Proof.
    intros Hsub1 Hleq.
    edestruct Nat.le_exists_sub as [n' [Hsum Hleq']]; subst.
    eassumption.
    subst.
    destruct n'.
    - simpl. intros x Hin. eexists; eauto.
    - replace (Datatypes.S n' + m) with (n' + m + 1) by omega.
      eapply post_fixed_aux. eassumption.
  Qed.

  Lemma reach_n_fixed_point S H m n :
    (post H ^ (m+1)) S \subset reach_n H m S ->
    reach_n H (n + m) S <--> reach_n H m S.  
  Proof.
    revert m. induction n; intros m Hsub.
    - reflexivity.
    - replace (Datatypes.S n + m)  with ((n + m) + 1) by omega.
      rewrite reach_n_fixed_point_aux.
      eapply IHn. 
      eassumption. eapply Included_trans. eapply post_fixed_aux.
      eassumption. eapply reach_n_monotonic. omega.
  Qed.

  Lemma size_heap_fixed_point S H:
   (post H ^ (1 + (size H))) S \subset reach_n H (size H) S.
  Proof.
    intros x Hpost. 
    edestruct post_path_n as [lr [ls [len [Hin [Hleq Hpath]]]]]. 
    eassumption.
    edestruct le_lt_eq_dec as [Hlt | Heq]; eauto.
    - eapply path_post_n in Hpath.
      eexists len. split; eauto. omega.
      eapply post_n_set_monotonic; try eassumption.
      eapply Singleton_Included. eassumption.
    - erewrite <- (path_length _ _ _ len) in Heq, Hpath; eauto.
      subst. eapply path_heap_elements in Hpath.
      eapply Subperm_length in Hpath. rewrite map_length in Hpath. 
      rewrite Heq in Hpath. unfold size in Hpath. omega.
  Qed.

  Lemma reach_n_size_H_fixed_point S H n :
    n >= size H ->
    reach_n H n S <--> reach' H S.
  Proof.
    split.
    - intros x [m [Hleq Hin]]. eexists. split; eauto.
      now constructor.
    - intros x [m [_ Hin]].
      destruct (le_lt_dec m (size H)).
      + eexists m; split; eauto. omega.
      + eapply reach_n_monotonic. now eauto.
        eapply post_fixed; [| | eassumption ]; try omega.
        replace (size H + 1) with (1 + size H) by omega.
        eapply size_heap_fixed_point.
  Qed.

  Lemma reach_n_Singleton_None H n l :
    get l H = None ->
    reach_n H n [set l] <--> [set l].
  Proof.
    intros Hget.
    split; [| now eapply reach_n_extensive ]. 
    intros x [y [Hleq Hin]].
    destruct y.
    - simpl in *. inv Hin. reflexivity.
    - eapply post_n_Singleton_None in Hin; eauto. inv Hin.
  Qed.


  (** * Lemmas about [env_locs] *)
  
  (** Set monotonicity *)
  Lemma env_locs_monotonic S1 S2 rho :
    S1 \subset S2 ->
    env_locs rho S1 \subset env_locs rho S2.
  Proof.
    intros H1. unfold env_locs. eapply Included_big_cup; eauto.
    intros x. reflexivity.
  Qed.
  
  Instance Proper_env_locs : Proper (eq ==> Same_set _ ==> Same_set _) env_locs.
  Proof.
    intros rho1 rho2 heq s1 s2 Hseq; subst.
    firstorder.
  Qed.

  (** Environment extension lemmas *)

  Lemma env_locs_set_not_In S rho x l :
    ~ x \in S ->
    env_locs (M.set x l rho) S <--> env_locs rho S.
  Proof.
     intros Hin; split; intros l' H1.
     - destruct H1 as [z [H1 H2]].
       destruct (peq z x); subst.
       + contradiction.
       + rewrite M.gso in *; eauto. eexists; eauto.
     - destruct H1 as [z [H1 H2]].
       destruct (peq z x); subst.
       + contradiction.
       + eexists. rewrite M.gso; eauto.
  Qed.
  
  Lemma env_locs_set_In S rho x v :
    x \in S ->
    env_locs (M.set x v rho) S <-->
    (val_loc v) :|: (env_locs rho (Setminus _ S [set x])).
  Proof.
    intros Hin; split; intros l' H1.
    - destruct H1 as [z [H1 H2]].
      destruct (peq z x); subst.
      + rewrite M.gss in *. destruct v; try contradiction.
        inv H2; eauto. left; simpl; eauto.
      + rewrite M.gso in *; eauto. right. eexists; split; eauto.
        constructor; eauto. intros Hc; inv Hc; eauto.
    - inv H1.
      + eexists; split; eauto.
        rewrite M.gss. eassumption.
      + destruct H as [y [Hin' Hget]]. inv Hin'. 
        eexists. split; eauto.
        rewrite M.gso. eassumption.
        intros Heq; subst. exfalso; eauto.
  Qed.
  
  Lemma env_locs_set_Inlcuded S rho x v :
    env_locs (M.set x v rho) (Union _ S [set x]) \subset
    ((val_loc v) :|: (env_locs rho S)).
  Proof.
    intros l' H1.
    - destruct H1 as [z [H1 H2]].
      destruct (peq z x); subst.
      + rewrite M.gss in *. left; eauto.
      + rewrite M.gso in *; eauto. right. eexists; split; eauto.
        inv H1; eauto. inv H; congruence.
   Qed.
  
  Lemma env_locs_set_Inlcuded' S rho x v :
    env_locs (M.set x v rho) S \subset
    (val_loc v) :|: (env_locs rho (Setminus _ S [set x])).
  Proof.
    intros l' H1.
    - destruct H1 as [z [H1 H2]].
      destruct (peq z x); subst.
      + rewrite M.gss in *. left; eauto.
      + rewrite M.gso in *; eauto. right. eexists; split; eauto.
        constructor; eauto. intros Heq. inv Heq; congruence. 
  Qed.

  (* name? *)
  Lemma env_locs_singleton_Included (x : var) (v : value) (rho : env)
          (S : Ensemble var):
    (val_loc v) \subset env_locs (M.set x v rho) (Union _ S [set x]).
  Proof.
    rewrite env_locs_set_In; eauto with Ensembles_DB.
  Qed.

  
  Lemma def_closures_env_locs_in_dom S H H' rho rho' B B0 l :
    def_closures B B0 rho H l = (H', rho') ->
    env_locs rho S \subset dom H ->
    env_locs rho' (S :|: name_in_fundefs B) \subset dom H'.
  Proof.
    revert S rho rho' H H'; induction B; intros S rho rho' H H' Hdef Hsub; simpl.
    - simpl in Hdef.
      destruct (def_closures B B0 rho H l) as [H'' rho''] eqn:Hdef'.
      destruct (alloc _ H'') as [l' H'''] eqn:Hal. inv Hdef.
      rewrite alloc_dom; [| eassumption ].
      rewrite env_locs_set_In; [| now eauto with Ensembles_DB ].
      simpl. eapply Included_Union_compat.
      reflexivity.
      eapply Included_trans; [| eapply IHB; eassumption ].
      eapply env_locs_monotonic.
      now eauto with Ensembles_DB.
    - rewrite Union_Empty_set_neut_r. inv Hdef. eassumption.
  Qed.

  Lemma env_locs_def_funs S S1 H1 H1' rho1 rho1'  B B0 cenv :
    env_locs rho1 (Setminus _ S (name_in_fundefs B)) \subset S1 ->
    (H1', rho1') = def_closures B B0 rho1 H1 cenv ->
    env_locs rho1' (Setminus _ S (name_in_fundefs B)) \subset S1.
  Proof.
    revert S H1' rho1'; induction B; intros S H1' rho1' Hsub1 Heq.
    - simpl in Heq. destruct (def_closures B B0 rho1 H1 cenv) as [H'' rho''].
      destruct (alloc _ H'') as [l' H'''] eqn:Heq'.
      inv Heq. rewrite env_locs_set_not_In.
      simpl; rewrite <- !Setminus_Union.
      simpl in Hsub1; rewrite <- !Setminus_Union in Hsub1.
      eapply IHB; eauto.
      intros Hc. inversion Hc as [Hc1 Hc2]; eauto. 
      eapply Hc2; left; eauto.
    - simpl in Hsub1.
      rewrite Setminus_Empty_set_neut_r in Hsub1; inv Heq.
      rewrite Setminus_Empty_set_neut_r; eauto.
  Qed.

  Lemma env_locs_def_funs' S {_ : ToMSet S} B B0 rho1 rho1' : 
    def_funs B B0 rho1 = rho1' ->
    env_locs rho1' S <--> env_locs rho1 (S \\ name_in_fundefs B). 
  Proof with (now eauto with Ensembles_DB).
    revert S X rho1 rho1'; induction B; intros S HS rho1 rho1'. 
    - simpl. intros Hdef. subst.
      destruct (@Dec _ S _ v). 
      + rewrite env_locs_set_In. 
        rewrite <- Setminus_Union. simpl.
        rewrite <- IHB; tci... eassumption.
      + rewrite env_locs_set_not_In; [| eassumption ].
        rewrite <- Setminus_Union, (Setminus_Disjoint S). now eauto.  
        eapply Disjoint_Singleton_r. 
        eassumption. 
    - intros Hin; inv Hin. simpl. rewrite Setminus_Empty_set_neut_r. reflexivity. 
  Qed.

  
  Lemma env_locs_setlist_Included ys ls rho rho' S :
    setlist ys ls rho = Some rho'  ->
    env_locs rho' (S :|: (FromList ys)) \subset
    (env_locs rho S) :|: (Union_list (map val_loc ls)).
  Proof with now eauto with Ensembles_DB.
    revert rho' S ls; induction ys; intros rho' S ls Hset.
    - rewrite FromList_nil, Union_Empty_set_neut_r. inv Hset.
      destruct ls; try discriminate. inv H0...
    - destruct ls; try discriminate. simpl in *.
      destruct (setlist ys ls rho) eqn:Hset'; try discriminate.
      inv Hset. rewrite !FromList_cons.
      rewrite (Union_commut [set a]), !Union_assoc. 
      eapply Included_trans. eapply env_locs_set_Inlcuded.
      eapply Union_Included; eauto with Ensembles_DB. 
      eapply Included_trans. eapply IHys; eauto.
      now eauto with Ensembles_DB. 
  Qed.

  Lemma env_locs_Leaf :
    env_locs Maps.PTree.Leaf (Full_set var) <--> Empty_set _.
  Proof.
    unfold env_locs.
    split; intros x Hin; try now inv Hin.
    destruct Hin as [y [_ Hin]].
    rewrite Maps.PTree.gleaf in Hin. inv Hin.
  Qed.

  Lemma env_locs_Node v rho1 rho2 :
    env_locs (M.Node rho1 (Some v) rho2) (Full_set var) <-->
    val_loc v :|: env_locs rho1 (Full_set var) :|: env_locs rho2 (Full_set var).
  Proof.
    unfold env_locs; split; intros x Hin.
    - destruct Hin as [y [Hins Hget]].
      destruct y; simpl in Hget.
      + right. exists y; split; [ now constructor |].
        eassumption.
      + left. right. exists y; split; [ now constructor |].
        eassumption.
      + left. left. eassumption.
    - inv Hin. inv H.
      + eexists xH. split.
        now constructor. eassumption.
      + destruct H0 as [y [_ Hget]].
        eexists (y~0)%positive. split.
        now constructor. simpl. eassumption.
      + destruct H as [y [_ Hget]].
        eexists (y~1)%positive. split.
        now constructor. simpl. eassumption.
  Qed.

  Lemma env_locs_Node_None rho1 rho2 :
    env_locs (M.Node rho1 None rho2) (Full_set var) <-->
    env_locs rho1 (Full_set var) :|: env_locs rho2 (Full_set var).
  Proof.
    unfold env_locs; split; intros x Hin.
    - destruct Hin as [y [Hins Hget]].
      destruct y; simpl in Hget.
      + right. exists y; split; [ now constructor |].
        eassumption.
      + left. exists y; split; [ now constructor |].
        eassumption.
      + inv Hget.
    - inv Hin.
      + destruct H as [y [_ Hget]].
        eexists (y~0)%positive. split.
        now constructor. simpl. eassumption.
      + destruct H as [y [_ Hget]].
        eexists (y~1)%positive. split.
        now constructor. simpl. eassumption.
  Qed.
  
  (* Decidability lemmas *)

  Lemma Decidable_val_loc v :
    Decidable (val_loc v).
  Proof.
    constructor. intros x. destruct v.
    - destruct (loc_dec l x); subst.
      left; reflexivity.
      right. intros Hc; inv Hc; eauto.
    - right; simpl; intros Hc; inv Hc.
  Qed.

  Lemma Decidable_env_locs rho S :
    Decidable S ->
    Decidable (env_locs rho S).
  Proof.
    intros HD. unfold env_locs, image'.
    inv HD. constructor.
    assert (forall l : loc,
              {exists (x : M.elt) v, In M.elt S x /\
                                l \in val_loc v /\
                                List.In (x, v) (M.elements rho)} +
              {~ exists (x : M.elt) v, In M.elt S x /\
                                  l \in val_loc v /\
                                  List.In (x, v) (M.elements rho)}).
    { generalize (M.elements rho) as el.
      induction el as [| [x v] el IHel]; simpl; intros l1.
      - right. firstorder.
      - destruct (Dec x) as [Hin1 | Hnin1].
        + destruct (Decidable_val_loc v).
          destruct (Dec0 l1) as [Hin2 | Hnin2]; subst.
          * left. do 2 eexists; repeat split; eauto.
          * destruct (IHel l1) as [Hl | Hr].
            left. destruct Hl as [x2 [v2 [H1 [H2 H3]]]].
            now do 2 eexists; repeat split; eauto.
            right. intros [x2 [v2 [Hc1 [Hc2 [Hc3 | Hc3]]]]]. inv Hc3; contradiction.
            now eapply Hr; eauto.
        + destruct (IHel l1) as [Hl | Hr].
          left. destruct Hl as [x2 [v2 [H1 [H2 H3]]]].
          now do 2 eexists; repeat split; eauto.
          right. intros [x2 [v2 [Hc1 [Hc2 Hc3]]]]. inv Hc3.
          inv H; try contradiction.
          now eapply Hr; eauto. }
    intros l. destruct (H l) as [Hl | Hr].
    - left. destruct Hl as [x [v [Hl1 [Hl2 Hl3]]]].
      eexists; split; eauto. eapply M.elements_complete in Hl3.
      rewrite Hl3. eassumption.
    - right. intros [x [H1 H2]].
      destruct (M.get x rho) eqn:Hget; try contradiction.
      eapply Hr; do 2 eexists; repeat split; eauto.
      eapply M.elements_correct; eassumption.
  Qed.

  Instance Decidable_locs v : Decidable (locs v).
  Proof.
    constructor. intros l1.
    destruct v; simpl.
    - eapply Decidable_map_UnionList; eauto with typeclass_instances.
      eapply Decidable_val_loc.
    - destruct v; destruct v0; simpl. 
      destruct (loc_dec l l1); subst.
      left. now left.
      destruct (loc_dec l0 l1); subst.
      left. now right. 
      right. intros Hc; inv Hc; now inv H; eauto.
      destruct (loc_dec l l1); subst.
      left. now left.
      right. intros Hc; inv Hc; inv H; now eauto.
      destruct (loc_dec l l1); subst.
      left. right. reflexivity.
      right. intros Hc; inv Hc; inv H; now eauto.

      right. intros Hc; inv Hc; inv H; now eauto.
    - eapply Decidable_env_locs.
      constructor. intros. now left.
  Qed.
  
  (** Set lemmas *)

  Lemma env_locs_Union rho S1 S2 :
    env_locs rho (Union _ S1 S2) <-->
    Union _ (env_locs rho S1) (env_locs rho S2).
  Proof.
    split; intros l.
    - intros [v [Hin Hget]]. inv Hin; firstorder.
      now left; repeat eexists; eauto.
      now right; repeat eexists; eauto.
    - intros [ l' [v [Hin Hget]] | l' [v [Hin Hget]] ];
      repeat eexists; eauto. left; eauto.
      right; eauto.
  Qed.

  Lemma env_locs_Empty_set (rho : env) :
    env_locs rho (Empty_set _) <--> Empty_set _.
  Proof.
    unfold env_locs. rewrite big_cup_Empty_set.
    reflexivity.
  Qed.
  
  Lemma env_locs_Singleton x rho v :
    M.get x rho = Some v ->
    env_locs rho [set x] <--> (val_loc v).
  Proof.
    intros Hget; split; intros l.
    - intros [y [Hin Hget']]. inv Hin.
      rewrite Hget in Hget'. eassumption.
    - intros Hin. eexists; split.
      reflexivity. rewrite Hget; eauto.
  Qed.

  Lemma env_locs_Singleton_None x rho :
    M.get x rho = None ->
    env_locs rho [set x] <--> Empty_set _.
  Proof.
    intros Hget; split; intros l.
    - intros [y [Hin Hget']]. inv Hin.
      rewrite Hget in Hget'. eassumption.
    - intros Hin. eexists; split.
      reflexivity. rewrite Hget; eauto.
  Qed.


  Lemma env_locs_singleton_env (x : var) (v : value) :
    (val_loc v) <--> env_locs (M.set x v (M.empty _)) [set x].
  Proof.
    rewrite env_locs_Singleton. reflexivity.
    rewrite M.gss; eauto.
  Qed.
  
  Lemma env_locs_Empty S :
    Empty_set _ <--> env_locs (M.empty _) S.
  Proof.
    split; eauto with Ensembles_DB.
    intros l [v [Hs Hp]]. rewrite M.gempty in Hp.
    inv Hp.
  Qed.

  (* get lemmas *)

  Lemma env_locs_FromList (rho : env) (xs : list var) (vs : list value) :
    getlist xs rho = Some vs ->
    env_locs rho (FromList xs) <--> (Union_list (map val_loc vs)).
  Proof.
    revert vs. induction xs; intros vs Hgetl; simpl in Hgetl.
    + inv Hgetl. simpl; rewrite !FromList_nil.
      rewrite env_locs_Empty_set. reflexivity.
    + destruct (M.get a rho) eqn:Hgeta; try discriminate.
      destruct (getlist xs rho) eqn:Hgetl'; try discriminate.
      inv Hgetl.
      simpl. rewrite !FromList_cons.
      rewrite env_locs_Union. eapply Same_set_Union_compat.
      eapply env_locs_Singleton. eassumption.
      eapply IHxs. reflexivity.
  Qed.
  
  (** get lemmas *)

  Lemma get_In_env_locs x S rho v:
    x \in S ->
    M.get x rho = Some v ->
    (val_loc v) \subset env_locs rho S.
  Proof.
    intros Hin Hget. eexists. split; eauto.
    rewrite Hget; eauto.
  Qed.


  Lemma FromList_env_locs (S : Ensemble var) (rho : env)
        (xs : list var) (ls : list value) :
    getlist xs rho = Some ls ->
    FromList xs \subset S ->
    Union_list (map val_loc ls) \subset env_locs rho S.
  Proof with now eauto with Ensembles_DB.
    revert ls; induction xs; intros ls Hget Hs; simpl in *.
    - inv Hget...
    - destruct (M.get a rho) eqn:Hgeta; try discriminate.
      destruct (getlist xs rho) eqn:Hgetl; try discriminate.
      inv Hget. rewrite !FromList_cons in Hs. simpl.
      eapply Union_Included.
      + eapply get_In_env_locs; [| eassumption ]...
      + eapply IHxs; eauto.
        eapply Included_trans...
  Qed.

  Lemma reach_env_locs_alloc_not_In S H H' rho x b l :
    alloc b H = (l, H') ->
    locs b \subset (reach' H (env_locs rho S)) ->
    ~ x \in S ->
    Union _ [set l] (reach' H (env_locs rho S)) \subset
    reach' H' (env_locs (M.set x (Loc l) rho) (Union _ S [set x])).
  Proof.
    intros Hal Hsub Hnin l1 Hin.
    rewrite <- (env_locs_set_not_In) with (l := Loc l) in Hin; eauto.
    rewrite env_locs_Union, reach'_Union. inv Hin.
    - inv H0. right. exists 0. split. 
      now constructor. simpl. eexists. split; eauto.
      reflexivity. now rewrite M.gss.
    - left. eapply reach'_heap_monotonic; eauto.
      eapply alloc_subheap. eassumption.
  Qed.

  Lemma restrict_env_env_locs rho rho' S :
    Restrict_env S rho rho' ->
    env_locs rho' (Full_set _) \subset env_locs rho S. 
  Proof.
    intros [H1 [H2 H3]] l [x [_ H]].
    destruct (M.get x rho') eqn:Hget; try contradiction.
    exists x. split.
    eapply H3. unfold key_set, In. now rewrite Hget.
    eapply H2 in Hget. now rewrite Hget.
  Qed.

  Lemma env_locs_setlist_Disjoint ys ls rho rho' S :
    setlist ys ls rho = Some rho'  ->
    Disjoint _ S (FromList ys) ->
    env_locs rho S <--> env_locs rho' S. 
  Proof with now eauto with Ensembles_DB.
    revert rho' S ls; induction ys; intros rho' S ls Hset Hd.
    - destruct ls; inv Hset. reflexivity.
    - destruct ls; try discriminate. simpl in *.
      destruct (setlist ys ls rho) eqn:Hset'; try discriminate.
      inv Hset. rewrite env_locs_set_not_In. eapply IHys.
      eassumption.
      eapply Disjoint_Included_r; [| eassumption ].
      normalize_sets...
      intros Hc; eapply Hd. constructor; eauto.
      normalize_sets. now left. 
  Qed.

  Lemma env_locs_setlist_In ys ls rho rho' :
    setlist ys ls rho = Some rho'  ->
    env_locs rho' (FromList ys) \subset Union_list (map val_loc ls). 
  Proof with now eauto with Ensembles_DB.
    revert rho' ls; induction ys; intros rho' ls Hset.
    - destruct ls; inv Hset. normalize_sets. rewrite env_locs_Empty_set...
    - destruct ls; try discriminate. simpl in *. 
      destruct (setlist ys ls rho) eqn:Hset'; try discriminate.
      inv Hset. normalize_sets. rewrite env_locs_Union.
      rewrite env_locs_Singleton; [| rewrite M.gss; reflexivity ].
      eapply Union_Included. now eapply Included_Union_preserv_l. 
      eapply Included_trans. eapply env_locs_set_Inlcuded'. eapply Included_Union_compat.
      reflexivity. eapply Included_trans; [| eapply IHys; eassumption ].
      eapply env_locs_monotonic...
  Qed.



  (** * Lemmas about [def_closures] *)

  Lemma def_funs_subheap H H' rho rho' B B0 l :
    (H', rho') = def_closures B B0 rho H l ->
    H ⊑ H'.
  Proof.
    revert H' rho'; induction B; intros H' rho' Heq;
    simpl; [| inv Heq; now apply subheap_refl ].
    simpl in Heq. destruct (def_closures B B0 rho H l) as [H'' rho''].
    destruct (alloc _ H'') as [l' H'''] eqn:Heq'.
    inv Heq. eapply subheap_trans; eauto.
    now eapply alloc_subheap; eauto.
  Qed.

  Lemma def_closures_env_locs_reach
        (S : Ensemble var) (H H' : heap block) (rho rho' : env)
        (B B0 : fundefs) (cenv : value) :
    def_closures B B0 rho H cenv = (H', rho') ->
    val_loc cenv \subset (reach' H (env_locs rho S)) ->
    val_loc cenv \subset (reach' H' (env_locs rho' (S :|: name_in_fundefs B))).
  Proof.
    revert S rho rho' H H'; induction B; intros S rho rho' H H' Hdef Hsub; simpl.
    - simpl in Hdef.
      destruct (def_closures B B0 rho H cenv) as [H'' rho''] eqn:Hdef'.
      destruct (alloc _ H'') as [l' H'''] eqn:Hal. inv Hdef.
      rewrite env_locs_set_In; [| now eauto ]. rewrite reach'_Union.
      eapply Included_Union_preserv_l.
      eapply Included_trans; [| eapply Included_post_reach' ].
      simpl. rewrite post_Singleton; [| erewrite gas; eauto ].
      simpl. now eauto with Ensembles_DB.
    - rewrite Union_Empty_set_neut_r. inv Hdef.
      eassumption.
  Qed.
  
  (** * Lemmas about [closed] *)

  Lemma in_dom_closed (S : Ensemble loc) (H : heap block) :
    closed S H ->
    S \subset dom H.
  Proof. 
    intros Hc l1 Hr.
    edestruct Hc as [v2 [Hget' Hdom]]; eauto.
    repeat eexists; eauto.
  Qed.

  Lemma reachable_closed H S l v:
    l \in reach' H S ->
    get l H = Some v ->
    locs v \subset reach' H S.
  Proof.
    intros Hin Hget.
    eapply Included_trans;
      [| now eapply reach'_post_fixed_point_n with (n := 1)]; simpl.
    intros l' Hin'. do 2 eexists. split. eassumption. now split; eauto.
  Qed.


  Lemma closed_reach_monotonic S1 S2 H :
    closed (reach' H S1) H ->
    S2 \subset S1 -> 
    closed (reach' H S2) H.
  Proof. 
    intros Hc sub l Hin.
    edestruct Hc as [v [Hget Hinv]].
    eapply reach'_set_monotonic; eassumption.
    eexists v; split; eauto.
    eapply Included_trans; [| eapply reach'_post_fixed_point ].
    eapply Included_trans. eapply post_Singleton. eassumption.
    eapply post_set_monotonic. eapply Singleton_Included. eassumption.
  Qed.     
      
  Lemma closed_alloc H H' l v :
    closed (dom H) H ->
    locs v \subset dom H ->
    alloc v H = (l, H') ->
    closed (dom H') H'.
  Proof with now eauto with Ensembles_DB.
    intros Hcl Hin Ha l1 Hin'.
    destruct (loc_dec l1 l); subst.
    - eexists. erewrite gas; eauto.
      split. reflexivity.
      eapply Included_trans. eassumption.
      rewrite (alloc_dom _ _ _ _ Ha)...
    - rewrite (alloc_dom _ _ _ _ Ha) in Hin'.
      inv Hin'. inv H0. congruence.
      edestruct Hcl as [l2 [Hget Hsub]]; try eassumption.
      eexists. erewrite gao; eauto; split; eauto.
      eapply Included_trans. eassumption.
      rewrite (alloc_dom _ _ _ _ Ha)...
  Qed.

  Instance Proper_closed : Proper (Same_set _ ==> eq ==> iff) closed.
  Proof.
    intros S1 S2 Heq x1 x2 Heq'; split; intros Hc x Hin; eapply Heq in Hin;
    subst; eauto.
    - setoid_rewrite <- Heq; eauto.
    - setoid_rewrite Heq; eauto.
  Qed.
  
  Lemma closed_Union (S1 S2 : Ensemble loc) (H : heap block) :
    closed S1 H ->
    closed S2 H ->
    closed (Union _ S1 S2) H.
  Proof with now eauto with Ensembles_DB.
    intros Hc1 Hc2 l Hin.
    inv Hin.
    - edestruct Hc1 as [c [Hget Hinv]]; eauto.
      eexists; split; eauto...
    - edestruct Hc2 as [c [Hget Hinv]]; eauto.
      eexists; split; eauto...
  Qed.

  Lemma closed_alloc' S H H' l v :
    closed S H ->
    locs v \subset S ->
    alloc v H = (l, H') ->
    closed S H'.
  Proof with now eauto with Ensembles_DB.
    intros Hcl Hin Ha l1 Hin'.
    destruct (loc_dec l1 l); subst.
    - eexists. erewrite gas; eauto.
    - edestruct Hcl as [l2 [Hget Hsub]]; try eassumption.
      eexists. erewrite gao; eauto; split; eauto.
  Qed.

  Lemma closed_alloc_Union S H H' l v :
    closed S H ->
    locs v \subset S ->
    alloc v H = (l, H') ->
    closed (l |: S) H'.
  Proof with now eauto with Ensembles_DB.
    intros Hcl Hin Ha l1 Hin'.
    destruct (loc_dec l1 l); subst.
    - eexists. erewrite gas; eauto. split; eauto...
    - inv Hin'. inv H0. contradiction.
      edestruct Hcl as [l2 [Hget Hsub]]; try eassumption.
      eexists. erewrite gao; eauto; split; eauto...
  Qed.

  Lemma closed_def_funs S1 H1 H1' rho1 rho1' B B0 envc :
    closed S1 H1 ->
    val_loc envc \subset S1 ->
    (H1', rho1') = def_closures B B0 rho1 H1 envc ->
    closed S1 H1'.
  Proof.
    revert H1' rho1'; induction B;
    intros H1' rho1' Hc Hsub Heq; [| inv Heq; now eauto ].
    simpl in Heq. destruct (def_closures B B0 rho1 H1 envc) as [H'' rho''].
    destruct (alloc _ H'') as [l' H'''] eqn:Heq'.
    inv Heq. eapply closed_alloc'; [| | eassumption ]; eauto.
    simpl. now eauto with Ensembles_DB. 
  Qed.
  
  Lemma def_funs_exists_new_set S S1 H1 H1' rho1 rho1' envc B B0 :
    closed S1 H1 ->
    env_locs rho1 (Setminus _ S (name_in_fundefs B)) \subset S1 ->
    val_loc envc \subset S1 ->
    (H1', rho1') = def_closures B B0 rho1 H1 envc ->
    exists S1', S1 \subset S1' /\ closed S1' H1' /\
           env_locs rho1' S \subset S1'.
  Proof with now eauto with Ensembles_DB.
    revert S H1' rho1'; induction B; intros S H1' rho1' Hc Henv Hsub Heq.
    - simpl in Heq. destruct (def_closures B B0 rho1 H1 envc) as [H'' rho''] eqn:Hdef.
      destruct (alloc _ H'') as [l' H'''] eqn:Heq'.
      inv Heq.
      edestruct IHB as [S1' [Hsub' [Hc' Henv']]]; eauto.
      eapply Included_trans; [| now apply Henv ].
      eapply env_locs_monotonic. simpl. rewrite <- !Setminus_Union.
      reflexivity.
      eexists (l' |: S1'). split. 
      now eauto with Ensembles_DB.
      split.
      + eapply closed_alloc_Union; [| | eassumption ];
        simpl; try now eauto with Ensembles_DB.
        eapply Included_trans; [| now apply Hsub' ]...
      + eapply Included_trans. now eapply env_locs_set_Inlcuded'.
        now eauto with Ensembles_DB.
    - simpl in Henv.
      rewrite Setminus_Empty_set_neut_r in Henv; inv Heq.
      eexists. split; eauto. reflexivity.
  Qed.

  Lemma closed_post_n_in_S (S : Ensemble loc) (H : heap block) (n : nat) :
    closed S H ->
    (post H ^ n) S \subset S.
  Proof. 
    induction n; intros Hc l1 Hr.
    - eassumption.
    - edestruct Hr as [l2 [b [Hin1 [Hget Hin2]]]]; eauto.
      eapply IHn in Hin1; [| eassumption ].
      edestruct Hc as [b1 [Hget2 Hsub]]; try eassumption.
      subst_exp. eapply Hsub. eassumption.
  Qed.

  Lemma closed_reach_in_S (S : Ensemble loc) (H : heap block) :
    closed S H ->
    reach' H S \subset S.
  Proof. 
    intros Hc l1 Hr.
    edestruct Hr as [n [_ Hr']].
    eapply closed_post_n_in_S; eauto.
  Qed.

  
  (** * Lemmas about [well_formed] and [well_formed_env] *)
  
  (** Monotonicity lemmas *)

  Lemma well_formed_antimon S1 S2 H :
    S1 \subset S2 ->
    well_formed S2 H ->
    well_formed S1 H.
  Proof.
    firstorder.
  Qed.

  Lemma well_formed_env_antimon S1 S2 H rho :
    well_formed_env S1 H rho ->
    S2 \subset S1 ->
    well_formed_env S2 H rho.
  Proof.
    firstorder.
  Qed.

  Lemma well_formed'_closed (S : Ensemble loc) (H : heap block) :
    closed (reach' H S) H ->
    well_formed (reach' H S) H.
  Proof. 
    intros Hc l1 v1 Hin Hget.
    edestruct Hc as [v2 [Hget' Hdom]]; eauto.
    rewrite Hget in Hget'. inv Hget'.
    eapply Included_trans. eassumption.
    eapply in_dom_closed; eauto.
  Qed.

  Lemma env_locs_closed (S : Ensemble loc) (H : heap block) :
    closed S H ->
    S \subset dom H. 
  Proof.
    intros Hc l Sin. edestruct Hc as [b' [Heq1 Heq2]]. eassumption.
    eexists; eauto.
  Qed.

  (** Proper instances *)

  Instance Proper_well_formed : Proper (Same_set _ ==> eq ==> iff) well_formed.
  Proof.
    intros s1 s2 hseq H1 h2 Heq; subst. firstorder.
  Qed.

  Lemma well_formed_heap_eq S H1 H2 :
    well_formed S H1 ->
    closed S H1 -> 
    S |- H1 ≡ H2 ->
    well_formed S H2.
  Proof.
    intros Hwf Hcl Heq x v Hin Hget l Hin'.
    rewrite <- Heq in Hget; eauto.
    destruct (Hwf x v Hin Hget l Hin') as [l' Hget'].
    rewrite -> Heq in Hget'; eauto. repeat eexists; eauto.
    edestruct Hcl as [v' [Hget'' Hin'']]; eauto.
    rewrite Hget in Hget''; inv Hget''; eauto.
  Qed.

  (** Set lemmas *)

  Lemma well_formed_Union S1 S2 H :
    well_formed S1 H ->
    well_formed S2 H ->
    well_formed (Union _ S1 S2) H.
  Proof.
    intros Hwf1 Hwf2 l v Hin Hget; inv Hin; eauto.
  Qed.
  
  Lemma well_formed_Empty_set H:
    well_formed (Empty_set _) H.
  Proof.
    firstorder.
  Qed.
  
  (** Reachable locations are in the domain of the heap *)
  Lemma reachable_in_dom H S :
    well_formed (reach' H S) H ->
    S \subset dom H ->
    reach' H S \subset dom H.
  Proof.
    intros H1 Hs l [n [_ Hr]]. destruct n; eauto.
    simpl in Hr. destruct Hr as [l' [v' [Hin [Hget Hin']]]].
    eapply H1; eauto. eexists; split; eauto. now constructor; eauto.
  Qed.

  (** The heap is closed in the set of the reachable locations *)
  Lemma reach'_closed S H :
    well_formed (reach' H S) H ->
    S \subset dom H ->
    closed (reach' H S) H.
  Proof.
    intros HHwf sub l Hreach.
    edestruct reachable_in_dom as [v Hget]; eauto.
    eexists; split; eauto.
    eapply reachable_closed; eauto.
  Qed.
    
  Lemma getlist_in_dom (S : Ensemble var) (H : heap block) (rho : env)
        (ys : list var) (vs : list value) :
    well_formed_env S H rho ->
    getlist ys rho = Some vs ->
    FromList ys \subset S ->
    Union_list (map val_loc vs) \subset dom H. 
  Proof.
    revert vs; induction ys; intros ls Hwf Hget Hin; destruct ls; simpl in *; try discriminate.
    - now eauto with Ensembles_DB.
    - now eauto with Ensembles_DB.
    - rewrite !FromList_cons in Hin.
      destruct (M.get a rho) eqn:Hgeta; try discriminate.
      destruct (getlist ys rho) eqn:Hgetys; try discriminate.
      inv Hget. eapply Union_Included.
      eapply Included_trans; [| now eapply Hwf].
      now eapply get_In_env_locs; eauto. 
      eapply IHys; eauto. eapply Included_trans; now eauto with Ensembles_DB.
  Qed.
  
  (** Well-formedness preservation under environment and heap extensions *)

  (** Allocation lemmas *)
  
  Lemma well_formed_alloc (S : Ensemble loc) (H H' : heap block)
             (b : block) (l : loc) :
    well_formed S H ->
    alloc b H = (l, H') ->
    locs b \subset dom H ->
    well_formed S H'.
  Proof with now eauto with Ensembles_DB.
    intros Hwf ha Hsub l' v' Sin Hget. destruct (loc_dec l l'); subst.
    - erewrite gas in Hget; eauto. inv Hget.
      eapply Included_trans. eassumption.
      rewrite (alloc_dom H _ _ _ ha)...
    - erewrite gao in Hget; eauto.
      eapply Included_trans. now eauto.
      rewrite (alloc_dom H _ _ _ ha)...
  Qed.

  Lemma well_formed_env_alloc_extend (S : Ensemble var) (H H' : heap block)
             (rho : env) (x : var) (b : block) (l : loc) :
    well_formed_env (Setminus _ S (Singleton _ x)) H rho ->
    alloc b H = (l, H') ->
    locs b \subset (dom H) ->
    well_formed_env S H' (M.set x (Loc l) rho).
  Proof with now eauto with Ensembles_DB.
    intros Hwf Ha Hsub l' [y [Hin Hget]]. destruct (peq x y); subst.
    - rewrite M.gss in Hget. inv Hget.
      eexists. eapply gas. eauto.
    - rewrite M.gso in Hget; eauto.
      rewrite (alloc_dom H _ _ _ Ha).
      right. eapply Hwf; eauto.
      eexists; split; eauto. constructor; eauto.
      intros Hc; inv Hc; congruence.
  Qed.  
  
  Lemma well_formed_reach_alloc (S : Ensemble var) (H H' : heap block)
        (rho : env) (x : var) (b : block) (l : loc) :
    well_formed (reach' H (env_locs rho S)) H  ->
    env_locs rho S \subset dom H ->
    alloc b H = (l, H') ->
    locs b \subset (reach' H (env_locs rho S)) ->
    well_formed (reach' H' (env_locs (M.set x (Loc l) rho) (Union _ S [set x]))) H'.
  Proof with now eauto with Ensembles_DB.
    intros Hwf Hsub Ha Hin.
    eapply well_formed_antimon.
    eapply reach'_set_monotonic. now eapply env_locs_set_Inlcuded.
    rewrite reach'_alloc; eauto.
    - rewrite reach'_Union. eapply well_formed_Union.
      + rewrite reach'_Disjoint.
        * intros l' v' Hin' Hget. inv Hin'.
          erewrite gas in Hget; eauto. inv Hget.
          eapply Included_trans; eauto.
          eapply Included_trans;
            [| now eapply dom_subheap; eapply alloc_subheap; eauto ].
          eapply reachable_in_dom; eauto.
        * constructor. intros l' Hc. inv Hc. inv H0.
          destruct H1 as [v' Hget]. erewrite alloc_fresh in Hget; eauto.
          discriminate.
      + eapply well_formed_alloc; eauto.
        eapply Included_trans; eauto. eapply reachable_in_dom; eauto.
    - rewrite reach'_Union. eapply Included_Union_preserv_r.
      eassumption.
  Qed.

  Lemma well_formed_reach_alloc' (S S' : Ensemble var) (H H' : heap block)
        (rho : env) (x : var) (b : block) (l : loc) :
    well_formed (reach' H (env_locs rho (S' :|: (S \\ [set x])))) H  ->
    env_locs rho (S' :|: (S \\ [set x])) \subset dom H ->
    alloc b H = (l, H') ->
    locs b \subset (reach' H (env_locs rho (S' :|: (S \\ [set x])))) ->
    well_formed (reach' H' (env_locs (M.set x (Loc l) rho) (S' :|: S))) H'.
  Proof with now eauto with Ensembles_DB.
    intros Hwf Hsub Ha Hin.
    eapply well_formed_reach_alloc with (x := x) (S := S' :|: (S \\ [set x])) in Hwf; try eassumption.
    eapply well_formed_antimon; [| eassumption ].
    eapply reach'_set_monotonic. eapply env_locs_monotonic.
    rewrite <- Union_assoc.
    eapply Included_Union_compat. reflexivity.
    eapply Included_trans; [| eapply Included_Union_Setminus ]; eauto.
    reflexivity. now eapply DecidableSingleton_positive.
  Qed.

  Lemma well_formed_reach_set_Loc (S : Ensemble var) (H : heap block) (rho : env)
        (x : var) (l : loc) :
    well_formed (reach' H (env_locs rho S)) H ->
    well_formed (reach' H [set l]) H ->
    well_formed (reach' H (env_locs (M.set x (Loc l) rho) (Union _ S [set x]))) H.
  Proof with now eauto with Ensembles_DB.
    intros Hwf  Hin.
    eapply well_formed_antimon.
    eapply reach'_set_monotonic. now eapply env_locs_set_Inlcuded.
    rewrite reach'_Union. eapply well_formed_Union; eauto.
  Qed.

  Lemma well_formed_reach_set (S : Ensemble var) (H : heap block) (rho : env)
        (x : var) (v : value) :
    well_formed (reach' H (env_locs rho S)) H ->
    well_formed (reach' H (val_loc v)) H ->
    well_formed (reach' H (env_locs (M.set x v rho) (Union _ S [set x]))) H.
  Proof with now eauto with Ensembles_DB.
    intros Hwf  Hin.
    eapply well_formed_antimon.
    eapply reach'_set_monotonic. now eapply env_locs_set_Inlcuded.
    rewrite reach'_Union. eapply well_formed_Union; eauto.
  Qed.

  Lemma well_formed_reach_set' (S S' : Ensemble var) (H : heap block) (rho : env) 
        (x : var) (v : value) :
    well_formed (reach' H (env_locs rho (S' :|: (S \\ [set x])))) H ->
    val_loc v \subset reach' H (env_locs rho (S' :|: (S \\ [set x]))) ->
    well_formed (reach' H (env_locs (M.set x v rho) (S' :|: S))) H.
  Proof.
    intros Hwf1 Hin.
    eapply well_formed_antimon.
    eapply reach'_set_monotonic. now eapply env_locs_set_Inlcuded'.
    rewrite reach'_Union. eapply well_formed_Union; eauto.
    eapply well_formed_antimon; [| eassumption ].
    rewrite (reach'_idempotent H (env_locs rho (S' :|: (S \\ [set x])))).
    eapply reach'_set_monotonic. eassumption.
    eapply well_formed_antimon; [| eassumption ].
    eapply reach'_set_monotonic. eapply env_locs_monotonic.
    rewrite Setminus_Union_distr. now eauto with Ensembles_DB.
  Qed.
  
  Lemma well_formed_def_funs S1 H1 H1' rho1 rho1' B B0 envc :
    well_formed S1 H1 ->
    val_loc envc \subset dom H1 ->
    (H1', rho1') = def_closures B B0 rho1 H1 envc ->
    well_formed S1 H1'.
  Proof.
    revert H1' rho1'; induction B;
    intros H1' rho1' Hc Hlocs Heq; [| inv Heq; now eauto ].
    simpl in Heq. destruct (def_closures B B0 rho1 H1 envc) as [H'' rho''] eqn:Hdef.
    destruct (alloc _ H'') as [l' H'''] eqn:Heq'.
    inv Heq. eapply well_formed_alloc; [| eassumption | ]; eauto.
    simpl. rewrite Union_Empty_set_neut_l.
    eapply Included_trans. eassumption.
    eapply dom_subheap. eapply def_funs_subheap; eauto.
  Qed.

  Lemma well_formed_reach_setlist  (S : Ensemble M.elt) (H : heap block) 
        (rho rho' : env)  (xs : list M.elt) (vs : list value) :
    well_formed (reach' H (env_locs rho S)) H ->
    well_formed (reach' H (Union_list (map val_loc vs))) H ->
    setlist xs vs rho = Some rho' -> 
    well_formed
      (reach' H (env_locs rho' (Union M.elt S (FromList xs)))) H.
  Proof with now eauto with Ensembles_DB.
    revert rho' vs. induction xs; intros rho' ls Hwf1 Hwf2 Hsetl.
    - destruct ls; try discriminate. inv Hsetl.
      rewrite FromList_nil, Union_Empty_set_neut_r. eassumption.
    - simpl. rewrite FromList_cons in *.
      simpl in Hsetl. destruct ls; try discriminate.
      destruct (setlist _ _ _) eqn:Hsetl'; try discriminate.
      inv Hsetl. rewrite (Union_commut [set a]), Union_assoc.
      simpl. eapply well_formed_reach_set.
      * eapply IHxs. eassumption.
        eapply well_formed_antimon; [| eassumption ].
        eapply reach'_set_monotonic.
        simpl... eassumption.
      * eapply well_formed_antimon; [| eassumption ].
        eapply reach'_set_monotonic. simpl...
  Qed.

  Lemma well_formed_reach_setlist_cor  (S : Ensemble M.elt) (H : heap block) 
        (rho rho' : env) (xs : list M.elt) (vs : list value) :
    well_formed (reach' H (env_locs rho S)) H ->
    Union_list (map val_loc vs) \subset (reach' H (env_locs rho S)) ->
    setlist xs vs rho = Some rho' -> 
    well_formed
      (reach' H (env_locs rho' (Union M.elt S (FromList xs)))) H.
  Proof.
    intros. eapply well_formed_reach_setlist; [ eassumption | | eassumption ].
    eapply well_formed_antimon.
    eapply reach'_set_monotonic. eassumption.
    rewrite <- reach'_idempotent. eassumption.
  Qed.   

     
  Lemma well_formed_post_n_alloc_same (S : Ensemble loc) (H H' : heap block)
        b l n :
    well_formed (reach' H S) H  ->
    S \subset dom H ->
    alloc b H = (l, H') ->
    (post H ^ n) S <--> (post H' ^ n) S.
  Proof.
    intros Hwf Hdom Hal. split; intros l' Hin.
    - revert l' Hin; induction n; simpl in *; intros l' Hin.
      + eassumption.
      + destruct Hin as [l'' [b' [Hin [Hget Hin']]]].
        eapply IHn in Hin.
        eexists. eexists. split. eassumption.
        split; [| eassumption ].
        erewrite gao; try eassumption.
        intros Heq; subst. 
        erewrite alloc_fresh in Hget; try eassumption.
        discriminate.
    - revert l' Hin; induction n; simpl in *; intros l' Hin.
      + eassumption.
      + destruct Hin as [l'' [b' [Hin [Hget Hin']]]].
        eapply IHn in Hin.
        eexists. eexists. split. eassumption.
        split; [| eassumption ].
        eapply reachable_in_dom in Hdom; [| eassumption ].
        edestruct Hdom as [b'' Hget''].
        eexists; split; [| exact Hin ]. now constructor.
        erewrite gao in Hget; try eassumption.
        intros Heq; subst.
        erewrite alloc_fresh in Hget''; try eassumption.
        discriminate.
  Qed.

  Lemma well_formed_reach_alloc_same (S : Ensemble loc) (H H' : heap block)
        b l :
    well_formed (reach' H S) H  ->
    S \subset dom H ->
    alloc b H = (l, H') ->
    reach' H S <--> reach' H' S.
  Proof.
    intros Hwf Hdom Hal. split; intros l' [n [_ Hin]].
    - eapply (well_formed_post_n_alloc_same S H H') in Hin; eauto.
      eexists; split; eauto. constructor.
    - eapply (well_formed_post_n_alloc_same S H H') in Hin; eauto.
      eexists; split; eauto. constructor.
  Qed.

  Lemma well_formed_post_n_subheap_same (S : Ensemble loc) (H H' : heap block) n :
    well_formed (reach' H S) H  ->
    S \subset dom H ->
    H ⊑ H' ->
    (post H ^ n) S <--> (post H' ^ n) S.
  Proof.
    intros Hwf Hdom Hal. split; intros l' Hin.
    - revert l' Hin; induction n; simpl in *; intros l' Hin.
      + eassumption.
      + destruct Hin as [l'' [b' [Hin [Hget Hin']]]].
        eapply IHn in Hin.
        eexists. eexists. split. eassumption.
        split; [| eassumption ].
        eapply Hal. eassumption.
    - revert l' Hin; induction n; simpl in *; intros l' Hin.
      + eassumption.
      + destruct Hin as [l'' [b' [Hin [Hget Hin']]]].
        eapply IHn in Hin.
        eexists. eexists. split. eassumption.
        split; [| eassumption ].
        eapply reachable_in_dom in Hdom; [| eassumption ].
        edestruct Hdom as [b'' Hget''].
        eexists; split; [| exact Hin ]. now constructor. rewrite Hget''.
         eapply Hal in Hget''. congruence.
  Qed.

  Lemma well_formed_reach_subheap_same 
        (S : Ensemble loc) (H H' : heap block) : 
    well_formed (reach' H S) H ->
    S \subset dom H -> H ⊑ H' ->
    reach' H S <--> reach' H' S.
  Proof.
    intros Hwf Hsub Hsub'; split; intros l [n1 [_ Hr]]. 
    - eexists; split.
      now constructor.
      eapply (well_formed_post_n_subheap_same _ H H') in Hr; try eassumption.
    - eexists; split.
      now constructor.
      eapply (well_formed_post_n_subheap_same _ H H') in Hr; try eassumption.
  Qed.

  Lemma well_formed_post_subheap_same 
        (S : Ensemble loc) (H H' : heap block) : 
    well_formed (reach' H S) H ->
    S \subset dom H -> H ⊑ H' ->
    post H S <--> post H' S.
  Proof.
    intros Hwf Hsub Hsub'.
    eapply well_formed_post_n_subheap_same with (n := 1); eassumption.
  Qed.

  Lemma reach'_subheap H H' S : 
    well_formed (reach' H S) H ->
    S \subset dom H ->
    H ⊑ H' ->
    reach' H S <--> reach' H' S.
  Proof. 
    intros Hwf Hsub Hsub'. split.
    - intros x [n [_ Hin]].
      eexists. split. now constructor.
      eapply (well_formed_post_n_subheap_same S H H') in Hin; eassumption.
    - intros x [n [_ Hin]].
      eexists. split. now constructor.
      eapply (well_formed_post_n_subheap_same S H H') in Hin; eassumption.
  Qed.

  Lemma well_formed_subheap H H' S :
    well_formed S H ->
    S \subset dom H ->
    H ⊑ H' ->
    well_formed S H'.
  Proof. 
    intros Hwf Henv Hsub x b Hget Hin.
    eapply Included_trans.
    eapply Hwf; eauto.
    eapply Henv in Hget.
    destruct Hget as [b' Hget]. rewrite Hget.
    now erewrite Hsub in Hin; eauto.

    eapply HL.dom_subheap. eassumption.
  Qed.

  Lemma well_formed_reach_def_closed_same (S : Ensemble loc) (H H' : heap block)
        B B0 rho rho' envc :
    well_formed (reach' H S) H  ->
    S \subset dom H ->
    val_loc envc \subset S ->
    def_closures B B0 rho H envc = (H', rho') ->
    reach' H S <--> reach' H' S.
  Proof.
    intros Hwf Hdom HS; revert H' rho'; induction B; intros H' rho' Hdef. 
    - simpl in Hdef.
      destruct (def_closures B B0 rho H envc) as [H'' rho''] eqn:Hdef'.
      destruct (alloc _ H'') as [l' H'''] eqn:Ha. inv Hdef.
      assert (Heq :reach' H'' S <--> reach' H' S).
      { eapply well_formed_reach_alloc_same; eauto.
        eapply well_formed_def_funs; eauto.
        rewrite <- IHB; [| reflexivity ]. eassumption.
        eapply Included_trans. eassumption.
        eassumption. eapply Included_trans. eassumption.
        eapply dom_subheap. eapply def_funs_subheap.
        eauto. }
      rewrite <- Heq, IHB; reflexivity.
    - inv Hdef. reflexivity.
  Qed.
  
  Lemma well_formed_reach_alloc_in_dom (S : Ensemble var) (H H' : heap block)
        (rho : env) (x : var) (b : block) (l : loc) :
    well_formed (reach' H (env_locs rho S)) H  ->
    env_locs rho S \subset dom H ->
    post H (locs b) \subset reach' H (env_locs rho S) ->
    alloc b H = (l, H') ->
    locs b \subset dom H ->
    well_formed (reach' H' (env_locs (M.set x (Loc l) rho) (Union _ S [set x]))) H'.
  Proof with now eauto with Ensembles_DB.
    intros Hwf Hsub Hpost Ha Hin.
    intros l1 b1 Hin1 Hget.
    destruct (loc_dec l l1); subst.
    - erewrite gas in Hget; eauto. inv Hget.
      eapply Included_trans. eassumption.
      eapply dom_subheap. eapply alloc_subheap. eassumption.
    - erewrite gao in Hget; eauto.
      rewrite env_locs_set_In in Hin1; [| now eauto with Ensembles_DB ].
      rewrite reach'_Union in Hin1.
      rewrite <- (well_formed_reach_alloc_same (env_locs _ _)) in Hin1; try eassumption.
      + inv Hin1.
        * rewrite reach_unfold in H0. inv H0.
          inv H1. contradiction.
          simpl in H1. rewrite post_Singleton in H1; [| now erewrite gas; eauto ].
          rewrite reach_unfold in H1. inv H1.
          { eapply Included_trans; [| now eapply dom_subheap; eapply alloc_subheap; eauto ].
            assert (Has : locs b1 \subset post H (locs b)).
            { intros l' Hlocs. eexists. eexists.
              split. eassumption. split. eassumption. eassumption. }
            eapply Included_trans. eassumption.
            eapply Included_trans. eassumption.
            eapply reachable_in_dom; eassumption.  }
          { assert (Heqp : post H (locs b) <--> post H' (locs b)).
            { eapply well_formed_post_n_alloc_same with (n := 1); try eassumption.
              rewrite reach_unfold. eapply well_formed_Union.
              intros l2 b2 Hin2 Hget2.
              assert (Has : locs b2 \subset post H (locs b)).
            { intros l' Hlocs. eexists. eexists.
              split. eassumption. split. eassumption. eassumption. }
            eapply Included_trans. eassumption.
            eapply Included_trans. eassumption.
            eapply reachable_in_dom; eassumption.
            eapply well_formed_antimon; [| eassumption ].
            rewrite (reach'_idempotent _ (env_locs rho S)).
            eapply reach'_set_monotonic. eassumption. }
            rewrite <- Heqp in H0.
            eapply well_formed_reach_alloc_same in H0; try eassumption.
            eapply Included_trans;
              [| now eapply dom_subheap; eapply alloc_subheap; eauto ].
            eapply Hwf; try eassumption.
            eapply reach'_idempotent. eapply reach'_set_monotonic; [| eassumption ].
            eassumption.
            eapply well_formed_antimon; [| eassumption ].
            rewrite (reach'_idempotent _ (env_locs rho S)).
            eapply reach'_set_monotonic. eassumption.
            eapply Included_trans; [| eapply reachable_in_dom ]; eauto. }
        * eapply Included_trans;
          [| now eapply dom_subheap; eapply alloc_subheap; eauto ].
          eapply Hwf; try eassumption.
          eapply reach'_set_monotonic; [| eassumption ]...
      + eapply well_formed_antimon; [| eassumption ].
        eapply reach'_set_monotonic.
        eapply env_locs_monotonic...
      + eapply Included_trans; [| exact Hsub ].
        eapply env_locs_monotonic...
  Qed.

  Lemma well_formed_reach_alloc_def_funs S H H' rho rho' B B0 envc :
    well_formed (reach' H (env_locs rho S)) H ->
    env_locs rho S \subset dom H ->
    val_loc envc \subset (reach' H (env_locs rho S)) ->
    def_closures B B0 rho H envc  = (H', rho') ->
    well_formed (reach' H' (env_locs rho' (Union _ S (name_in_fundefs B)))) H'.
  Proof with now eauto with Ensembles_DB.
    revert rho rho' H H';
    induction B; intros rho rho' H H' Hwf Hsub Hlocs Hdef; simpl. 
    - simpl in Hdef.
      destruct (def_closures B B0 rho H envc) as [H'' rho''] eqn:Hdef'.
      destruct (alloc _ H'') as [l' H'''] eqn:Hal. inv Hdef.
      rewrite (Union_commut [set v]), Union_assoc.
      eapply well_formed_reach_alloc; [| | eassumption |].
      + eapply IHB; eassumption.
      + eapply def_closures_env_locs_in_dom; eauto.
      + simpl. rewrite Union_Empty_set_neut_l.
        eapply def_closures_env_locs_reach;  try eassumption.
    - inv Hdef. rewrite Union_Empty_set_neut_r. eassumption.
  Qed.

  Lemma closed_set_alloc S H H' b l rho x :
    closed (reach' H (locs b :|: (env_locs rho (S \\ [set x])))) H ->
    alloc b H = (l, H') ->
    closed (reach' H' (env_locs (M.set x (Loc l) rho) S)) H'.
  Proof with now eauto with Ensembles_DB.
    intros Hcl Ha.
    eapply reach'_closed.
    - eapply well_formed_antimon.
      eapply reach'_set_monotonic. eapply env_locs_monotonic.
      eapply Included_Union_Setminus with (s2 := [set x]); typeclasses eauto.
      rewrite env_locs_Union.
      rewrite env_locs_set_not_In.
      + rewrite env_locs_Singleton; [| now rewrite M.gss ].
        rewrite reach'_Union. 
        rewrite (reach_unfold H' [set l]).
        rewrite post_Singleton; [| now erewrite gas; eauto ].
        rewrite Union_commut, <- Union_assoc.
        eapply well_formed_Union.
        * intros l1 b1 Hin Hget.
          inv Hin.
          erewrite gas in Hget; eauto. inv Hget.
          eapply Included_trans.
          eapply in_dom_closed in Hcl.
          eapply Included_trans; [| eassumption ].
          eapply Included_trans; [| eapply reach'_extensive ]...
          eapply dom_subheap. eapply alloc_subheap; now eauto.
        * rewrite <- reach'_Union.
          eapply well_formed_alloc; try eassumption.
          rewrite reach'_alloc; try eassumption.
          eapply well_formed'_closed in Hcl.
          eassumption.
          eapply Included_trans; [| now eapply reach'_extensive ]...
          eapply in_dom_closed in Hcl. eapply Included_trans; [| eassumption ].
          eapply Included_trans; [| now eapply reach'_extensive ]...
      + intros Hc. inv Hc; eauto.
    - eapply Included_trans. eapply env_locs_set_Inlcuded'.
      eapply Union_Included.
      + eapply Singleton_Included. eexists b.
        erewrite gas; eauto.
      + eapply Included_trans;
        [| eapply dom_subheap; eapply alloc_subheap; now eauto ].
        eapply in_dom_closed in Hcl.
        eapply Included_trans; [| eassumption ].
        eapply Included_trans; [| now eapply reach'_extensive ]...
  Qed.    

  Lemma closed_set_alloc_alt S H H' b l rho x :
    closed (reach' H (env_locs rho (S \\ [set x]))) H ->
    locs b \subset (reach' H (env_locs rho (S \\ [set x]))) ->
    alloc b H = (l, H') ->
    closed (reach' H' (env_locs (M.set x (Loc l) rho) S)) H'.
  Proof with now eauto with Ensembles_DB.
    intros Hcl Hin Ha l1 Hin'.
    destruct (loc_dec l1 l); subst.
    - eexists. erewrite gas; eauto.
      split. reflexivity.
      eapply Included_trans. eassumption.
      eapply Included_trans.
      eapply reach'_heap_monotonic.
      now eapply alloc_subheap; eauto.
      eapply reach'_set_monotonic.
      rewrite <- env_locs_set_not_In.
      eapply env_locs_monotonic...
      intros Hinx. now inv Hinx; eauto.
    - eapply reach'_set_monotonic in Hin';
      [| now eapply env_locs_set_Inlcuded'].
      rewrite reach'_Union in Hin'.
      rewrite reach_unfold in Hin'.
      simpl in Hin'. rewrite post_Singleton in Hin'; [| now erewrite gas; eauto ].
      inv Hin'.
      + inv H0.
        * inv H1. congruence.
        * edestruct Hcl as [b1 [Hget1 Hsub]]; eauto.
          rewrite <- reach'_alloc; try eassumption.
          rewrite reach'_idempotent.
          eapply reach'_set_monotonic; [| eassumption ].
          eapply Included_trans. eassumption.
          eapply reach'_heap_monotonic.
          eapply alloc_subheap. eassumption.
          eexists; split; eauto.
          
          now erewrite gao; eauto.
          
          eapply Included_trans. eassumption.
          eapply Included_trans. eapply reach'_heap_monotonic.
          eapply alloc_subheap. eassumption.
          eapply reach'_set_monotonic. 
          rewrite <- env_locs_set_not_In.
          eapply env_locs_monotonic...
          intros Hc. inv Hc; eauto.            
      + edestruct Hcl as [b1 [Hget1 Hsub]]; eauto.
        rewrite <- reach'_alloc; try eassumption.
        eexists.
        erewrite gao; eauto; split; eauto.
        eapply Included_trans. eassumption.
        eapply Included_trans. eapply reach'_heap_monotonic.
        eapply alloc_subheap. eassumption.
        eapply reach'_set_monotonic. 
        rewrite <- env_locs_set_not_In.
        eapply env_locs_monotonic...
        intros Hc. inv Hc; eauto.
  Qed.  
  
  (** Lemmas about [Restrict_env] *)

  Lemma key_set_Restrict_env S rho rho' :
    Restrict_env S rho rho' ->
    key_set rho' \subset S.
  Proof.
    now intros [_ [_ R]].
  Qed.

  Lemma restrict_env_correct S s rho :
    S <--> FromList (set_util.PS.elements s) ->
    Restrict_env S rho (restrict_env s rho).
  Proof.
    intros Heq. unfold restrict_env.
    split; [ | split ].
    - intros x Hin. rewrite gfilter.
      eapply Heq in Hin.
      simpl in Hin.
      unfold FromList, In in Hin. simpl in Hin.
      eapply In_InA with (eqA := eq) in Hin; eauto with typeclass_instances.
      eapply PS.elements_spec1 in Hin.
      eapply PS.mem_spec in Hin. rewrite Hin.
      destruct (M.get x rho); reflexivity.
    - intros x v Hget.
      rewrite gfilter in Hget.
      destruct (M.get x rho); try discriminate.
      destruct (PS.mem x s); try discriminate. 
      eauto.
    - intros x Hget. unfold key_set, In in Hget. simpl in Hget.
      rewrite gfilter in Hget.
      destruct (M.get x rho); try contradiction.
      destruct (PS.mem x s) eqn:Hin; try contradiction. 
      eapply PS.mem_spec in Hin.
      eapply PS.elements_spec1 in Hin.
      eapply InA_alt in Hin. destruct Hin as [x' [Heq' Hin']]; subst; eauto.
      eapply Heq. eassumption. 
  Qed.

  Lemma key_set_binding_in_map_alt (S : PS.t) (rho : env) :
    binding_in_map (FromSet S) rho ->
    key_set (restrict_env S rho) <--> FromSet S.
  Proof.
    intros Hbin.
    assert (HR : Restrict_env (FromSet S) rho (restrict_env S rho)). 
    { eapply restrict_env_correct. reflexivity. }
    split. 
    eapply key_set_Restrict_env. eassumption.

    intros x Hin. edestruct Hbin as [v Hget1]. eassumption.
    destruct HR as [Hs1 Hr]. 
    unfold key_set, In. rewrite <- Hs1, Hget1; eauto.
  Qed.


  (** * Correspondence of [set] and [Ensemble] definitions *)
  
  Lemma env_locs_set_full_correct (rho : env) :
    env_locs rho (Full_set var) <--> FromSet (env_locs_set_full rho).
  Proof.
    induction rho; simpl.
    - rewrite FromSet_empty. rewrite env_locs_Leaf. reflexivity.
    - destruct o as [v |].
      + rewrite env_locs_Node. destruct v.
        * rewrite FromSet_add, FromSet_union, IHrho1, IHrho2, Union_assoc.
          simpl. reflexivity. 
        * rewrite FromSet_union, IHrho1, IHrho2, Union_Empty_set_neut_l.
          simpl. reflexivity. 
      + rewrite env_locs_Node_None.
        rewrite FromSet_union, IHrho1, IHrho2. reflexivity.
  Qed.
  
  Lemma env_locs_set_correct_aux S s s' (rho : env) :
    S <--> FromSet s ->
    env_locs rho S :|: FromSet s' <--> FromSet (PS.fold
                                               (fun (x : PS.elt) (s' : PS.t) =>
                                                  match M.get x rho with
                                                    | Some (Loc l) => PS.add l s'
                                                    | Some (FunPtr _ _) => s'
                                                    | None => s'
                                                  end) s s').
  Proof with (now eauto with Ensembles_DB).
    unfold env_locs_set, FromSet at 1. rewrite PS.fold_spec.

    revert S s'; induction (PS.elements s); intros S s' Heq; simpl.
    - rewrite FromList_nil in Heq. rewrite Heq, env_locs_Empty_set, Union_Empty_set_neut_l.
      reflexivity.
    - rewrite FromList_cons in Heq.
      rewrite Heq, env_locs_Union.
      destruct (M.get a rho) as [v | ] eqn:Hget.
      + rewrite env_locs_Singleton; eauto.
        rewrite <- IHl; [| reflexivity ].
        destruct v as [l'| ].
        * rewrite FromSet_add...
        * simpl...
      + rewrite env_locs_Singleton_None; eauto.
        rewrite Union_Empty_set_neut_l. rewrite <- IHl; reflexivity.
  Qed.

  Lemma env_locs_set_correct S s (rho : env) :
    S <--> FromSet s ->
    env_locs rho S  <--> FromSet (env_locs_set rho s).
  Proof with (now eauto with Ensembles_DB).
    intros Heq. unfold env_locs_set.
    rewrite <- env_locs_set_correct_aux; [| eassumption ].
    rewrite FromSet_empty, Union_Empty_set_neut_r...
  Qed.
  
  Instance ToMSet_env_locs (S : Ensemble var) (rho : env) (HS : ToMSet S) : ToMSet (env_locs rho S) :=
    {
      mset := env_locs_set rho mset
    }.
  Proof.
    eapply env_locs_set_correct. eapply mset_eq.
  Qed.

  Lemma val_loc_set_correct v :
    val_loc v <--> FromSet (val_loc_set v).
  Proof.
    destruct v; simpl.
    - rewrite FromSet_singleton. reflexivity.
    - rewrite FromSet_empty. reflexivity. 
  Qed.

  Lemma locs_set_correct (b : block) :
    locs b <--> FromSet (locs_set b).
  Proof with (now eauto with Ensembles_DB).
    destruct b; simpl.
    - rewrite FromSet_union_list, FromSet_empty, Union_Empty_set_neut_l.
      induction l; simpl.
      + rewrite FromList_nil. reflexivity.
      + destruct a; simpl.
        * rewrite FromList_cons. now rewrite IHl.
        * rewrite Union_Empty_set_neut_l. eassumption.
    - rewrite FromSet_union.
      eapply Same_set_Union_compat;
        eapply val_loc_set_correct.
    - rewrite env_locs_set_full_correct. reflexivity.
  Qed.    


  Lemma post_set_correct_aux (S S' : Ensemble loc) (s s': PS.t) (H : heap block) :
    S <--> FromSet s ->
    S' <--> FromSet s' ->
    post H S :|: S' <--> FromSet (PS.fold
                                 (fun (l : PS.elt) (r : PS.t) =>
                                    match get l H with
                                      | Some v => PS.union (locs_set v) r
                                      | None => r
                                    end) s s').
  Proof.
    rewrite PS.fold_spec.
    unfold FromSet at 1. revert S S' s'. 
    induction (PS.elements s); intros S S' s' Heq1 Heq2.
    - rewrite FromList_nil in Heq1. rewrite Heq1, post_Empty_set.
      simpl. rewrite Union_Empty_set_neut_l. eassumption.
    - simpl. rewrite <- IHl; [| reflexivity | reflexivity ].
      rewrite Heq1, FromList_cons, post_Union, (Union_commut (post H [set a]) (post H (FromList l))).
      rewrite <- Union_assoc. eapply Same_set_Union_compat.
      reflexivity.
      destruct (get a H) eqn:Hget.
      + rewrite post_Singleton; eauto. simpl. rewrite FromSet_union.
        eapply Same_set_Union_compat; [| eassumption ].
        eapply locs_set_correct.
      + rewrite post_Singleton_None; eauto.
        rewrite Union_Empty_set_neut_l. eassumption.
  Qed.


  Lemma post_set_correct (S : Ensemble loc) (s : PS.t) (H : heap block) :
    S <--> FromSet s ->
    post H S <--> FromSet (post_set H s).
  Proof.
    intros Heq.
    erewrite <- (Union_Empty_set_neut_r (post H S)).
    rewrite post_set_correct_aux; [ | eassumption | ].
    unfold post_set. reflexivity.
    rewrite FromSet_empty. reflexivity.
  Qed.

  Lemma dfs_correct (S  : Ensemble loc) (s s' : PS.t) (H : heap block) (n m: nat) :
    (post H ^ (m+1)) S \\ reach_n H m S <--> FromSet s ->
    reach_n H m S <--> FromSet s' ->
    FromSet (dfs s s' H n) <--> reach_n H (n + 1 + m) S.
  Proof.
    revert S s s' m. induction n; intros S s s' m Heq1 Heq2; simpl.
    - rewrite FromSet_union, <- Heq1, <- Heq2.
      rewrite Union_commut, Union_Setminus_Included; try reflexivity.
      replace (Datatypes.S m) with (m + 1) by omega.
      rewrite reach_S_n. reflexivity.
      eapply Decidable_Same_set. symmetry. eassumption.
      eapply Decidable_FromSet. 
    - destruct (PS.cardinal s) eqn:Hcar.
      + rewrite FromSet_cardinal_empty in Heq1; [| eassumption ].
        rewrite <- Heq2.
        replace (Datatypes.S (n + 1 + m)) with ((n + 2) + m) by omega. 
        rewrite reach_n_fixed_point. reflexivity.
        eapply Setminus_Included_Empty_set_l.
        eapply Decidable_Same_set. symmetry. eassumption.
        eapply Decidable_FromSet.
        destruct Heq1. eassumption. 
      + assert (Heq : reach_n H (m + 1) S <--> FromSet (PS.union s' s)).
        { rewrite FromSet_union. rewrite <- Heq1, <- Heq2.
          rewrite Union_Setminus_Included; try reflexivity.
          rewrite reach_S_n. reflexivity.
          eapply Decidable_Same_set. symmetry. eassumption.
          eapply Decidable_FromSet. } 
        rewrite IHn with (m := m+1).
        * replace (Datatypes.S (n + 1 + m)) with (n + 1 + (m + 1)) by omega.
          reflexivity.
        * rewrite FromSet_diff. rewrite <- Heq.
          rewrite <- post_set_correct; [| eassumption ].
          split.

          intros x Hin. inv Hin.
          constructor; try eassumption.
          replace (m + 1 + 1) with (1 + (m + 1)) in H0 by omega.
          simpl in H0.
          destruct H0 as [y [b [Hin' [Hget Hl]]]].
          exists y, b. split; eauto. constructor. eassumption.
          intros Hc. eapply H1.
          destruct Hc as [k [Hleq Hp]]. 
          eexists (1 + k). split. omega.
          eexists y, b. now split; eauto.

          intros x Hin. inv Hin.
          constructor; eauto.
          replace (m + 1 + 1) with (1 + (m + 1)) by omega.
          destruct H0 as [y [b [Hin' [Hget Hl]]]]. inv Hin'.
          exists y, b. split; eauto.
        * rewrite <- Heq. reflexivity.
  Qed.

  Lemma reach_set_correct S s H :
    FromSet s <--> S ->
    FromSet (reach_set H s) <--> reach' H S.
  Proof.
    intros Heq. 
    unfold reach_set.
    unfold dfs. destruct (size H) eqn:Hs.
    - rewrite FromSet_union, FromSet_empty, Union_Empty_set_neut_r.
      rewrite reach_size_H_O; eauto.
    - destruct (PS.cardinal s) eqn:Hcard.
      + rewrite FromSet_cardinal_empty in Heq; eauto.
        rewrite <- Heq, FromSet_empty. rewrite reach'_Empty_set. reflexivity.
      + rewrite dfs_correct with (m := 0).
        * eapply reach_n_size_H_fixed_point. omega.
        * rewrite FromSet_diff. simpl.
          rewrite post_set_correct; [| symmetry; eassumption ].
          rewrite FromSet_union, reach_0, FromSet_empty, Union_Empty_set_neut_l, Heq. 
          reflexivity.
        * rewrite FromSet_union, reach_0, FromSet_empty, Union_Empty_set_neut_l, Heq.
          reflexivity.
  Qed.


  Lemma Decidable_reach' (S : Ensemble loc) (H : heap block) :
    ToMSet S ->
    Decidable (reach' H S).
  Proof.
    intros [s Heq]. eapply Decidable_Same_set.
    eapply reach_set_correct. symmetry; eassumption.
    eapply Decidable_FromSet.
  Qed.

  (** Lemmas about dfs *)

  
  Instance Proper_post_set : Proper (eq ==> PS.Equal ==> PS.Equal) post_set.
  Proof.
    intros x y Heq x' y' Heq2; subst. unfold post_set. rewrite !PS.fold_spec.
    erewrite elements_eq. reflexivity. assumption.
  Qed.
  
  Instance Proper_dfs : Proper (PS.Equal ==> PS.Equal ==> Logic.eq ==> Logic.eq ==> PS.Equal) dfs.
  Proof.
    intros x y Heq1 x' y' Heq2 H' H Heq3 n' n Heq4; subst.
    revert x y Heq1 x' y' Heq2. 
    induction n; simpl; intros x y Heq1 x' y' Heq2.
    - rewrite Heq2, Heq1. reflexivity.
    - rewrite Heq1. destruct (PS.cardinal y). eassumption.
      eapply IHn. repeat rewrite Heq1 at 1. rewrite Heq2. reflexivity.
      rewrite Heq1, Heq2. reflexivity.
  Qed.

  Instance Proper_reach_set : Proper (Logic.eq ==> PS.Equal ==> PS.Equal) reach_set.
  Proof.
    intros x y Heq1 x' y' Heq2; subst.
    unfold reach_set. rewrite Heq2. reflexivity.
  Qed.

  Instance ToMSet_reach' S {HS : ToMSet S} H : ToMSet (reach' H S).
  Proof.
    destruct HS.
    econstructor. symmetry. eapply reach_set_correct.
    symmetry. eassumption.
  Qed.

  (** Size of the reachable portion of the heap *)
  Definition size_reachable (S : Ensemble loc) {Hmset : ToMSet S} (H : heap block) : nat :=
    size_with_measure_filter size_val (reach' H S) H.

  Definition reach_size (H : heap block) (rho : env) (e : exp) :=
    size_reachable (env_locs rho (occurs_free e)) H. 
  
  Lemma size_reachable_same_set S1 S2 {H1 : ToMSet S1} {H2 : ToMSet S2} H :
    S1 <--> S2 ->
    size_reachable S1 H = size_reachable S2 H.
  Proof.
    unfold size_reachable. intros Heq.
    unfold size_reachable. eapply size_with_measure_Same_set. rewrite Heq.
    reflexivity. 
  Qed.

  Lemma reach'_alloc_set (S : Ensemble var) (H H' : heap block) (rho : env)
        (x : var) (b : block) (l : loc) :
    locs b \subset reach' H (env_locs rho S)->
    alloc b H = (l, H')  ->  
    reach' H' (env_locs (M.set x (Loc l) rho) (S :|: [set x])) \subset
    l |: reach' H (env_locs rho S).
  Proof.
    intros Hsub Hal.
    eapply Included_trans. eapply reach'_set_monotonic.
    eapply env_locs_set_Inlcuded. 
    rewrite reach'_Union.
    rewrite (reach'_alloc (env_locs rho S)); try eassumption.
    eapply Union_Included; [| now eauto with Ensembles_DB ].
    simpl. rewrite reach_unfold. eapply Included_Union_compat.
    reflexivity.
    rewrite post_Singleton; [| erewrite gas; eauto].
    rewrite (reach'_idempotent _ (env_locs rho S)).
    rewrite (reach'_alloc (locs b)); eauto.
    eapply reach'_set_monotonic. eassumption.
    now apply reach'_extensive. 
  Qed.      

  (** * Lemmas about [def_closures] *)

  
  Lemma def_closures_post B1 B2 rho H rho' H' rc :
    def_closures B1 B2 rho H rc = (H', rho') ->
    post H' (env_locs rho' (name_in_fundefs B1)) \subset val_loc rc.
  Proof with  (now eauto with Ensembles_DB).
    revert rho rho' H H'. induction B1; intros rho rho' H H' Hdef; simpl.
    - simpl in Hdef.
      destruct (def_closures B1 B2 _ _ _) as [H'' rho''] eqn:Hclo.
      destruct (alloc _ H'') as [l1 H'''] eqn:Ha.
      inv Hdef. 
      rewrite env_locs_Union, post_Union, env_locs_Singleton;
      [| now rewrite M.gss; eauto ].

      eapply Union_Included.

      + simpl. rewrite post_Singleton; [| now erewrite gas; eauto ]...

      + assert (Hclo' := Hclo). eapply IHB1 in Hclo.

        eapply Included_trans.
        eapply post_set_monotonic. eapply env_locs_set_Inlcuded'.

        rewrite post_Union. 
        simpl. rewrite post_Singleton; [| now erewrite gas; eauto ].
        
        eapply Union_Included; [ now eauto with Ensembles_DB |].
        eapply Included_trans. eapply post_alloc. eassumption.

        eapply Union_Included.

        eapply Included_trans; [| eassumption ].
        eapply post_set_monotonic.
        eapply env_locs_monotonic...
        now eauto with Ensembles_DB. 
    - rewrite env_locs_Empty_set, post_Empty_set...
  Qed.


  Lemma def_closures_exists (H1 H1' : heap block)
    (rho1 rho1' : env) envc (B B0 : fundefs) f :
    def_closures B B0 rho1 H1 envc = (H1', rho1') ->
    f \in name_in_fundefs B ->
    exists l, M.get f rho1' = Some (Loc l) /\ get l H1' = Some (Clos (FunPtr B0 f) envc) /\ ~ l \in dom H1.
  Proof.
    revert H1 H1' rho1 rho1'; induction B; intros H1 H1' rho1 rho1' Hdef Hin. 
    - simpl in Hdef.
      destruct (def_closures B B0 rho1 H1 envc) as [H' rho'] eqn:Hdef'.
      destruct (alloc (Clos (FunPtr B0 v) envc) H') as [lf H''] eqn:Ha. inv Hdef.
      destruct (var_dec v f); subst. 
      + rewrite M.gss. eexists; split. reflexivity. split. 
        erewrite gas; [| eassumption ]. reflexivity.
        intros [b Hgetl]. eapply def_funs_subheap in Hgetl; eauto.
        erewrite alloc_fresh in Hgetl; eauto. congruence. 
      + rewrite M.gso; [| now eauto ].
        edestruct IHB as [lf' [Hgetf [Hgetlf Hdom]]]. eassumption.
        inv Hin; eauto. now inv H.
        eexists; split; eauto.
        
        erewrite HL.alloc_subheap; try eassumption. split. reflexivity.
        eassumption. 
    - inv Hin.
  Qed.

  Lemma def_closures_get_neq (H1 H1' : heap block)
    (rho1 rho1' : env) envc (B B0 : fundefs) f :
    def_closures B B0 rho1 H1 envc = (H1', rho1') ->
    ~ f \in name_in_fundefs B ->
    M.get f rho1' = M.get f rho1.
  Proof.
    revert H1 H1' rho1 rho1'; induction B; intros H1 H1' rho1 rho1' Hdef Hnin. 
    - simpl in Hdef.
      destruct (def_closures B B0 rho1 H1 envc) as [H' rho'] eqn:Hdef'.
      destruct (alloc (Clos (FunPtr B0 v) envc) H') as [lf H''] eqn:Ha. inv Hdef.
      rewrite M.gso. eapply IHB; eauto.
      intros Hc; eapply Hnin; now right.
      intros Hc; subst; eapply Hnin; now left.

    - inv Hdef. reflexivity. 
  Qed.

  Lemma def_funs_neq
    (rho1 rho1' : env) (B B0 : fundefs) f :
    def_funs B B0 rho1 = rho1' ->
    ~ f \in name_in_fundefs B ->
    M.get f rho1' = M.get f rho1.
  Proof.
    revert rho1 rho1'; induction B; intros rho1 rho1' Hdef Hnin. 
    - simpl in Hdef. subst. 
      rewrite M.gso. eapply IHB; eauto.
      intros Hc; eapply Hnin; now right.
      intros Hc; subst; eapply Hnin; now left.

    - inv Hdef. reflexivity. 
  Qed.

  Lemma def_funs_eq
    (rho1 rho1' : env) (B B0 : fundefs) f :
    def_funs B B0 rho1 = rho1' ->
    f \in name_in_fundefs B ->
    M.get f rho1' = Some (FunPtr B0 f).
  Proof.
    revert rho1 rho1'; induction B; intros rho1 rho1' Hdef Hnin. 
    - simpl in Hdef. subst. 
      destruct (var_dec f v); subst.
      + rewrite M.gss. reflexivity.
      + rewrite M.gso. eapply IHB; eauto. inv Hnin; eauto.
        inv H; contradiction. eassumption.
    - inv Hnin. 
  Qed.


  Lemma def_closures_env_locs  (H1 H1' : heap block)
    (rho1 rho1' : env) envc (B B0 : fundefs) S :
    def_closures B B0 rho1 H1 envc = (H1', rho1') ->
    unique_functions B ->
    env_locs rho1' S \subset env_locs rho1 (S \\ name_in_fundefs B) :|: env_locs rho1' (name_in_fundefs B). 
  Proof.
    revert S H1 H1' rho1 rho1'; induction B; intros S H1 H1' rho1 rho1' Hdef Hun. 
    - simpl in Hdef.
      destruct (def_closures B B0 rho1 H1 envc) as [H' rho'] eqn:Hdef'.
      destruct (alloc (Clos (FunPtr B0 v) envc) H') as [lf H''] eqn:Ha. inv Hdef.
      eapply Included_trans.
      eapply env_locs_set_Inlcuded'.
      eapply Union_Included.
      + eapply Included_Union_preserv_r.
        rewrite env_locs_set_In. now eauto with Ensembles_DB.
        now left.
      + eapply Included_trans.
        
        eapply IHB. eassumption. now inv Hun.
        eapply Included_Union_compat.
        
        simpl. rewrite Setminus_Union. reflexivity.
        
        rewrite env_locs_set_In. simpl.
        rewrite Setminus_Union_distr. rewrite (Setminus_Disjoint (name_in_fundefs B)).
        rewrite env_locs_Union. now eauto with Ensembles_DB.
        eapply Disjoint_Singleton_r. inv Hun. eassumption.
        now left.
    - inv Hdef. simpl. rewrite Setminus_Empty_set_neut_r.
      now eauto with Ensembles_DB.
  Qed.

  Lemma def_closures_env_locs'  (H1 H1' : heap block)
    (rho1 rho1' : env) envc (B B0 : fundefs) S :
    def_closures B B0 rho1 H1 envc = (H1', rho1') ->
    Disjoint _ S (name_in_fundefs B) ->
    env_locs rho1' S <--> env_locs rho1 S.
  Proof with (now eauto with Ensembles_DB).
    revert H1 H1' rho1 rho1'; induction B; intros H1 H1' rho1 rho1' Hdef Hun.
    - simpl in Hdef.
      destruct (def_closures B B0 rho1 H1 envc) as [H' rho'] eqn:Hdef'.
      destruct (alloc (Clos (FunPtr B0 v) envc) H') as [lf H''] eqn:Ha. inv Hdef.
      rewrite env_locs_set_not_In. eapply IHB. eassumption.
      eapply Disjoint_Included_r; [| eassumption ]...
      intros Hc.  eapply Hun. constructor; eauto. now left.
    - inv Hdef...
  Qed.       

  Lemma def_closures_reach  (H1 H1' : heap block)
        (rho1 rho1' : env) envc (B B0 : fundefs) S :
    well_formed (reach' H1 (env_locs rho1 (S \\ name_in_fundefs B))) H1 ->
    env_locs rho1 (S \\ name_in_fundefs B) \subset dom H1 ->

    def_closures B B0 rho1 H1 envc = (H1', rho1') ->
    unique_functions B ->
    val_loc envc \subset reach' H1 (env_locs rho1 (S \\ name_in_fundefs B)) ->
    reach' H1' (env_locs rho1' S) \subset
    reach' H1 (env_locs rho1 (S \\ name_in_fundefs B)) :|: env_locs rho1' (name_in_fundefs B). 
  Proof.
    intros Hwf Hlocs Hdef Hun Henv. eapply Included_trans. eapply reach'_set_monotonic.
    
    eapply def_closures_env_locs. eassumption. eassumption.
    
    rewrite reach'_Union. eapply Union_Included.
    
    rewrite <- well_formed_reach_subheap_same; [| eassumption | eassumption | ].
    now eauto with Ensembles_DB.

    eapply def_funs_subheap. now eauto.

    rewrite reach_unfold. eapply Union_Included. now eauto with Ensembles_DB.
    
    eapply Included_trans. eapply reach'_set_monotonic.
    eapply Included_trans. eapply def_closures_post. eassumption.
    eassumption.
    
    rewrite <- well_formed_reach_subheap_same.
    rewrite <- reach'_idempotent. now eauto with Ensembles_DB.
    rewrite <- reach'_idempotent. eassumption.
    eapply reachable_in_dom. eassumption. eassumption.
    eapply def_funs_subheap. now eauto.

  Qed. 
    

  Lemma def_closures_env_locs_Disjoint  (H1 H1' : heap block)
    (rho1 rho1' : env) envc (B B0 : fundefs) :
    def_closures B B0 rho1 H1 envc = (H1', rho1') ->
    Disjoint _ (env_locs rho1' (name_in_fundefs B)) (dom H1). 
  Proof.
    revert H1 H1' rho1 rho1'; induction B; intros H1 H1' rho1 rho1' Hdef. 
    - simpl in Hdef.
      destruct (def_closures B B0 rho1 H1 envc) as [H' rho'] eqn:Hdef'.
      destruct (alloc (Clos (FunPtr B0 v) envc) H') as [lf H''] eqn:Ha. inv Hdef.
      rewrite env_locs_set_In. simpl.
      eapply Union_Disjoint_l. eapply Disjoint_Singleton_l.

      intros [vl Hgetvl]. eapply def_funs_subheap in Hgetvl; [| now eauto ].
      erewrite alloc_fresh in Hgetvl; eauto.
      congruence.
      
      eapply Disjoint_Included_l; [| eapply IHB; eauto ].
      eapply env_locs_monotonic. now eauto with Ensembles_DB.

      now left.

    - simpl. rewrite env_locs_Empty_set.
      now eauto with Ensembles_DB. 
  Qed. 

  Lemma def_closures_env_locs_fresh (H1 H1' : heap block)
    (rho1 rho1' : env) envc (B B0 : fundefs) f :
    def_closures B B0 rho1 H1 envc = (H1', rho1') ->
    unique_functions B ->
    f \in name_in_fundefs B ->
    Disjoint _ (env_locs rho1' [set f]) (env_locs rho1' (name_in_fundefs B \\ [set f])).
  Proof. 
    revert H1 H1' rho1 rho1'; induction B; intros H1 H1' rho1 rho1' Hdef Hun Hin. 
    - simpl in Hdef.
      destruct (def_closures B B0 rho1 H1 envc) as [H' rho'] eqn:Hdef'.
      destruct (alloc (Clos (FunPtr B0 v) envc) H') as [lf H''] eqn:Ha. inv Hdef.
      assert (Hdef'' := Hdef').
      eapply def_closures_env_locs_in_dom with (S := Empty_set _) in Hdef'';
        [| rewrite env_locs_Empty_set; now eauto with Ensembles_DB ].
      
      destruct (var_dec v f); subst.
      + rewrite env_locs_set_In; [| reflexivity ].
        rewrite Setminus_Same_set_Empty_set, env_locs_Empty_set, Union_Empty_set_neut_r. 

        rewrite env_locs_set_not_In; [ | now intros Hc; inv Hc; eauto ]. 

        eapply Disjoint_Singleton_l.

        intros Hc. 
        eapply env_locs_monotonic in Hc. eapply Hdef'' in Hc.
        
        destruct Hc as [b Hget]. erewrite alloc_fresh in Hget; try eassumption.
        congruence.
        
        simpl. now eauto with Ensembles_DB.

      + inv Hin. now inv H; contradiction.

        rewrite env_locs_set_not_In; [ | intros Hc; inv Hc; contradiction ]. 

        rewrite env_locs_set_In.

        eapply Union_Disjoint_r. 

        eapply Disjoint_Singleton_r. intros Hc.

        eapply env_locs_monotonic in Hc. eapply Hdef'' in Hc.
        
        destruct Hc as [b Hget]. erewrite alloc_fresh in Hget; try eassumption.
        congruence.
        
        now eauto with Ensembles_DB.

        eapply Disjoint_Included_r; [| eapply IHB; try eassumption ].

        eapply env_locs_monotonic. simpl.

        rewrite !Setminus_Union_distr. now eauto with Ensembles_DB.

        inv Hun. eassumption.

        constructor; eauto. left. reflexivity.

        intros Hc. inv Hc. eauto.

    - inv Hin. 
  Qed. 

  Lemma def_closures_env_locs_post_reach
        (S : Ensemble var) (H H' : heap block) (rho rho' : env)
        (B B0 : fundefs) (cenv : value) :
    def_closures B B0 rho H cenv = (H', rho') ->
    post H (val_loc cenv) \subset (reach' H (env_locs rho S)) ->
    post H' (val_loc cenv) \subset (reach' H' (env_locs rho' (S :|: name_in_fundefs B))).
  Proof.
    revert S rho rho' H H'; induction B; intros S rho rho' H H' Hdef Hsub; simpl.
    - simpl in Hdef.
      destruct (def_closures B B0 rho H cenv) as [H'' rho''] eqn:Hdef'.
      destruct (alloc _ H'') as [l' H'''] eqn:Hal. inv Hdef.
      rewrite env_locs_set_In; [| now eauto ]. rewrite reach'_Union.
      eapply Included_Union_preserv_l.
      eapply Included_trans; [| eapply Included_post_n_reach' with (n := 2) ].
      simpl. rewrite post_Singleton; [| erewrite gas; eauto ].
      simpl. eapply post_set_monotonic. now eauto with Ensembles_DB.
    - rewrite Union_Empty_set_neut_r. inv Hdef.
      eassumption.
  Qed.

  Lemma def_closures_env_locs_reach_reach
        (S : Ensemble var) (H H' : heap block) (rho rho' : env)
        (B B0 : fundefs) (cenv : value) :
    def_closures B B0 rho H cenv = (H', rho') ->
    reach' H (val_loc cenv) \subset (reach' H (env_locs rho S)) ->
    reach' H' (val_loc cenv) \subset (reach' H' (env_locs rho' (S :|: name_in_fundefs B))).
  Proof.
    revert S rho rho' H H'; induction B; intros S rho rho' H H' Hdef Hsub; simpl.
    - simpl in Hdef.
      destruct (def_closures B B0 rho H cenv) as [H'' rho''] eqn:Hdef'.
      destruct (alloc _ H'') as [l' H'''] eqn:Hal. inv Hdef.
      rewrite env_locs_set_In; [| now eauto ]. rewrite reach'_Union.
      eapply Included_Union_preserv_l.
      rewrite (reach_unfold H' (val_loc (Loc l'))). 
      simpl. rewrite post_Singleton; [| erewrite gas; eauto ]. simpl.
      eapply Included_Union_preserv_r. rewrite Union_Empty_set_neut_l.
      reflexivity. 
    - rewrite Union_Empty_set_neut_r. inv Hdef.
      eassumption.
  Qed.

  
End HeapDefs.
