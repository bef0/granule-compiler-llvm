{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
module Language.Granule.Codegen.TopsortDefinitions where

import Language.Granule.Syntax.Expr
import Language.Granule.Syntax.Identifiers
import Language.Granule.Codegen.NormalisedDef
import Language.Granule.Codegen.MarkGlobals

import Data.Set (Set)
import qualified Data.Set as Set
import Data.Either
import Data.Bifunctor.Foldable
import Data.Bifoldable

import Data.Graph
import Data.Tree

data TopsortResult ev a =
    Ok (NormalisedAST ev a)
    | RecursiveValues [ValueDef ev a]
    | InitializationCycle [FunctionDef ev a] [ValueDef ev a]

deriving instance (Show ev, Show a) => Show (TopsortResult ev a)
deriving instance (Eq ev, Eq a) => Eq (TopsortResult ev a)

topologicallySortDefinitions ::  NormalisedAST GlobalMarker a -> TopsortResult GlobalMarker a
topologicallySortDefinitions (NormalisedAST dataDefs functionDefs valueDefs)
  | any isRecursiveValue valueDefs =
      RecursiveValues $ filter isRecursiveValue valueDefs
  | otherwise =
      case topSortValueDefinitions functionDefs valueDefs of
        Right (cyclicalFunctionDefs, cyclicalValueDefs) ->
          InitializationCycle cyclicalFunctionDefs cyclicalValueDefs
        Left sortedValueDefs ->
          Ok $ NormalisedAST dataDefs functionDefs (reverse sortedValueDefs)

type BadDefs a = ([FunctionDef GlobalMarker a], [ValueDef GlobalMarker a])

topSortValueDefinitions :: [FunctionDef GlobalMarker a]
                        -> [ValueDef GlobalMarker a]
                        -> Either [ValueDef GlobalMarker a] (BadDefs a)
topSortValueDefinitions functionDefs valueDefs =
    let (depGraph, vertexToNode, _) = dependencyGraph functionDefs valueDefs
        sccs = map flatten $ scc depGraph
        cycles = [vertexToNode <$> cyc | cyc <- sccs, cyc `longerThan` 1]
        forbiddenCycles = filter (any isRight) cycles
    in
      case forbiddenCycles of
        [] -> Left $ rights (vertexToNode <$> topSort depGraph)
        (badDefs:_) -> Right (lefts badDefs, rights badDefs)

dependencyGraph :: [FunctionDef GlobalMarker a]
                -> [ValueDef GlobalMarker a]
                -> (Graph, Vertex -> Either (FunctionDef GlobalMarker a) (ValueDef GlobalMarker a), Id -> Maybe Vertex)
dependencyGraph functionDefs valueDefs =
    let graph = graphFromEdges $ map functionNode functionDefs ++ map valueNode valueDefs
                where
                  functionNode def = (Left def,  functionDefIdentifier def, edges $ functionDefBody def)
                  valueNode    def = (Right def, valueDefIdentifier def, edges $ valueDefInitializer def)
                  edges        expr = Set.toList $ expressionDependencies definitionIds expr
                  definitionIds    = allDefinitionIds functionDefs valueDefs
    in let (g, vertexToNode, keyToVertex) = graph
       in (g, (\(~(n, _, _)) -> n) . vertexToNode, keyToVertex)

expressionDependencies :: [Id] -> Expr GlobalMarker a -> Set Id
expressionDependencies defIds expr =
    referencedDefinitions expr defIds

referencedDefinitions :: Expr GlobalMarker a -> [Id] -> Set Id
referencedDefinitions ex defIds =
    Set.filter (`elem` defIds) $ bicata exprDeps valueDeps ex
    where valueDeps (ExtF _ (GlobalVar _ ident)) = Set.singleton ident
          valueDeps other = bifold other
          exprDeps = bifold

longerThan :: [a] -> Int -> Bool
longerThan list count = length list > count

allDefinitionIds :: [FunctionDef GlobalMarker a] -> [ValueDef GlobalMarker a] -> [Id]
allDefinitionIds functionDefs valueDefs =
    map functionDefIdentifier functionDefs ++ map valueDefIdentifier valueDefs

isRecursiveValue :: ValueDef GlobalMarker a -> Bool
isRecursiveValue def =
    not $ Set.null $ expressionDependencies [valueDefIdentifier def] (valueDefInitializer def)
