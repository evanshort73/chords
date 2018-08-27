module Paragraph exposing
  ( Paragraph, init, update, highlights, song, suggestions, chords, mapChords
  , defaultTitle, lastWordEnd
  )

import Chord exposing (Chord)
import Highlight exposing (Highlight)
import IdChord
import MapCells exposing (mapCells)
import Replacement exposing (Replacement)
import Song exposing (Song)
import Substring exposing (Substring)
import Suggestion exposing (Suggestion)
import Train exposing (Train)
import Word exposing (Word)
import Zipper

import Regex exposing (Regex)

type alias Paragraph =
  { nextId : Int
  , words : Train Word
  }

init : List Substring -> Paragraph
init lines =
  let
    firstId = IdChord.count
    substrings = split lines
  in
    { nextId = firstId + Train.length substrings
    , words =
        Train.indexedMap (Word.init << (+) firstId) substrings
    }

update : List Substring -> Paragraph -> Paragraph
update lines { nextId, words } =
  let
    doubleZipped =
      Zipper.doubleZip Word.update (split lines) words
  in
    { nextId =
        nextId + Train.length doubleZipped.upper
    , words =
        List.concat
          [ doubleZipped.left
          , Train.indexedMap
              (Word.init << (+) nextId)
              doubleZipped.upper
          , doubleZipped.right
          ]
    }

split : List Substring -> Train Substring
split lines =
  Train.fromCars (List.map (Substring.find wordRegex) lines)

wordRegex : Regex
wordRegex =
  Maybe.withDefault Regex.never (Regex.fromString "[^ ]+")

highlights : Int -> Paragraph -> List Highlight
highlights tonic paragraph =
  List.filterMap
    (Word.highlight tonic)
    (Train.flatten paragraph.words)

song : Paragraph -> Song
song paragraph =
  List.filter
    (not << List.isEmpty)
    (Train.cars (Train.filterMap Word.meaning paragraph.words))

suggestions : Int -> Paragraph -> List Suggestion
suggestions tonic paragraph =
  Suggestion.groupByReplacement
    ( List.filterMap
        (Word.suggestion tonic)
        (Train.flatten paragraph.words)
    )

chords : Paragraph -> List Chord
chords paragraph =
  ( List.filterMap
      Word.getChord
      (Train.flatten paragraph.words)
  )

mapChords : (Chord -> Chord) -> List Substring -> List Replacement
mapChords f lines =
  mapCells (Word.mapChord f) lines

maxLength : Int
maxLength = 20

defaultTitle : Paragraph -> String
defaultTitle paragraph =
  let
    codes =
      List.filterMap
        Word.code
        (Train.flatten paragraph.words)
  in
  let
    longTitle = String.join " " codes
  in
    if String.length longTitle <= maxLength then
      longTitle
    else
      let
        shortTitle =
          String.join
            " "
            (truncateByLength (maxLength - 3) codes)
      in
        shortTitle ++ "..."

truncateByLength : Int -> List String -> List String
truncateByLength length strings =
  case strings of
    [] ->
      []
    string :: rest ->
      let
        remainingLength = length - String.length string
      in
        if remainingLength < 0 then
          []
        else if remainingLength == 0 then
          [ string ]
        else
          string ::
            truncateByLength (remainingLength - 1) rest

lastWordEnd : Paragraph -> Maybe Int
lastWordEnd paragraph =
  case List.reverse (Train.flatten paragraph.words) of
    [] ->
      Nothing
    word :: _ ->
      Just (Substring.stop word.substring)
