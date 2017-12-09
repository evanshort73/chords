module Player exposing
  ( Player, setTime, willChange, PlayStatus, playStatus, playStrum
  , playArpeggio
  )

import AudioChange exposing (AudioChange(..), Note)
import Chord exposing (Chord)

type alias Player =
  { openings : List Opening
  , schedule : List Segment
  }

type alias Opening =
  { endTime : Float
  , beatInterval : Float
  , beat : Float
  , id : Int
  , highStart : Bool
  }

type alias Segment =
  { id : Int
  , stop : Float
  }

setTime : Float -> Player -> Maybe Player
setTime now player =
  case player.schedule of
    [] ->
      Nothing
    segment :: rest ->
      if now < segment.stop then
        Nothing
      else
        Just { player | schedule = dropSegmentsBefore now rest }

dropSegmentsBefore : Float -> List Segment -> List Segment
dropSegmentsBefore now segments =
  case segments of
    [] -> []
    segment :: rest ->
      if now < segment.stop then segments
      else dropSegmentsBefore now rest

willChange : Player -> Bool
willChange player =
  player.schedule /= []

type alias PlayStatus =
  { active : Int
  , next : Int
  }

playStatus : Player -> PlayStatus
playStatus player =
  case player.schedule of
    [] ->
      { active = -1, next = -1 }
    [ segment ] ->
      { active = segment.id, next = -1 }
    segment :: nextSegment :: _ ->
      { active = segment.id, next = nextSegment.id }

playStrum :
  Float -> Chord -> Int -> Float -> Player ->
    ( Player, List AudioChange )
playStrum strumInterval chord id now player =
  let
    currentSchedule = dropSegmentsBefore now player.schedule
  in
    ( { player
      | openings = []
      , schedule = [ { id = id, stop = now + 2.25 } ]
      }
    , List.concat
        [ [ let
              mute =
                case currentSchedule of
                  [] -> False
                  segment :: _ -> segment.id /= id
            in
              (if mute then MuteAllNotes else CancelFutureNotes)
                { t = now, before = False }
          , SetDecay 3
          ]
        , let
            notes =
              List.map
                (strumNote strumInterval chord now)
                (List.range 0 (List.length chord))
          in
            List.map AddNote notes
        ]
    )

strumNote : Float -> Chord -> Float -> Int -> Note
strumNote strumInterval chord now i =
  { t = now + strumInterval * toFloat i
  , f = pitchFrequency (Chord.get chord i)
  }

playArpeggio :
  Float -> Chord -> Int -> Float -> Player ->
    ( Player, List AudioChange )
playArpeggio beatInterval chord id now player =
  let
    openingsNotAfter = dropOpeningsAfter now player.openings
  in let
    truncatedOpenings =
      case openingsNotAfter of
        [] -> openingsNotAfter
        opening :: _ ->
          if now <= opening.endTime then openingsNotAfter
          else []
  in let
    ( startTime, beat, highStart ) =
      case truncatedOpenings of
        [] ->
          ( now, now / beatInterval, False )
        opening :: _ ->
          ( opening.beat * opening.beatInterval
          , if opening.beatInterval == beatInterval then
              opening.beat
            else
              opening.beat * opening.beatInterval / beatInterval
          , opening.highStart && opening.id /= id
          )
  in let
    additionalOpenings =
      [ { endTime = (beat + 4 + leniency) * beatInterval
        , beatInterval = beatInterval
        , beat = beat + 4
        , id = id
        , highStart = False
        }
      , { endTime = (beat + 2 + leniency) * beatInterval
        , beatInterval = beatInterval
        , beat = beat + 2
        , id = id
        , highStart = True
        }
      ]
  in let
    currentSchedule = dropSegmentsBefore now player.schedule
  in let
    truncatedSchedule =
      if now < startTime then
        case currentSchedule of
          [] ->
            []
          segment :: _ ->
            [ { id = segment.id
              , stop = startTime
              }
            ]
      else
        []
  in let
    additionalSchedule =
      [ { id = id
        , stop = (beat + 4) * beatInterval
        }
      ]
  in
    ( { player
      | openings = additionalOpenings ++ truncatedOpenings
      , schedule = truncatedSchedule ++ additionalSchedule
      }
    , List.concat
        [ [ let
              mute =
                case currentSchedule of
                  [] -> False
                  segment :: _ -> segment.id /= id
            in
              (if mute then MuteAllNotes else CancelFutureNotes)
                { t = max now startTime
                , before = now < startTime
                }
          , SetDecay 1.5
          ]
        , let
            arpeggio =
              if highStart then highArpeggio else lowArpeggio
          in let
            notes =
              List.map
                (arpeggioNote chord now startTime beatInterval)
                arpeggio
          in
            List.map AddNote notes
        ]
    )

dropOpeningsAfter : Float -> List Opening -> List Opening
dropOpeningsAfter t openings =
  case openings of
    [] -> openings
    _ :: previousOpenings ->
      case previousOpenings of
        [] -> openings
        previousOpening :: _ ->
          if previousOpening.endTime < t then openings
          else dropOpeningsAfter t previousOpenings

leniency : Float
leniency = 0.05

arpeggioNote : Chord -> Float -> Float -> Float -> IndexNote -> Note
arpeggioNote chord now startTime beatInterval { offset, beat, i } =
  { t = max now (startTime + beatInterval * beat)
  , f = pitchFrequency (Chord.get chord i + offset)
  }

pitchFrequency : Int -> Float
pitchFrequency pitch =
  440 * 2 ^ (toFloat (pitch - 69) / 12)

type alias IndexNote =
  { offset : Int
  , beat : Float
  , i : Int
  }

highArpeggio : List IndexNote
highArpeggio = IndexNote 24 0 0 :: lowArpeggio

lowArpeggio : List IndexNote
lowArpeggio =
  [ IndexNote 0 0 0
  , IndexNote 0 0.25 1
  , IndexNote 0 0.5 2
  , IndexNote 0 0.75 3
  , IndexNote 0 1 4
  , IndexNote 0 1.25 5
  , IndexNote 0 1.5 3
  , IndexNote 0 1.75 4
  , IndexNote 0 2 0
  , IndexNote 0 2 6
  , IndexNote 0 2.25 1
  , IndexNote 0 2.5 2
  , IndexNote 0 2.75 3
  , IndexNote 0 3 4
  , IndexNote 0 3.25 5
  , IndexNote 0 3.5 3
  , IndexNote 0 3.75 4
  ]
