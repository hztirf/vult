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

(** Printing of types *)

open TypesVult
open PrintBuffer

(** Add an identifier to the print buffer *)
let identifierBuff buffer id =
   printList buffer append "." id

let commentedId buffer id =
   match id with
   | Some(ids) ->
      append buffer "/*";
      identifierBuff buffer ids;
      append buffer "*/";
      newline buffer
   | _ -> ()

(** Adds to the print buffer a namedId *)
let rec namedIdBuff buffer id =
   match id with
   | SimpleId(id1,_) -> identifierBuff buffer id1
   | NamedId(["_"],id2,_) ->
      expressionBuff buffer id2
   | NamedId(id1,id2,_) ->
      identifierBuff buffer id1;
      append buffer ":";
      expressionBuff buffer id2

(** Adds to the print buffer an expression *)
and expressionBuff buffer (exp:exp) =
   match exp with
   | PId(s,type_exp,_)   ->
      identifierBuff buffer s;
      CCOpt.iter (fun a ->
            append buffer ":";
            expressionBuff buffer a;
         ) type_exp;
   | PInt(s,_)  -> append buffer (string_of_int s)
   | PReal(s,_) -> append buffer (string_of_float s)
   | PBool(true,_)  -> append buffer "true"
   | PBool(false,_) -> append buffer "false"
   | PTyped(e1,e2,_) ->
      expressionBuff buffer e1;
      append buffer ":";
      expressionBuff buffer e2;
   | PBinOp(op,e1,e2,_) ->
      append buffer "(";
      expressionBuff buffer e1;
      append buffer op;
      expressionBuff buffer e2;
      append buffer ")"
   | PUnOp(op,e,_) ->
      append buffer "(";
      append buffer op;
      expressionBuff buffer e;
      append buffer ")"
   | PCall(id,fname,args,_,_) ->
      CCOpt.iter (fun a ->
            identifierBuff buffer a;
            append buffer ":") id;
      identifierBuff buffer fname;
      append buffer "(";
      expressionListBuff buffer args;
      append buffer ")"
   | PUnit(_) -> append buffer "()"
   | PTuple(elems,_) ->
      expressionListBuff buffer elems
   | PGroup(e1,_) ->
      append buffer "(";
      expressionBuff buffer e1;
      append buffer ")"
   | PIf(cond,then_exp,else_exp,_) ->
      append buffer "if ";
      expressionBuff buffer cond;
      append buffer " then ";
      expressionBuff buffer then_exp;
      append buffer " else ";
      expressionBuff buffer else_exp
   | PSeq(name,stmts,_) ->
      commentedId buffer name;
      pseqListBuff buffer stmts;
   | PEmpty -> append buffer "Empty"

   | StmtVal(e1,Some(e2),_) ->
      append buffer "val ";
      expressionBuff buffer e1;
      append buffer "=";
      expressionBuff buffer e2;
      append buffer ";"
   | StmtVal(e1,None,_) ->
      append buffer "val ";
      expressionBuff buffer e1;
      append buffer ";"
   | StmtMem(e1,e2,e3,_) ->
      append buffer "mem ";
      expressionBuff buffer e1;
      CCOpt.iter (fun a ->
            append buffer "@";
            expressionBuff buffer a) e2;
      CCOpt.iter (fun a ->
            append buffer "=";
            expressionBuff buffer a) e3;
      append buffer ";"
   | StmtTable(id,elems,_) ->
      append buffer "table ";
      identifierBuff buffer id;
      append buffer " = [|";
      expressionListBuff buffer elems;
      append buffer "|];"
   | StmtReturn(e,_) ->
      append buffer "return ";
      expressionBuff buffer e;
      append buffer ";"
   | StmtIf(cond,true_stmt,None,_) ->
      append buffer "if(";
      expressionBuff buffer cond;
      append buffer ")";
      indent buffer;
      expressionBuff buffer true_stmt;
      outdent buffer
   | StmtIf(cond,true_stmt,Some(false_stmt),_) ->
      append buffer "if(";
      expressionBuff buffer cond;
      append buffer ")";
      indent buffer;
      expressionBuff buffer true_stmt;
      outdent buffer;
      newline buffer;
      append buffer "else";
      indent buffer;
      expressionBuff buffer false_stmt;
      outdent buffer
   | StmtFun(name,args,body,type_exp,_,_) ->
      append buffer "fun ";
      identifierBuff buffer name;
      append buffer "(";
      printList buffer namedIdBuff "," args;
      append buffer ") ";
      CCOpt.iter(fun a ->
            append buffer ":";
            expressionBuff buffer a;
            append buffer " ") type_exp;
      expressionBuff buffer body
   | StmtBind(PUnit(_),e,_) ->
      expressionBuff buffer e;
      append buffer ";"
   | StmtBind(e1,e2,_) ->
      expressionBuff buffer e1;
      append buffer "=";
      expressionBuff buffer e2;
      append buffer ";"
   | StmtBlock(name,stmts,_) ->
      commentedId buffer name;
      stmtListBuff buffer stmts;
   | StmtWhile(cond,stmts,_) ->
      append buffer "while(";
      expressionBuff buffer cond;
      append buffer ")";
      expressionBuff buffer stmts
   | StmtAliasType(id,args,alias,_) ->
      append buffer "type ";
      identifierBuff buffer id;
      begin
         match args with
         | [] -> append buffer " "
         | _  ->
            append buffer "(";
            printList buffer namedIdBuff "," args;
            append buffer ")"
      end;
      append buffer ":";
      expressionBuff buffer alias;
      append buffer ";"
   | StmtType(id,args,decl_list,_) ->
      append buffer "type ";
      identifierBuff buffer id;
      begin
         match args with
         | [] -> append buffer " "
         | _  ->
            append buffer "(";
            printList buffer namedIdBuff "," args;
            append buffer ")"
      end;
      append buffer "{";
      indent buffer;
      List.iter (valDecl buffer) decl_list;
      outdent buffer;
      append buffer "}"
   | StmtEmpty -> ()

(** Adds to the print buffer an expression list *)
and expressionListBuff buffer expl =
   printList buffer expressionBuff "," expl

(** Adds to the print buffer a statement in a block list *)
and stmtListBuff buffer (expl:exp list) =
   match expl with
   | [h] -> expressionBuff buffer h
   | _ ->
      let rec loop l =
         match l with
         | [] -> ()
         | h::t ->
            expressionBuff buffer h;
            newline buffer;
            loop t
      in
      append buffer "{";
      indent buffer;
      loop expl;
      outdent buffer;
      append buffer "}"

(** Adds to the print buffer a statement in a block list *)
and pseqListBuff buffer expl =
   let rec loop l =
      match l with
      | [] -> ()
      | h::t ->
         expressionBuff buffer h;
         newline buffer;
         loop t
   in
   append buffer "{|";
   indent buffer;
   loop expl;
   outdent buffer;
   append buffer "|}"

(** Adds a val declaration part of a type definition *)
and valDecl buffer val_decl =
   let id,e,_ = val_decl in
   append buffer "val ";
   identifierBuff buffer id;
   append buffer " : ";
   expressionBuff buffer e;
   append buffer ";";
   newline buffer

(** Converts to string a list of statememts *)
let stmtListStr e =
   let print_buffer = makePrintBuffer () in
   stmtListBuff print_buffer e;
   contents print_buffer

(** Converts to string an expression *)
let expressionStr e =
   let print_buffer = makePrintBuffer () in
   expressionBuff print_buffer e;
   contents print_buffer
