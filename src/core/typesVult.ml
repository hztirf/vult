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

type identifier = string list
   [@@deriving show,eq,ord]

(** This type is used to attach more information to the function calls *)
type call_attribute =
   | SimpleBinding (* Used by Passes.bindFunctionCalls to mark the function calls that have been bound *)
   | DummtAttr
   [@@deriving show,eq,ord]

type call_attributes = call_attribute list
   [@@deriving show,eq,ord]

type fun_attribute =
   | ActiveFunction
   | JoinFunction
   [@@deriving show,eq,ord]

type fun_attributes = fun_attribute list
   [@@deriving show,eq,ord]

type type_exp =
   | TUnit      of Loc.t
   | TId        of identifier    * Loc.t
   | TTuple     of type_exp list * Loc.t
   | TComposed  of identifier    * type_exp list * Loc.t
   | TSignature of type_exp list * Loc.t
   [@@deriving show,eq,ord]

type typed_id =
   | SimpleId of identifier * Loc.t
   | TypedId  of identifier * type_exp * Loc.t
   [@@deriving show,eq,ord]

type lhs_exp =
   | LWild  of Loc.t
   | LId    of identifier   * Loc.t
   | LTuple of lhs_exp list * Loc.t
   | LTyped of lhs_exp * type_exp * Loc.t
   [@@deriving show,eq,ord]

(** Parser syntax tree *)
type exp =
   | PUnit
      of Loc.t
   | PBool
      of bool
      *  Loc.t
   | PInt
      of int
      *  Loc.t
   | PReal
      of float
      *  Loc.t
   | PId
      of identifier  (* name *)
      *  Loc.t
   | PUnOp
      of string      (* operator *)
      *  exp
      *  Loc.t
   | PBinOp
      of string      (* operator *)
      *  exp
      *  exp
      *  Loc.t
   | PCall
      of identifier option (* name/instance *)
      *  identifier        (* type/function name *)
      *  exp list          (* arguments *)
      *  call_attributes
      *  Loc.t
   | PIf
      of exp (* condition *)
      *  exp (* then *)
      *  exp (* else *)
      *  Loc.t
   | PGroup
      of exp
      *  Loc.t
   | PTuple
      of exp list
      *  Loc.t
   | PSeq
      of identifier option (* Scope name *)
      *  stmt list
      *  Loc.t
   | PEmpty
   [@@deriving show,eq,ord]
and stmt =
   | StmtVal
      of lhs_exp     (* names/lhs *)
      *  exp option  (* rhs *)
      *  Loc.t
   | StmtMem
      of lhs_exp     (* names/lhs *)
      *  exp option  (* initial value *)
      *  exp option  (* rhs *)
      *  Loc.t
   | StmtTable
      of identifier  (* name *)
      *  exp list    (* data *)
      *  Loc.t
   | StmtWhile
      of exp         (* condition*)
      *  stmt        (* statements *)
      *  Loc.t
   | StmtReturn
      of exp
      *  Loc.t
   | StmtIf
      of exp         (* condition *)
      *  stmt        (* then *)
      *  stmt option (* else *)
      *  Loc.t
   | StmtFun
      of identifier       (* name *)
      *  typed_id list    (* arguments *)
      *  stmt             (* body *)
      *  type_exp option  (* return type *)
      *  fun_attributes   (* attributes *)
      *  Loc.t
   | StmtBind
      of lhs_exp     (* lhs *)
      *  exp         (* rhs *)
      *  Loc.t
   | StmtBlock
      of identifier option (* scope name *)
      *  stmt list
      *  Loc.t
   | StmtType
      of identifier           (* name *)
      *  typed_id list        (* arguments *)
      *  val_decl list        (* members *)
      *  Loc.t
   | StmtAliasType
      of identifier           (* name *)
      *  typed_id list        (* arguments *)
      *  type_exp             (* alias type *)
      *  Loc.t
   | StmtEmpty
   [@@deriving show,eq,ord]

and val_decl =
   identifier  (* name *)
   * type_exp  (* type *)
   * Loc.t
   [@@deriving show,eq,ord]

type exp_list = exp list
   [@@deriving show,eq,ord]

type scope_kind =
   | FuncScope
   | LocalScope

type parser_results =
   {
      presult : (stmt list,Error.t list) CCError.t;
      file    : string;
      lines   : string array;
   }

type interpreter_results =
   {
      iresult : (string,Error.t list) CCError.t;
      lines   : string array;
   }

(** Stores the options passed to the command line *)
type arguments =
   {
      mutable files  : string list;
      mutable dparse : bool;
      mutable rundyn : bool;
      mutable debug  : bool;
      mutable ccode  : bool;
      mutable jscode : bool;
      mutable run_check  : bool;
      mutable output : string;
      mutable real   : string;
   }

let default_arguments =
   {
      files = ["live.vult"];
      dparse = false;
      rundyn = false;
      debug = false;
      ccode = false;
      jscode = true;
      run_check = false;
      output = "live";
      real = "float";
   }