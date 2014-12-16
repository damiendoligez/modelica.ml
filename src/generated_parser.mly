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

%token GT LT NEQ GEQ LEQ EQ EQEQ LPAREN RPAREN LBRACKET RBRACKET LBRACE RBRACE SEMICOLON COMMA DOT

%token <int> INT
%token <float> FLOAT
%token <string> IDENT
%token <string> STRING
%token DOTPOWER POWER PLUS MINUS TIMES DIV DOTPLUS DOTMINUS DOTTIMES DOTDIV 
%token EOF

%token ALGORITHM DISCRETE FALSE LOOP PURE AND EACH FINAL MODEL RECORD ANNOTATION ELSE
%token FLOW NOT REDECLARE ASSERT ELSEIF FOR OPERATOR REPLACEABLE BLOCK ELSEWHEN FUNCTION OR RETURN
%token BREAK ENCAPSULATED IF OUTER STREAM CLASS END IMPORT OUTPUT THEN CONNECT ENUMERATION IMPURE
%token PACKAGE TRUE CONNECTOR EQUATION IN PARAMETER TYPE CONSTANT EXPANDABLE INITIAL PARTIAL WHEN
%token CONSTRAINEDBY EXTENDS INNER PROTECTED WHILE DER EXTERNAL INPUT PUBLIC WITHIN
                                   
%right lowest /* lowest precedence */
%nonassoc IDENT INT FLOAT STRING LPAREN RPAREN RBRACKET LBRACE RBRACE 
%left COMMA 
%left SEMICOLON 
%left GT LT NEQ GEQ LEQ EQ 
%left PLUS MINUS DOTPLUS DOTMINUS     /* medium precedence */
%left TIMES DIV DOTTIMES DOTDIV
%left POWER DOTPOWER
%nonassoc UMINUS        
%nonassoc below_app
%left app_prec     
%left DOT LBRACKET /* highest precedence */

%{
   open Syntax
%}


%start <Syntax.exp> modelica_expr

%%

modelica_expr: e = expr EOF { e }

expr:
  | TRUE { Bool(true) }
  | FALSE { Bool(false) }
  | i = INT 
        { Int (i) }
  | f = FLOAT
        { Real (f) }
  | x = IDENT 
        { Ide(x) }
  | LPAREN e = expr RPAREN
        { e }

  | left = expr PLUS right = expr
       { Plus ( {left ; right} ) } 
  | left = expr MINUS right = expr
       { Minus ( {left ; right} ) } 
  | left = expr TIMES right = expr
       { Mul ( {left ; right} ) } 
  | left = expr DIV right = expr
       { Div ( {left ; right} ) } 

  | left = expr DOTPLUS right = expr
       { DPlus ( {left ; right} ) } 
  | left = expr DOTMINUS right = expr
       { DMinus ( {left ; right} ) } 
  | left = expr DOTTIMES right = expr
       { DMul ( {left ; right} ) } 
  | left = expr DOTDIV right = expr
       { DDiv ( {left ; right} ) } 





                        
                        

                        
                                               
                                               
                                               

                                               

