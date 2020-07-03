module Parens: sig
  type kind = Parenthesized | Braced of Location.t | Nothing

  val expr: Parsetree.expression -> kind
  val structureExpr: Parsetree.expression -> kind

  val unaryExprOperand: Parsetree.expression -> kind

  val binaryExprOperand: isLhs:bool -> Parsetree.expression -> string -> kind
  val subBinaryExprOperand: string -> string -> bool
  val rhsBinaryExprOperand: string -> Parsetree.expression -> bool
  val flattenOperandRhs: string -> Parsetree.expression -> bool

  val lazyOrAssertExprRhs: Parsetree.expression -> kind

  val fieldExpr: Parsetree.expression -> kind

  val setFieldExprRhs: Parsetree.expression -> kind

  val ternaryOperand: Parsetree.expression -> kind

  val jsxPropExpr: Parsetree.expression -> kind
  val jsxChildExpr: Parsetree.expression -> kind

  val binaryExpr: Parsetree.expression -> kind
  val modTypeFunctorReturn: Parsetree.module_type -> bool
  val modTypeWithOperand: Parsetree.module_type -> bool
  val modExprFunctorConstraint: Parsetree.module_type -> bool

  val bracedExpr: Parsetree.expression -> bool
end = struct
  type kind = Parenthesized | Braced of Location.t | Nothing

  let expr expr =
    let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
    match optBraces with
    | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
    | _ ->
      begin match expr with
      | {Parsetree.pexp_desc = Pexp_constraint (
          {pexp_desc = Pexp_pack _},
          {ptyp_desc = Ptyp_package _}
        )} -> Nothing
      | {pexp_desc = Pexp_constraint _ } -> Parenthesized
      |  _ -> Nothing
      end

  let structureExpr expr =
    let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
    match optBraces with
    | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
    | None ->
      begin match expr with
      | _ when ParsetreeViewer.hasAttributes expr.pexp_attributes &&
        not (ParsetreeViewer.isJsxExpression expr) -> Parenthesized
      | {Parsetree.pexp_desc = Pexp_constraint (
          {pexp_desc = Pexp_pack _},
          {ptyp_desc = Ptyp_package _}
        )} -> Nothing
      | {pexp_desc = Pexp_constraint _ } -> Parenthesized
      |  _ -> Nothing
      end

  let unaryExprOperand expr =
    let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
    match optBraces with
    | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
    | None ->
      begin match expr with
      | {Parsetree.pexp_attributes = attrs} when
          begin match ParsetreeViewer.filterParsingAttrs attrs with
          | _::_ -> true
          | [] -> false
          end
          -> Parenthesized
      | expr when
          ParsetreeViewer.isUnaryExpression expr ||
          ParsetreeViewer.isBinaryExpression expr
        -> Parenthesized
      | {pexp_desc = Pexp_constraint (
          {pexp_desc = Pexp_pack _},
          {ptyp_desc = Ptyp_package _}
        )} -> Nothing
      | {pexp_desc =
            Pexp_lazy _
          | Pexp_assert _
          | Pexp_fun _
          | Pexp_newtype _
          | Pexp_function _
          | Pexp_constraint _
          | Pexp_setfield _
          | Pexp_extension _ (* readability? maybe remove *)
          | Pexp_match _
          | Pexp_try _
          | Pexp_while _
          | Pexp_for _
          | Pexp_ifthenelse _
        } -> Parenthesized
      | _ -> Nothing
      end

  let binaryExprOperand ~isLhs expr parentOperator =
    let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
    match optBraces with
    | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
    | None ->
      begin match expr with
      | {Parsetree.pexp_desc = Pexp_constraint (
          {pexp_desc = Pexp_pack _},
          {ptyp_desc = Ptyp_package _}
        )} -> Nothing
      | {pexp_desc = Pexp_constraint _ | Pexp_fun _ | Pexp_function _ | Pexp_newtype _} -> Parenthesized
      | expr when ParsetreeViewer.isBinaryExpression expr -> Parenthesized
      | expr when ParsetreeViewer.isTernaryExpr expr -> Parenthesized
      | {pexp_desc =
            Pexp_lazy _
          | Pexp_assert _
        } when isLhs -> Parenthesized
      | _ -> Nothing
      end

  let subBinaryExprOperand parentOperator childOperator =
    let precParent = ParsetreeViewer.operatorPrecedence parentOperator in
    let precChild =  ParsetreeViewer.operatorPrecedence childOperator in
    precParent > precChild ||
    (precParent == precChild &&
    not (ParsetreeViewer.flattenableOperators parentOperator childOperator)) ||
    (* a && b || c, add parens to (a && b) for readability, who knows the difference by heart‚Ä¶ *)
    (parentOperator = "||" && childOperator = "&&")

  let rhsBinaryExprOperand parentOperator rhs =
    match rhs.Parsetree.pexp_desc with
    | Parsetree.Pexp_apply(
      {pexp_attributes = [];
        pexp_desc = Pexp_ident {txt = Longident.Lident operator}},
        [_, left; _, right]
      ) when ParsetreeViewer.isBinaryOperator operator ->
    let precParent = ParsetreeViewer.operatorPrecedence parentOperator in
    let precChild =  ParsetreeViewer.operatorPrecedence operator in
    precParent == precChild
    | _ -> false

  let flattenOperandRhs parentOperator rhs =
    match rhs.Parsetree.pexp_desc with
    | Parsetree.Pexp_apply(
        {pexp_desc = Pexp_ident {txt = Longident.Lident operator}},
        [_, left; _, right]
      ) when ParsetreeViewer.isBinaryOperator operator ->
      let precParent = ParsetreeViewer.operatorPrecedence parentOperator in
      let precChild =  ParsetreeViewer.operatorPrecedence operator in
      precParent >= precChild || rhs.pexp_attributes <> []
    | Pexp_constraint (
        {pexp_desc = Pexp_pack _},
        {ptyp_desc = Ptyp_package _}
      ) -> false
    | Pexp_fun _
    | Pexp_newtype _
    | Pexp_setfield _
    | Pexp_constraint _ -> true
    | _ when ParsetreeViewer.isTernaryExpr rhs -> true
    | _ -> false

  let lazyOrAssertExprRhs expr =
    let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
    match optBraces with
    | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
    | None ->
      begin match expr with
      | {Parsetree.pexp_attributes = attrs} when
          begin match ParsetreeViewer.filterParsingAttrs attrs with
          | _::_ -> true
          | [] -> false
          end
          -> Parenthesized
      | expr when ParsetreeViewer.isBinaryExpression expr -> Parenthesized
      | {pexp_desc = Pexp_constraint (
          {pexp_desc = Pexp_pack _},
          {ptyp_desc = Ptyp_package _}
        )} -> Nothing
      | {pexp_desc =
            Pexp_lazy _
          | Pexp_assert _
          | Pexp_fun _
          | Pexp_newtype _
          | Pexp_function _
          | Pexp_constraint _
          | Pexp_setfield _
          | Pexp_match _
          | Pexp_try _
          | Pexp_while _
          | Pexp_for _
          | Pexp_ifthenelse _
        } -> Parenthesized
      | _ -> Nothing
      end

  let fieldExpr expr =
    let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
    match optBraces with
    | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
    | None ->
      begin match expr with
      | {Parsetree.pexp_attributes = attrs} when
          begin match ParsetreeViewer.filterParsingAttrs attrs with
          | _::_ -> true
          | [] -> false
          end
          -> Parenthesized
      | expr when
          ParsetreeViewer.isBinaryExpression expr ||
          ParsetreeViewer.isUnaryExpression expr
        -> Parenthesized
      | {pexp_desc = Pexp_constraint (
          {pexp_desc = Pexp_pack _},
          {ptyp_desc = Ptyp_package _}
        )} -> Nothing
      | {pexp_desc =
            Pexp_lazy _
          | Pexp_assert _
          | Pexp_fun _
          | Pexp_newtype _
          | Pexp_function _
          | Pexp_constraint _
          | Pexp_setfield _
          | Pexp_match _
          | Pexp_try _
          | Pexp_while _
          | Pexp_for _
          | Pexp_ifthenelse _
        } -> Parenthesized
      | _ -> Nothing
      end

  let setFieldExprRhs expr =
    let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
    match optBraces with
    | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
    | None ->
      begin match expr with
      | {Parsetree.pexp_desc = Pexp_constraint (
          {pexp_desc = Pexp_pack _},
          {ptyp_desc = Ptyp_package _}
        )} -> Nothing
      | {pexp_desc = Pexp_constraint _ } -> Parenthesized
      | _ -> Nothing
      end

  let ternaryOperand expr =
    let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
    match optBraces with
    | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
    | None ->
      begin match expr with
      | {Parsetree.pexp_desc = Pexp_constraint (
          {pexp_desc = Pexp_pack _},
          {ptyp_desc = Ptyp_package _}
        )} -> Nothing
      | {pexp_desc = Pexp_constraint _ } -> Parenthesized
      | {pexp_desc = Pexp_fun _ | Pexp_newtype _} ->
        let (_attrsOnArrow, _parameters, returnExpr) = ParsetreeViewer.funExpr expr in
        begin match returnExpr.pexp_desc with
        | Pexp_constraint _ -> Parenthesized
        | _ -> Nothing
        end
      | _ -> Nothing
      end

  let startsWithMinus txt =
    let len = String.length txt in
    if len == 0 then
      false
    else
      let s = String.get txt 0 in
      s = '-'

  let jsxPropExpr expr =
    match expr.Parsetree.pexp_desc with
    | Parsetree.Pexp_let _
    | Pexp_sequence _
    | Pexp_letexception _
    | Pexp_letmodule _
    | Pexp_open _ -> Nothing
    | _ ->
      let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
      begin match optBraces with
      | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
      | None ->
        begin match expr with
        | {Parsetree.pexp_desc =
            Pexp_constant (Pconst_integer (x, _) | Pconst_float (x, _));
            pexp_attributes = []}
          when startsWithMinus x -> Parenthesized
        | {Parsetree.pexp_desc =
            Pexp_ident _ | Pexp_constant _ | Pexp_field _ | Pexp_construct _ |
            Pexp_array _ | Pexp_pack _ | Pexp_record _ | Pexp_extension _ |
            Pexp_letmodule _ | Pexp_letexception _ | Pexp_open _ | Pexp_sequence _ |
            Pexp_let _ | Pexp_tuple _;
           pexp_attributes = []
          } -> Nothing
        | {Parsetree.pexp_desc = Pexp_constraint (
            {pexp_desc = Pexp_pack _},
            {ptyp_desc = Ptyp_package _}
          ); pexp_attributes = []} -> Nothing
        | _ -> Parenthesized
        end
      end

  let jsxChildExpr expr =
    match expr.Parsetree.pexp_desc with
    | Parsetree.Pexp_let _
    | Pexp_sequence _
    | Pexp_letexception _
    | Pexp_letmodule _
    | Pexp_open _ -> Nothing
    | _ ->
      let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
      begin match optBraces with
      | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
      | _ ->
        begin match expr with
        | {Parsetree.pexp_desc = Pexp_constant (Pconst_integer (x, _) | Pconst_float (x, _));
           pexp_attributes = []
          } when startsWithMinus x -> Parenthesized
        | {Parsetree.pexp_desc =
            Pexp_ident _ | Pexp_constant _ | Pexp_field _ | Pexp_construct _ |
            Pexp_array _ | Pexp_pack _ | Pexp_record _ | Pexp_extension _ |
            Pexp_letmodule _ | Pexp_letexception _ | Pexp_open _ | Pexp_sequence _ |
            Pexp_let _;
            pexp_attributes = []
          } -> Nothing
        | {Parsetree.pexp_desc = Pexp_constraint (
            {pexp_desc = Pexp_pack _},
            {ptyp_desc = Ptyp_package _}
           ); pexp_attributes = []} -> Nothing
        | expr when ParsetreeViewer.isJsxExpression expr -> Nothing
        | _ -> Parenthesized
        end
      end

  let binaryExpr expr =
    let optBraces, _ = ParsetreeViewer.processBracesAttr expr in
    match optBraces with
    | Some ({Location.loc = bracesLoc}, _) -> Braced(bracesLoc)
    | None ->
      begin match expr with
      | {Parsetree.pexp_attributes = _::_} as expr
        when ParsetreeViewer.isBinaryExpression expr -> Parenthesized
      | _ -> Nothing
      end

  let modTypeFunctorReturn modType = match modType with
    | {Parsetree.pmty_desc = Pmty_with _} -> true
    | _ -> false

  (* Add parens for readability:
       module type Functor = SetLike => Set with type t = A.t
     This is actually:
       module type Functor = (SetLike => Set) with type t = A.t
  *)
  let modTypeWithOperand modType = match modType with
    | {Parsetree.pmty_desc = Pmty_functor _} -> true
    | _ -> false

  let modExprFunctorConstraint modType = match modType with
    | {Parsetree.pmty_desc = Pmty_functor _} -> true
    | _ -> false

  let bracedExpr expr = match expr.Parsetree.pexp_desc with
    | Pexp_constraint (
        {pexp_desc = Pexp_pack _},
        {ptyp_desc = Ptyp_package _}
      ) -> false
    | Pexp_constraint _ -> true
    | _ -> false
end
