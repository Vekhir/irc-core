{-# Language OverloadedStrings #-}
{-|
Module      : Client.View.MaskList
Description : Line renderers for channel mask list view
Copyright   : (c) Eric Mertens, 2016
License     : ISC
Maintainer  : emertens@gmail.com

This module renders the lines used in the channel mask list. A mask list
can show channel bans, quiets, invites, and exceptions.
-}
module Client.View.MaskList
  ( maskListImages
  ) where

import           Client.Image.PackedImage
import           Client.Image.Palette
import           Client.State
import           Client.State.Channel
import           Client.State.Network
import           Control.Lens
import           Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import           Data.List
import           Data.Ord
import           Data.Text (Text)
import qualified Data.Text.Lazy as LText
import           Data.Time
import           Graphics.Vty.Attributes
import           Irc.Identifier

-- | Render the lines used in a channel mask list
maskListImages ::
  Char        {- ^ Mask mode  -} ->
  Text        {- ^ network    -} ->
  Identifier  {- ^ channel    -} ->
  Int         {- ^ draw width -} ->
  ClientState -> [Image']
maskListImages mode network channel w st =
  case mbEntries of
    Nothing      -> [text' (view palError pal) "Mask list not loaded"]
    Just entries -> maskListImages' entries w st

  where
    pal = clientPalette st
    mbEntries = preview
                ( clientConnection network
                . csChannels . ix channel
                . chanLists . ix mode
                ) st

maskListImages' :: HashMap Text MaskListEntry -> Int -> ClientState -> [Image']
maskListImages' entries w st = countImage : images
  where
    pal = clientPalette st

    countImage = text' (view palLabel pal) "Masks (visible/total): " <>
                 string defAttr (show (length entryList)) <>
                 char (view palLabel pal) '/' <>
                 string defAttr (show (HashMap.size entries))

    filterOn (mask,entry) = LText.fromChunks [mask, " ", view maskListSetter entry]

    entryList = sortBy (flip (comparing (view (_2 . maskListTime))))
              $ clientFilter st filterOn
              $ HashMap.toList entries

    renderWhen = formatTime defaultTimeLocale " %F %T"

    (masks, whoWhens) = unzip entryList
    maskImages       = text' defAttr <$> masks
    maskColumnWidth  = maximum (imageWidth <$> maskImages) + 1
    paddedMaskImages = resizeImage maskColumnWidth <$> maskImages
    width            = max 1 w

    images = [ cropLine $ mask <>
                          text' defAttr who <>
                          string defAttr (renderWhen when)
             | (mask, MaskListEntry who when) <- zip paddedMaskImages whoWhens ]

    cropLine img
      | imageWidth img > width = resizeImage width img
      | otherwise              = img
