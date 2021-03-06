
open TypesVult
open PrintBuffer
open TypesUtil

type ident = string
type member = ident list

type ctyp =
   | TReal
   | TInt
   | TObj of ident

type op =
   | OPlus
   | OTimes
   | ODiv
   | OMinus
   | OLt
   | OGt
   | OEq
   | OGtEq
   | OLtEq
   | OUEq
   | OAnd
   | OOr
   | ORef
   | ODeRef
   | OMod
   | ONot

type ctyp_def =
   {
      name    : ident;
      members : (ctyp * ident) list;
   }

type cexp =
   | EOp     of cexp * op * cexp
   | ECall   of ident * cexp list
   | EVar    of ident list
   | EString of string
   | EReal   of float
   | EInt    of int
   | EUop    of op * cexp
   | ERef    of ident
   | EIf     of cexp * cexp * cexp
   | ENewObj

type cstmt =
   | SDecl     of ctyp * ident
   | SFunction of ctyp * ident * (ctyp * ident) list * cstmt
   | SBind     of member * cexp
   | SWhile    of cexp * cstmt
   | SReturn   of cexp
   | SBlock    of cstmt list
   | SIf       of cexp * cstmt * cstmt option
   | SStruct   of ctyp_def
   | STypeDef  of ident * ident
   | SArray    of ident * cexp list
   | SEmpty

type creal_type =
   | Fixed
   | Float
   | Double


let convertOp (op:string) : op option =
   match op with
   | "+"  -> Some(OPlus)
   | "*"  -> Some(OTimes)
   | "/"  -> Some(ODiv)
   | "-"  -> Some(OMinus)
   | "<"  -> Some(OLt)
   | ">"  -> Some(OGt)
   | "%"  -> Some(OMod)
   | "==" -> Some(OEq)
   | "!=" -> Some(OUEq)
   | "&&" -> Some(OAnd)
   | "||" -> Some(OOr)
   | "!"  -> Some(ONot)
   | "p&" -> Some(ORef)
   | "*&" -> Some(ODeRef)
   | "<=" -> Some(OLtEq)
   | ">=" -> Some(OGtEq)
   | _    ->
      (*print_endline ("convertOp: Unsupported operator "^op);*)
      None

let rec convertExp (e:exp) : cexp =
   match e with
   | PUnit(_)    -> EInt(0)
   | PBool(v,_)  -> if v then EInt(1) else EInt(0)
   | PInt(v,_)   -> EInt(v)
   | PReal(v,_)  -> EReal(v)
   | PId(id,_,_) -> EVar(id)
   | PUnOp(op,e1,_) ->
      EUop(CCOpt.get_exn (convertOp op),convertExp e1)
   | PBinOp(op,e1,e2,_) ->
      EOp(convertExp e1,CCOpt.get_exn (convertOp op),convertExp e2)
   | PCall(_,[op],[e1;e2],_,_) when CCOpt.is_some (convertOp op) ->
      EOp(convertExp e1,CCOpt.get_exn (convertOp op),convertExp e2)
   | PCall(_,[op],[e1],_,_) when CCOpt.is_some (convertOp op) ->
      EUop(CCOpt.get_exn (convertOp op),convertExp e1)
   | PCall(None,[fname],args,_,_) ->
      ECall(fname,convertExpList args)
   | PIf(cond,e1,e2,_) ->
      EIf(convertExp cond,convertExp e1,convertExp e2)
   | PGroup(e1,_) ->
      convertExp e1
   | PTuple(_,_) -> failwith "Tuples are not yet supported in expression context"
   | PSeq(_,_,_) -> failwith "Sequence expressions are not yet supported in expression context"
   | _ ->
      print_endline ("convertExp: unsupported expression\n"^(show_exp e));
      failwith "convertExp: not an expression"

and convertExpList (e:exp list) : cexp list =
   List.map convertExp e

let convertType (e:exp option) : ctyp =
   match e with
   | Some(PId(["int"],None,_))  -> TInt
   | Some(PId(["real"],None,_)) -> TReal
   | Some(PId(["bool"],None,_)) -> TInt
   | Some(PId([name],None,_))   -> TObj(name)
   | Some(_) -> failwith "convertType: unsupported type"
   | None -> TReal

let convertNamedId (name:named_id) : ctyp * ident =
   match name with
   | SimpleId([id],_) -> TReal,id
   | NamedId([id],tp,_) -> (convertType (Some(tp))),id
   | _ -> failwith "convertNamedId: invalid function argument"

let convertMember (member:val_decl) : ctyp * ident =
   match member with
   | [name],e,_ -> convertType (Some(e)),name
   | name,e,_ -> failwith ("convertMember: cannot convert member "^(identifierStr name))

let rec convertStmt (e:exp) : cstmt =
   match e with
   | StmtVal(PId([name],tp,_),None,_) -> SDecl(convertType tp,name)
   | StmtVal(_,_,_)   -> failwith "convertStmt: unsupported val declaration"
   | StmtMem(_,_,_,_) -> SEmpty
   | StmtTable([name],elems,_) ->
      SArray(name,convertExpList elems)
   | StmtWhile(cond,stmts,_) ->
      SWhile(convertExp cond,convertStmt stmts)
   | StmtReturn(v,_) -> SReturn(convertExp v)
   | StmtIf(cond,then_,Some(else_),_) ->
      SIf(convertExp cond,convertStmt then_,Some(convertStmt else_))
   | StmtIf(cond,then_,None,_) ->
      SIf(convertExp cond,convertStmt then_,None)
   | StmtFun([name],args,body,ret,_,_) ->
      let cargs = List.map convertNamedId args in
      SFunction(convertType ret,name,cargs,convertStmt body)
   | StmtBind(PId(lhs,_,_),rhs,_) ->
      SBind(lhs,convertExp rhs)
   | StmtBind(PUnit(_),rhs,_) ->
      SBind([],convertExp rhs)
   | StmtBlock(_,stmts,_) ->
      SBlock(convertStmtList stmts)
   | StmtType([name],[],members,_) ->
      SStruct({ name = name; members = List.map convertMember members })
   | StmtAliasType([name],[],PId([alias],_,_),_) ->
      STypeDef(alias,name)
   | _ ->
      print_endline ("convertStmt: unsupported statement\n"^(show_exp e));
      failwith ("convertStmt: unsupported statement ")

and convertStmtList (l:exp list) : cstmt list =
   List.map convertStmt l

type print_options =
   {
      buffer     : print_buffer;
      header     : bool;
      num_type   : creal_type;
   }

let fix_scale = 1 lsl 16 |> float_of_int

let printTyp (o:print_options) pointers t =
   match t,o.num_type with
   | TObj(id),_ when pointers  -> append o.buffer (id^"* ")
   | TObj(id),_   -> append o.buffer (id^" ")
   | TInt,Fixed -> append o.buffer "int32_t "
   | TInt,_ -> append o.buffer "int "
   | TReal,Double -> append o.buffer "double "
   | TReal,Float  -> append o.buffer "float "
   | TReal,Fixed  -> append o.buffer "int32_t "

let printOpNormal (o:print_options) op =
   match op with
   | OPlus  -> append o.buffer " + "
   | OTimes -> append o.buffer " * "
   | ODiv   -> append o.buffer " / "
   | OMinus -> append o.buffer " - "
   | OLt    -> append o.buffer " < "
   | OGt    -> append o.buffer " > "
   | OEq    -> append o.buffer " == "
   | OUEq   -> append o.buffer " != "
   | OAnd   -> append o.buffer " && "
   | OOr    -> append o.buffer " || "
   | OMod   -> append o.buffer " % "
   | OLtEq  -> append o.buffer " <= "
   | OGtEq  -> append o.buffer " >= "
   | ORef   -> append o.buffer "&"
   | ODeRef -> append o.buffer "*"
   | ONot   -> append o.buffer "!"

let funNameJs (f:string) =
   match f with
   | "sin"   -> "Math.sin"
   | "cos"   -> "Math.cos"
   | "tan"   -> "Math.tah"
   | "exp"   -> "Math.exp"
   | "floor" -> "Math.floor"
   | "min"   -> "Math.min"
   | "max"   -> "Math.max"
   | "abs"   -> "Math.abs"
   | _ -> "this."^f

let opIsFunction op =
   match op with
   | OPlus  -> true
   | OTimes -> true
   | ODiv   -> true
   | OMinus -> true
   | _ -> false

let printOpFixed (o:print_options) op =
   match op with
   | OPlus  -> append o.buffer "fix_add"
   | OTimes -> append o.buffer "fix_mul"
   | ODiv   -> append o.buffer "fix_div"
   | OMinus -> append o.buffer "fix_sub"
   | _ -> failwith "printOpFixed: unknown operator"

let printUOpFixed (o:print_options) op =
   match op with
   | OMinus -> append o.buffer "fix_minus"
   | ORef -> append o.buffer "&"
   | _ -> failwith "Invalid unary operator"

let printUOpNormal (o:print_options) op =
   match op with
   | OMinus -> append o.buffer "-"
   | ORef -> append o.buffer "&"
   | _ -> failwith "Invalid unary operator"

let rec printExp (o:print_options) (e:cexp) =
   match e,o.num_type with
   | EOp(e1,OEq,e2),_ ->
      printExp o e1;
      printOpNormal o OEq;
      printExp o e2
   | EOp(e1,op,e2),_ ->
      append o.buffer "(";
      printExp o e1;
      printOpNormal o op;
      printExp o e2;
      append o.buffer ")"
   | ECall(name,args),_ ->
      append o.buffer (funNameJs name);
      append o.buffer "(";
      printExpSep o ", " args;
      append o.buffer ")"

   | EVar(name),_ ->
      printList o.buffer (fun b a-> append b a) "." name
   | EString(s),_ ->
      append o.buffer s
   | EReal(0.0),_ | EInt(0),_->
      append o.buffer "0.0"
   | EReal(f),_ ->
      append o.buffer (string_of_float f)
   | EInt(i),_ ->
      append o.buffer (string_of_float (float_of_int i))
   | EUop(ORef,e1),_ ->
      printExp o e1;

   | EUop(op,e1),_ ->
      append o.buffer "(";
      printUOpNormal o op;
      printExp o e1;
      append o.buffer ")"

   | ERef(n),_ ->
      append o.buffer n
   | EIf(cond,e1,e2),_ ->
      append o.buffer "(";
      printExp o cond;
      append o.buffer "?";
      printExp o e1;
      append o.buffer ":";
      printExp o e2;
      append o.buffer ")"
   | ENewObj,_ -> append o.buffer "{}"
and printExpSep (o:print_options) sep el =
   match el with
   | []   -> ()
   | [h]  -> printExp o h
   | h::t -> printExp o h; append o.buffer sep; printExpSep o sep t


let printVarDecl pointers (o:print_options) ((tp,name):ctyp * ident) =
   (*printTyp o pointers tp;*)
   append o.buffer name

let rec printArgs (o:print_options) (args:(ctyp * ident) list) =
   printListSep o (printVarDecl true) (fun o -> append o.buffer ", ") args

let printMembers (o:print_options) (members:(ctyp * ident) list) =
   printListSepLast o (printVarDecl false) (fun o -> append o.buffer ";"; newline o.buffer) members

let rec printStm (o:print_options) (s:cstmt) =
   match s with
   | SDecl(tp,name) ->
      append o.buffer "var ";
      append o.buffer name;
      append o.buffer ";";
      newline o.buffer
   | SFunction(tp,name,args,body) ->
      append o.buffer "this.";
      append o.buffer name;
      append o.buffer " = function ";
      append o.buffer "(";
      printArgs o args;
      append o.buffer ")";
      printBlock o body;
      newline o.buffer;
   | SBind([],e1) ->
      printExp o e1;
      append o.buffer ";";
      newline o.buffer
   | SBind(name,e1) ->
      printList o.buffer (fun buffer a->append buffer a) "." name;
      append o.buffer " = ";
      printExp o e1;
      append o.buffer ";";
      newline o.buffer
   | SWhile(cond,body) ->
      append o.buffer "while";
      printExp o cond;
      printStm o body;
      newline o.buffer
   | SReturn(exp) ->
      append o.buffer "return ";
      printExp o exp;
      append o.buffer ";";
      newline o.buffer
   | SBlock(body) ->
      append o.buffer "{";
      indent o.buffer;
      printStmList o body;
      outdent o.buffer;
      append o.buffer "}";
      newline o.buffer
   | SIf(cond,then_e,opt_else_e) ->
      append o.buffer "if(";
      printExp o cond;
      append o.buffer ")";
      printBlock o then_e;
      if CCOpt.is_some opt_else_e then
         begin
            append o.buffer "else ";
            printBlock o (CCOpt.get SEmpty opt_else_e)
         end
   | SStruct(s)  when o.header ->
      append o.buffer "typedef struct _";
      append o.buffer s.name;
      append o.buffer " {";
      indent o.buffer;
      printMembers o s.members;
      outdent o.buffer;
      append o.buffer "} ";
      append o.buffer s.name;
      append o.buffer ";";
      newline o.buffer;
      newline o.buffer
   | SStruct(s) -> ()
   | STypeDef(alias,name) when o.header ->
      append o.buffer "typedef struct _";
      append o.buffer alias;
      append o.buffer " ";
      append o.buffer name;
      append o.buffer ";";
      newline o.buffer;
      newline o.buffer
   | STypeDef(alias,name) -> ()
   | SArray(name,elems) ->
      append o.buffer "static const ";
      printTyp o false (convertType None);
      append o.buffer name;
      append o.buffer "[] = { ";
      printExpSep o ", " elems;
      append o.buffer " };";
      newline o.buffer;
      newline o.buffer
   | SEmpty -> ()

and printBlock (o:print_options) (stmt:cstmt) =
   match stmt with
   | SBlock(_) -> printStm o stmt
   | _ ->
      append o.buffer "{";
      indent o.buffer;
      printStm o stmt;
      outdent o.buffer;
      append o.buffer "}";
      newline o.buffer

and printStmList (o:print_options) (sl:cstmt list) =
   match sl with
   | [] -> ()
   | h::t ->
      printStm o h;
      printStmList o t

and printOptStm (o:print_options) stm =
   match stm with
   | None    -> ()
   | Some(s) -> printStm o s

let printStmListStr args stms =
   let options = { buffer = makePrintBuffer (); num_type = Float; header = false } in
   printStmList options stms;
   contents options.buffer

(** Returns the corresponding default value for the type *)
let getDefaultValue (id:ident) (tp:ctyp) : cexp =
   match tp with
   | TReal       -> EReal(0.0)
   | TInt        -> EInt(0)
   | TObj(name)  -> ECall(name^"_init",[EVar(["st";id])])

(** Returns a mem declaration or a function call to initialize the member of a type *)
let generateInitialization (id:ident) (tp:ctyp) : cstmt list =
   match tp with
   | TReal | TInt ->
      [ SBind(["st";id],getDefaultValue id tp);]
   | TObj(tpname) ->
      [ SBind(["st";id],ENewObj); SBind([],getDefaultValue id tp) ]

(** Generates a function to initialize the types *)
let generateTypeInitializer (tp:cstmt) : cstmt list =
   match tp with
   | SStruct({ name = name ; members = members }) ->
      let finit_name   = name^"_init" in
      let body =
         members
         |> List.map (fun (tp,id) -> generateInitialization id tp)
         |> List.flatten
         |> fun a -> a@[SReturn(EInt(0))]
      in
      [tp;SFunction(TInt,finit_name,[TObj(name),"st"],SBlock(body))]
   | STypeDef(base,name) ->
      let finit_name   = name^"_init" in
      let body = [SBind([],ECall(base^"_init",[EVar(["st"])]));SReturn(EInt(0))] in
      [tp;SFunction(TInt,finit_name,[TObj(name),"st"],SBlock(body))]
   | _ -> [tp]

let getRealType (real:string) : creal_type =
   match real with
   | "float"  -> Float
   | "fixed"  -> Fixed
   | "double" -> Double
   | _ ->
      failwith (Printf.sprintf "Invalid real number type %s. Valid types are: fixed, float and double." real)


let generateModule (args:arguments) (stmts:exp_list) : string =
   let creal = getRealType args.real in
   let c_options = { buffer = makePrintBuffer (); num_type = creal; header = false } in
   let converted_code =
      convertStmtList stmts
      |> List.map generateTypeInitializer
      |> List.flatten
   in
   converted_code |> printStmList c_options;
   contents c_options.buffer

