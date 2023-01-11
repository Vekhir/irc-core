{-# Language OverloadedStrings #-}
{-|
Module      : Client.Image.PackedImage
Description : Packed vty Image type
Copyright   : (c) Eric Mertens, 2016
License     : ISC
Maintainer  : emertens@gmail.com

This module provides a more memory efficient way to store images.

-}
module Client.Image.PackedImage
  ( Image'
  , unpackImage

  -- * Packed image construction
  , char
  , text'
  , string
  , imageWidth
  , splitImage
  , imageText
  , resizeImage
  ) where

import Data.List (findIndex)
import Data.String (IsString(..))
import Data.Text qualified as S
import Data.Text.Lazy qualified as L
import Graphics.Vty.Attributes (Attr, defAttr)
import Graphics.Vty.Image ((<|>), wcswidth, wcwidth)
import Graphics.Vty.Image.Internal (Image(..))


unpackImage :: Image' -> Image
unpackImage i =
  case i of
    EmptyImage'          -> EmptyImage
    HorizText' a b c d e -> HorizText a (L.fromStrict b) c d <|> unpackImage e


-- | Packed, strict version of 'Image' used for long-term storage of images.
data Image'
  = HorizText'
      !Attr -- don't unpack, these get reused from the palette
      {-# UNPACK #-} !S.Text
      {-# UNPACK #-} !Int -- terminal width
      {-# UNPACK #-} !Int -- codepoint count
      !Image'
  | EmptyImage'
  deriving (Show)

instance Monoid Image' where
  mempty  = EmptyImage'
  mappend = (<>)

instance Semigroup Image' where
  -- maintain compressed form
  HorizText' a b c d EmptyImage' <> HorizText' a' b' c' d' rest
    | a == a' = HorizText' a (b <> b') (c + c') (d + d') rest

  EmptyImage'          <> y = y
  HorizText' a b c d e <> y = HorizText' a b c d (e <> y)

instance IsString Image' where fromString = string defAttr

text' :: Attr -> S.Text -> Image'
text' a s
  | S.null s  = EmptyImage'
  | otherwise = HorizText' a s (wcswidth (S.unpack s)) (S.length s) EmptyImage'

char :: Attr -> Char -> Image'
char a c = HorizText' a (S.singleton c) (wcwidth c) 1 EmptyImage'

string :: Attr -> String -> Image'
string a s
  | null s    = EmptyImage'
  | otherwise = HorizText' a t (wcswidth s) (S.length t) EmptyImage'
  where t = S.pack s

splitImage :: Int {- ^ image width -} -> Image' -> (Image',Image')
splitImage _ EmptyImage' = (EmptyImage', EmptyImage')
splitImage w (HorizText' a t w' l rest)
  | w >= w' = case splitImage (w-w') rest of
                (x,y) -> (HorizText' a t w' l x, y)
  | otherwise = (text' a (S.take i t), text' a (S.drop i t) <> rest)
  where
    ws = scanl1 (+) (map wcwidth (S.unpack t))
    i  = case findIndex (> w) ws of
           Nothing -> 0
           Just ix -> ix

-- | Width in terms of terminal columns
imageWidth :: Image' -> Int
imageWidth = go 0
  where
    go acc EmptyImage'            = acc
    go acc (HorizText' _ _ w _ x) = go (acc + w) x

imageText :: Image' -> L.Text
imageText = L.fromChunks . go
  where
    go EmptyImage' = []
    go (HorizText' _ t _ _ xs) = t : go xs

resizeImage :: Int -> Image' -> Image'
resizeImage w img =
  let iw = imageWidth img in
  case compare w iw of
    LT -> fst (splitImage w img)
    EQ -> img
    GT -> img <> string defAttr (replicate (w-iw) ' ')
