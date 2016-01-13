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

open OUnit2
open Batteries
open Modlib
open Utils
open Syntax

open Normalized
open NormImpl
open NormLib
open Class_tests

let nl = Location.mknoloc

let assert_path lib path =
  match lookup_path lib path with
    `Found f -> f.found_value
  | `Recursion _ -> assert_failure "unexpected recursion"
  | (`PrefixFound _ | `NothingFound) as r -> assert_failure (Normalized.show_search_error r)
    
let assert_env path expected td =  
  let parsed = {within = Some []; toplevel_defs = [td] } in
  let {Report.final_messages; final_result} = Report.run (NormSig.norm_pkg_root (Trans.translate_pkg_root {root_units=[{FileSystem.scanned="testcase"; parsed}];root_packages=[]} )) {messages=[]; output=empty_elements} in
  IO.flush (!BatLog.output) ;
  let () = assert_equal ~msg:"No warnings and errors expected" ~printer:show_messages [] final_messages in (* TODO: filter warnings / errors *)
  let lib = assert_result final_result in
  let cl = assert_path lib path in
  assert_equal ~printer:show_environment expected (env lib cl)

let assert_ctxt_names path td = 
  let parsed = {within = Some []; toplevel_defs = [td] } in
  let {Report.final_messages; final_result} = Report.run (NormSig.norm_pkg_root (Trans.translate_pkg_root {root_units=[{FileSystem.scanned="testcase"; parsed}];root_packages=[]} )) {messages=[]; output=empty_elements} in
  IO.flush (!BatLog.output) ;
  let () = assert_equal ~msg:"No warnings and errors expected" ~printer:show_messages [] final_messages in (* TODO: filter warnings / errors *)
  let lib = assert_result final_result in
  let ctxt = lexical_ctxt lib path in

  let rec check_ctxt todo = function
      [] -> assert_equal ~printer:Inter.Path.show DQ.empty todo
    | ctxt::ctxts -> begin match DQ.rear todo with
        | Some(xs,x) ->
          (* Contexts are in bottom-up-order *)
          assert_equal ~cmp:Inter.Path.equal ~printer:Inter.Path.show ctxt.source_path todo ;
          check_ctxt xs ctxts
        | None -> assert_failure ("End of path reached, but context non-empty: " ^ Inter.Path.show ctxt.source_path)
      end

  in check_ctxt path ctxt.ctxt_classes

let assert_lex_env path expected td =  
  let parsed = {within = Some []; toplevel_defs = [td] } in
  let {Report.final_messages; final_result} = Report.run (NormSig.norm_pkg_root (Trans.translate_pkg_root {root_units=[{FileSystem.scanned="testcase"; parsed}];root_packages=[]} )) {messages=[]; output=empty_elements} in
  IO.flush (!BatLog.output) ;
  let () = assert_equal ~msg:"No warnings and errors expected" ~printer:show_messages [] final_messages in (* TODO: filter warnings / errors *)
  let lib = assert_result final_result in
  assert_equal ~cmp:equal_lexical_env ~printer:show_lexical_env expected (lexical_env lib path)

let protected = false
let public = true

let assert_fld vis fld pred = function
  | Class {public} when vis && StrMap.mem fld public.fields -> pred (StrMap.find fld public.fields)
  | Class {protected} when (not vis) && StrMap.mem fld protected.fields -> pred (StrMap.find fld protected.fields)
  | cv -> assert_failure ("No field: '"^fld^"' in: " ^ (show_class_value cv)) 

let field = assert_fld

let assert_cm vis cm pred = function
  | Class {public} when vis && StrMap.mem cm public.class_members -> pred (StrMap.find cm public.class_members)
  | Class {protected} when (not vis) && StrMap.mem cm protected.class_members -> pred (StrMap.find cm protected.class_members)
  | cv -> assert_failure ("No class: '"^cm^"' in: " ^ (show_class_value cv)) 
  
let class_member = assert_cm

let assert_norm path pred td =  
  let parsed = {within = Some []; toplevel_defs = [td] } in

  let {Report.final_messages; final_result} =
    Report.run (NormLib.norm_pkg_root (Trans.translate_pkg_root {root_units=[{FileSystem.scanned="testcase"; parsed}];root_packages=[]} )) {messages=[]; output=empty_elements} in
  IO.flush (!BatLog.output) ;
  assert_equal ~msg:"No warnings and errors expected" ~printer:show_messages [] final_messages ; (* TODO: filter warnings / errors *)

  let impl = (assert_result final_result).implementation in
  let cv = assert_path impl path in
  pred cv

let show_option f = function None -> "None" | Some x -> "(Some " ^ (f x) ^ ")"

let show_list f l =
  let o = IO.output_string () in
  (List.print (fun o x -> IO.write_string o (f x))) o l ;
  IO.close_out o

let equal_option f x = function None -> x = None | Some y -> begin match x with Some x -> f x y | _ -> false end 

let equal_list f as_ bs = try List.fold_left2 (fun a b c -> a && (f b c)) true as_ bs with _ -> false

let has_equation eq = function
    Class {behavior} -> assert_equal ~printer:(show_list show_equation) ~cmp:(equal_list Syntax.equal_equation) [eq] (List.map Parser_tests.prep_eq behavior.equations)
  | cv -> assert_failure ("Expected a class. Got: " ^ (show_class_value cv))

let has_binding exp {field_binding} =
    assert_equal ~printer:(show_option show_exp) ~cmp:(equal_option Syntax.equal_exp) (Some exp) (Option.map Parser_tests.prep_expr field_binding)

let is_modification_kind k m =
  assert_equal ~printer:show_component_kind k m.mod_kind

let is_modified_to exp m =
  assert_equal ~printer:show_field_modification_desc (Modify exp) m.mod_desc

let (&&&) p1 p2 e = (p1 e) ; (p2 e)

let assert_modification name pred mods =
  if StrMap.mem name mods then
    pred (StrMap.find name mods)
  else
    assert_failure ("No modification to '" ^ name ^ "'")  

let has_modification fld pred {field_mod} =
  assert_modification fld pred field_mod
    
let has_class_modification fld pred {class_mod} =
  assert_modification fld pred class_mod

let is_nested p m = match m.mod_desc with Nested m -> p m
                                        | Modify e -> assert_failure ("Expected a nested modification, got binding = %s" ^ (show_exp e))

let modified_element = assert_modification 

let test_ctxt descr input path =
  descr >:: (Parser_tests.parse_test Parser.td_parser input (assert_ctxt_names (DQ.of_list path)))

let test_env descr input classname expected =
  descr >:: (Parser_tests.parse_test Parser.td_parser input (assert_env (Inter.Path.of_list classname) expected))

let test_lex_env descr input classname expected =
  descr >:: (Parser_tests.parse_test Parser.td_parser input (assert_lex_env (Inter.Path.of_list classname) expected))  

let test_norm descr input classname pred =
  descr >:: (Parser_tests.parse_test Parser.td_parser input (assert_norm (Inter.Path.of_list classname) pred))

open Syntax_fragments

let known_component kind x = {kind;component={ident=nl x; subscripts=[]}}

let cclass = known_component CK_Class

let cattr = known_component CK_BuiltinAttr

let cconstfld = known_component CK_Constant 

let cfld = known_component CK_Continuous

let cbuiltinfun = known_component CK_BuiltinFunction

let cbuiltinclass = known_component CK_BuiltinClass

let cr x = ComponentReference x

let knownref cks = KnownRef (DQ.of_list cks)
                  
let test_cases = [
  test_env "Empty class" "class A end A" [`ClassMember "A"] NormImpl.empty_env ;

  test_env "Constant" "class A constant Real x = 42. ; end A" [`ClassMember "A"]
    {public_env=StrMap.of_list [("x", EnvField (const Real))]; protected_env=StrMap.empty} ;

  test_env "Protected Constant" "class A protected constant Real x = 42. ; end A" [`ClassMember "A"]
    {public_env=StrMap.empty; protected_env=StrMap.of_list [("x", EnvField (const Real))]} ;

  test_env "Type declaration" "class A type X = constant Real; end A" [`ClassMember "A"]
    {public_env=StrMap.of_list [("X", EnvClass (const (type_ Real)))]; protected_env=StrMap.empty} ;

  test_env "Inherited type declaration"
    "class A class B type X = constant Real; end B; class C extends B; end C; end A"
    [`ClassMember "A"; `ClassMember "C"]
    {public_env=StrMap.of_list [("X", EnvClass (const (type_ Real)))]; protected_env=StrMap.empty} ;

  test_ctxt "Simple context"
    "class A class B end B; end A"
    [`ClassMember "A"; `ClassMember "B"] ;

  test_ctxt "Simple context"
    "class A class B class C end C; end B; end A"
    [`ClassMember "A"; `ClassMember "B"; `ClassMember "C"] ;

  (
  let b = Class {empty_object_struct with source_path = Inter.Path.of_list [`ClassMember "A"; `ClassMember "B"] } in 
  test_lex_env "Simple lexical environment"
    "class A constant Real x = 42.; class B end B; end A"
    [`ClassMember "A"; `ClassMember "B"] 
    [ empty_env; {empty_env with public_env = StrMap.of_list ["B", EnvClass b; "x", EnvField (const Real)]} ] ) ; 

  test_norm "Normalize Simple Binding"
    "class A constant Real x = 42.; end A"
    [`ClassMember "A"] (field public "x" (has_binding (Real 42.))) ;

  test_norm "Normalize Simple Protected Binding"
    "class A protected constant Real x = 42.; end A"
    [`ClassMember "A"] (field protected "x" (has_binding (Real 42.))) ;

  test_norm "Normalize Binding to Builtin Attributes"
    "class A constant Real x = y.start; Real y; end A"
    [`ClassMember "A"] (field public "x" (has_binding (cr (knownref [cclass "A"; cfld "y"; cattr "start"])))) ;  

  test_norm "Normalize Builtin 'size'"
    "class A constant Integer x = size(y); Real y; end A"
    [`ClassMember "A"] (field public "x" (has_binding (app {fun_= knownref [cbuiltinfun "size"] ;
                                                            args=[cr (knownref [cclass "A"; cfld "y"])];
                                                            named_args=[]}))) ;

  test_norm "Normalize Builtin 'stateSelect'"
    "class A Real y(stateSelect=StateSelect.never); end A"
    [`ClassMember "A"] (field public "y" (has_binding (cr (knownref [cbuiltinclass "StateSelect" ; cattr "never"] )))) ;

  test_norm "Normalize Builtin 'String'"
    "class A constant Integer x = String(1); end A"
    [`ClassMember "A"] (field public "x" (has_binding (app {fun_= knownref [cbuiltinclass "String"] ;
                                                            args=[int 1];
                                                            named_args=[]}))) ;
  
  test_norm "Normalize Simple Modification"
    "class A constant Real x(start = 42.); end A"
    [`ClassMember "A"] (field public "x" (has_modification "start" (is_modified_to (Real 42.)))) ;  
  
  test_norm "Normalize Simple Protected Modification"
    "class A protected constant Real x(start = 42.); end A"
    [`ClassMember "A"] (field protected "x" (has_modification "start" (
        (is_modified_to (Real 42.)) &&& (is_modification_kind CK_BuiltinAttr)
      )));

  test_norm "Normalize Class Modification"
    "class A class B constant Real x = 42.; end B; class C = B(x = 21.); end A"
    [`ClassMember "A"] (class_member public "C" (has_class_modification "x" (
        (is_modification_kind CK_Constant)
        &&& 
        (is_modified_to (Real 21.)) ))) ;

  test_norm "Normalize Nested Class Modification"
    "class A class B constant Real x = 42.; end B; class C class B = .A.B(x = 21.); end C; class D = C(B(x=42.)); end A"
    [`ClassMember "A"] (class_member public "D" (has_class_modification "B" (
        (is_modification_kind CK_Class)
        &&&
        (is_nested (modified_element "x" (            
             (is_modification_kind CK_Constant) &&& (is_modified_to (Real 42.))))
          ) ))) ;
  
  test_norm "Normalize Nested Class Modification to a field"
    "class A class B constant Real x = 42.; end B; class C class B = .A.B(x = 21.); end C; class D C c(B(x=42.)); end D; end A"
    [`ClassMember "A"; `ClassMember "D"] (field public "c" (has_modification "B" (
        (is_modification_kind CK_Class)
        &&&
        (is_nested (modified_element "x" (            
             (is_modification_kind CK_Constant) &&& (is_modified_to (Real 42.))))
        ) ))) ;
  
  test_norm "Self Name Resolution Inside Binding"
    "class A class B constant Real x = x; end B; protected constant Real x = 42.; end A"
    [`ClassMember "A"; `ClassMember "B"] (field public "x" (has_binding (ComponentReference (knownref [cclass "A"; cclass "B"; cconstfld "x"]))));

  test_norm "Name Resolution Inside Binding"
    "class A constant Real y = x; constant Real x = 42.; end A"
    [`ClassMember "A"] (field public "y" (has_binding (ComponentReference (knownref [cclass "A"; cconstfld "x"])))) ;

  test_norm "Protected Name Resolution Inside Binding"
    "class A constant Real y = x; protected constant Real x = 42.; end A"
    [`ClassMember "A"] (field public "y" (has_binding (ComponentReference (knownref [cclass "A"; cconstfld "x"])))) ;

  test_norm "Inherited Name Resolution Inside Binding"
    "class A class B constant Real x = 42.; end B; class C extends B; protected constant Real y = x; end C; end A"
    [`ClassMember "A"; `ClassMember "C"]
    (field protected "y"
       (has_binding (ComponentReference (knownref [cclass "A"; cclass "C"; cconstfld "x"]))))  ;

  test_norm
    "Lookup a modified constant in a simple Modelica class using extensions" 
    "package A model C extends B(x = 21.); end C; model B constant Real x = 42.; end B; end A" 
    [`ClassMember "A"; `ClassMember "C"] (field public "x"  
    (has_binding (Real 21.))) ;   

  (
  let expected_ref = knownref [cclass "A"; cfld "x"] in 
  test_norm
    "Lookup an unknown in an equation"
    "model A Real x; equation x = 0.0; end A"
    [`ClassMember "A"] (has_equation {comment = no_comment; commented = SimpleEquation {left=ComponentReference expected_ref; right=Real 0.0}}) );
]

let suite = "Implementation Normalization" >::: test_cases

