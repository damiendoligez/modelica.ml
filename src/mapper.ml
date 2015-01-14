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

(** {2 A generic Syntax mapper inspired by OCaml's Ast_mapper } *)

open Batteries
open Syntax
open Location

type 'sort map_method = mapper -> 'sort -> 'sort
                                             
and mapper = {
  map_unit_ : mapper -> unit_ -> unit_ ;
  map_within : mapper -> name option -> name option ;
  map_comment : mapper -> comment -> comment ;              
  map_annotation : mapper -> modification -> modification;
  
  map_typedef_options : mapper -> typedef_options -> typedef_options;
  map_typedef : mapper -> typedef -> typedef;

  map_composition : mapper -> composition -> composition;

  map_redeclared_typedef : mapper -> typedef -> typedef;
  map_extension : mapper -> extension -> extension ;
  
  map_def : mapper -> definition -> definition ;
  map_redeclared_def : mapper -> definition -> definition ;

  map_import : mapper -> import -> import ;
  map_import_desc : mapper -> import_desc -> import_desc ;
  map_extend : mapper -> extend -> extend;
  
  map_imports : mapper -> import list -> import list ;
  map_public : mapper -> elements -> elements ;
  map_protected : mapper -> elements -> elements ;
  map_cargo : mapper -> behavior -> behavior ;

  map_constraint_ : mapper -> constraint_ -> constraint_ ;

  map_der_spec : mapper -> der_spec -> der_spec;
  
  map_enum_literal : mapper -> enum_literal -> enum_literal ;
  
  map_algorithm : mapper -> algorithm -> algorithm ;
  map_external_def : mapper -> external_def -> external_def ;

  map_texp : mapper -> texp -> texp ;
  map_exp : mapper -> exp -> exp;

  map_idx : mapper -> idx -> idx ;
  
  map_statement_desc : mapper -> statement_desc -> statement_desc;
  map_statement : mapper -> statement -> statement;
  map_equation_desc : mapper -> equation_desc -> equation_desc;
  map_equation : mapper -> equation -> equation ;

  map_modification : mapper -> modification -> modification;
  map_type_redeclaration : mapper -> type_redeclaration -> type_redeclaration ;
  map_component_redeclaration : mapper -> component_redeclaration -> component_redeclaration ;
  map_component_modification : mapper -> component_modification -> component_modification ;
  map_component_modification_struct : mapper -> component_modification_struct -> component_modification_struct ;
  map_modification_value : mapper -> modification_value -> modification_value ;
  
  map_name : mapper -> name -> name ;
  map_named_arg : mapper -> named_arg -> named_arg ;
  map_identifier : mapper -> string -> string;
  map_comment_str : mapper -> string -> string ;
  map_location : mapper -> Location.t -> Location.t;
}  

let (&&&) l r = fun sub this x -> l (r sub) this x
                
(** Lift a sub-map function to a map function over lists *)
let map_list sub this = List.map (sub this)

let map_option sub this = function
  | None -> None
  | Some x -> Some (sub this x)
                                 
let map_commented sub this {commented; comment} = { commented = sub this commented ;
                                                    comment = this.map_comment this comment }

let map_located sub this { txt ; loc } = { txt = sub this txt ; loc = this.map_location this loc }

let map_else_conditional sub this { guard ; elsethen } =
  { guard = this.map_exp this guard ;
    elsethen = sub this elsethen }
                                           
let map_conditional sub this { condition ; then_ ; else_if ; else_ } =
  { condition = this.map_exp this condition ;
    then_ = sub this then_ ;
    else_if = map_list (map_else_conditional sub) this else_if ;
    else_ = sub this else_;
  }
  
let map_for_loop sub this {idx; body} = {idx= map_list this.map_idx this idx ;
                                         body = sub this body }
                                           
(** The identity map function. Does {b no} traversal *)
let map_id this x = x

