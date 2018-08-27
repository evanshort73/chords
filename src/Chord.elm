module Chord exposing
  ( Chord, fromCode, fromCodeExtended, maxRange, transpose, toPitchSet
  , fromPitchSet, toPitches, dict, list, flavors
  )

import Pitch
import Submatches exposing (submatches)

import Dict exposing (Dict)
import Regex exposing (Regex)
import Set exposing (Set)

type alias Chord =
  { flavor : List Int
  , root : Int
  }

fromCode : String -> Maybe Chord
fromCode code =
  case submatches regex code of
    [ Just rootCode, maybeFlavorCode ] ->
      case Dict.get (Maybe.withDefault "" maybeFlavorCode) flavorDict of
        Nothing ->
          Nothing
        Just flavor ->
          Just
            { flavor = flavor
            , root = Pitch.fromCode rootCode
            }
    _ ->
      Nothing

fromCodeExtended : String -> Maybe Chord
fromCodeExtended code =
  case fromCode code of
    Just chord ->
      Just chord
    Nothing ->
      let
        words =
          List.filter
            (not << String.isEmpty)
            (String.split " " code)
      in
      let
        pitches = List.filterMap String.toInt words
      in
        if List.length pitches < List.length words then
          Nothing
        else
          case removeDuplicates (List.sort pitches) of
            [] ->
              Nothing
            rootPitch :: flavorPitches ->
              let
                tallFlavor =
                  List.map ((+) -rootPitch) flavorPitches
              in
                Just
                  { flavor =
                      List.filter ((>=) maxRange) tallFlavor
                  , root = modBy 12 rootPitch
                  }

removeDuplicates : List a -> List a
removeDuplicates xs =
  case xs of
    x :: y :: rest ->
      if x == y then
        removeDuplicates (y :: rest)
      else
        x :: removeDuplicates (y :: rest)
    other ->
      other

maxRange : Int
maxRange = 23

regex : Regex
regex =
  Maybe.withDefault
    Regex.never
    (Regex.fromString "^([A-Ga-g][b#♭♯]?)(.*)")

dict : List (String, a) -> Dict (List Int) a
dict codePairs =
  Dict.fromList (dictHelp codePairs flavorPairs)

dictHelp : List (String, a) -> List (String, List Int) -> List (List Int, a)
dictHelp codePairs remainingFlavorPairs =
  case ( codePairs, remainingFlavorPairs ) of
    ( ( code, value ) :: laterCodePairs, ( rightCode, flavor ) :: laterFlavorPairs ) ->
      if code == rightCode then
        ( flavor, value ) ::
          dictHelp laterCodePairs laterFlavorPairs
      else
        Debug.todo
          ( String.concat
              [ "Chord.dict: Expected \""
              , rightCode
              , "\", got \""
              , code
              , "\""
              ]
          )
    ( [], [] ) ->
      []
    _ ->
      Debug.todo "Chord.dict: Wrong number of pairs"

list : List String -> List (List Int)
list codeList =
  List.map listHelp codeList

listHelp : String -> List Int
listHelp code =
  case Dict.get code flavorDict of
    Nothing ->
      Debug.todo
        ("Chord.list: Unknown flavor \"" ++ code ++ "\"")
    Just flavor ->
      flavor

flavorDict : Dict String (List Int)
flavorDict =
  Dict.fromList flavorPairs

flavors : List (List Int)
flavors =
  List.map Tuple.second flavorPairs

flavorPairs : List (String, (List Int))
flavorPairs =
  [ ( "", [ 4, 7 ] )
  , ( "m", [ 3, 7 ] )
  , ( "o", [ 3, 6 ] )
  , ( "7", [ 4, 7, 10 ] )
  , ( "M7", [ 4, 7, 11 ] )
  , ( "m7", [ 3, 7, 10 ] )
  , ( "0", [ 3, 6, 10 ] )
  , ( "o7", [ 3, 6, 9 ] )
  , ( "mM7", [ 3, 7, 11 ] )
  , ( "9", [ 4, 7, 10, 14 ] )
  , ( "M9", [ 4, 7, 11, 14 ] )
  , ( "m9", [ 3, 7, 10, 14 ] )
  , ( "7b9", [ 4, 7, 10, 13 ] )
  , ( "M7#11", [ 4, 7, 11, 14, 18 ] )
  , ( "13", [ 4, 7, 10, 14, 21 ] )
  , ( "M13", [ 4, 7, 11, 14, 21 ] )
  , ( "add9", [ 4, 7, 14 ] )
  , ( "madd9", [ 3, 7, 14 ] )
  , ( "addb9", [ 4, 7, 13 ] )
  , ( "add#11", [ 4, 7, 18 ] )
  , ( "6", [ 4, 7, 9 ] )
  , ( "m6", [ 3, 7, 9 ] )
  , ( "+", [ 4, 8 ] )
  , ( "sus4", [ 5, 7 ] )
  , ( "sus2", [ 2, 7 ] )
  ]

transpose : Int -> Chord -> Chord
transpose offset chord =
  { chord | root = modBy 12 (chord.root + offset) }

toPitchSet : Int -> Int -> Maybe Chord -> Set Int
toPitchSet lowestPitch octave maybeChord =
  case maybeChord of
    Nothing ->
      Set.empty
    Just chord ->
      let
        rootPitch =
          modBy 12 (chord.root - lowestPitch) +
            lowestPitch +
            12 * octave
      in
        Set.fromList
          (List.map ((+) rootPitch) (0 :: chord.flavor))

fromPitchSet : Int -> Set Int -> Maybe (Chord, Int)
fromPitchSet lowestPitch pitchSet =
  case Set.toList pitchSet of
    [] ->
      Nothing
    rootPitch :: flavorPitches ->
      Just
        ( Chord
            (List.map ((+) -rootPitch) flavorPitches)
            (modBy 12 rootPitch)
        , ( rootPitch - lowestPitch -
              modBy 12 (rootPitch - lowestPitch)
          ) //
            12
        )

toPitches : Int -> Chord -> List Int
toPitches lowestPitch chord =
  let
    rootPitch =
      modBy 12 (chord.root - lowestPitch) + lowestPitch
  in
    rootPitch :: List.map ((+) rootPitch) chord.flavor
