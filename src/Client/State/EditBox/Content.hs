{-# Language TemplateHaskell, BangPatterns #-}
{-|
Module      : Client.State.EditBox.Content
Description : Multiline text container with cursor
Copyright   : (c) Eric Mertens, 2016
License     : ISC
Maintainer  : emertens@gmail.com

This module manages simple text navigation and manipulation,
but leaves more complicated operations like yank/kill and
history management to "Client.State.EditBox"

-}
module Client.State.EditBox.Content
  (
  -- * Multiple lines
    Content
  , above
  , below
  , singleLine
  , noContent
  , shift
  , toStrings
  , fromStrings

  -- * Focused line
  , Line(..)
  , HasLine(..)
  , endLine

  -- * Movements
  , left
  , right

  , leftWord
  , rightWord

  , jumpLeft
  , jumpRight

  -- * Edits
  , delete
  , backspace
  , insertPastedString
  , insertString
  , insertChar
  , toggle
  , digraph
  ) where

import Control.Applicative ((<|>))
import Control.Lens (view, views, (+~), (-~), over, set, makeClassy, makeLenses)
import Control.Monad (guard)
import Data.Char (isAlphaNum)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty(..), (<|))
import Data.Map (Map)
import Data.Map qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Digraphs (Digraph(..), lookupDigraph)

data Line = Line
  { _pos  :: !Int
  , _text :: !String
  }
  deriving (Read, Show)

makeClassy ''Line

emptyLine :: Line
emptyLine = Line 0 ""

beginLine :: String -> Line
beginLine = Line 0

endLine :: String -> Line
endLine s = Line (length s) s

-- | Zipper-ish view of the multi-line content of an 'EditBox'.
-- Lines 'above' the 'currentLine' are stored in reverse order.
data Content = Content
  { _above       :: ![String]
  , _currentLine :: !Line
  , _below       :: ![String]
  }
  deriving (Read, Show)

makeLenses ''Content

instance HasLine Content where
  line = currentLine

-- | Default 'Content' value
noContent :: Content
noContent = Content [] emptyLine []

-- | Single line 'Content'.
singleLine :: Line -> Content
singleLine l = Content [] l []

-- | Shifts the first line off of the 'Content', yielding the
-- text of the line and the rest of the content.
shift :: Content -> (String, Content)
shift (Content [] l []) = (view text l, noContent)
shift (Content a@(_:_) l b) = (last a, Content (init a) l b)
shift (Content [] l (b:bs)) = (view text l, Content [] (beginLine b) bs)

-- | When at beginning of line, jump to beginning of previous line.
-- Otherwise jump to beginning of current line.
jumpLeft :: Content -> Content
jumpLeft c
  | view pos c == 0 = maybe c begin1 (backwardLine c)
  | otherwise       = begin1 c
  where
    begin1 = set pos 0

-- | When at end of line, jump to end of next line.
-- Otherwise jump to end of current line.
jumpRight :: Content -> Content
jumpRight c
  | view pos c == len = maybe c end1 (forwardLine c)
  | otherwise         = set pos len c
  where
    len    = views text length c
    end1 l = set pos (views text length l) l


-- | Move the cursor left, across lines if necessary.
left :: Content -> Content
left c =
  case compare (view pos c) 0 of
    GT                             -> (pos -~ 1) c
    EQ | Just c' <- backwardLine c -> c'
    _                              -> c

-- | Move the cursor right, across lines if necessary.
right :: Content -> Content
right c =
  let Line n s = view line c in
  case compare n (length s) of
    LT                            -> (pos +~ 1) c
    EQ | Just c' <- forwardLine c -> c'
    _                             -> c

-- | Move the cursor left to the previous word boundary.
leftWord :: Content -> Content
leftWord c
  | n == 0    = maybe c leftWord (backwardLine c)
  | otherwise = set pos search c
  where
    Line n txt = view line c
    search = maybe 0 fst
           $ find      (not . isAlphaNum . snd)
           $ dropWhile (not . isAlphaNum . snd)
           $ reverse
           $ take n
           $ zip [1..] txt

-- | Move the cursor right to the next word boundary.
rightWord :: Content -> Content
rightWord c
  | n == txtLen = maybe c rightWord (forwardLine c)
  | otherwise   = set pos search c
  where
    Line n txt = view line c
    txtLen = length txt
    search = maybe txtLen fst
           $ find      (not . isAlphaNum . snd)
           $ dropWhile (not . isAlphaNum . snd)
           $ drop n
           $ zip [0..] txt

-- | Delete the character before the cursor.
backspace :: Content -> Content
backspace c
  | n == 0
  = case view above c of
      []   -> c
      a:as -> set above as
            . set line (Line (length a) (a ++ s))
            $ c

  | (preS, postS) <- splitAt (n-1) s
  = set line (Line (n-1) (preS ++ drop 1 postS)) c
  where
    Line n s = view line c

-- | Delete the character after/under the cursor.
delete :: Content -> Content
delete c =
  let Line n s = view line c in
  case splitAt n s of
    (preS, _:postS) -> set text (preS ++ postS) c
    _               -> case view below c of
                         []   -> c
                         b:bs -> set below bs
                               . set text (s ++ b)
                               $ c

-- | Insert character at cursor, cursor is advanced.
insertChar :: Char -> Content -> Content
insertChar '\n' c =
  let Line n txt = view line c in
  case splitAt n txt of
    (preS, postS) -> over above (preS :)
                   $ set line (beginLine postS) c

insertChar ins c = over line aux c
  where
    aux (Line n txt) =
      case splitAt n txt of
        (preS, postS) -> Line (n+1) (preS ++ ins : postS)

-- | Smarter version of 'insertString' that removes spurious newlines.
insertPastedString :: String -> Content -> Content
insertPastedString paste c = insertString (foldr scrub "" paste) c
  where
    cursorAtEnd = null (view below c)
               && length (view text c) == view pos c

    -- ignore formfeeds
    scrub '\r' xs = xs

    -- avoid adding empty lines
    scrub '\n' xs@('\n':_) = xs

    -- avoid adding trailing newline at end of textbox
    scrub '\n' "" | cursorAtEnd = ""

    -- pass-through everything else
    scrub x xs = x : xs

-- | Insert string at cursor, cursor is advanced to the
-- end of the inserted string.
insertString :: String -> Content -> Content
insertString ins c =
  case push (view above c) (preS ++ l) ls of
    (newAbove, newLine) -> set above newAbove
                         $ set line newLine c
  where
    l:ls          = lines (ins ++ "\n")
    Line n txt    = view line c
    (preS, postS) = splitAt n txt

    push stk x []     = (stk, Line (length x) (x ++ postS))
    push stk x (y:ys) = push (x:stk) y ys

-- | Advance to the beginning of the next line
forwardLine :: Content -> Maybe Content
forwardLine c =
  case view below c of
    []   -> Nothing
    b:bs -> Just
         $! over above (view text c :)
          $ set below bs
          $ set line (beginLine b) c

-- | Retreat to the end of the previous line
backwardLine :: Content -> Maybe Content
backwardLine c =
  case view above c of
    []   -> Nothing
    a:as -> Just
         $! over below (view text c :)
          $ set above as
          $ set line (endLine a) c

toggle :: Content -> Content
toggle !c
  | p < 1     = c
  | n < 2     = c
  | n == p    = over text (swapAt (p-2)) c
  | otherwise = set pos (p+1)
              $ over text (swapAt (p-1)) c
  where
    p = view pos c
    n = views text length c

    swapAt 0 (x:y:z) = y:x:z
    swapAt i (x:xs)  = x:swapAt (i-1) xs
    swapAt _ _       = error "toggle: PANIC! Invalid argument"


-- | Use the two characters preceeding the cursor as a digraph and replace
-- them with the corresponding character.
digraph :: Map Digraph Text -> Content -> Maybe Content
digraph extras !c =
  do let Line n txt = view line c
     guard (2 <= n)
     let (pfx,x:y:sfx) = splitAt (n - 2) txt
     let key = Digraph x y
     d <-  Text.unpack <$> Map.lookup key extras
       <|> pure        <$> lookupDigraph key
     let line' = Line (n-1) (pfx++d++sfx)
     Just $! set line line' c

fromStrings :: NonEmpty String -> Content
fromStrings (x :| xs) = Content xs (endLine x) []

toStrings :: Content -> NonEmpty String
toStrings c = foldl (flip (<|)) (view text c :| view above c) (view below c)
