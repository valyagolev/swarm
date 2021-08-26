{-# LANGUAGE OverloadedStrings #-}

module Swarm.Typecheck where

import           Data.Map    (Map)
import qualified Data.Map    as M
import           Data.Text   (Text)

import           Swarm.AST
import           Swarm.Types


------------------------------------------------------------
-- Type errors

data TypeErr
  = NotFunTy Term Type
  | NotCmdTy Term Type
  | Mismatch Term {- expected -} Type {- inferred -} Type
  | UnboundVar Text
  | CantInfer Term

------------------------------------------------------------
-- Type inference / checking

type Ctx = Map Text Type

infer :: Ctx -> Term -> Either TypeErr Type
infer _ TUnit         = return TyUnit
infer _ (TConst c)    = inferConst c
infer _ (TDir _)      = return TyDir
infer _ (TInt _)      = return TyInt
infer _ (TString _)   = return TyString
infer ctx (TVar x)    = maybe (Left (UnboundVar x)) Right (M.lookup x ctx)
infer ctx (TLam x (Just argTy) t) = do
  resTy <- infer (M.insert x argTy ctx) t
  return (argTy :->: resTy)
infer ctx (TApp f x)    = do
  (ty1, ty2) <- inferFunTy ctx f
  check ctx x ty1
  return ty2
infer ctx (TLet x Nothing t1 t2) = do
  xTy <- infer ctx t1
  infer (M.insert x xTy ctx) t2
infer ctx (TLet x (Just xTy) t1 t2) = do
  check ctx t1 xTy
  infer (M.insert x xTy ctx) t2
infer ctx (TBind mx c1 c2) = do
  a <- decomposeCmdTy c1 =<< infer ctx c1
  cmdb <- infer (maybe id (`M.insert` a) mx ctx) c2
  _ <- decomposeCmdTy c2 cmdb
  return cmdb
infer _ TNop          = return $ TyCmd TyUnit
infer _ t             = Left $ CantInfer t

decomposeCmdTy :: Term -> Type -> Either TypeErr Type
decomposeCmdTy _ (TyCmd resTy) = return resTy
decomposeCmdTy t ty            = Left (NotCmdTy t ty)

-- | The types of some constants can be inferred.  Others (e.g. those
--   that are overloaded) must be checked.
inferConst :: Const -> Either TypeErr Type
inferConst Wait    = return $ TyCmd TyUnit
inferConst Move    = return $ TyCmd TyUnit
inferConst Turn    = return $ TyDir :->: TyCmd TyUnit
inferConst Harvest = return $ TyCmd TyUnit
inferConst Repeat  = return $ TyInt :->: TyCmd TyUnit :->: TyCmd TyUnit
inferConst Build   = return $ TyCmd TyUnit :->: TyCmd TyUnit
inferConst Run     = return $ TyString :->: TyCmd TyUnit
inferConst GetX    = return $ TyCmd TyInt
inferConst GetY    = return $ TyCmd TyInt

inferFunTy :: Ctx -> Term -> Either TypeErr (Type, Type)
inferFunTy ctx t = infer ctx t >>= decomposeFunTy t

decomposeFunTy :: Term -> Type -> Either TypeErr (Type, Type)
decomposeFunTy _ (ty1 :->: ty2) = return (ty1, ty2)
decomposeFunTy t ty             = Left (NotFunTy t ty)

check :: Ctx -> Term -> Type -> Either TypeErr ()
check _ (TConst c) ty = checkConst c ty
check ctx t@(TLam x Nothing body) ty = do
  (ty1, ty2) <- decomposeFunTy t ty
  check (M.insert x ty1 ctx) body ty2
check ctx (TApp t1 t2) ty = do
  ty2 <- infer ctx t2
  check ctx t1 (ty2 :->: ty)

-- Fall-through case: switch into inference mode
check ctx t ty          = infer ctx t >>= checkEqual t ty

checkEqual :: Term -> Type -> Type -> Either TypeErr ()
checkEqual t ty ty'
  | ty == ty' = return ()
  | otherwise = Left (Mismatch t ty ty')

checkConst :: Const -> Type -> Either TypeErr ()
-- No cases for now!  Add some cases once constants become overloaded.

-- Fall-through case
checkConst c ty = inferConst c >>= checkEqual (TConst c) ty
