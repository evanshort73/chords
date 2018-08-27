module Colour exposing
  (borderOpacity, shineOpacity, fg, bg, swatchBg, pitchBg, ropeColor)

import Chord exposing (Chord)

import Dict exposing (Dict)

borderOpacity : Chord -> String
borderOpacity chord =
  if fg chord == "#ffffff" then "0.8" else "0.3"

shineOpacity : Chord -> String
shineOpacity chord =
  if fg chord == "#ffffff" then "0.6" else "0.7"

fg : Chord -> String
fg chord =
  case Dict.get chord.flavor schemes of
    Nothing ->
      black
    Just scheme ->
      scheme.fg

bg : Int -> Chord -> String
bg tonic chord =
  case Dict.get chord.flavor schemes of
    Nothing ->
      gray
    Just scheme ->
      case modBy 3 (chord.root - tonic) of
        0 -> scheme.c
        1 -> scheme.g
        _ -> scheme.f

swatchBg : Int -> Chord -> String
swatchBg tonic chord =
  case Dict.get chord.flavor swatchSchemes of
    Nothing ->
      swatchGray
    Just scheme ->
      case modBy 3 (chord.root - tonic) of
        0 -> scheme.c
        1 -> scheme.g
        _ -> scheme.f

pitchBg : Int -> Int -> String
pitchBg tonic pitch =
  case modBy 3 (pitch - tonic) of
    0 -> cyan
    1 -> pink
    _ -> yellow

ropeColor : Int -> Int -> String
ropeColor tonic pitch =
  case modBy 3 (pitch - tonic) of
    0 -> "#00ebf0"
    1 -> "#cb4dd6"
    _ -> "#cac200"

type alias Scheme =
  { fg : String
  , f : String
  , c : String
  , g : String
  }

schemes : Dict (List Int) Scheme
schemes =
  Chord.dict
    [ ( "", major )
    , ( "m", minor )
    , ( "o", diminished )
    , ( "7", dominant7 )
    , ( "M7", major7 )
    , ( "m7", minor7 )
    , ( "0", minor6 )
    , ( "o7", diminished )
    , ( "mM7", minor7 )
    , ( "9", dominant9 ) -- 7 + 0
    , ( "M9", major9 ) -- M7 + m7
    , ( "m9", major ) -- m7 + M7
    , ( "7b9", dominant9 ) -- 7 + o7
    , ( "M7#11", major7 ) -- M7 + M7
    , ( "13", dominant7 ) -- m7b9 + 7
    , ( "M13", major7 ) -- m9 + M9
    , ( "add9", major9 )
    , ( "madd9", major )
    , ( "addb9", dominant9 )
    , ( "add#11", minor7 )
    , ( "6", minor7 )
    , ( "m6", minor6 )
    , ( "+", allGray )
    , ( "sus4", allGray )
    , ( "sus2", allGray )
    ]

allGray : Scheme
allGray =
  { fg = black
  , f = gray
  , c = gray
  , g = gray
  }

major : Scheme
major =
  { fg = black
  , f = teal
  , c = purple
  , g = orange
  }

minor : Scheme
minor =
  { fg = black
  , f = lime
  , c = sky
  , g = rose
  }

major7 : Scheme
major7 =
  { fg = black
  , f = cyan
  , c = pink
  , g = yellow
  }

minor7 : Scheme
minor7 =
  { fg = black
  , f = green
  , c = blue
  , g = red
  }

dominant7 : Scheme
dominant7 =
  { fg = white
  , f = darkTeal
  , c = darkPurple
  , g = darkOrange
  }

minor6 : Scheme
minor6 =
  { fg = white
  , f = darkLime
  , c = darkSky
  , g = darkRose
  }

diminished : Scheme
diminished =
  { fg = white
  , f = darkYellow
  , c = darkCyan
  , g = darkPink
  }

major9 : Scheme
major9 = -- major7 + minor7
  { fg = black
  , f = sky
  , c = rose
  , g = lime
  }

dominant9 : Scheme
dominant9 = -- dominant7 + minor6
  { fg = white
  , f = darkCyan
  , c = darkPink
  , g = darkYellow
  }

minor13 : Scheme
minor13 =
  { fg = white
  , f = darkGreen
  , c = darkBlue
  , g = darkRed
  }

toHexPair : Int -> String
toHexPair n =
  let
    ones = modBy 16 n
    sixteens = n // 16
  in
    String.concat
      [ String.slice sixteens (sixteens + 1) "0123456789abcdef"
      , String.slice ones (ones + 1) "0123456789abcdef"
      ]

parseHexPair : Int -> String -> Int
parseHexPair offset s =
  16 * parseHexDigit (String.slice offset (offset + 1) s) +
    parseHexDigit (String.slice (offset + 1) (offset + 2) s)

parseHexDigit : String -> Int
parseHexDigit s =
  case s of
    "1" -> 1
    "2" -> 2
    "3" -> 3
    "4" -> 4
    "5" -> 5
    "6" -> 6
    "7" -> 7
    "8" -> 8
    "9" -> 9
    "a" -> 10
    "b" -> 11
    "c" -> 12
    "d" -> 13
    "e" -> 14
    "f" -> 15
    _ -> 0

black : String
black = "#000000"

white : String
white = "#ffffff"

gray : String
gray = "#cfcfcf"

red : String
red = "#ff997f"
orange : String
orange = "#ffad4c"
yellow : String
yellow = "#e9de28"
lime : String
lime = "#d6f446"
green : String
green = "#bdff8e"
teal : String
teal = "#9effd3"
cyan : String
cyan = "#7dfcff"
sky : String
sky = "#a2e1ff"
blue : String
blue = "#b7caff"
purple : String
purple = "#d0a0ff"
pink : String
pink = "#e86af3"
rose : String
rose = "#ff7da5"

darkRed : String
darkRed = "#822600"
darkOrange : String
darkOrange = "#784c00"
darkYellow : String
darkYellow = "#6b6600"
darkLime : String
darkLime = "#617400"
darkGreen : String
darkGreen = "#4a8525"
darkTeal : String
darkTeal = "#268662"
darkCyan : String
darkCyan = "#007d80"
darkSky : String
darkSky = "#007191"
darkBlue : String
darkBlue = "#0059a7"
darkPurple : String
darkPurple = "#4f139d"
darkPink : String
darkPink = "#6d0077"
darkRose : String
darkRose = "#800038"

swatchOpacity : Float
swatchOpacity = 0.7

swatchSchemes : Dict (List Int) Scheme
swatchSchemes = Dict.map (always fadeBg) schemes

swatchGray : String
swatchGray = fade swatchOpacity gray

fadeBg : Scheme -> Scheme
fadeBg scheme =
  if scheme.fg == "#000000" then
    { fg = "#000000"
    , f = fade swatchOpacity scheme.f
    , c = fade swatchOpacity scheme.c
    , g = fade swatchOpacity scheme.g
    }
  else
    scheme

fade : Float -> String -> String
fade opacity x =
  String.concat
    [ "#"
    , toHexPair (fadeChannel opacity (parseHexPair 1 x))
    , toHexPair (fadeChannel opacity (parseHexPair 3 x))
    , toHexPair (fadeChannel opacity (parseHexPair 5 x))
    ]

fadeChannel : Float -> Int -> Int
fadeChannel opacity channel =
  round (toFloat channel * opacity + 255 * (1 - opacity))
