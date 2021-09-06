{-# LANGUAGE OverloadedStrings #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Swarm.Language.Elaborate
-- Copyright   :  Brent Yorgey
-- Maintainer  :  byorgey@gmail.com
--
-- SPDX-License-Identifier: BSD-3-Clause
--
-- Term elaboration which happens after type checking.
--
-----------------------------------------------------------------------------


module Swarm.Language.Elaborate where

import           Swarm.Language.Syntax
import           Swarm.Language.Types

-- | Perform some elaboration / rewriting on a fully type-annotated
--   term, given its top-level type.  This currently performs such
--   operations as rewriting @if@ expressions and recursive let
--   expressions to use laziness appropriately.  In theory it could
--   also perform rewriting for overloaded constants depending on the
--   actual type they are used at, but currently that sort of thing
--   tends to make type inference fall over.
elaborate :: Type -> ATerm -> ATerm
elaborate = bottomUp rewrite
  where
    -- if cond thn els ---> force (if cond (delay thn) (delay els))
    -- When if is evaluated, its arguments are eagerly evaluated, just
    -- like any function application.  This ensures that evaluation of
    -- the arguments is delayed until one of them is chosen by the if.
    rewrite _ (TApp resTy (TApp _ (TApp condTy (TConst If) cond) thn) els)
      = TApp resTy (TConst Force) (TApp resTy (TApp resTy (TApp condTy (TConst If) cond) (TDelay thn)) (TDelay els))

    -- Rewrite any recursive occurrences of x inside t1 to (force x).
    -- When interpreting t1, we will put a binding (x |-> delay t1)
    -- in the context.
    rewrite _ (TLet x ty t1 t2) = TLet x ty (mapFree x (TApp ty (TConst Force)) t1) t2

    -- Rewrite any recursive occurrences of x inside t1 to (force x).
    -- When interpreting t1, we will put a binding (x |-> delay t1)
    -- in the context.
    rewrite _ (TDef x ty t1) = TDef x ty (mapFree x (TApp ty (TConst Force)) t1)

    -- Delay evaluation of the program argument to a 'Build' command,
    -- so it will be evaluated by the constructed robot instead of the one
    -- doing the constructing.
    rewrite _ (TApp ty1 (TApp ty2 (TConst Build) nm) prog)
      = TApp ty1 (TApp ty2 (TConst Build) nm) (TDelay prog)

    -- Leave any other subterms alone.
    rewrite _ t = t
