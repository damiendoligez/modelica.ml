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
       
(** A mapper record implements one "method" per syntactic category,
    using an open recursion style: each method takes as its first
    argument the mapper to be applied to children in the syntax
    tree. *)
type mapper = {
  unit_ : mapper -> unit_ -> unit_ ;
  within : mapper -> name option -> name option ;
  comment : mapper -> comment -> comment ;              
  annotation : mapper -> modification -> modification;
  
  typedef_options : mapper -> typedef_options -> typedef_options;
  typedef : mapper -> typedef -> typedef;

  composition : mapper -> composition -> composition;

  redeclared_typedef : mapper -> typedef -> typedef;
  extension : mapper -> extension -> extension ;
  
  def : mapper -> definition -> definition ;
  redeclared_def : mapper -> definition -> definition ;

  import : mapper -> import -> import ;
  import_desc : mapper -> import_desc -> import_desc ;
  extend : mapper -> extend -> extend;
  
  imports : mapper -> import list -> import list ;
  public : mapper -> elements -> elements ;
  protected : mapper -> elements -> elements ;
  cargo : mapper -> behavior -> behavior ;

  constraint_ : mapper -> constraint_ -> constraint_ ;

  der_spec : mapper -> der_spec -> der_spec;
  
  enum_literal : mapper -> enum_literal -> enum_literal ;
  
  algorithm : mapper -> algorithm -> algorithm ;
  external_def : mapper -> external_def -> external_def ;

  texp : mapper -> texp -> texp ;
  exp : mapper -> exp -> exp;

  idx : mapper -> idx -> idx ;
  
  statement_desc : mapper -> statement_desc -> statement_desc;
  statement : mapper -> statement -> statement;
  equation_desc : mapper -> equation_desc -> equation_desc;
  equation : mapper -> equation -> equation ;

  modification : mapper -> modification -> modification;
  type_redeclaration : mapper -> type_redeclaration -> type_redeclaration ;
  component_redeclaration : mapper -> component_redeclaration -> component_redeclaration ;
  component_modification : mapper -> component_modification -> component_modification ;
  component_modification_struct : mapper -> component_modification_struct -> component_modification_struct ;
  modification_value : mapper -> modification_value -> modification_value ;
  
  name : mapper -> name -> name ;
  named_arg : mapper -> named_arg -> named_arg ;
  identifier : mapper -> string -> string;
  comment_str : mapper -> string -> string ;
  location : mapper -> Location.t -> Location.t;
}  

(** combine two generic mappers *)
let (&&&) l r = fun sub this x -> l (r sub) this x
                
(** Lift a sub-map function to a map function over lists *)
let map_list sub this = List.map (sub this)

let map_option sub this = function
  | None -> None
  | Some x -> Some (sub this x)
                                 
let map_commented sub this {commented; comment} = { commented = sub this commented ;
                                                    comment = this.comment this comment }

let map_located sub this { txt ; loc } = { txt = sub this txt ; loc = this.location this loc }

let map_else_conditional sub this { guard ; elsethen } =
  { guard = this.exp this guard ;
    elsethen = sub this elsethen }
                                           
let map_conditional sub this { condition ; then_ ; else_if ; else_ } =
  { condition = this.exp this condition ;
    then_ = sub this then_ ;
    else_if = map_list (map_else_conditional sub) this else_if ;
    else_ = sub this else_;
  }
  
let map_for_loop sub this {idx; body} = {idx= map_list this.idx this idx ;
                                         body = sub this body }
                                           
(** The identity map function. Does {b no} traversal *)
let id this x = x
                                 
(** Map for type-definitions *)                
module TD = struct
  let map_tds sub this { td_name ; sort ; type_exp ; cns ; type_options } =
    let type_options = this.typedef_options this type_options in
    let type_exp = sub this type_exp in
    let cns = Option.map (this.constraint_ this) cns in
    { td_name ; sort ; type_exp ; cns ; type_options }

  let map_desc this = function
      Short tds -> Short (map_tds this.texp this tds)
    | Composition tds -> Composition (map_tds this.composition this tds)
    | Extension tds -> Extension (map_tds this.extension this tds)
    | Enumeration tds -> Enumeration (map_tds (map_list this.enum_literal) this tds)
    | OpenEnumeration tds -> OpenEnumeration (map_tds id this tds)       
    | DerSpec tds -> DerSpec (map_tds this.der_spec this tds)
                                                         
  let map = map_commented map_desc

end

module Unit = struct              
  let map this { within; toplevel_defs; } = { within = this.within this within ;
                                              toplevel_defs = map_list this.typedef this toplevel_defs }
end

module DerSpec = struct
  let map this { der_name ; idents } =
    { der_name = this.name this der_name ;
      idents = map_list (map_located this.identifier) this idents } 
end

module Name = struct
  let map this = map_list (map_located this.identifier) this
end

module Import_Desc = struct
  let map this = function
      NamedImport { global ; local } -> NamedImport { global = this.name this global ; local }
    | Unnamed name -> Unnamed (this.name this name)
    | UnqualifiedImport name -> UnqualifiedImport (this.name this name)

end
                
module Import = struct
  let map this = map_commented this.import_desc this
end

module Comment = struct
  let map this { annotated_elem ; annotation } = { annotated_elem = (map_option &&& map_located) this.comment_str this annotated_elem ;
                                                   annotation = map_option this.annotation this annotation }
end

module TRD = struct
  (** Map type redeclarations *)
  let map this { redecl_each ; redecl_type } =
    { redecl_each ; redecl_type = map_commented (TD.map_tds this.texp) this redecl_type }
end

module CRD = struct
  (** Map component redeclarations *)
  let map this { each ; def } =
    { each ; def = this.def this def }
end

module CMOD = struct
  let map this = (map_commented this.component_modification_struct) this
end
               
module CMOD_Struct = struct
  (** Map component modifications *)
  let map this { mod_each ; mod_final ; mod_name ;
                 mod_value ; } = {mod_each ; mod_final ;
                                  mod_name = this.name this mod_name ;                                  
                                  mod_value = map_option this.modification_value this mod_value }
end

module CMOD_Value = struct
  let map this = function
      Nested modification -> Nested (this.modification this modification)
    | Rebind exp -> Rebind (this.exp this exp)
    | NestedRebind { nested ; new_value } -> NestedRebind { nested = this.modification this nested ;
                                                            new_value = this.exp this new_value
                                                          }
end
                       
module Modification = struct
  let map this {types ; components; modifications } = { types = map_list this.type_redeclaration this types ;
                                                        components = map_list this.component_redeclaration this components ;
                                                        modifications = map_list this.component_modification this modifications }
end

module Equation_Desc = struct
  let map this = function
    | SimpleEquation { left ; right } -> SimpleEquation { left = this.exp this left ;
                                                          right = this.exp this right }
    | ForEquation loop -> ForEquation (map_for_loop (map_list this.equation) this loop)
    | IfEquation ifeq -> IfEquation (map_conditional (map_list this.equation) this ifeq)
    | WhenEquation when_eq -> WhenEquation (map_conditional (map_list this.equation) this when_eq)
    | ExpEquation exp -> ExpEquation (this.exp this exp)
end

module Equation = struct
  let map this = map_commented this.equation_desc this
end
         
module Idx = struct
  let map this { variable ; range } = { variable = map_located id this variable ;
                                        range = map_option this.exp this range  }
end

module Algorithm = struct
  let map this = map_list this.statement this 
end

module Statement = struct
  let map this = map_commented this.statement_desc this
end

module Statement_Desc = struct
  let map this = function
      Assignment { target ; source } -> Assignment { target = this.exp this target ;
                                                     source = this.exp this source }

    | Call {procedure; pargs; pnamed_args} -> Call { procedure = this.exp this procedure ;
                                                     pargs = map_list this.exp this pargs ;
                                                     pnamed_args = map_list this.named_arg this pnamed_args }
                                                   
    | IfStmt if_statement -> IfStmt (map_conditional (map_list this.statement) this if_statement) 
    | WhenStmt when_statement -> WhenStmt (map_conditional (map_list this.statement) this when_statement) 
    | Break -> Break
    | Return -> Return
    | ForStmt for_statement -> ForStmt (map_for_loop (map_list this.statement) this for_statement)
    | WhileStmt { while_ ; do_ } -> WhileStmt { while_ = this.exp this while_ ;
                                                do_ = map_list this.statement this do_ }
end


module Named_Arg = struct
  let map this { argument_name ; argument } = { argument_name = map_located this.identifier this argument_name ;
                                                argument = this.exp this argument }
end


module Exp = struct
  let map_binary this {left ; right } = {left=this.exp this left ; right = this.exp this right }
                                          
  let map this = function
    | Pow b -> Pow (map_binary this b)
    | DPow b -> DPow (map_binary this b)
    | Mul b -> Mul (map_binary this b)
    | DMul b -> DMul (map_binary this b)
    | Div b -> Div (map_binary this b)
    | DDiv b -> DDiv (map_binary this b)
    | Plus b -> Plus (map_binary this b)
    | DPlus b -> DPlus (map_binary this b)
    | Minus b -> Minus (map_binary this b)
    | DMinus b -> DMinus (map_binary this b)


    | UMinus e -> UMinus (this.exp this e)
    | UPlus e -> UPlus (this.exp this e)
    | UDPlus e -> UDPlus (this.exp this e)
    | UDMinus e -> UDMinus (this.exp this e)

    | Not e -> Not (this.exp this e)
    | And b -> And (map_binary this b)
    | Or b -> Or (map_binary this b)
    | Gt b -> Gt (map_binary this b)
    | Lt b -> Lt (map_binary this b)
    | Leq b -> Leq (map_binary this b)
    | Geq b -> Geq (map_binary this b)
    | Neq b -> Neq (map_binary this b)
    | Eq b -> Eq (map_binary this b)

    | If if_expression -> If (map_conditional this.exp this if_expression)
    | ArrayAccess {lhs; indices} -> ArrayAccess { lhs = this.exp this lhs ; indices = map_list this.exp this indices }

    | Range {start; end_; step} -> Range { start = this.exp this start ;
                                           end_ = this.exp this end_ ;
                                           step = map_option this.exp this step }

    | RootIde s -> RootIde s
    | Ide s -> Ide s
    | Proj {object_; field} -> Proj { object_ = this.exp this object_ ; field }
    | App { fun_; args; named_args} -> App { fun_ = this.exp this fun_ ;
                                             args = map_list this.exp this args ;
                                             named_args = map_list this.named_arg this named_args }

    | Compr { exp ; idxs } -> Compr { exp = this.exp this exp;
                                      idxs = map_list this.idx this idxs }
                                
    | Array es -> Array (map_list this.exp this es)
    | MArray ess -> MArray (map_list (map_list this.exp) this ess)
    | ExplicitClosure e -> ExplicitClosure (this.exp this e)                           
    | OutputExpression eos -> OutputExpression (map_list (map_option this.exp) this eos)
    | ( End | Colon | Der | Initial | Assert | Bool _ | Int _ | Real _ | String _) as e -> e


end
                     
let default_mapper = {
  unit_ = Unit.map ;
  within = id;

  typedef_options = id;
  typedef = TD.map;

  composition = id;

  redeclared_typedef = id;
  extension = id;
  
  def = map_commented id ;
  redeclared_def = id;

  import_desc = Import_Desc.map ;
  import = Import.map;
  extend = id;
  
  imports = id;
  public = id;
  protected = id;
  cargo = id;

  constraint_ = id;

  der_spec = DerSpec.map;
  
  enum_literal = id;
  
  algorithm = Algorithm.map;
  external_def = id;

  texp = id;

  comment = Comment.map;
  annotation = Modification.map;
  
  exp = Exp.map;
  statement = Statement.map;
  statement_desc = Statement_Desc.map;
  idx = Idx.map;
  
  equation_desc = Equation_Desc.map;
  equation = Equation.map;

  name = Name.map ;
  identifier = id;
  named_arg = Named_Arg.map;
  comment_str = id;
  location = id;
  
  modification = Modification.map;
  type_redeclaration = TRD.map;
  component_redeclaration = CRD.map;
  component_modification = CMOD.map;
  component_modification_struct = CMOD_Struct.map;
  modification_value = CMOD_Value.map;
};
