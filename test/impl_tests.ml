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
open Class_tests
    
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

let test_ctxt descr input path =
  descr >:: (Parser_tests.parse_test Parser.td_parser input (assert_ctxt_names (DQ.of_list path)))

let test_env descr input classname expected =
  descr >:: (Parser_tests.parse_test Parser.td_parser input (assert_env (Inter.Path.of_list classname) expected))

let test_lex_env descr input classname expected =
  descr >:: (Parser_tests.parse_test Parser.td_parser input (assert_lex_env (Inter.Path.of_list classname) expected))  

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

  let b = Class {empty_object_struct with source_path = Inter.Path.of_list [`ClassMember "A"; `ClassMember "B"] } in 
  test_lex_env "Simple lexical environment"
    "class A constant Real x = 42.; class B end B; end A"
    [`ClassMember "A"; `ClassMember "B"] 
    [ empty_env; {empty_env with public_env = StrMap.of_list ["B", EnvClass b; "x", EnvField (const Real)]} ] ; 
  
]

let suite = "Implementation Normalization" >::: test_cases

