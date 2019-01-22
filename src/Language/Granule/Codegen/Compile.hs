{-# LANGUAGE ImplicitParams #-}
module Language.Granule.Codegen.Compile where

import Control.Exception (SomeException)
import Language.Granule.Syntax.Def
import Language.Granule.Syntax.Type
import Language.Granule.Codegen.NormalisedDef
import Language.Granule.Codegen.TopsortDefinitions
import Language.Granule.Codegen.ConvertClosures
import Language.Granule.Codegen.EmitLLVM
import Language.Granule.Utils
import qualified LLVM.AST as IR
import Debug.Trace
import Language.Granule.Syntax.Pretty

compile :: String -> AST () Type -> Either SomeException IR.Module
compile moduleName typedAST =
    let ?globals       = defaultGlobals in
    let normalised     = normaliseDefinitions typedAST
        (Ok topsorted) = topologicallySortDefinitions normalised
        closureFree    = convertClosures topsorted
    in trace ("CFAST:\n" ++ pretty closureFree) (emitLLVM moduleName closureFree)
    -- NOTE Closures have the wrong type
