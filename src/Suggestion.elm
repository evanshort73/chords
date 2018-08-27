module Suggestion exposing
  (Suggestion, Msg(..), view, sort, groupByReplacement)

import Substring exposing (Substring)
import Swatch exposing (Swatch)

import Dict exposing (Dict)
import Html exposing (Html, span, button)
import Html.Attributes exposing (style)
import Html.Events exposing
  (onMouseEnter, onMouseLeave, onFocus, onBlur, onClick)

type alias Suggestion =
  { swatches : List Swatch
  , ranges : List Substring
  }

type Msg
  = Hover Bool
  | Focus Bool
  | Replace

view : List Swatch -> Html Msg
view swatches =
  button
    [ onMouseEnter (Hover True)
    , onMouseLeave (Hover False)
    , onFocus (Focus True)
    , onBlur (Focus False)
    , onClick Replace
    , style "font-family" "\"Lucida Console\", Monaco, monospace"
    , style "font-size" "160%"
    , style "padding" "0"
    , style "min-width" "3ch"
    ]
    [ span
        [ style "background" "white"
        , style "padding" "0 8px"
        , style "display" "block"
        ]
        (List.map Swatch.view swatches)
    ]

sort : List Suggestion -> List Suggestion
sort = List.sortBy (List.map .i << .ranges)

groupByReplacement : List ( List Swatch, Substring ) -> List Suggestion
groupByReplacement suggestions =
  Dict.values (groupByReplacementHelp suggestions)

reverseRanges : Suggestion -> Suggestion
reverseRanges suggestion =
  { suggestion | ranges = List.reverse suggestion.ranges }

groupByReplacementHelp :
  List ( List Swatch, Substring ) -> Dict String Suggestion
groupByReplacementHelp suggestions =
  case suggestions of
    [] -> Dict.empty
    ( swatches, range ) :: rest ->
      Dict.update
        (Swatch.concat swatches)
        (addRange swatches range)
        (groupByReplacementHelp rest)

addRange : List Swatch -> Substring -> Maybe Suggestion -> Maybe Suggestion
addRange swatches range maybeSuggestion =
  case maybeSuggestion of
    Nothing ->
      Just { swatches = swatches, ranges = [ range ] }
    Just suggestion ->
      Just { suggestion | ranges = range :: suggestion.ranges }
