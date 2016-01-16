(*
The MIT License (MIT)

Copyright (c) 2014 Leonardo Laguna Ruiz, Carl Jönsson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*)

type id = string list
   [@@deriving show,eq,ord]

type vtype =
   | TUnbound  of string * int option * Loc.t option
   | TId       of id * Loc.t option
   | TComposed of id * t list * Loc.t option
   | TArrow    of t * t * Loc.t option
   | TLink     of t
   | TExpAlt   of t list
   [@@deriving show,eq,ord]

and t = vtype ref
   [@@deriving show,eq,ord]

let rec unlink t =
   match t with
   | { contents = TLink(e) } -> unlink e
   | { contents = TComposed(id,elems,_) } ->
      { contents = TComposed(id,List.map unlink elems,None) }
   | { contents = TArrow(t1,t2,_) } ->
      { contents = TArrow(unlink t1,unlink t2,None) }
   | { contents = TExpAlt(elems) } ->
      { contents = TExpAlt(List.map unlink elems) }
   | { contents = TId(id,_) } ->
      { contents = TId(id,None) }
   | { contents = TUnbound(name,level,_) } ->
      { contents = TUnbound(name,level,None) }

let compare a b = compare (unlink a) (unlink b)

let gensym_counter = ref 0
let reset_gensym : unit -> unit =
   fun () -> gensym_counter := 0

let gensym : unit -> string = fun () ->
   let n = !gensym_counter in
   let () = incr gensym_counter in
   string_of_int n


(* Determining the |let|-nesting level during the type-checking,
   or just the _level_.
   Each top-level expression to type-check is implicitly wrapped into a let.
   So, the numbering starts with 1.
*)

let current_level_val = ref 1
let current_level () = !current_level_val

let reset_level () = current_level_val := 1

let reset_type_variables () =       (* name from OCaml's typing/typetext.ml *)
   reset_gensym ();
   reset_level ()

(* Increase level *)
let enterLevel () =
   incr current_level_val
(* Restore level *)
let leaveLevel () =
   decr current_level_val

let rec makeArrowType (last:t) (types:t list) : t =
   match types with
   | [] -> last
   | h::t -> ref (TArrow(h,makeArrowType last t,None))

let rec stripArrow (typ:t) : t list * t =
   match typ with
   | { contents = TArrow(t1,t2,_) } ->
      let args,last = stripArrow t2 in
      t1 :: args, last
   | _ -> [], typ

(* Make a fresh type variable *)
let newvar : unit -> t =
   fun () -> (ref (TUnbound (gensym (),Some(current_level()),None)))
(* Make a fresh type variable *)

(** Makes a copy of a type (a new instance) *)
let newinst (t:t) : t =
   let rec copy table t =
      try (List.find (fun (key,_) -> key == t) table |> snd),table with | Not_found ->
         match !t with
         | TUnbound(s,level,loc) ->
            let o = ref (TUnbound(s,level,loc)) in
            o, ((t,o) :: table)
         | TId(id,loc) ->
            let o = ref (TId(id,loc)) in
            o, (t,o) :: table
         | TComposed(id,elems,loc) ->
            let elems', table' = copyList table elems in
            let o = ref (TComposed(id,elems',loc)) in
            o, (t,o) :: table'
         | TArrow(t1,t2,loc) ->
            let t1', table' = copy table t1 in
            let t2', table' = copy table' t2 in
            let o = ref (TArrow(t1',t2',loc)) in
            o, (t,o) :: table'
         | TLink(link) ->
            let link', table' = copy table link in
            let o = ref (TLink(link')) in
            o, (t,o) :: table'
         | TExpAlt(elems) ->
            let elems', table' = copyList table elems in
            let o = ref (TExpAlt(elems')) in
            o, (t,o) :: table'
   and copyList table l =
      let l',table' =
         List.fold_left
            (fun (ol,table) t -> let o, table' = copy table t in o :: ol,table')
            ([],table) l
      in
      List.rev l', table'
   in copy [] t |> fst

let rec fixType table t =
   try
      List.find (fun key -> equal key t) table, table
      with
   | _ ->
      match t with
      | { contents = TUnbound(_,_,_) } -> t, t :: table
      | { contents = TComposed(id,elems,loc) } ->
         let elems', table' = fixTypeList table elems in
         ref (TComposed(id,elems',loc)), table'
      | { contents = TArrow(t1,t2,loc) } ->
         let t1', table' = fixType table t1 in
         let t2', table' = fixType table' t2 in
         ref (TArrow(t1',t2',loc)), table'
      | { contents = TLink(link) } ->
         let link', table' = fixType table link in
         ref (TLink(link')), table'
      | { contents = TExpAlt(elems) } ->
         let elems', table' = fixTypeList table elems in
         ref (TExpAlt(elems')), table'
      | _ -> t, table

and fixTypeList table tl =
   let tl', table' =
      List.fold_left
         (fun (ol,table) t -> let o, table' = fixType table t in o :: ol,table')
         ([],table) tl
   in List.rev tl', table'

let fixOptType table ot =
   match ot with
   | None -> None, table
   | Some(t) ->
      let t', table' = fixType table t in
      Some(t'), table'

let rec isUnbound (t:t) =
   match t with
   | { contents = TUnbound(_,_,_) } -> true
   | { contents = TId(_,_) } -> false
   | { contents = TComposed(_,elems,_) } -> List.exists isUnbound elems
   | { contents = TArrow(t1,t2,_) } ->
      isUnbound t1 || isUnbound t2
   | { contents = TLink(t) } -> isUnbound t
   | { contents = TExpAlt(_) } -> true

let getLevel = function
   | None -> current_level ()
   | Some(n) -> n

let pickLoc (loc1:Loc.t option) (loc2:Loc.t option) : Loc.t option =
   match loc1, loc2 with
   | None, _ -> loc2
   | _, None -> loc1
   | Some(l1),_ when l1 = Loc.default -> loc2
   | _,Some(l2) when l2 = Loc.default -> loc1
   | _ -> loc1

let rec unify (t1:t) (t2:t) : bool =
   if t1 == t2 then true else
   match t1,t2 with
   | { contents = TUnbound(n1,level1,loc1)}, { contents = TUnbound(_,level2,loc2) } ->
      let loc = pickLoc loc1 loc2 in
      let level = min (getLevel level1) (getLevel level2) in
      let n = if n1 = "" then gensym () else n1 in
      let t = TUnbound(n,Some(level),loc) in
      t1 := t;
      t2 := TLink(t1);
      true
   | { contents = TLink(tlink) },t | t, { contents = TLink(tlink) } ->
      unify t tlink
   | ({ contents = TUnbound _ } as tu), t | t, ({ contents = TUnbound _ } as tu) ->
      tu := TLink(t);
      true
   | { contents = TComposed(n1,elems1,_) }, { contents = TComposed(n2,elems2,_) } when n1 = n2 ->
      List.for_all2 unify elems1 elems2
   | { contents = TArrow(a1,a2,_) }, { contents = TArrow(b1,b2,_) } ->
      unify a1 b1 && unify a2 b2
   | { contents = TId(id1,_) }, { contents = TId(id2,_) } when id1 = id2 -> true

   | { contents = (TExpAlt(_) as tp1) },{ contents = (TExpAlt(_) as tp2) } when equal_vtype tp1 tp2 ->
      t2 := TLink(t1);
      true

   (* TODO: unify types with different alternatives *)

   | ({ contents = TExpAlt(alt) } as tu), t
   | t, ({ contents = TExpAlt(alt) } as tu) ->
      let rec loop alt =
         match alt with
         | [] -> false
         | first_alt :: alt_rest ->
            if unify t first_alt then
               begin
               tu := TLink(first_alt);
               true
            end
         else
            loop alt_rest
      in loop alt
   | { contents = tp1 }, { contents = tp2 } when equal_vtype tp1 tp2 ->
      true

   | _ -> false


(** Constant types *)
module Constants = struct
   let type_type   = ref (TId(["type"],None))
   let unit_type   = ref (TId(["unit"],None))
   let bool_type   = ref (TId(["bool"],None))
   let int_type    = ref (TId(["int"],None))
   let real_type   = ref (TId(["real"],None))
   let string_type = ref (TId(["string"],None))

   let num_type    () = ref (TExpAlt([real_type; int_type; bool_type]))

   let real_real () =
      ref (TArrow(real_type,real_type,None))

   let a_a_a () =
      let a = ref (TUnbound("'a",None,None)) in
      ref (TArrow(a,ref (TArrow(a,a,None)),None))

   let num_num () =
      let num = num_type () in
      ref (TArrow(num,num,None))

   let num_num_bool () =
      let num = num_type () in
      ref (TArrow(num,ref (TArrow(num,bool_type,None)),None))

   let a_a_bool () =
      let a = ref (TUnbound("'a",None,None)) in
      ref (TArrow(a,ref (TArrow(a,bool_type,None)),None))

   let int_int_int () =
      ref (TArrow(int_type,ref (TArrow(int_type,int_type,None)),None))

   let num_num_num_num () =
      let num = num_type () in
      ref (TArrow(num,ref (TArrow(num,ref (TArrow(num,num,None)),None)),None))

   let a_a_a_a () =
      let a = ref (TUnbound("'a",None,None)) in
      ref (TArrow(a,ref (TArrow(a,ref (TArrow(a,a,None)),None)),None))

   let bool_bool () = ref (TArrow(bool_type,bool_type,None))

   let bool_bool_bool () =
      ref (TArrow(bool_type,ref (TArrow(bool_type,bool_type,None)),None))

   let num_int () =
      ref (TArrow(num_type (),int_type,None))

   let num_real () =
      ref (TArrow(num_type (),real_type,None))

end
