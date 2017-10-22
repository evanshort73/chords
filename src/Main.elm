port module Main exposing (..)

import Metronome exposing (Metronome)
import AudioTime

import AnimationFrame
import Html exposing (Html, a, div, pre, span, text, textarea)
import Html.Attributes exposing (href, style)
import Html.Events exposing (onMouseDown, on, targetValue)
import Json.Decode
import Json.Encode
import Task exposing (Task)

main =
  Html.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

-- MODEL

type alias Model =
  { playing : Maybe PlayInfo
  , text : String
  }

type alias PlayInfo =
  { metronome : Metronome
  , chordIndex : Int
  , nextChord : Maybe ScheduledChord
  }

type alias ScheduledChord =
  { index : Int
  , tick : Int
  }

init : ( Model, Cmd Msg )
init =
  ( { playing = Nothing
    , text = "C G a F"
    }
  , Cmd.none
  )

type alias Chord =
  { name : String
  , root : Int
  , bgColor : String
  , textColor : String
  , arpeggio : List Int
  }

errorChord : Chord
errorChord =
  Chord "error" 72 "#800000" "#ffffff" [ 0 ]

-- http://www.colourlovers.com/palette/324465/Pastel_Rainbow
-- blue and orange from http://www.colourlovers.com/palette/36070/pastel_rainbow
chords : List Chord
chords =
  [ Chord "C" 48 "#f8facd" "#000000" majorArpeggio
  , Chord "d" 50 "#eccdfa" "#000000" minorArpeggio
  , Chord "e" 52 "#d2facd" "#000000" minorArpeggio
  , Chord "F" 53 "#facdcd" "#000000" majorArpeggio
  , Chord "G" 55 "#c9ffff" "#000000" majorArpeggio
  , Chord "a" 57 "#ffe7c9" "#000000" minorArpeggio
  , Chord "b°" 59 "#005e93" "#ffffff" diminishedArpeggio
  ]

majorArpeggio : List Int
majorArpeggio = [ 12, 7, 4, 7, 0, 7, 4, 7 ]

minorArpeggio : List Int
minorArpeggio = [ 12, 7, 3, 7, 0, 7, 3, 7 ]

diminishedArpeggio : List Int
diminishedArpeggio = [ 12, 6, 3, 6, 0, 6, 3, 6 ]

-- UPDATE

type Msg
  = NeedsTime (Float -> Msg)
  | CurrentTime Float
  | PlayChord ( Int, Float )
  | TextEdited String

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    NeedsTime partialMsg ->
      ( model, Task.perform partialMsg AudioTime.now )

    CurrentTime now ->
      case model.playing of
        Just p ->
          if now >= Metronome.getStop p.metronome then
            ( { model | playing = Nothing }, Cmd.none )
          else
            case p.nextChord of
              Nothing -> ( model, Cmd.none )
              Just { index, tick } ->
                if now >= Metronome.getTickTime p.metronome tick then
                  ( { model
                    | playing =
                        Just { p | chordIndex = index, nextChord = Nothing }
                    }
                  , Cmd.none
                  )
                else
                  ( model, Cmd.none )
        Nothing ->
          ( model, Cmd.none )

    PlayChord ( chordIndex, now ) ->
      let
        start =
          case model.playing of
            Nothing -> now
            Just p -> p.metronome.start
      in let
        oldTicks =
          case model.playing of
            Nothing -> 0
            Just p -> p.metronome.ticks
      in let
        changeTick =
          case model.playing of
            Nothing -> 0
            Just p -> Metronome.getNextBeat p.metronome now
      in let
        chord =
          Maybe.withDefault errorChord <|
            List.head (List.drop chordIndex chords)
      in let
        arpeggioStartIndex = changeTick % List.length chord.arpeggio
      in let
        missingTicks =
          max 0 <|
            minTicks - (List.length chord.arpeggio - arpeggioStartIndex)
      in let
        extraCopies =
          (missingTicks + List.length chord.arpeggio - 1) //
            List.length chord.arpeggio
      in let
        offsets =
          List.concat <|
            (List.drop arpeggioStartIndex chord.arpeggio) ::
              List.repeat extraCopies chord.arpeggio
      in let
        m = { start = start, ticks = changeTick + List.length offsets }
      in let
        changeTime = Metronome.getTickTime m changeTick
      in let
        oldChordIndex =
          case model.playing of
            Nothing -> Nothing
            Just p ->
              if changeTime > now then Just p.chordIndex else Nothing
      in let
        p =
          case oldChordIndex of
            Nothing ->
              { metronome = m
              , chordIndex = chordIndex
              , nextChord = Nothing
              }
            Just i ->
              { metronome = m
              , chordIndex = i
              , nextChord = Just { index = chordIndex, tick = changeTick }
              }
      in let
        audioChanges =
          ( if changeTick < oldTicks then
              if now + latency >= changeTime then
                let notBeforeNote = max now changeTime in
                  [ CancelFutureNotes
                      { t = notBeforeNote, before = False }
                  , MuteLoudestNote notBeforeNote
                  ]
              else
                [ CancelFutureNotes { t = changeTime, before = True } ]
            else
              []
          ) ++
            ( offsetsToNotes
                start
                changeTick
                now
                chord.root
                offsets
            )
      in
        ( { model | playing = Just p }
        , changeAudioUsingJson (List.map audioChangeToJson audioChanges)
        )

    TextEdited newText ->
      ( { model | text = newText }, Cmd.none )

minTicks : Int
minTicks = 9

latency : Float
latency = 0.01

mtof : Int -> Float
mtof m =
  440 * 2 ^ (toFloat (m - 69) / 12)

-- root octave is midi notes 48 - 59 (C2 - B2)

offsetsToNotes : Float -> Int -> Float -> Int -> List Int -> List AudioChange
offsetsToNotes start changeTick now root offsets =
  List.map2
    (toNote now)
    ( List.map
        ((+) start << (*) Metronome.interval << toFloat)
        (List.range changeTick <| changeTick + List.length offsets)
    )
    (List.map (mtof << (+) root) offsets)

toNote : Float -> Float -> Float -> AudioChange
toNote now t f =
  NewNote (Note (max now t) f)

-- SUBSCRIPTIONS

port changeAudioUsingJson : List Json.Encode.Value -> Cmd msg

audioChangeToJson : AudioChange -> Json.Encode.Value
audioChangeToJson change =
  case change of
    NewNote note ->
      Json.Encode.object
        [ ( "type", Json.Encode.string "note" )
        , ( "t", Json.Encode.float note.t )
        , ( "f", Json.Encode.float note.f )
        ]
    MuteLoudestNote t ->
      Json.Encode.object
        [ ( "type", Json.Encode.string "muteLoudest" )
        , ( "t", Json.Encode.float t )
        ]
    MuteAllNotes ct ->
      Json.Encode.object
        [ ( "type", Json.Encode.string "mute" )
        , ( "t", Json.Encode.float ct.t )
        , ( "before", Json.Encode.bool ct.before )
        ]
    CancelFutureNotes ct ->
      Json.Encode.object
        [ ( "type", Json.Encode.string "cancel" )
        , ( "t", Json.Encode.float ct.t )
        , ( "before", Json.Encode.bool ct.before )
        ]

type AudioChange
  = NewNote Note
  | MuteLoudestNote Float
  | MuteAllNotes ChangeTime
  | CancelFutureNotes ChangeTime

type alias Note =
  { t : Float
  , f : Float
  }

type alias ChangeTime =
  { t : Float
  , before : Bool
  }

subscriptions : Model -> Sub Msg
subscriptions model =
  case model.playing of
    Nothing -> Sub.none
    Just _ -> AnimationFrame.times (always (NeedsTime CurrentTime))

-- VIEW

view : Model -> Html Msg
view model =
  div
    [ style
        [ ( "font-family", "calibri, helvetica, arial, sans-serif" )
        ]
    ]
    [ div
        [ style
            [ ( "width", "500px" )
            , ( "position", "relative" )
            , ( "border-style", "inset" )
            , ( "border-width", "2px" )
            , ( "border-color", "#e3e3e3")
            ]
        ]
        [ textarea
            [ on "input" (Json.Decode.map TextEdited targetValue)
            , style
                [ ( "font", "inherit" )
                , ( "width", "100%" )
                , ( "height", "100%" )
                , ( "padding", "10px" )
                , ( "border", "none" )
                , ( "margin", "0px" )
                , ( "position", "absolute" )
                , ( "resize", "none" )
                , ( "overflow", "hidden" )
                , ( "box-sizing", "border-box" )
                , ( "background", "transparent" )
                ]
            ]
            [ text model.text
            ]
        , pre
            [ style
                [ ( "font", "inherit")
                , ( "padding", "10px" )
                , ( "margin", "0px" )
                , ( "white-space", "pre-wrap" )
                , ( "word-wrap", "break-word" )
                , ( "color", "transparent" )
                ]
            ]
            [ text (model.text ++ "\n")
            ]
        ]
    , div
        [ style [ ( "height", "200px" ) ] ] <|
        List.indexedMap
          ( viewChord
            ( case model.playing of
                Nothing -> -1
                Just p -> p.chordIndex
            )
            ( case Maybe.andThen .nextChord model.playing of
                Nothing -> -1
                Just { index, tick } -> index
            )
          )
          chords
    , div []
        [ a
            [ href "https://github.com/evanshort73/chords" ]
            [ text "GitHub" ]
        ]
    ]

viewChord : Int -> Int -> Int -> Chord -> Html Msg
viewChord activeChordIndex nextChordIndex chordIndex chord =
  let
    selected =
      chordIndex == activeChordIndex || chordIndex == nextChordIndex
  in
    span
      [ style
          [ ( "border-style"
            , if chordIndex == nextChordIndex then
                "dashed"
              else
                "solid"
            )
          , ( "border-width", "5px" )
          , ( "display", "inline-block" )
          , ( "margin-right", "-5px" )
          , ( "border-color"
            , if selected then
                "#3399ff"
              else
                "transparent"
            )
          , ( "border-radius", "10px" )
          ]
      ]
      [ span
          [ onMouseDown <| NeedsTime (PlayChord << (,) chordIndex)
          , style
              [ ( "background", chord.bgColor )
              , ( "color", chord.textColor )
              , ( "width", "50px" )
              , ( "line-height", "50px" )
              , ( "font-size", "20pt" )
              , ( "text-align", "center" )
              , ( "display", "inline-block" )
              , ( "border-radius", "5px" )
              , ( "box-shadow", "1px 1px 3px rgba(0, 0, 0, 0.6)" )
              , ( "cursor", "pointer" )
              ]
          ]
          [ text chord.name ]
      ]
