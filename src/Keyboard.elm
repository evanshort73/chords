module Keyboard exposing (Keyboard, init, Msg(..), UpdateResult, update, view)

import AudioChange exposing (AudioChange(..))
import Chord exposing (Chord)
import Colour
import CustomEvents exposing
  ( isAudioTimeButton, onClickWithAudioTime
  , isAudioTimeInput, onInputWithAudioTime, onIntInputWithAudioTime
  )
import Harp exposing
  ( viewBoxLeft, viewBoxRight, isWhiteKey, neckLeft, headLeft
  , borderWidth, headWidth, scale
  )
import IdChord exposing (IdChord)
import Name
import Note exposing (Note)
import Path
import Ports exposing (Pluck)
import Selection exposing (Selection)

import Html exposing (Html, span, text, input, button)
import Html.Attributes as Attributes exposing (attribute, style, class, id)
import Html.Events exposing (onInput, onClick)
import Set exposing (Set)
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Lazy

type alias Keyboard =
  { customCode : String
  , customOctave : Int
  }

init : Keyboard
init =
  { customCode = ""
  , customOctave = 0
  }

getCode : Selection -> Keyboard -> String
getCode selection keyboard =
  case selection of
    Selection.Static (Just idChord) ->
      Name.code idChord.chord
    Selection.Static Nothing ->
      ""
    Selection.Dynamic player ->
      case List.drop (player.unfinishedCount - 1) player.schedule of
        current :: _ ->
          Name.code current.chord
        _ ->
          ""
    Selection.Custom ->
      keyboard.customCode

getChord : Selection -> Keyboard -> Maybe Chord
getChord selection keyboard =
  case selection of
    Selection.Static maybeIdChord ->
      Maybe.map .chord maybeIdChord
    Selection.Dynamic player ->
      case List.drop (player.unfinishedCount - 1) player.schedule of
        current :: _ ->
          Just current.chord
        _ ->
          Nothing
    Selection.Custom ->
      Chord.fromCodeExtended keyboard.customCode

getOctave : Selection -> Keyboard -> Int
getOctave selection keyboard =
  if selection == Selection.Custom then
    keyboard.customOctave
  else
    0

type Msg
  = SetCode (String, Float)
  | SetOctave (Int, Float)
  | AddPitch (Int, Int, Float)
  | RemovePitch (Int, Int, Float)
  | HarpPlucked Pluck
  | AddWord String

type alias UpdateResult msg =
  { selectionPlucked : Bool
  , selection : Selection
  , keyboard : Keyboard
  , sequence : List Chord
  , cmd : Cmd msg
  }

update : Msg -> Bool -> Selection -> Keyboard -> UpdateResult msg
update msg selectionPlucked selection keyboard =
  case msg of
    SetCode ( code, now ) ->
      { selectionPlucked = False
      , selection =
          if code == "" then
            Selection.Static Nothing
          else
            Selection.Custom
      , keyboard =
          { customCode = code
          , customOctave = getOctave selection keyboard
          }
      , sequence = Selection.sequenceAtTime now selection
      , cmd =
          case ( selection, selectionPlucked ) of
            ( Selection.Dynamic _, False ) ->
              AudioChange.perform [ Mute now ]
            _ ->
              Cmd.none
      }

    SetOctave ( octave, now ) ->
      { selectionPlucked = False
      , selection = Selection.Custom
      , keyboard =
          { customCode = getCode selection keyboard
          , customOctave = octave
          }
      , sequence = Selection.sequenceAtTime now selection
      , cmd =
          case ( selection, selectionPlucked ) of
            ( Selection.Dynamic _, False ) ->
              AudioChange.perform [ Mute now ]
            _ ->
              Cmd.none
      }

    AddPitch ( lowestPitch, pitch, now ) ->
      let
        pitchSet =
          Chord.toPitchSet
            lowestPitch
            (getOctave selection keyboard)
            (getChord selection keyboard)
      in
      let
        newPitchSet =
          Set.filter
            ( inRange
                (pitch - Chord.maxRange)
                (pitch + Chord.maxRange)
            )
            (Set.insert pitch pitchSet)
      in
      let
        ( newChord, newOctave ) =
          case Chord.fromPitchSet lowestPitch newPitchSet of
            Just x ->
              x
            Nothing ->
              Debug.todo
                "Keyboard.update: Pitch set empty after inserting pitch"
      in
        { selectionPlucked = True
        , selection = Selection.Custom
        , keyboard =
            { customCode = Name.codeExtended newChord
            , customOctave = newOctave
            }
        , sequence = Selection.sequenceAtTime now selection
        , cmd =
            AudioChange.perform
              ( ( if selectionPlucked then
                    []
                  else
                    [ Mute now ]
                ) ++
                  [ AddPianoNote
                      { v = 1
                      , t = now
                      , f = pitchFrequency pitch
                      }
                  ]
              )
        }

    RemovePitch ( lowestPitch, pitch, now ) ->
      let
        pitchSet =
          Chord.toPitchSet
            lowestPitch
            (getOctave selection keyboard)
            (getChord selection keyboard)
      in
      let
        newPitchSet =
          Set.remove pitch pitchSet
      in
        { selectionPlucked = True
        , selection =
            if Set.isEmpty newPitchSet then
              Selection.Static Nothing
            else
              Selection.Custom
        , keyboard =
            case Chord.fromPitchSet lowestPitch newPitchSet of
              Just ( newChord, newOctave ) ->
                { customCode = Name.codeExtended newChord
                , customOctave = newOctave
                }
              Nothing ->
                { customCode = ""
                , customOctave = 0
                }
        , sequence = Selection.sequenceAtTime now selection
        , cmd =
            AudioChange.perform
              [ if selectionPlucked then
                  NoteOff
                    { v = 1
                    , t = now
                    , f = pitchFrequency pitch
                    }
                else
                  Mute now
              ]
        }

    HarpPlucked pluck ->
      let
        changes =
          List.append
            ( List.map
                ( NoteOff <<
                    Note 1 pluck.now <<
                      pitchFrequency
                )
                pluck.mutes
            )
            ( List.map
                ( AddGuitarNote <<
                    Note 1 pluck.now <<
                      pitchFrequency
                )
                pluck.pitches
            )
      in
        { selectionPlucked = True
        , selection = Selection.stop pluck.now selection
        , keyboard = keyboard
        , sequence = []
        , cmd =
            if selectionPlucked then
              AudioChange.perform changes
            else
              AudioChange.perform (Mute pluck.now :: changes)
        }

    AddWord _ ->
      { selectionPlucked = selectionPlucked
      , selection = selection
      , keyboard = keyboard
      , sequence = []
      , cmd = Cmd.none
      }

inRange : Int -> Int -> Int -> Bool
inRange low high x =
  low <= x && x <= high

pitchFrequency : Int -> Float
pitchFrequency pitch =
  440 * 2 ^ (toFloat (pitch - 69) / 12)

view : String -> Int -> Int -> Selection -> Keyboard -> Html Msg
view gridArea tonic lowestPitch selection keyboard =
  let
    maybeChord = getChord selection keyboard
    octave = getOctave selection keyboard
  in
  let
    maxOctave =
      case maybeChord of
        Nothing ->
          0
        Just chord ->
          let
            rootPitch =
              modBy 12 (chord.root - lowestPitch) + lowestPitch
            highestOffset =
              case List.reverse chord.flavor of
                [] ->
                  0
                flavorPitch :: _ ->
                  flavorPitch
          in
          let
            highestPitch = rootPitch + highestOffset
            maxPitch = lowestPitch + 11 + Chord.maxRange
          in
          let
            maxTransposition = maxPitch - highestPitch
          in
            (maxTransposition - modBy 12 maxTransposition) // 12
    pitchSet =
      Chord.toPitchSet lowestPitch octave maybeChord
  in
    span
      [ id gridArea
      , style "grid-area" gridArea
      , style "margin-top" "5px"
      ]
      [ Harp.view
          tonic
          lowestPitch
          (lowestPitch + 11 + Chord.maxRange)
          pitchSet
      , viewKeys
          tonic
          lowestPitch
          pitchSet
      , span
          [ style "display" "block"
          ]
          [ text "Chord "
          , input
              [ class "textInput"
              , Attributes.type_ "text"
              , isAudioTimeInput True
              , onInputWithAudioTime SetCode
              , Attributes.value (getCode selection keyboard)
              ]
              []
          , button
              [ class "button"
              , case Maybe.map Name.code maybeChord of
                  Just "unknown" ->
                    Attributes.disabled True
                  Just word ->
                    onClick (AddWord word)
                  Nothing ->
                    Attributes.disabled True
              ]
              [ text "Add"
              ]
          , text " Octave "
          , input
              [ class "numberInput"
              , Attributes.type_ "number"
              , Attributes.disabled
                  (maxOctave <= 0 && octave == 0)
              , isAudioTimeInput True
              , onIntInputWithAudioTime octave SetOctave
              , Attributes.value (String.fromInt octave)
              , Attributes.min "0"
              , Attributes.max (String.fromInt maxOctave)
              , style "width" "5ch"
              ]
              []
          ]
      ]

-- the origin is the top left corner of middle C,
-- not including its border
viewKeys : Int -> Int -> Set Int -> Html Msg
viewKeys tonic lowestPitch pitchSet =
  let
    highestPitch = lowestPitch + 11 + Chord.maxRange
  in
  let
    left = viewBoxLeft lowestPitch
    right = viewBoxRight highestPitch
  in
  let
    width = right - left
    height = fullHeight
  in
    Svg.svg
      [ SA.width (String.fromFloat width)
      , SA.height (String.fromFloat height)
      , SA.viewBox
          ( String.join
              " "
              [ String.fromFloat left
              , "0"
              , String.fromFloat width
              , String.fromFloat height
              ]
          )
      , style "display" "block"
      ]
      ( List.concat
          [ [ Svg.defs
                []
                [ blackKeyGradient
                , whiteKeyGradient
                , specularGradient
                ]
            , Svg.rect
                [ SA.x (String.fromFloat left)
                , SA.y "0"
                , SA.width (String.fromFloat width)
                , SA.height (String.fromFloat height)
                , SA.fill "black"
                ]
                []
            ]
          , [ Svg.map
                (pitchMsg lowestPitch pitchSet)
                (Svg.Lazy.lazy2 viewStaticKeys tonic lowestPitch)
            ]
          , List.map
              (Svg.map (pitchMsg lowestPitch pitchSet))
              ( List.concatMap
                  (viewKey tonic lowestPitch highestPitch True)
                  ( List.filter
                      (inRange lowestPitch highestPitch)
                      (Set.toList pitchSet)
                  )
              )
          , [ Svg.text_
                [ style "pointer-events" "none"
                , SA.textAnchor "middle"
                , SA.x
                    (String.fromFloat (0.5 * (headWidth - borderWidth)))
                , SA.y
                    ( String.fromFloat
                        ( fullHeight - borderWidth -
                            0.25 * (headWidth - borderWidth)
                        )
                    )
                ]
                [ Svg.text "C4"
                ]
            ]
          ]
      )

pitchMsg : Int -> Set Int -> (Int, Float) -> Msg
pitchMsg lowestPitch pitchSet ( pitch, now ) =
  if Set.member pitch pitchSet then
    RemovePitch (lowestPitch, pitch, now)
  else
    AddPitch (lowestPitch, pitch, now)

viewStaticKeys : Int -> Int -> Svg (Int, Float)
viewStaticKeys tonic lowestPitch =
  let
    highestPitch = lowestPitch + 11 + Chord.maxRange
  in
    Svg.g
      []
      ( List.concatMap
          (viewKey tonic lowestPitch highestPitch False)
          (List.range lowestPitch highestPitch)
      )

viewKey : Int -> Int -> Int -> Bool -> Int -> List (Svg (Int, Float))
viewKey tonic lowestPitch highestPitch selected pitch =
  let
    commonAttributes =
      if selected then
        []
      else
        [ isAudioTimeButton True
        , onClickWithAudioTime (Tuple.pair pitch)
        ]
  in
    if isWhiteKey pitch then
      let
        path = whitePath lowestPitch highestPitch pitch
      in
        [ Svg.path
            ( [ if selected then
                  style "pointer-events" "none"
                else
                  style "cursor" "pointer"
              , SA.fill
                  ( if selected then
                      Colour.pitchBg tonic pitch
                    else
                      "white"
                  )
              , SA.d path
              ] ++
                commonAttributes
            )
            []
        ] ++
          ( if selected then
              [ Svg.path
                  [ style "pointer-events" "none"
                  , SA.fill "url(#whiteKeyGradient)"
                  , SA.d path
                  ]
                  []
              ]
            else
              []
          )
    else
      [ Svg.rect
          ( [ if selected then
                style "pointer-events" "none"
              else
                style "cursor" "pointer"
            , SA.fill
                ( if selected then
                    Colour.pitchBg tonic pitch
                  else
                    "black"
                )
            , SA.strokeWidth (String.fromFloat borderWidth)
            , SA.strokeLinejoin "round"
            , SA.x (String.fromFloat (neckLeft pitch))
            , SA.y "0"
            , SA.width (String.fromFloat blackWidth)
            , SA.height (String.fromFloat (blackHeight - borderWidth))
            ] ++
              commonAttributes
          )
          []
      , Svg.path
          [ style "pointer-events" "none"
          , SA.fill "url(#blackKeyGradient)"
          , SA.opacity (String.fromFloat (leftSideOpacity selected))
          , SA.d (leftSidePath pitch)
          ]
          []
      , Svg.path
          [ style "pointer-events" "none"
          , SA.fill "url(#specularGradient)"
          , SA.opacity (String.fromFloat (specularOpacity selected))
          , SA.d (specularPath pitch)
          ]
          []
      , Svg.path
          [ style "pointer-events" "none"
          , SA.fill "url(#blackKeyGradient)"
          , SA.opacity (String.fromFloat fingerOpacity)
          , SA.d (fingerPath pitch)
          ]
          []
      , Svg.path
          [ style "pointer-events" "none"
          , SA.fill "url(#blackKeyGradient)"
          , SA.opacity (String.fromFloat (hillOpacity selected))
          , SA.d (hillPath pitch)
          ]
          []
      ]

whitePath : Int -> Int -> Int -> String
whitePath lowestPitch highestPitch pitch =
  String.join
    " "
    [ Path.bigM
        ( if pitch == lowestPitch then
            headLeft pitch
          else
            neckLeft pitch
        )
        0
    , Path.bigV blackHeight
    , Path.bigH (headLeft pitch)
    , Path.bigV (fullHeight - borderWidth - borderRadius)
    , Path.a
        borderRadius borderRadius
        90 False False
        borderRadius borderRadius
    , Path.h (headWidth - borderWidth - 2 * borderRadius)
    , Path.a
        borderRadius borderRadius
        90 False False
        borderRadius -borderRadius
    , Path.bigV blackHeight
    , Path.bigH
        ( if pitch == highestPitch then
            headLeft pitch + headWidth - borderWidth
          else
            neckLeft (pitch + 1) - borderWidth
        )
    , Path.bigV 0
    , Path.bigZ
    ]

fingerPath : Int -> String
fingerPath pitch =
  String.join
    " "
    [ Path.bigM (neckLeft pitch + sideWidth) 0
    , Path.bigV
        (blackHeight - borderWidth - hillHeight - nailHeight)
    , Path.c
        0 (nailHeight / 0.75)
        (blackWidth - 2 * sideWidth) (nailHeight / 0.75)
        (blackWidth - 2 * sideWidth) 0
    , Path.bigV 0
    , Path.bigZ
    ]

leftSidePath : Int -> String
leftSidePath pitch =
  String.join
    " "
    [ Path.bigM (neckLeft pitch) 0
    , Path.bigV (blackHeight - borderWidth)
    , Path.c
        (hillHeight / 1.5 / hillSlope) (-hillHeight / 1.5)
        (0.25 * blackWidth + hillHeight / 3 / hillSlope) (-hillHeight)
        (0.5 * blackWidth) (-hillHeight)
    , Path.c
        (-0.25 * blackWidth + 0.5 * sideWidth) 0
        (-0.5 * blackWidth + sideWidth) (-nailHeight / 3)
        (-0.5 * blackWidth + sideWidth) (-nailHeight)
    , Path.bigV 0
    , Path.bigZ
    ]

specularPath : Int -> String
specularPath pitch =
  String.join
    " "
    [ Path.bigM (neckLeft pitch) (blackHeight - borderWidth - specularHeight)
    , Path.bigV (blackHeight - borderWidth)
    , Path.c
        (hillHeight / 1.5 / hillSlope) (-hillHeight / 1.5)
        (0.25 * blackWidth + hillHeight / 3 / hillSlope) (-hillHeight)
        (0.5 * blackWidth) (-hillHeight)
    , Path.c
        (-0.25 * blackWidth + 0.5 * sideWidth) 0
        (-0.5 * blackWidth + sideWidth) (-nailHeight / 3)
        (-0.5 * blackWidth + sideWidth) (-nailHeight)
    , Path.bigV (blackHeight - borderWidth - specularHeight)
    , Path.bigZ
    ]

hillPath : Int -> String
hillPath pitch =
  String.join
    " "
    [ Path.bigM (neckLeft pitch + blackWidth) 0
    , Path.bigV (blackHeight - borderWidth)
    , Path.h -blackWidth
    , Path.partialC
        rightShineT
        (hillHeight / 0.75 / hillSlope) (-hillHeight / 0.75)
        (blackWidth - hillHeight / 0.75 / hillSlope) (-hillHeight / 0.75)
        blackWidth 0
    , Path.bigV 0
    , Path.bigZ
    ]

-- white keys have rounded corners at the bottom
-- the radius is measured at the edge of the white area,
-- inside the border
borderRadius : Float
borderRadius = 0.75 * scale

blackHeight : Float -- includes one border width
blackHeight = 15.5 * scale

fullHeight : Float -- includes one border width
fullHeight = 24 * scale

-- black key lighting parameters (these don't include any border width)
blackWidth : Float
blackWidth = 4 * headWidth / 7 - borderWidth

nailHeight : Float
nailHeight = 0.27 * blackWidth

hillHeight : Float
hillHeight = 0.44 * blackWidth

hillSlope : Float
hillSlope = 7

sideWidth : Float
sideWidth = 0.07 * blackWidth

rightShineT : Float
rightShineT = 1 - 0.12

specularHeight : Float
specularHeight = 2 * blackWidth

fingerOpacity : Float
fingerOpacity = 0.28

hillOpacity : Bool -> Float
hillOpacity selected =
  if selected then 0.6 else 0.46

leftSideOpacity : Bool -> Float
leftSideOpacity selected =
  if selected then 1 else 0.67

specularOpacity : Bool -> Float
specularOpacity selected =
  if selected then 1 else 0.4

blackKeyStartOpacity : Float
blackKeyStartOpacity = 0.3

blackKeyGradient : Svg msg
blackKeyGradient =
  Svg.linearGradient
    [ SA.id "blackKeyGradient"
    , SA.y1 "0%"
    , SA.y2 "100%"
    , SA.x1 "50%"
    , SA.x2 "50%"
    ]
    [ Svg.stop
        [ SA.offset "0%"
        , style "stop-color" "white"
        , style "stop-opacity" (String.fromFloat blackKeyStartOpacity)
        ]
        []
    , Svg.stop
        [ SA.offset "100%"
        , style "stop-color" "white"
        , style "stop-opacity" "1"
        ]
        []
    ]

whiteKeyGradient : Svg msg
whiteKeyGradient =
  let
    startOpacity = blackKeyStartOpacity * fingerOpacity
    slope =
      (1 - blackKeyStartOpacity) * fingerOpacity /
        (blackHeight - borderWidth - hillHeight)
  in
  let
    endOpacity =
      startOpacity + slope * (fullHeight - borderWidth)
  in
    Svg.linearGradient
      [ SA.id "whiteKeyGradient"
      , SA.y1 "0%"
      , SA.y2 "100%"
      , SA.x1 "50%"
      , SA.x2 "50%"
      ]
      [ Svg.stop
          [ SA.offset "0%"
          , style "stop-color" "white"
          , style "stop-opacity" (String.fromFloat startOpacity)
          ]
          []
      , Svg.stop
          [ SA.offset "100%"
          , style "stop-color" "white"
          , style "stop-opacity" (String.fromFloat endOpacity)
          ]
          []
      ]

specularGradient : Svg msg
specularGradient =
  Svg.radialGradient
    [ SA.id "specularGradient"
    , SA.cx "7.1%"
    , SA.cy "76%"
    , SA.r "7%"
    , SA.fx "7.1%"
    , SA.fy "76%"
    , SA.gradientTransform "scale(4 1)"
    ]
    [ Svg.stop
        [ SA.offset "0%"
        , style "stop-color" "white"
        , style "stop-opacity" "1"
        ]
        []
    , Svg.stop
        [ SA.offset "100%"
        , style "stop-color" "white"
        , style "stop-opacity" "0"
        ]
        []
    ]
