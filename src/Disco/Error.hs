{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE StandaloneDeriving #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Disco.Error
-- Copyright   :  disco team and contributors
-- Maintainer  :  byorgey@gmail.com
--
-- SPDX-License-Identifier: BSD-3-Clause
--
-- Type for collecting all potential Disco errors at the top level,
-- and a type for runtime errors.
--
-----------------------------------------------------------------------------

module Disco.Error (DiscoError(..), EvalError(..), outputDiscoErrors) where

import           Control.Monad                    ((<=<))
import           Prelude                          hiding ((<>))

import           Text.Megaparsec                  (ParseErrorBundle,
                                                   errorBundlePretty)
import           Unbound.Generics.LocallyNameless (Name)

import           Disco.Effects.LFresh
import           Polysemy
import           Polysemy.Error
import           Polysemy.Output
import           Polysemy.Reader

import           Disco.Messages
import           Disco.Names                      (ModuleName)
import           Disco.Parser
import           Disco.Pretty
import           Disco.Typecheck.Util             (TCError)

-- | Top-level error type for Disco.
data DiscoError where

  -- | Module not found.
  ModuleNotFound :: String -> DiscoError

  -- | Cyclic import encountered.
  CyclicImport :: [ModuleName] -> DiscoError

  -- | Error encountered during typechecking.
  TypeCheckErr :: TCError -> DiscoError

  -- | Error encountered during parsing.
  ParseErr :: ParseErrorBundle String DiscoParseError -> DiscoError

  -- | Error encountered at runtime.
  EvalErr :: EvalError -> DiscoError

  -- | Something that shouldn't happen; indicates the presence of a
  --   bug.
  Panic         :: String    -> DiscoError

  deriving Show

-- | Errors that can be generated at runtime.
data EvalError where

  -- | An unbound name.
  UnboundError  :: Name core  -> EvalError

  -- | Division by zero.
  DivByZero     ::              EvalError

  -- | Underflow, e.g. (2 - 3 : Nat)
  Underflow     ::              EvalError

  -- | Overflow, e.g. (2^66)!
  Overflow      ::              EvalError

  -- | Non-exhaustive case analysis.
  NonExhaustive ::              EvalError

  -- | Infinite loop detected via black hole.
  InfiniteLoop  ::              EvalError

  -- | User-generated crash.
  Crash         :: String    -> EvalError

deriving instance Show EvalError

outputDiscoErrors :: Member (Output Message) r => Sem (Error DiscoError ': r) () -> Sem r ()
outputDiscoErrors m = do
  e <- runError m
  either (err <=< runLFresh . renderDoc . prettyDiscoError) return e

prettyDiscoError :: Members '[Reader PA, LFresh] r => DiscoError -> Sem r Doc
prettyDiscoError = \case
  ModuleNotFound m -> "Error: couldn't find a module named '" <> text m <> "'."
  CyclicImport ms  -> cyclicImportError ms
  TypeCheckErr te  -> prettyTCError te
  ParseErr pe      -> text (errorBundlePretty pe)
  EvalErr ee       -> prettyEvalError ee
  Panic s          ->
    hcat
      [ "Bug! " <> text s
      , "Please report this as a bug at https://github.com/disco-lang/disco/issues/"
      ]

cyclicImportError
  :: Members '[Reader PA, LFresh] r
  => [ModuleName] -> Sem r Doc
cyclicImportError ms =
  vcat
    [ "Error: module imports form a cycle:"
    , nest 2 $ intercalate " ->" (map pretty ms)
    ]

prettyTCError :: Members '[Reader PA, LFresh] r => TCError -> Sem r Doc
prettyTCError = text . show . TypeCheckErr

prettyEvalError :: Members '[Reader PA, LFresh] r => EvalError -> Sem r Doc
prettyEvalError = text . show . EvalErr
