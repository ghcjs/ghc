{-
-----------------------------------------------------------------------------
$Id: Parser.y,v 1.67 2001/06/11 12:21:17 simonpj Exp $

Haskell grammar.

Author(s): Simon Marlow, Sven Panne 1997, 1998, 1999
-----------------------------------------------------------------------------
-}

{
module Parser ( parseModule, parseStmt ) where

import HsSyn
import HsTypes		( mkHsTupCon )

import RdrHsSyn
import Lex
import ParseUtil
import RdrName
import PrelNames	( mAIN_Name, unitTyCon_RDR, funTyCon_RDR, listTyCon_RDR,
			  tupleTyCon_RDR, unitCon_RDR, nilCon_RDR, tupleCon_RDR
			)
import ForeignCall	( Safety(..), CExportSpec(..), CCallSpec(..), 
			  CCallConv(..), CCallTarget(..), defaultCCallConv,
			  DNCallSpec(..) )
import OccName		( UserFS, varName, tcName, dataName, tcClsName, tvName )
import SrcLoc		( SrcLoc )
import Module
import Demand		( StrictnessMark(..) )
import CmdLineOpts	( opt_SccProfilingOn )
import BasicTypes	( Boxity(..), Fixity(..), FixityDirection(..), NewOrData(..) )
import Panic

import GlaExts
import CStrings		( CLabelString )
import FastString	( tailFS )
import Maybes		( orElse )
import Outputable

#include "HsVersions.h"
}

{-
-----------------------------------------------------------------------------
Conflicts: 14 shift/reduce
	(note: it's currently 21 -- JRL, 31/1/2000)

8 for abiguity in 'if x then y else z + 1'
	(shift parses as 'if x then y else (z + 1)', as per longest-parse rule)
1 for ambiguity in 'if x then y else z :: T'
	(shift parses as 'if x then y else (z :: T)', as per longest-parse rule)
3 for ambiguity in 'case x of y :: a -> b'
	(don't know whether to reduce 'a' as a btype or shift the '->'.
	 conclusion:  bogus expression anyway, doesn't matter)

1 for ambiguity in '{-# RULES "name" forall = ... #-}' 
	since 'forall' is a valid variable name, we don't know whether
	to treat a forall on the input as the beginning of a quantifier
	or the beginning of the rule itself.  Resolving to shift means
	it's always treated as a quantifier, hence the above is disallowed.
	This saves explicitly defining a grammar for the rule lhs that
	doesn't include 'forall'.

1 for ambiguity in 'x @ Rec{..}'.  
	Only sensible parse is 'x @ (Rec{..})', which is what resolving
	to shift gives us.

-----------------------------------------------------------------------------
-}

%token
 '_'            { ITunderscore }		-- Haskell keywords
 'as' 		{ ITas }
 'case' 	{ ITcase }  	
 'class' 	{ ITclass } 
 'data' 	{ ITdata } 
 'default' 	{ ITdefault }
 'deriving' 	{ ITderiving }
 'do' 		{ ITdo }
 'else' 	{ ITelse }
 'hiding' 	{ IThiding }
 'if' 		{ ITif }
 'import' 	{ ITimport }
 'in' 		{ ITin }
 'infix' 	{ ITinfix }
 'infixl' 	{ ITinfixl }
 'infixr' 	{ ITinfixr }
 'instance' 	{ ITinstance }
 'let' 		{ ITlet }
 'module' 	{ ITmodule }
 'newtype' 	{ ITnewtype }
 'of' 		{ ITof }
 'qualified' 	{ ITqualified }
 'then' 	{ ITthen }
 'type' 	{ ITtype }
 'where' 	{ ITwhere }
 '_scc_'	{ ITscc }	      -- ToDo: remove

 'forall'	{ ITforall }			-- GHC extension keywords
 'foreign'	{ ITforeign }
 'export'	{ ITexport }
 'label'	{ ITlabel } 
 'dynamic'	{ ITdynamic }
 'unsafe'	{ ITunsafe }
 'with' 	{ ITwith }
 'stdcall'      { ITstdcallconv }
 'ccall'        { ITccallconv }
 'dotnet'       { ITdotnet }
 '_ccall_'	{ ITccall (False, False, PlayRisky) }
 '_ccall_GC_'	{ ITccall (False, False, PlaySafe)  }
 '_casm_'	{ ITccall (False, True,  PlayRisky) }
 '_casm_GC_'	{ ITccall (False, True,  PlaySafe)  }

 '{-# SPECIALISE'  { ITspecialise_prag }
 '{-# SOURCE'	   { ITsource_prag }
 '{-# INLINE'      { ITinline_prag }
 '{-# NOINLINE'    { ITnoinline_prag }
 '{-# RULES'	   { ITrules_prag }
 '{-# SCC'	   { ITscc_prag }
 '{-# DEPRECATED'  { ITdeprecated_prag }
 '#-}'		   { ITclose_prag }

{-
 '__interface'	{ ITinterface }			-- interface keywords
 '__export'	{ IT__export }
 '__instimport'	{ ITinstimport }
 '__forall'	{ IT__forall }
 '__letrec'	{ ITletrec }
 '__coerce'	{ ITcoerce }
 '__depends'	{ ITdepends }
 '__inline'	{ ITinline }
 '__DEFAULT'	{ ITdefaultbranch }
 '__bot'	{ ITbottom }
 '__integer'	{ ITinteger_lit }
 '__float'	{ ITfloat_lit }
 '__rational'	{ ITrational_lit }
 '__addr'	{ ITaddr_lit }
 '__label'	{ ITlabel_lit }
 '__litlit'	{ ITlit_lit }
 '__string'	{ ITstring_lit }
 '__ccall'	{ ITccall $$ }
 '__scc' 	{ IT__scc }
 '__sccC'       { ITsccAllCafs }

 '__A'		{ ITarity }
 '__P'		{ ITspecialise }
 '__C'		{ ITnocaf }
 '__U'		{ ITunfold $$ }
 '__S'		{ ITstrict $$ }
 '__M'		{ ITcprinfo $$ }
-}

 '..'		{ ITdotdot }  			-- reserved symbols
 '::'		{ ITdcolon }
 '='		{ ITequal }
 '\\'		{ ITlam }
 '|'		{ ITvbar }
 '<-'		{ ITlarrow }
 '->'		{ ITrarrow }
 '@'		{ ITat }
 '~'		{ ITtilde }
 '=>'		{ ITdarrow }
 '-'		{ ITminus }
 '!'		{ ITbang }
 '.'		{ ITdot }

 '{'		{ ITocurly } 			-- special symbols
 '}'		{ ITccurly }
 '{|'           { ITocurlybar }
 '|}'           { ITccurlybar }
 vccurly	{ ITvccurly } -- virtual close curly (from layout)
 '['		{ ITobrack }
 ']'		{ ITcbrack }
 '('		{ IToparen }
 ')'		{ ITcparen }
 '(#'		{ IToubxparen }
 '#)'		{ ITcubxparen }
 ';'		{ ITsemi }
 ','		{ ITcomma }
 '`'		{ ITbackquote }

 VARID   	{ ITvarid    $$ }		-- identifiers
 CONID   	{ ITconid    $$ }
 VARSYM  	{ ITvarsym   $$ }
 CONSYM  	{ ITconsym   $$ }
 QVARID  	{ ITqvarid   $$ }
 QCONID  	{ ITqconid   $$ }
 QVARSYM 	{ ITqvarsym  $$ }
 QCONSYM 	{ ITqconsym  $$ }

 IPVARID   	{ ITipvarid  $$ }		-- GHC extension

 CHAR		{ ITchar     $$ }
 STRING		{ ITstring   $$ }
 INTEGER	{ ITinteger  $$ }
 RATIONAL	{ ITrational $$ }

 PRIMCHAR	{ ITprimchar   $$ }
 PRIMSTRING	{ ITprimstring $$ }
 PRIMINTEGER	{ ITprimint    $$ }
 PRIMFLOAT	{ ITprimfloat  $$ }
 PRIMDOUBLE	{ ITprimdouble $$ }
 CLITLIT	{ ITlitlit     $$ }

%monad { P } { thenP } { returnP }
%lexer { lexer } { ITeof }
%name parseModule module
%name parseStmt   maybe_stmt
%tokentype { Token }
%%

-----------------------------------------------------------------------------
-- Module Header

-- The place for module deprecation is really too restrictive, but if it
-- was allowed at its natural place just before 'module', we get an ugly
-- s/r conflict with the second alternative. Another solution would be the
-- introduction of a new pragma DEPRECATED_MODULE, but this is not very nice,
-- either, and DEPRECATED is only expected to be used by people who really
-- know what they are doing. :-)

module 	:: { RdrNameHsModule }
 	: srcloc 'module' modid maybemoddeprec maybeexports 'where' body 
		{ HsModule $3 Nothing $5 (fst $7) (snd $7) $4 $1 }
	| srcloc body
		{ HsModule mAIN_Name Nothing Nothing (fst $2) (snd $2) Nothing $1 }

maybemoddeprec :: { Maybe DeprecTxt }
	: '{-# DEPRECATED' STRING '#-}' 	{ Just $2 }
	|  {- empty -}				{ Nothing }

body 	:: { ([RdrNameImportDecl], [RdrNameHsDecl]) }
	:  '{'            top '}'		{ $2 }
 	|      layout_on  top close		{ $2 }

top 	:: { ([RdrNameImportDecl], [RdrNameHsDecl]) }
	: importdecls				{ (reverse $1,[]) }
	| importdecls ';' cvtopdecls		{ (reverse $1,$3) }
	| cvtopdecls				{ ([],$1) }

cvtopdecls :: { [RdrNameHsDecl] }
	: topdecls				{ cvTopDecls (groupBindings $1)}

-----------------------------------------------------------------------------
-- The Export List

maybeexports :: { Maybe [RdrNameIE] }
	:  '(' exportlist ')'			{ Just $2 }
	|  {- empty -}				{ Nothing }

exportlist :: { [RdrNameIE] }
 	:  exportlist ',' export		{ $3 : $1 }
	|  exportlist ','			{ $1 }
 	|  export				{ [$1]  }
	|  {- empty -}				{ [] }

   -- GHC extension: we allow things like [] and (,,,) to be exported
export 	:: { RdrNameIE }
	:  qvar					{ IEVar $1 }
	|  gtycon				{ IEThingAbs $1 }
	|  gtycon '(' '..' ')'			{ IEThingAll $1 }
	|  gtycon '(' ')'		        { IEThingWith $1 [] }
	|  gtycon '(' qcnames ')'		{ IEThingWith $1 (reverse $3) }
	|  'module' modid			{ IEModuleContents $2 }

qcnames :: { [RdrName] }
	:  qcnames ',' qcname			{ $3 : $1 }
	|  qcname				{ [$1]  }

qcname 	:: { RdrName }
	:  qvar					{ $1 }
	|  gcon					{ $1 }

-----------------------------------------------------------------------------
-- Import Declarations

-- import decls can be *empty*, or even just a string of semicolons
-- whereas topdecls must contain at least one topdecl.

importdecls :: { [RdrNameImportDecl] }
	: importdecls ';' importdecl		{ $3 : $1 }
	| importdecls ';'			{ $1 }
	| importdecl				{ [ $1 ] }
	| {- empty -}				{ [] }

importdecl :: { RdrNameImportDecl }
	: 'import' srcloc maybe_src optqualified CONID maybeas maybeimpspec 
		{ ImportDecl (mkModuleNameFS $5) $3 $4 $6 $7 $2 }

maybe_src :: { WhereFrom }
	: '{-# SOURCE' '#-}'			{ ImportByUserSource }
	| {- empty -}				{ ImportByUser }

optqualified :: { Bool }
      	: 'qualified'                           { True  }
      	| {- empty -}				{ False }

maybeas :: { Maybe ModuleName }
      	: 'as' modid                            { Just $2 }
      	| {- empty -}				{ Nothing }

maybeimpspec :: { Maybe (Bool, [RdrNameIE]) }
	: impspec				{ Just $1 }
	| {- empty -}				{ Nothing }

impspec :: { (Bool, [RdrNameIE]) }
	:  '(' exportlist ')'  			{ (False, reverse $2) }
	|  'hiding' '(' exportlist ')' 		{ (True,  reverse $3) }

-----------------------------------------------------------------------------
-- Fixity Declarations

prec 	:: { Int }
	: {- empty -}				{ 9 }
	| INTEGER				{%  checkPrec $1 `thenP_`
						    returnP (fromInteger $1) }

infix 	:: { FixityDirection }
	: 'infix'				{ InfixN  }
	| 'infixl'				{ InfixL  }
	| 'infixr'				{ InfixR }

ops   	:: { [RdrName] }
	: ops ',' op				{ $3 : $1 }
	| op					{ [$1] }

-----------------------------------------------------------------------------
-- Top-Level Declarations

topdecls :: { [RdrBinding] }
	: topdecls ';' topdecl		{ ($3 : $1) }
	| topdecls ';'			{ $1 }
	| topdecl			{ [$1] }

topdecl :: { RdrBinding }
	: srcloc 'type' simpletype '=' ctype	
		-- Note ctype, not sigtype.
		-- We allow an explicit for-all but we don't insert one
		-- in 	type Foo a = (b,b)
		-- Instead we just say b is out of scope
		{ RdrHsDecl (TyClD (TySynonym (fst $3) (snd $3) $5 $1)) }

	| srcloc 'data' ctype constrs deriving
		{% checkDataHeader $3 `thenP` \(cs,c,ts) ->
		   returnP (RdrHsDecl (TyClD
		      (mkTyData DataType cs c ts (reverse $4) (length $4) $5 $1))) }

	| srcloc 'newtype' ctype '=' newconstr deriving
		{% checkDataHeader $3 `thenP` \(cs,c,ts) ->
		   returnP (RdrHsDecl (TyClD
		      (mkTyData NewType cs c ts [$5] 1 $6 $1))) }

	| srcloc 'class' ctype fds where
		{% checkDataHeader $3 `thenP` \(cs,c,ts) ->
		   let 
			(binds,sigs) = cvMonoBindsAndSigs cvClassOpSig (groupBindings $5) 
		   in
	 	   returnP (RdrHsDecl (TyClD
		      (mkClassDecl cs c ts $4 sigs (Just binds) $1))) }

	| srcloc 'instance' inst_type where
		{ let (binds,sigs) 
			= cvMonoBindsAndSigs cvInstDeclSig 
				(groupBindings $4)
		  in RdrHsDecl (InstD (InstDecl $3 binds sigs Nothing $1)) }

	| srcloc 'default' '(' types0 ')'		{ RdrHsDecl (DefD (DefaultDecl $4 $1)) }
	| 'foreign' fordecl				{ RdrHsDecl $2 }
	| '{-# DEPRECATED' deprecations '#-}'	 	{ $2 }
	| '{-# RULES' rules '#-}'		 	{ $2 }
      	| decl						{ $1 }

fordecl :: { RdrNameHsDecl }
fordecl : srcloc 'label' ext_name varid '::' sigtype
		{ ForD (ForeignImport $4 $6 (LblImport ($3 `orElse` mkExtName $4)) $1) }


	----------- ccall/stdcall decls ------------
	| srcloc 'import' ccallconv ext_name unsafe_flag varid_no_unsafe '::' sigtype
		{ let
		    call_spec = CCallSpec (StaticTarget ($4 `orElse` mkExtName $6)) $3 $5
		  in
		  ForD (ForeignImport $6 $8 (CImport call_spec) $1)
		}

	| srcloc 'import' ccallconv 'dynamic' unsafe_flag varid_no_unsafe '::' sigtype
		{ let
		    call_spec = CCallSpec DynamicTarget $3 $5
		  in
		  ForD (ForeignImport $6 $8 (CImport call_spec) $1)
		}

	| srcloc 'export' ccallconv ext_name varid '::' sigtype
		{ ForD (ForeignExport $5 $7 (CExport (CExportStatic ($4 `orElse` mkExtName $5) $3)) $1) }

	| srcloc 'export' ccallconv 'dynamic' varid '::' sigtype
		{ ForD (ForeignImport $5 $7 (CDynImport $3) $1) } 


	----------- .NET decls ------------
	| srcloc 'import' 'dotnet' ext_name varid '::' sigtype
		{ ForD (ForeignImport $5 $7 (DNImport (DNCallSpec ($4 `orElse` mkExtName $5))) $1) }

	| srcloc 'import' 'dotnet' 'type' tycon
		{ TyClD (ForeignType $5 DNType $1) }

decls 	:: { [RdrBinding] }
	: decls ';' decl		{ $3 : $1 }
	| decls ';'			{ $1 }
	| decl				{ [$1] }
	| {- empty -}			{ [] }

decl 	:: { RdrBinding }
	: fixdecl			{ $1 }
	| valdef			{ $1 }
	| '{-# INLINE'   srcloc opt_phase qvar '#-}'	 { RdrSig (InlineSig $4 $3 $2) }
	| '{-# NOINLINE' srcloc opt_phase qvar '#-}'	 { RdrSig (NoInlineSig $4 $3 $2) }
	| '{-# SPECIALISE' srcloc qvar '::' sigtypes '#-}'
	 	{ foldr1 RdrAndBindings 
		    (map (\t -> RdrSig (SpecSig $3 t $2)) $5) }
	| '{-# SPECIALISE' srcloc 'instance' inst_type '#-}'
		{ RdrSig (SpecInstSig $4 $2) }

opt_phase :: { Maybe Int }
          : INTEGER                     { Just (fromInteger $1) }
          | {- empty -}                 { Nothing }

wherebinds :: { RdrNameHsBinds }
	: where			{ cvBinds cvValSig (groupBindings $1) }

where 	:: { [RdrBinding] }
	: 'where' decllist		{ $2 }
	| {- empty -}			{ [] }

declbinds :: { RdrNameHsBinds }
	: decllist			{ cvBinds cvValSig (groupBindings $1) }

decllist :: { [RdrBinding] }
	: '{'            decls '}'	{ $2 }
	|     layout_on  decls close	{ $2 }

fixdecl :: { RdrBinding }
	: srcloc infix prec ops	    	{ foldr1 RdrAndBindings
					    [ RdrSig (FixSig (FixitySig n 
							    (Fixity $3 $2) $1))
					    | n <- $4 ] }

-----------------------------------------------------------------------------
-- Transformation Rules

rules	:: { RdrBinding }
	:  rules ';' rule			{ $1 `RdrAndBindings` $3 }
        |  rules ';'				{ $1 }
        |  rule					{ $1 }
	|  {- empty -}				{ RdrNullBind }

rule  	:: { RdrBinding }
	: STRING rule_forall infixexp '=' srcloc exp
	     { RdrHsDecl (RuleD (HsRule $1 [] $2 $3 $6 $5)) }

rule_forall :: { [RdrNameRuleBndr] }
	: 'forall' rule_var_list '.'            { $2 }
        | {- empty -}				{ [] }

rule_var_list :: { [RdrNameRuleBndr] }
        : rule_var				{ [$1] }
        | rule_var rule_var_list		{ $1 : $2 }

rule_var :: { RdrNameRuleBndr }
	: varid                              	{ RuleBndr $1 }
       	| '(' varid '::' ctype ')'             	{ RuleBndrSig $2 $4 }

-----------------------------------------------------------------------------
-- Deprecations

deprecations :: { RdrBinding }
	: deprecations ';' deprecation		{ $1 `RdrAndBindings` $3 }
	| deprecations ';'			{ $1 }
	| deprecation				{ $1 }
	| {- empty -}				{ RdrNullBind }

-- SUP: TEMPORARY HACK, not checking for `module Foo'
deprecation :: { RdrBinding }
	: srcloc depreclist STRING
		{ foldr RdrAndBindings RdrNullBind 
			[ RdrHsDecl (DeprecD (Deprecation n $3 $1)) | n <- $2 ] }

-----------------------------------------------------------------------------
-- Foreign import/export

ccallconv :: { CCallConv }
	: 'stdcall'		{ StdCallConv }
	| 'ccall'               { CCallConv }
	| {- empty -}		{ defaultCCallConv }

unsafe_flag :: { Safety }
	: 'unsafe'		{ PlayRisky }
	| {- empty -}		{ PlaySafe }

ext_name :: { Maybe CLabelString }
	: STRING		{ Just $1 }
	| {- empty -}           { Nothing }


-----------------------------------------------------------------------------
-- Type signatures

opt_sig :: { Maybe RdrNameHsType }
	: {- empty -}			{ Nothing }
	| '::' sigtype			{ Just $2 }

opt_asig :: { Maybe RdrNameHsType }
	: {- empty -}			{ Nothing }
	| '::' atype			{ Just $2 }

sigtypes :: { [RdrNameHsType] }
	: sigtype			{ [ $1 ] }
	| sigtypes ',' sigtype		{ $3 : $1 }

sigtype :: { RdrNameHsType }
	: ctype				{ (mkHsForAllTy Nothing [] $1) }

sig_vars :: { [RdrName] }
	 : sig_vars ',' var		{ $3 : $1 }
	 | var				{ [ $1 ] }

-----------------------------------------------------------------------------
-- Types

-- A ctype is a for-all type
ctype	:: { RdrNameHsType }
	: 'forall' tyvars '.' ctype	{ mkHsForAllTy (Just $2) [] $4 }
	| context type			{ mkHsForAllTy Nothing   $1 $2 }
	-- A type of form (context => type) is an *implicit* HsForAllTy
	| type				{ $1 }

type :: { RdrNameHsType }
	: gentype '->' type		{ HsFunTy $1 $3 }
	| ipvar '::' type		{ mkHsIParamTy $1 $3 }
	| gentype			{ $1 }

gentype :: { RdrNameHsType }
        : btype                         { $1 }
-- Generics
        | atype tyconop atype           { HsOpTy $1 $2 $3 }

btype :: { RdrNameHsType }
	: btype atype			{ (HsAppTy $1 $2) }
	| atype				{ $1 }

atype :: { RdrNameHsType }
	: gtycon			{ HsTyVar $1 }
	| tyvar				{ HsTyVar $1 }
	| '(' type ',' types ')'	{ HsTupleTy (mkHsTupCon tcName Boxed  ($2:$4)) ($2 : reverse $4) }
	| '(#' types '#)'		{ HsTupleTy (mkHsTupCon tcName Unboxed     $2) (reverse $2)	 }
	| '[' type ']'			{ HsListTy $2 }
	| '(' ctype ')'		        { $2 }
-- Generics
        | INTEGER                       { HsNumTy $1 }

-- An inst_type is what occurs in the head of an instance decl
--	e.g.  (Foo a, Gaz b) => Wibble a b
-- It's kept as a single type, with a MonoDictTy at the right
-- hand corner, for convenience.
inst_type :: { RdrNameHsType }
	: ctype				{% checkInstType $1 }

types0  :: { [RdrNameHsType] }
	: types				{ reverse $1 }
	| {- empty -}			{ [] }

types	:: { [RdrNameHsType] }
	: type				{ [$1] }
	| types  ',' type		{ $3 : $1 }

simpletype :: { (RdrName, [RdrNameHsTyVar]) }
	: tycon tyvars			{ ($1, reverse $2) }

tyvars :: { [RdrNameHsTyVar] }
	: tyvars tyvar			{ UserTyVar $2 : $1 }
	| {- empty -}			{ [] }

fds :: { [([RdrName], [RdrName])] }
	: {- empty -}			{ [] }
	| '|' fds1			{ reverse $2 }

fds1 :: { [([RdrName], [RdrName])] }
	: fds1 ',' fd			{ $3 : $1 }
	| fd				{ [$1] }

fd :: { ([RdrName], [RdrName]) }
	: varids0 '->' varids0		{ (reverse $1, reverse $3) }

varids0	:: { [RdrName] }
	: {- empty -}			{ [] }
	| varids0 tyvar			{ $2 : $1 }

-----------------------------------------------------------------------------
-- Datatype declarations

newconstr :: { RdrNameConDecl }
	: srcloc conid atype	{ mkConDecl $2 [] [] (VanillaCon [unbangedType $3]) $1 }
	| srcloc conid '{' var '::' type '}'
				{ mkConDecl $2 [] [] (RecCon [([$4], unbangedType $6)]) $1 }

constrs :: { [RdrNameConDecl] }
        : {- empty; a GHC extension -}  { [] }
        | '=' constrs1                  { $2 }

constrs1 :: { [RdrNameConDecl] }
	: constrs1 '|' constr		{ $3 : $1 }
	| constr			{ [$1] }

constr :: { RdrNameConDecl }
	: srcloc forall context constr_stuff
		{ mkConDecl (fst $4) $2 $3 (snd $4) $1 }
	| srcloc forall constr_stuff
		{ mkConDecl (fst $3) $2 [] (snd $3) $1 }

forall :: { [RdrNameHsTyVar] }
	: 'forall' tyvars '.'		{ $2 }
	| {- empty -}			{ [] }

context :: { RdrNameContext }
	: btype '=>'			{% checkContext $1 }

constr_stuff :: { (RdrName, RdrNameConDetails) }
	: btype				{% mkVanillaCon $1 []		    }
	| btype '!' atype satypes	{% mkVanillaCon $1 (BangType MarkedUserStrict $3 : $4) }
	| gtycon '{' fielddecls '}' 	{% mkRecCon $1 $3 }
	| sbtype conop sbtype		{ ($2, InfixCon $1 $3) }

satypes	:: { [RdrNameBangType] }
	: atype satypes			{ unbangedType $1 : $2 }
	| '!' atype satypes		{ BangType MarkedUserStrict $2 : $3 }
	| {- empty -}			{ [] }

sbtype :: { RdrNameBangType }
	: btype				{ unbangedType $1 }
	| '!' atype			{ BangType MarkedUserStrict $2 }

fielddecls :: { [([RdrName],RdrNameBangType)] }
	: fielddecl ',' fielddecls	{ $1 : $3 }
	| fielddecl			{ [$1] }

fielddecl :: { ([RdrName],RdrNameBangType) }
	: sig_vars '::' stype		{ (reverse $1, $3) }

stype :: { RdrNameBangType }
	: ctype				{ unbangedType $1 }
	| '!' atype			{ BangType MarkedUserStrict $2 }

deriving :: { Maybe [RdrName] }
	: {- empty -}			{ Nothing }
	| 'deriving' qtycls		{ Just [$2] }
	| 'deriving' '('          ')'	{ Just [] }
	| 'deriving' '(' dclasses ')'	{ Just (reverse $3) }

dclasses :: { [RdrName] }
	: dclasses ',' qtycls		{ $3 : $1 }
       	| qtycls			{ [$1] }

-----------------------------------------------------------------------------
-- Value definitions

{- There's an awkward overlap with a type signature.  Consider
	f :: Int -> Int = ...rhs...
   Then we can't tell whether it's a type signature or a value
   definition with a result signature until we see the '='.
   So we have to inline enough to postpone reductions until we know.
-}

{-
  ATTENTION: Dirty Hackery Ahead! If the second alternative of vars is var
  instead of qvar, we get another shift/reduce-conflict. Consider the
  following programs:
  
     { (^^) :: Int->Int ; }          Type signature; only var allowed

     { (^^) :: Int->Int = ... ; }    Value defn with result signature;
				     qvar allowed (because of instance decls)
  
  We can't tell whether to reduce var to qvar until after we've read the signatures.
-}

valdef :: { RdrBinding }
	: infixexp srcloc opt_sig rhs		{% (checkValDef $1 $3 $4 $2) }
	| infixexp srcloc '::' sigtype		{% (checkValSig $1 $4 $2) }
	| var ',' sig_vars srcloc '::' sigtype	{ foldr1 RdrAndBindings 
							 [ RdrSig (Sig n $6 $4) | n <- $1:$3 ]
                                                }


rhs	:: { RdrNameGRHSs }
	: '=' srcloc exp wherebinds	{ (GRHSs (unguardedRHS $3 $2) 
								$4 Nothing)}
	| gdrhs	wherebinds		{ GRHSs (reverse $1) $2 Nothing }

gdrhs :: { [RdrNameGRHS] }
	: gdrhs gdrh			{ $2 : $1 }
	| gdrh				{ [$1] }

gdrh :: { RdrNameGRHS }
	: '|' srcloc quals '=' exp  	{ GRHS (reverse (ResultStmt $5 $2 : $3)) $2 }

-----------------------------------------------------------------------------
-- Expressions

exp   :: { RdrNameHsExpr }
	: infixexp '::' sigtype		{ (ExprWithTySig $1 $3) }
	| infixexp 'with' dbinding	{ HsWith $1 $3 }
	| infixexp			{ $1 }

infixexp :: { RdrNameHsExpr }
	: exp10				{ $1 }
	| infixexp qop exp10		{ (OpApp $1 (HsVar $2) 
						(panic "fixity") $3 )}

exp10 :: { RdrNameHsExpr }
	: '\\' srcloc aexp aexps opt_asig '->' srcloc exp	
			{% checkPatterns $2 ($3 : reverse $4) `thenP` \ ps -> 
			   returnP (HsLam (Match [] ps $5 
					    (GRHSs (unguardedRHS $8 $7) 
						   EmptyBinds Nothing))) }
  	| 'let' declbinds 'in' exp		{ HsLet $2 $4 }
	| 'if' srcloc exp 'then' exp 'else' exp { HsIf $3 $5 $7 $2 }
   	| 'case' srcloc exp 'of' altslist	{ HsCase $3 $5 $2 }
	| '-' fexp				{ mkHsNegApp $2 }
  	| srcloc 'do' stmtlist			{% checkDo $3  `thenP` \ stmts ->
						   returnP (HsDo DoExpr stmts $1) }

	| '_ccall_'    ccallid aexps0		{ HsCCall $2 $3 PlayRisky False cbot }
	| '_ccall_GC_' ccallid aexps0		{ HsCCall $2 $3 PlaySafe  False cbot }
	| '_casm_'     CLITLIT aexps0		{ HsCCall $2 $3 PlayRisky True  cbot }
	| '_casm_GC_'  CLITLIT aexps0		{ HsCCall $2 $3 PlaySafe  True  cbot }

        | scc_annot exp		    		{ if opt_SccProfilingOn
							then HsSCC $1 $2
							else HsPar $2 }

	| fexp					{ $1 }

scc_annot :: { FAST_STRING }
	: '_scc_' STRING			{ $2 }
	| '{-# SCC' STRING '#-}'		{ $2 }

ccallid :: { FAST_STRING }
	:  VARID				{ $1 }
	|  CONID				{ $1 }

fexp 	:: { RdrNameHsExpr }
	: fexp aexp				{ (HsApp $1 $2) }
  	| aexp					{ $1 }

aexps0 	:: { [RdrNameHsExpr] }
	: aexps					{ (reverse $1) }

aexps 	:: { [RdrNameHsExpr] }
	: aexps aexp				{ $2 : $1 }
  	| {- empty -}				{ [] }

aexp	:: { RdrNameHsExpr }
        : var_or_con '{|' gentype '|}'          { (HsApp $1 (HsType $3)) }
  	| aexp '{' fbinds '}' 			{% (mkRecConstrOrUpdate $1 
							(reverse $3)) }
  	| aexp1					{ $1 }

var_or_con :: { RdrNameHsExpr }
        : qvar                          { HsVar $1 }
        | gcon                          { HsVar $1 }

aexp1	:: { RdrNameHsExpr }
	: ipvar				{ HsIPVar $1 }
	| var_or_con			{ $1 }
	| literal			{ HsLit $1 }
	| INTEGER			{ HsOverLit (HsIntegral   $1) }
	| RATIONAL			{ HsOverLit (HsFractional $1) }
	| '(' exp ')'			{ HsPar $2 }
	| '(' exp ',' texps ')'		{ ExplicitTuple ($2 : reverse $4) Boxed}
	| '(#' texps '#)'		{ ExplicitTuple (reverse $2)      Unboxed }
	| '[' list ']'                  { $2 }
	| '(' infixexp qop ')'		{ (SectionL $2 (HsVar $3))  }
	| '(' qopm infixexp ')'		{ (SectionR $2 $3) }
	| qvar '@' aexp			{ EAsPat $1 $3 }
	| '_'				{ EWildPat }
	| '~' aexp1			{ ELazyPat $2 }

texps :: { [RdrNameHsExpr] }
	: texps ',' exp			{ $3 : $1 }
	| exp				{ [$1] }


-----------------------------------------------------------------------------
-- List expressions

-- The rules below are little bit contorted to keep lexps left-recursive while
-- avoiding another shift/reduce-conflict.

list :: { RdrNameHsExpr }
	: exp				{ ExplicitList [$1] }
	| lexps 			{ ExplicitList (reverse $1) }
	| exp '..'			{ ArithSeqIn (From $1) }
	| exp ',' exp '..' 		{ ArithSeqIn (FromThen $1 $3) }
	| exp '..' exp	 		{ ArithSeqIn (FromTo $1 $3) }
	| exp ',' exp '..' exp		{ ArithSeqIn (FromThenTo $1 $3 $5) }
	| exp srcloc pquals		{% let { body [qs] = qs;
					         body  qss = [ParStmt (map reverse qss)] }
					   in
					   returnP ( HsDo ListComp
							   (reverse (ResultStmt $1 $2 : body $3))
							   $2
						  )
					}

lexps :: { [RdrNameHsExpr] }
	: lexps ',' exp 		{ $3 : $1 }
	| exp ',' exp			{ [$3,$1] }

-----------------------------------------------------------------------------
-- List Comprehensions

pquals :: { [[RdrNameStmt]] }
	: pquals '|' quals		{ $3 : $1 }
	| '|' quals			{ [$2] }

quals :: { [RdrNameStmt] }
	: quals ',' stmt		{ $3 : $1 }
	| stmt				{ [$1] }

-----------------------------------------------------------------------------
-- Case alternatives

altslist :: { [RdrNameMatch] }
	: '{'            alts '}'	{ reverse $2 }
	|     layout_on  alts  close	{ reverse $2 }

alts    :: { [RdrNameMatch] }
        : alts1				{ $1 }
	| ';' alts			{ $2 }

alts1 	:: { [RdrNameMatch] }
	: alts1 ';' alt			{ $3 : $1 }
	| alts1 ';'			{ $1 }
	| alt				{ [$1] }

alt 	:: { RdrNameMatch }
	: srcloc infixexp opt_sig ralt wherebinds
					{% (checkPattern $1 $2 `thenP` \p ->
				   	   returnP (Match [] [p] $3
					             (GRHSs $4 $5 Nothing))  )}

ralt :: { [RdrNameGRHS] }
	: '->' srcloc exp		{ [GRHS [ResultStmt $3 $2] $2] }
	| gdpats			{ (reverse $1) }

gdpats :: { [RdrNameGRHS] }
	: gdpats gdpat			{ $2 : $1 }
	| gdpat				{ [$1] }

gdpat	:: { RdrNameGRHS }
	: srcloc '|' quals '->' exp 	{ GRHS (reverse (ResultStmt $5 $1:$3)) $1}

-----------------------------------------------------------------------------
-- Statement sequences

stmtlist :: { [RdrNameStmt] }
	: '{'            	stmts '}'	{ $2 }
	|     layout_on_for_do  stmts close	{ $2 }

--	do { ;; s ; s ; ; s ;; }
-- The last Stmt should be a ResultStmt, but that's hard to enforce
-- here, because we need too much lookahead if we see do { e ; }
-- So we use ExprStmts throughout, and switch the last one over
-- in ParseUtils.checkDo instead
stmts :: { [RdrNameStmt] }
	: stmt stmts_help		{ $1 : $2 }
	| ';' stmts			{ $2 }
	| {- empty -}			{ [] }

stmts_help :: { [RdrNameStmt] }
	: ';' stmts			{ $2 }
	| {- empty -}			{ [] }

-- For typing stmts at the GHCi prompt, where 
-- the input may consist of just comments.
maybe_stmt :: { Maybe RdrNameStmt }
	: stmt				{ Just $1 }
	| {- nothing -}			{ Nothing }

stmt  :: { RdrNameStmt }
	: srcloc infixexp '<-' exp	{% checkPattern $1 $2 `thenP` \p ->
					   returnP (BindStmt p $4 $1) }
	| srcloc exp			{ ExprStmt $2 $1 }
  	| srcloc 'let' declbinds	{ LetStmt $3 }

-----------------------------------------------------------------------------
-- Record Field Update/Construction

fbinds 	:: { RdrNameHsRecordBinds }
	: fbinds ',' fbind		{ $3 : $1 }
	| fbinds ','			{ $1 }
	| fbind				{ [$1] }
	| {- empty -}			{ [] }

fbind	:: { (RdrName, RdrNameHsExpr, Bool) }
	: qvar '=' exp			{ ($1,$3,False) }

-----------------------------------------------------------------------------
-- Implicit Parameter Bindings

dbinding :: { [(RdrName, RdrNameHsExpr)] }
	: '{' dbinds '}'		{ $2 }
	| layout_on dbinds close	{ $2 }

dbinds 	:: { [(RdrName, RdrNameHsExpr)] }
	: dbinds ';' dbind		{ $3 : $1 }
	| dbinds ';'			{ $1 }
	| dbind				{ [$1] }
	| {- empty -}			{ [] }

dbind	:: { (RdrName, RdrNameHsExpr) }
dbind	: ipvar '=' exp			{ ($1, $3) }

-----------------------------------------------------------------------------
-- Variables, Constructors and Operators.

depreclist :: { [RdrName] }
depreclist : deprec_var			{ [$1] }
	   | deprec_var ',' depreclist	{ $1 : $3 }

deprec_var :: { RdrName }
deprec_var : var			{ $1 }
	   | tycon			{ $1 }

gtycon 	:: { RdrName }
	: qtycon			{ $1 }
 	| '(' qtyconop ')'		{ $2 }
	| '(' ')'			{ unitTyCon_RDR }
	| '(' '->' ')'			{ funTyCon_RDR }
	| '[' ']'			{ listTyCon_RDR }
	| '(' commas ')'		{ tupleTyCon_RDR $2 }

gcon 	:: { RdrName }
	: '(' ')'		{ unitCon_RDR }
	| '[' ']'		{ nilCon_RDR }
	| '(' commas ')'	{ tupleCon_RDR $2 }
 	| qcon			{ $1 }

var 	:: { RdrName }
	: varid			{ $1 }
	| '(' varsym ')'	{ $2 }

qvar 	:: { RdrName }
	: qvarid		{ $1 }
	| '(' varsym ')'	{ $2 }
	| '(' qvarsym1 ')'	{ $2 }
-- We've inlined qvarsym here so that the decision about
-- whether it's a qvar or a var can be postponed until
-- *after* we see the close paren.

ipvar	:: { RdrName }
	: IPVARID		{ (mkUnqual varName (tailFS $1)) }

qcon	:: { RdrName }
	: qconid		{ $1 }
	| '(' qconsym ')'	{ $2 }

varop	:: { RdrName }
	: varsym		{ $1 }
	| '`' varid '`'		{ $2 }

qvarop :: { RdrName }
	: qvarsym		{ $1 }
	| '`' qvarid '`'	{ $2 }

qvaropm :: { RdrName }
	: qvarsym_no_minus	{ $1 }
	| '`' qvarid '`'	{ $2 }

conop :: { RdrName }
	: consym		{ $1 }	
	| '`' conid '`'		{ $2 }

qconop :: { RdrName }
	: qconsym		{ $1 }
	| '`' qconid '`'	{ $2 }

-----------------------------------------------------------------------------
-- Any operator

op	:: { RdrName }   -- used in infix decls
	: varop			{ $1 }
	| conop 		{ $1 }

qop	:: { RdrName {-HsExpr-} }   -- used in sections
	: qvarop		{ $1 }
	| qconop		{ $1 }

qopm	:: { RdrNameHsExpr }   -- used in sections
	: qvaropm		{ HsVar $1 }
	| qconop		{ HsVar $1 }

-----------------------------------------------------------------------------
-- VarIds

qvarid :: { RdrName }
	: varid			{ $1 }
	| QVARID		{ mkQual varName $1 }

varid :: { RdrName }
	: varid_no_unsafe 	{ $1 }
	| 'unsafe'		{ mkUnqual varName SLIT("unsafe") }

varid_no_unsafe :: { RdrName }
	: VARID			{ mkUnqual varName $1 }
	| special_id		{ mkUnqual varName $1 }
	| 'forall'		{ mkUnqual varName SLIT("forall") }

tyvar 	:: { RdrName }
	: VARID			{ mkUnqual tvName $1 }
	| special_id		{ mkUnqual tvName $1 }
	| 'unsafe' 		{ mkUnqual tvName SLIT("unsafe") }

-- These special_ids are treated as keywords in various places, 
-- but as ordinary ids elsewhere.   A special_id collects all thsee
-- except 'unsafe' and 'forall' whose treatment differs depending on context
special_id :: { UserFS }
special_id
	: 'as'			{ SLIT("as") }
	| 'qualified'		{ SLIT("qualified") }
	| 'hiding'		{ SLIT("hiding") }
	| 'export'		{ SLIT("export") }
	| 'label'		{ SLIT("label")  }
	| 'dynamic'		{ SLIT("dynamic") }
	| 'stdcall'             { SLIT("stdcall") }
	| 'ccall'               { SLIT("ccall") }

-----------------------------------------------------------------------------
-- ConIds

qconid :: { RdrName }
	: conid			{ $1 }
	| QCONID		{ mkQual dataName $1 }

conid 	:: { RdrName }
	: CONID			{ mkUnqual dataName $1 }

-----------------------------------------------------------------------------
-- ConSyms

qconsym :: { RdrName }
	: consym		{ $1 }
	| QCONSYM		{ mkQual dataName $1 }

consym :: { RdrName }
	: CONSYM		{ mkUnqual dataName $1 }

-----------------------------------------------------------------------------
-- VarSyms

qvarsym :: { RdrName }
	: varsym		{ $1 }
	| qvarsym1		{ $1 }

qvarsym_no_minus :: { RdrName }
	: varsym_no_minus	{ $1 }
	| qvarsym1		{ $1 }

qvarsym1 :: { RdrName }
qvarsym1 : QVARSYM		{ mkQual varName $1 }

varsym :: { RdrName }
	: varsym_no_minus 	{ $1 }
	| '-'			{ mkUnqual varName SLIT("-") }

varsym_no_minus :: { RdrName } -- varsym not including '-'
	: VARSYM		{ mkUnqual varName $1 }
	| special_sym		{ mkUnqual varName $1 }


-- See comments with special_id
special_sym :: { UserFS }
special_sym : '!'	{ SLIT("!") }
	    | '.' 	{ SLIT(".") }

-----------------------------------------------------------------------------
-- Literals

literal :: { HsLit }
	: CHAR 			{ HsChar       $1 }
	| STRING		{ HsString     $1 }
	| PRIMINTEGER		{ HsIntPrim    $1 }
	| PRIMCHAR		{ HsCharPrim   $1 }
	| PRIMSTRING		{ HsStringPrim $1 }
	| PRIMFLOAT		{ HsFloatPrim  $1 }
	| PRIMDOUBLE		{ HsDoublePrim $1 }
	| CLITLIT		{ HsLitLit     $1 (error "Parser.y: CLITLIT") }

srcloc :: { SrcLoc }	:	{% getSrcLocP }
 
-----------------------------------------------------------------------------
-- Layout

close :: { () }
	: vccurly		{ () } -- context popped in lexer.
	| error			{% popContext }

layout_on  	  :: { () }	: {% layoutOn True{-strict-} }
layout_on_for_do  :: { () }	: {% layoutOn False }

-----------------------------------------------------------------------------
-- Miscellaneous (mostly renamings)

modid 	:: { ModuleName }
	: CONID			{ mkModuleNameFS $1 }

tycon 	:: { RdrName }
	: CONID			{ mkUnqual tcClsName $1 }

tyconop	:: { RdrName }
	: CONSYM		{ mkUnqual tcClsName $1 }

qtycon :: { RdrName }
	: tycon			{ $1 }
	| QCONID		{ mkQual tcClsName $1 }

qtyconop :: { RdrName }
 	  : tyconop		{ $1 }
	  | QCONSYM		{ mkQual tcClsName $1 }

qtycls 	:: { RdrName }
	: qtycon		{ $1 }

commas :: { Int }
	: commas ','			{ $1 + 1 }
	| ','				{ 2 }

-----------------------------------------------------------------------------

{
happyError :: P a
happyError buf PState{ loc = loc } = PFailed (srcParseErr buf loc)
}
