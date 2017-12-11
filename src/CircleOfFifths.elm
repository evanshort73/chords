module CircleOfFifths exposing (chordCount, view, Msg(..))

import CachedChord
import ChordParser exposing (IdChord)
import CustomEvents exposing (onLeftDown, onLeftClick, onKeyDown)
import Player exposing (PlayStatus)

import Html exposing (Html)
import Html.Attributes exposing (attribute, style)
import Svg exposing (Svg, svg, defs, linearGradient, path, text_, rect)
import Svg.Attributes exposing
  ( width, height, viewBox
  , d, fill, opacity
  , stroke, strokeWidth, strokeLinejoin, strokeDasharray, strokeOpacity
  , x1, y1, x2, y2
  , textAnchor
  )

chordCount : Int
chordCount = 24

getMajorChords : Int -> Int -> List IdChord
getMajorChords octaveBase rotation =
  List.map
    (nthMajorChord 0 octaveBase)
    (List.range rotation (rotation + 11))

nthMajorChord : Int -> Int -> Int -> IdChord
nthMajorChord firstId octaveBase i =
  { id = firstId + i % 12
  , cache =
      CachedChord.fromChord
        ( List.map
            ((+) (octaveBase + (7 * i - octaveBase) % 12))
            [ 0, 4, 7 ]
        )
  }

getMinorChords : Int -> Int -> List IdChord
getMinorChords octaveBase rotation =
  List.map
    (nthMinorChord 12 octaveBase)
    (List.range rotation (rotation + 11))

nthMinorChord : Int -> Int -> Int -> IdChord
nthMinorChord firstId octaveBase i =
  { id = firstId + i % 12
  , cache =
      CachedChord.fromChord
        ( List.map
            ((+) (octaveBase + (7 * i + 9 - octaveBase) % 12))
            [ 0, 3, 7 ]
        )
  }

type Msg
  = PlayChord ( IdChord )
  | StopChord

view : Int -> Int -> PlayStatus -> Html Msg
view octaveBase key playStatus =
  let
    rInner = 100
  in let
    rOuter = 247.5
  in let
    rMid = areaAverage 100 247.5
  in let
    rotation = 7 * key
  in let
    majorChords = getMajorChords octaveBase rotation
  in let
    minorChords = getMinorChords octaveBase rotation
  in let
    stopButtonId =
      if playStatus.stoppable then playStatus.active else -1
  in
    Html.span
      [ style
          [ ( "position", "relative" )
          , ( "display", "inline-block" )
          , ( "font-size", "18pt" )
          , ( "text-align", "center" )
          , ( "-webkit-touch-callout", "none" )
          , ( "-webkit-user-select", "none" )
          , ( "-khtml-user-select", "none" )
          , ( "-moz-user-select", "none" )
          , ( "-ms-user-select", "none" )
          , ( "user-select", "none" )
          ]
      ]
      ( List.concat
          [ [ Svg.svg
                [ width "500"
                , height "500"
                , viewBox "0 0 500 500"
                ]
                ( List.concat
                    [ [ gradients ]
                    , keyShadow
                    , List.concat
                        ( List.indexedMap
                            (viewChord key playStatus rMid rOuter)
                            majorChords
                        )
                    , List.concat
                        ( List.indexedMap
                            (viewChord key playStatus rInner rMid)
                            minorChords
                        )
                    ]
                )
            ]
          , List.indexedMap
              (viewChordText stopButtonId (0.5 * (rMid + rOuter)))
              majorChords
          , List.indexedMap
              (viewChordText stopButtonId (0.5 * (rInner + rMid)))
              minorChords
          ]
      )

gradients : Svg msg
gradients =
  defs []
    [ linearGradient
        [ Svg.Attributes.id "twelfthShine"
        , x1 "0%", y1 "0%", x2 "10%", y2 "100%"
        ]
        [ Svg.stop
            [ Svg.Attributes.offset "0%"
            , style [ ( "stop-color", "white" ), ( "stop-opacity", "1" ) ]
            ]
            []
        , Svg.stop
            [ Svg.Attributes.offset "60%"
            , style [ ( "stop-color", "white" ), ( "stop-opacity", "0" ) ]
            ]
            []
        ]
    ]

keyShadow : List (Svg msg)
keyShadow =
  [ path
      [ fill "lightgray"
      , stroke "lightgray"
      , strokeWidth "5"
      , strokeLinejoin "round"
      , d
          ( paddedWedge 5
              97.5 250
              (2 * pi * 9 / 24) (2 * pi * 3 / 24)
          )
      ]
      []
  , path
      [ fill "lightgray"
      , stroke "lightgray"
      , strokeWidth "5"
      , strokeLinejoin "round"
      , d
          ( paddedWedge 5
              (areaAverage 100 247.5) 250
              (2 * pi * -1 / 24) (2 * pi * -3 / 24)
          )
      ]
      []
  ]

areaAverage : Float -> Float -> Float
areaAverage x y =
  sqrt (0.5 * (x * x + y * y))

viewChord :
  Int -> PlayStatus -> Float -> Float -> Int -> IdChord -> List (Svg Msg)
viewChord key playStatus rInner rOuter i chord =
  List.filterMap
    identity
    [ if playStatus.active == chord.id || playStatus.next == chord.id then
        Just
          ( path
              [ fill "none"
              , stroke "#3399ff"
              , strokeWidth "5"
              , strokeLinejoin "round"
              , strokeDasharray
                  (if playStatus.next == chord.id then "10, 10" else "none")
              , d (twelfth 0 rInner rOuter i)
              ]
              []
          )
      else
        Nothing
    , let
        stopButton = playStatus.active == chord.id && playStatus.stoppable
      in let
        play =
          if stopButton then StopChord
          else PlayChord chord
      in
        Just
          ( path
              [ onLeftDown play
              , onKeyDown
                  [ ( 13, play )
                  , ( 32, play )
                  ]
              , fill (CachedChord.bg key chord.cache)
              , attribute "tabindex" "0"
              , style [ ( "cursor", "pointer" ) ]
              , d (twelfth 5 rInner rOuter i)
              ]
              []
          )
    , Just
        ( path
            [ fill "url(#twelfthShine)"
            , opacity (CachedChord.shineOpacity chord.cache)
            , d (twelfth 7 rInner rOuter i)
            , style [ ( "pointer-events", "none" ) ]
            ]
            []
        )
    , Just
        ( path
            [ fill "none"
            , stroke "black"
            , strokeOpacity (CachedChord.borderOpacity chord.cache)
            , d (twelfth 6 rInner rOuter i)
            , style [ ( "pointer-events", "none" ) ]
            ]
            []
        )
    ]


viewChordText : Int -> Float -> Int -> IdChord -> Html msg
viewChordText stopButtonId r i chord =
  let
    ( x, y ) =
      polar r (2 * pi * (0.25 - toFloat i / 12))
  in
    if chord.id == stopButtonId then
      Html.span
        [ style
            [ ( "position", "absolute" )
            , ( "left", toString (x - 10) ++ "px" )
            , ( "top", toString (y - 10) ++ "px" )
            , ( "pointer-events", "none" )
            , ( "background", CachedChord.fg chord.cache )
            , ( "width", "20px" )
            , ( "height", "20px" )
            ]
        ]
        []
    else
      Html.span
        [ style
            [ ( "position", "absolute" )
            , ( "left", toString (x - 0.5 * 75) ++ "px" )
            , ( "top", toString (y - 0.5 * 75) ++ "px" )
            , ( "pointer-events", "none" )
            , ( "line-height", "75px" )
            , ( "color", CachedChord.fg chord.cache )
            ]
        ]
        [ Html.span
            [ style
                [ ( "display", "inline-block" )
                , ( "width", "75px" )
                ]
            ]
            (CachedChord.view chord.cache)
        ]

twelfth : Float -> Float -> Float -> Int -> String
twelfth padding rInner rOuter i =
  paddedWedge
    padding
    rInner
    rOuter
    (2 * pi * (0.25 - (-0.5 + toFloat i) / 12))
    (2 * pi * (0.25 - (0.5 + toFloat i) / 12))

paddedWedge : Float -> Float -> Float -> Float -> Float -> String
paddedWedge padding rInner rOuter early late =
  let
    innerPadding = 0.5 * padding / rInner
  in let
    outerPadding = 0.5 * padding / rOuter
  in
    wedge
      (rInner + 0.5 * padding) (rOuter - 0.5 * padding)
      (early - innerPadding) (early - outerPadding)
      (late + innerPadding) (late + outerPadding)

wedge : Float -> Float -> Float -> Float -> Float -> Float -> String
wedge rInner rOuter earlyInner earlyOuter lateInner lateOuter =
  String.join
    " "
    [ moveTo (polar rOuter earlyOuter)
    , arc rOuter True (polar rOuter lateOuter)
    , lineTo (polar rInner lateInner)
    , arc rInner False (polar rInner earlyInner)
    , closePath
    ]

polar : Float -> Float -> ( Float, Float )
polar r a =
  ( 250 + r * cos a, 250 - r * sin a )

moveTo : ( Float, Float ) -> String
moveTo ( x, y ) =
  "M" ++ toString x ++ "," ++ toString y

lineTo : ( Float, Float ) -> String
lineTo ( x, y ) =
  "L" ++ toString x ++ "," ++ toString y

arc : Float -> Bool -> ( Float, Float ) -> String
arc r clockwise ( x, y ) =
  String.concat
    [ "A"
    , toString r
    , ","
    , toString r
    , " 0 0,"
    , if clockwise then "1" else "0"
    , " "
    , toString x
    , ","
    , toString y
    ]

closePath : String
closePath = "Z"