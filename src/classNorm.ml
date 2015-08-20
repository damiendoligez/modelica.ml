(*
 * Copyright (c) 2014, TU Berlin
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *   * Neither the name of the TU Berlin nor the
 *     names of its contributors may be used to endorse or promote products
 *     derived from this software without specific prior written permission.

 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL TU Berlin BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 *)

(** Normalization of classLang expressions *)

module CamlFormat = Format
open Batteries
module Format = CamlFormat
                  
open Utils
open Location
open Motypes
open Report
       
exception ExpansionException of string
                                        
type prefix_found_struct = { found : class_path ; not_found : Name.t } [@@deriving show]

let show_prefix_found {found; not_found} = "No element named " ^ (Name.show not_found) ^ " in " ^ (Name.show (Name.of_ptr found))
                      
type found_struct = { found_path : class_path ; found_value : Normalized.class_value ; found_visible : bool } [@@deriving show]

type search_error = [ `NothingFound | `PrefixFound of prefix_found_struct ] [@@deriving show]

type found_recursion = { rec_term : Normalized.rec_term ; search_state : prefix_found_struct } [@@deriving show]
                                                                            
type search_result = [`Found of found_struct | `Recursion of found_recursion | search_error ] [@@deriving show]
                                                   
type unresolved_dependency = { searching : Name.t ; result : search_error }
                               
let fail_unresolved {searching; result} = Report.do_ ; log{level=Error;where=none;what=Printf.sprintf "Dependency %s not evaluated:\n%s\n" (Name.show searching)
                                                                                                      (show_search_error result)} ; fail

exception EmptyName

let rec get_class_element_in global current_path {Normalized.class_members; super; fields} x xs =
  if StrMap.mem x class_members then begin
      let found = (DQ.snoc current_path (`ClassMember x)) in
      let r = (get_class_element global found (StrMap.find x class_members) xs) in
      match r with
        `NothingFound -> (`PrefixFound {not_found=xs; found})      
      | r -> r
    end
  else if StrMap.mem x fields then begin
      let found = (DQ.snoc current_path (`Field x)) in
      let r = (get_class_element global found (StrMap.find x fields) xs) in
      match r with
        `NothingFound -> (`PrefixFound {not_found=xs; found})      
      | r -> r
    end
  else (
    pickfirst_class global 0 current_path (DQ.cons x xs) (IntMap.bindings super) )
		   
and pickfirst_class global n current_path name = function
    [] -> `NothingFound
  | (k,v)::vs ->
     let next_path = DQ.snoc current_path (`SuperClass n) in
     let f = get_class_element global next_path v name in
     begin match f with
             `NothingFound -> pickfirst_class global (n+1) current_path name vs
           | r -> r
     end
                    
and get_class_element global found_path e p =
  let open Normalized in 
  match DQ.front p with
    None -> (`Found {found_path ; found_value = e; found_visible=true})
  | Some (x, xs) -> begin
      match e with
      | Class {protected;public} ->
	 begin
           let f = get_class_element_in global found_path public x xs in
           begin
             match f with
	       `NothingFound -> get_class_element_in global found_path protected x xs
             | _ as r -> r
           end
	 end
           
      (* we might encounter recursive elements *)
      | Recursive rec_term -> `Recursion {rec_term; search_state={found = found_path; not_found = p}}
           
      (* follow global references through self to implement redeclarations *)
      | GlobalReference g ->
         begin match DQ.front g with
                 Some(x,xs) ->
                 begin match get_class_element_in global DQ.empty global x xs with
                       | `Found {found_value} -> get_class_element global found_path found_value p
                       | `Recursion _ as r -> r
                       | `NothingFound | `PrefixFound _ as result ->  BatLog.logf "Could not follow (probably recursive) %s\n" (Name.show g); result
                 end
               | None -> raise EmptyName
         end
	   
      (* Replaceable/Constr means to look into it *)
      | Replaceable v -> get_class_element global found_path v p    
      | Constr {arg} -> get_class_element global found_path arg p
      | _ -> `NothingFound
    end    
                                          
let lookup o p =
  let open Normalized in
  match DQ.front p with
    None -> (`Found {found_value = Class {empty_object_struct with public = o}; found_path = DQ.empty; found_visible=true}) ;
  | Some(x,xs) -> get_class_element_in o DQ.empty o x xs


open Normalized

exception IllegalPathElement 
                                    
exception CannotUpdate of string * string * string

let rec update_ (lhs:class_path) rhs ({class_members;fields;super} as elements) = match DQ.front lhs with
    None -> elements
  | Some (`SuperClass i, r) -> {elements with super = update_intmap r rhs i super} 
  | Some (`Field x, r) -> {elements with fields = update_map r rhs x fields}
  | Some (`ClassMember x, r) -> {elements with class_members = update_map r rhs x class_members}
  | Some (`Protected,_) -> raise IllegalPathElement
				 
and update_map lhs rhs x m =  
  StrMap.modify_def empty_class x (update_class_value lhs rhs) m
                                     
and update_intmap lhs rhs i map =  
  IntMap.modify_def empty_class i (update_class_value lhs rhs) map

and update_class_value lhs rhs = function
  | Constr {constr; arg} -> Constr {constr ; arg = (update_class_value lhs rhs arg)}
  | Class ({public; protected} as os) -> begin match DQ.front lhs with
						 None -> rhs
					       | Some(`Protected, q) -> Class {os with protected = update_ q rhs protected}
					       | Some _ -> Class {os with public = update_ lhs rhs public}
					 end
  | Replaceable cv -> Replaceable (update_class_value lhs rhs cv)
  | (Recursive _ | Int | Real | String | Bool | Unit | ProtoExternalObject | Enumeration _ | GlobalReference _ | DynamicReference _) as v ->
     begin match DQ.front lhs with
             None -> rhs
           | Some (x,xs) -> raise (CannotUpdate(show_class_path_elem x, show_class_path xs, show_class_value v))
     end

let update lhs rhs es = update_ lhs rhs es
			      
exception NonLeafRecursion

exception Stratification of class_path * string
       
let rec stratify_non_existing done_ todo = match DQ.front todo with
    None -> done_
  | Some(`Any x, _) -> raise (Stratification (done_, x))
  | Some((`Protected | `ClassMember _ | `Field _ | `SuperClass _ ) as x, xs) -> stratify_non_existing (DQ.snoc done_ x) xs
    
let rec stratify global c (done_:class_path) (todo:class_ptr) =
  match DQ.front todo with
    None -> done_
  | Some(`Any x,xs) -> begin match get_class_element global DQ.empty c (DQ.singleton x) with
                               `Found {found_value;found_path} -> begin match DQ.front found_path with
                                                                          None -> raise (Failure "internal error, succeeded lookup returned empty path") 
                                                                        | Some (y, ys) -> stratify global found_value (DQ.snoc done_ y) xs
                                                                  end
                             | _ -> raise (Stratification (done_, x))
                       end

  | Some(`Protected, xs) -> 
     begin match c with
             Class {protected} -> stratify_elements global protected (DQ.snoc done_ `Protected) xs
           | _ -> stratify_non_existing done_ todo
     end
  | Some(x,xs) -> begin match c with
                          Class {public} -> stratify_elements global public done_ todo
                        | _ -> stratify_non_existing done_ todo
                  end
       
and stratify_elements global ({class_members; super; fields} as es) (done_:class_path) (todo:class_ptr) =
  match DQ.front todo with
  | None -> done_
  | Some(`Field x, xs) when StrMap.mem x fields -> stratify global (StrMap.find x fields) (DQ.snoc done_ (`Field x)) xs 
  | Some(`ClassMember x, xs) when StrMap.mem x class_members -> stratify global (StrMap.find x class_members) (DQ.snoc done_ (`ClassMember x)) xs 
  | Some(`SuperClass i, xs) when IntMap.mem i super -> stratify global (IntMap.find i super) (DQ.snoc done_ (`SuperClass i)) xs
								
  | Some (`Protected, xs) -> raise IllegalPathElement
				   
  | Some(`Any x, xs) -> begin match get_class_element_in global DQ.empty es x DQ.empty with
                                `Found {found_value;found_path} -> begin match DQ.front found_path with
                                                                           None -> raise (Failure "internal error, succeeded lookup returned empty path") 
                                                                         | Some (y, ys) -> stratify global found_value (DQ.snoc done_ y) xs
                                                                   end
                              | _ -> raise (Stratification (done_, x))
                        end
  | Some _ -> stratify_non_existing done_ todo
				    
let stratify_ptr ptr =
  Report.do_ ;
  o <-- output ;
  try return (stratify_elements o o DQ.empty ptr) with
  | Stratification (found, not_found) ->
     Report.do_ ;
     log{level=Error;where=none;what=Printf.sprintf "Stratification error: No element %s in %s" not_found (show_class_path found)};fail

            
let rec find_lexical global previous path ctxt x current =
  match DQ.front ctxt with
    None -> begin
      let r = get_class_element global path current (DQ.singleton x) in
      match r with
        (`Found _ | `Recursion _) as f -> f                                                                                                 
      | _ -> previous
    end
  | Some(y, p) ->
     let previous' = 
       match get_class_element global path current (DQ.singleton x) with
        (`Found _ | `Recursion _) as f -> f                                                                                                 
       | _ -> previous
     in
     match get_class_element global path current (DQ.singleton y) with
       `Found {found_value;found_path} ->       
       find_lexical global previous' found_path p x found_value
     | `Recursion _ -> raise NonLeafRecursion
     | _ -> previous'
                                                                                                                
let rec norm_recursive {rec_term; search_state} = let name = (DQ.append (Name.of_ptr search_state.found) search_state.not_found) in
                                                  let lhs = rec_term.rec_lhs in
                                                  (* BatLog.logf "Recursively unfolding %s\n" (show_class_term rec_term.rec_rhs) ; *)
                                                  Report.do_ ;                                                  
                                                  n <-- norm lhs rec_term.rec_rhs ;
                                                  o <-- output ;
                                                  value <-- begin
                                                  match get_class_element o search_state.found n search_state.not_found with
                                                    `Found {found_value = Replaceable v} -> return (GlobalReference name)
                                                  | `Found {found_value} -> return found_value
                                                  | `NothingFound | `PrefixFound _ as result -> fail_unresolved {searching=name; result}
                                                  | `Recursion r -> norm_recursive r
                                                  end ;
                                                  set_output (update lhs value o) ;
                                                  return value
                                                  
and norm lhs =
                                                              
  let open Normalized in
  function
    Empty {class_sort; class_name} -> (if DQ.is_empty class_name then BatLog.logf "Empty class name for %s!\n" (show_class_path lhs) else ()) ;
  
                                      return (Class {empty_object_struct with object_sort = class_sort ; source_name = class_name})
  | Delay rec_rhs -> return (Recursive {rec_lhs=lhs;rec_rhs})

  | Close ->
     let name = Name.of_ptr lhs in
     Report.do_ ; o <-- output ; begin match lookup o name with
                                         `Found {found_value} -> return found_value
                                       | `Recursion _ -> BatLog.logf "Internal error. Trying to close a recursive element.\n"; fail
                                       | `NothingFound | `PrefixFound _ as result ->  BatLog.logf "Could not find closed scope\n"; fail_unresolved {searching=name; result}
                                 end
				   
  | RedeclareExtends -> begin match DQ.rear lhs with
                                Some(parent, `SuperClass _) -> begin match DQ.rear parent with
                                                                       Some(enclosing, `ClassMember id) -> Report.do_ ; o <-- output ;
                                                                                                           let name = (Name.of_ptr enclosing) in
                                                                                                           begin match lookup o name with
                                                                                                                 | `Found {found_value=Class os} ->
                                                                                                                    begin
                                                                                                                      BatLog.logf "Enclosing class source name: %s\n" (Name.show os.source_name) ;
                                                                                                                      let base_only = Class {os with public = {empty_elements with super = os.public.super};
                                                                                                                                                     protected = {empty_elements with super = os.protected.super}} in

                                                                                                                      match get_class_element o enclosing base_only (DQ.singleton id) with
                                                                                                                       
                                                                                                                        `Found {found_value;found_path} -> BatLog.logf "Found redeclare-base (%s): \n%s\n" id (show_class_value found_value); return found_value
                                                                                                                                                      
                                                                                                                      | `Recursion _ -> Report.do_ ;
                                                                                                                                        log{where=none;level=Error;what="Trying to extend from recursive element."};
                                                                                                                                        fail

                                                                                                                      | `NothingFound | `PrefixFound _ as result ->
                                                                                                                                         Report.do_ ;
                                                                                                                                         log{where=none;level=Error;
                                                                                                                                             what=Printf.sprintf "Could not find redeclared base class %s\n" id};
                                                                                                                                         fail_unresolved {searching=name; result}
                                                                                                                    end
                                                                                                                 | `NothingFound | `PrefixFound _ as result ->  BatLog.logf "Could not find parent of redeclared base class %s\n" id; fail_unresolved {searching=name; result}     
                                                                                                                 | _ -> BatLog.logf "Internal error. Parent of redeclare-extends is not a class.\n"; fail
                                                                                                           end
                                                                     | _ ->  BatLog.logf "Illegal redeclare extends\n"; fail
                                                               end
                              | _ -> BatLog.logf "Illegal redeclare extends\n"; fail
                        end

  | RootReference n -> return (GlobalReference (Name.of_list (lunloc n)))

  | KnownPtr p -> Report.do_ ;
		  path <-- stratify_ptr p ;
		  return (GlobalReference (Name.of_ptr path))
			      
  | Reference n ->
     let ctxt = Name.scope_of_ptr lhs in
     let name = Name.of_list (lunloc n) in
     let previous = `NothingFound in
     begin match DQ.front name with
             Some(x, xs) ->
             Report.do_ ; o <-- output ;
             begin match find_lexical o previous DQ.empty ctxt x (Class {empty_object_struct with public = o}) with
                   | `Recursion r -> norm_recursive {r with search_state = {r.search_state with not_found = xs}}
                   | `Found {found_value = Replaceable v ; found_path} -> return (DynamicReference (DQ.append (Name.of_ptr found_path) xs))
                   | `Found {found_value;found_path} -> begin match get_class_element o found_path found_value xs with
                                                              | `Recursion r -> norm_recursive r
                                                              | `Found {found_value = Replaceable v} -> return (DynamicReference (DQ.append (Name.of_ptr found_path) xs))
                                                              | `Found {found_value} -> return found_value
                                                              | `NothingFound | `PrefixFound _ as result -> BatLog.logf "Could not find suffix\n"; fail_unresolved {searching=name; result}
                                                        end
                   | `NothingFound | `PrefixFound _ as result ->  BatLog.logf "Could not find prefix %s in %s\n" x (Name.show ctxt) ; fail_unresolved {searching=name; result}
             end
           | None -> Report.do_; log{level=Error; where=none; what=Printf.sprintf "Empty name when evaluating %s. Most likely an internal bug." (show_class_path lhs)} ; fail
     end

  | Constr {constr=CRepl; arg} -> Report.do_ ;
                                  argv <-- norm lhs arg ;
                                  return (Replaceable argv) 
                                   
  | Constr {constr; arg} -> Report.do_ ;
                            argv <-- norm lhs arg ;
                            begin match argv with
                                    Replaceable arg -> return (Replaceable (Constr {arg;constr=norm_constr constr})) 
                                  | arg -> return (Constr {arg; constr = norm_constr constr})
                            end

  | PInt -> return Int
  | PBool -> return Bool
  | PReal -> return Real
  | PString -> return String
  | PExternalObject -> return ProtoExternalObject
  | PEnumeration ids -> return (Enumeration ids)

exception Check
                               
let rec check = function
    Class os -> if os.source_name = empty_object_struct.source_name then raise Check else
                  begin
                    el_check os.public ;
                    el_check os.protected
                  end
  | Constr {arg} -> check arg
  | _ -> ()               

and el_check {class_members} = StrMap.iter (fun k v -> check v) class_members
           
let rec norm_prog i p =
    Report.do_ ;
    o <-- output;
    if i >= Array.length p then return o
    else
      let {lhs;rhs} = p.(i) in
      Report.do_ ;
      lhs <-- stratify_ptr lhs ;
      let () = BatLog.logf "[%d / %d] %s\n" i (Array.length p) (show_class_stmt p.(i)) in
      norm <-- norm lhs rhs;
      let o' = update lhs (norm_cv norm) o in
      set_output (o') ;
      norm_prog (i+1) p

open ClassDeps

                                                   
open FileSystem


let link_unit linkage {ClassTrans.class_code} = linkage @ class_code

let rec link_package linkage {sub_packages; external_units; package_unit} =
  List.fold_left link_package (List.fold_left link_unit (link_unit linkage package_unit) external_units) sub_packages

let link_root {root_units; root_packages} =
  List.fold_left link_package (List.fold_left link_unit [] root_units) root_packages
                 
type open_term = { open_lhs : class_path ;
                   open_rhs : rec_term }


let rec resolve_recursive {rec_term; search_state} = let name = (DQ.append (Name.of_ptr search_state.found) search_state.not_found) in
                                                     let lhs = rec_term.rec_lhs in
                                                     (*BatLog.logf "Recursively unfolding %s\n" (show_class_term rec_term.rec_rhs) ;*)
                                                     Report.do_ ;                                                  
                                                     n <-- norm lhs rec_term.rec_rhs ;
                                                     o <-- output ;                                                       
                                                     match get_class_element o search_state.found n search_state.not_found with
                                                     | `Found {found_path} -> return found_path
                                                     | `NothingFound | `PrefixFound _ as result -> fail_unresolved {searching=name; result}
                                                     | `Recursion r -> resolve_recursive r

                               
and resolve lhs n =
     let ctxt = Name.scope_of_ptr lhs in
     let name = Name.of_list (lunloc n) in
     let previous = `NothingFound in
     begin match DQ.front name with
             Some(x, xs) ->
             Report.do_ ; o <-- output ;
             begin match find_lexical o previous DQ.empty ctxt x (Class {empty_object_struct with public = o}) with
                   | `Recursion r -> resolve_recursive {r with search_state = {r.search_state with not_found = xs}}
                   | `Found {found_value;found_path} -> begin match get_class_element o found_path found_value xs with
                                                              | `Recursion r -> resolve_recursive r
                                                              | `Found {found_path} -> return found_path
                                                              | `NothingFound | `PrefixFound _ as result -> BatLog.logf "Could not find suffix\n"; fail_unresolved {searching=name; result}
                                                        end
                   | `NothingFound | `PrefixFound _ as result ->  BatLog.logf "Could not find prefix\n"; fail_unresolved {searching=name; result}
             end
           | None -> Report.do_; log{level=Error; where=none; what=Printf.sprintf "Empty name when evaluating %s. Most likely an internal bug." (show_class_ptr lhs)} ; fail
     end

let rec close_term lhs = function
  | RedeclareExtends | Empty _ | Delay _ | Close -> Report.do_ ; Report.log {what=Printf.sprintf "Error closing %s. Cannot close artificial class-statements." (show_class_path lhs);level=Error;where=none}; fail


  | RootReference n -> return (GlobalReference (Name.of_list (lunloc n)))
  | KnownPtr p ->
     Report.do_ ;
     path <-- stratify_ptr p ;		  
     return (GlobalReference (Name.of_ptr path))

  | Reference n -> Report.do_ ; p <--resolve (lhs :> class_ptr) n ; return (GlobalReference (Name.of_ptr p))

  | Constr {constr=CRepl; arg} -> Report.do_ ;
                                  argv <-- close_term lhs arg ;
                                  return (Replaceable argv) 
                                   
  | Constr {constr; arg} -> Report.do_ ;
                            argv <-- close_term lhs arg ;
                            begin match argv with
                                    Replaceable arg -> return (Replaceable (Constr {arg;constr=norm_constr constr})) 
                                  | arg -> return (Constr {arg; constr = norm_constr constr})
                            end

  | PInt -> return Int
  | PBool -> return Bool
  | PReal -> return Real
  | PString -> return String
  | PExternalObject -> return ProtoExternalObject
  | PEnumeration ids -> return (Enumeration ids) 

let rec collect_recursive_terms p rts = function
    Class os -> let rts' =
                  elements_collect_recursive_terms p rts os.public in
                elements_collect_recursive_terms (DQ.snoc p `Protected) rts' os.protected

  | Constr {arg} -> collect_recursive_terms p rts arg
  | Replaceable v -> collect_recursive_terms p rts v
  | Recursive open_rhs -> {open_lhs = p; open_rhs}::rts
  | v -> rts

and elements_collect_recursive_terms p rts {class_members; fields;} =
  let rts' = StrMap.fold (fun k v rts -> collect_recursive_terms (DQ.snoc p (`ClassMember k)) rts v) class_members rts in
  StrMap.fold (fun k v rts -> collect_recursive_terms (DQ.snoc p (`Field k)) rts v) fields rts'               
                                  
let rec close_terms i p =
    Report.do_ ;
    o <-- output;
    if i >= Array.length p then return o
    else
      let {open_lhs;open_rhs} = p.(i) in
      Report.do_ ;
      let () = BatLog.logf "Close [%d / %d] %s := %s\n" i (Array.length p) (show_class_path open_lhs) (show_class_term open_rhs.rec_rhs) in      
      closed <-- close_term open_rhs.rec_lhs open_rhs.rec_rhs;
      set_output (update open_lhs closed o) ;
      close_terms (i+1) p


let norm_pkg_root root =
  let linkage = link_root root in
  let cc = preprocess linkage in
  Report.do_ ;
  o <-- norm_prog 0 cc ;
  let c = compress_elements o in
  let ct = Array.of_list (elements_collect_recursive_terms DQ.empty [] c) in
  let () = BatLog.logf "Closing %d possibly recursive terms.\n" (Array.length ct) in
  o <-- close_terms 0 ct ;
  let () = BatLog.logf "Done.\n%!" in
  return o
   		      	    
type decompression = {
    parent_class : class_path ;
    superclass_nr : int;
    superclass_name : Name.t ;
  }
              
let rec decompressions p dcs = function
    Class os -> let dcs' = elements_decompressions p dcs os.public in
                elements_decompressions (DQ.snoc p `Protected) dcs' os.protected
  | _ -> dcs
					   
and superclass_to_decompress parent_class superclass_nr dcs = function
    GlobalReference superclass_name -> {parent_class; superclass_nr ; superclass_name}::dcs
  | Constr {arg} -> superclass_to_decompress parent_class superclass_nr dcs arg
  | _ -> dcs
           
and elements_decompressions p dcs es =
  let dcs' = IntMap.fold (fun k v dcs -> superclass_to_decompress p k dcs v) es.super dcs in
  StrMap.fold (fun k v dcs -> decompressions (DQ.snoc p (`ClassMember k)) dcs v) es.class_members dcs'
                            
let rec do_decompression i dcs =
  if i >= Array.length dcs then (Report.do_ ; log{where=none;level=Info;what="Finished Decompression"} ; output) else
    let n = dcs.(i).superclass_name in
    match DQ.front n with
    None -> Report.do_ ; log {where=none; level=Error; what="Inconsistent normal form: Empty superclass name."} ; fail
  | Some (x,xs) ->
     BatLog.logf "[%d/%d] Superclass %d of %s = %s\n" i (Array.length dcs) dcs.(i).superclass_nr (show_class_path dcs.(i).parent_class) (Name.show n);
     Report.do_ ;
     o <-- output ;
     match get_class_element_in o DQ.empty o x xs with
       `Recursion _ -> Report.do_ ; log {where=none; level=Error; what="Inconsistent normal form: Recursive Entry found."} ; fail

     | `Found {found_value; found_path} ->
        Report.do_ ;
        set_output (update (DQ.snoc dcs.(i).parent_class (`SuperClass dcs.(i).superclass_nr)) found_value o) ;
        do_decompression (i+1) dcs 

     | `PrefixFound _ | `NothingFound as result -> fail_unresolved {searching=n; result}


module GInt = struct include Int let hash i = i end                                  
module DepGraph = Graph.Persistent.Digraph.Concrete(GInt)
module Scc = Graph.Components.Make(DepGraph)


(* record all decompressions required for a class-name *)                                  
let decompress_map dcm i {parent_class} =
  let name = Name.of_ptr parent_class in
  if NameMap.mem name dcm then    
    NameMap.add name (i::(NameMap.find name dcm)) dcm
  else
    NameMap.add name [i] dcm

let decompress_dep dcm g i {superclass_name} =
  if NameMap.mem superclass_name dcm then
    List.fold_left (fun g j -> DepGraph.add_edge g i j) g (NameMap.find superclass_name dcm)
  else
    DepGraph.add_vertex g i
                
let load_from_json js =
  let cv = elements_struct_of_yojson js in
      
  match cv with
    `Error err -> Report.do_; log{where=none; level=Error; what=err} ; fail
  | `Ok es ->
     let dcs = Array.of_list (elements_decompressions DQ.empty [] es) in
     BatLog.logf "Decompressing %d superclass-references\n" (Array.length dcs) ;
     let dcm = Array.fold_lefti decompress_map NameMap.empty dcs in
     let dcg = Array.fold_lefti (decompress_dep dcm) DepGraph.empty dcs in
     let sccs = Scc.scc_list dcg in
     
     let rec reorder_sccs = function
       | [] -> return []
       | []::sccs -> reorder_sccs sccs
       | [i]::sccs -> Report.do_ ;
                      sccs' <-- (reorder_sccs sccs) ;
                      return (dcs.(i)::sccs')

       | (i::is)::sccs -> let what = Printf.sprintf "Recursive inheritance involving %s" (Name.show dcs.(i).superclass_name) in
                          Report.do_ ;
                          log {level=Error;what;where=none}; fail
     in  

     Report.do_ ;              
     set_output es ;     
     dcs <-- reorder_sccs sccs;
     do_decompression 0 (Array.of_list dcs)
                         
           
