module Views.Channel where

import Control.Lens
import Data.ByteString (ByteString)
import Data.Monoid
import Data.Foldable (toList)
import Data.List (stripPrefix, intersperse)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Time (UTCTime, formatTime)
import Graphics.Vty.Image
import System.Locale (defaultTimeLocale)
import qualified Data.ByteString.Char8 as BS8
import qualified Data.CaseInsensitive as CI

import Irc.Format
import Irc.Model

import ClientState
import ImageUtils

detailedImageForState :: ClientState -> Image
detailedImageForState st
  = vertCat
  $ startFromBottom st
  $ reverse
  $ take (view clientHeight st - 4)
  $ drop (view clientScrollPos st)
  $ concatMap (reverse . renderOne)
  $ activeMessages st
  where
  width = view clientWidth st
  renderOne x =
    composeLine width
      (renderTimestamp (view mesgStamp x)
       <|> string (withForeColor defAttr blue) (ty ++ " ")
       <|> renderFullUsermask (view mesgSender x)
       <|> string (withForeColor defAttr blue) (": "))
      (view mesgContent x)
    where
    ty = case view mesgType x of
           JoinMsgType -> "J"
           PartMsgType -> "P"
           NickMsgType -> "C"
           QuitMsgType -> "Q"
           PrivMsgType -> "M"
           TopicMsgType -> "T"
           ActionMsgType -> "A"
           NoticeMsgType -> "N"
           KickMsgType -> "K"

renderTimestamp :: UTCTime -> Image
renderTimestamp
  = string (withForeColor defAttr brightBlack)
  . formatTime defaultTimeLocale "%H:%M:%S "

activeMessages :: ClientState -> [IrcMessage]
activeMessages st =
    case preview (focusMessages (view clientFocus st)) conn of
      Nothing -> mempty
      Just xs ->
        case stripPrefix "/filter " (clientInput st) of
          Nothing -> toList xs
          Just nick -> filter (nickFilter (BS8.pack nick)) (toList xs)
  where
  conn = view clientConnection st
  nickFilter nick msg
    = CI.foldCase (views mesgSender userNick msg)
      == CI.foldCase nick

startFromBottom :: ClientState -> [Image] -> [Image]
startFromBottom st xs
  = replicate (view clientHeight st - 4 - length xs)
                (char defAttr ' ')
    ++ xs


compressedImageForState :: ClientState -> Image
compressedImageForState st
  = vertCat
  $ startFromBottom st
  $ reverse
  $ take (view clientHeight st - 4)
  $ drop (view clientScrollPos st)
  $ concatMap (reverse . renderOne)
  $ compressMessages
  $ activeMessages st
  where
  width = view clientWidth st

  formatNick me = utf8Bytestring' (withForeColor defAttr color)
    where
    color
      | me        = green
      | otherwise = yellow

  renderOne (CompChat modes me who what) =
    composeLine width
      (modePrefix modes <|>
       formatNick me who <|>
       string (withForeColor defAttr blue) (": "))
      what

  renderOne (CompNotice modes who what) =
    composeLine width
      (modePrefix modes <|>
       utf8Bytestring' (withForeColor defAttr red) who <|>
       string (withForeColor defAttr blue) (": "))
      what

  renderOne (CompAction modes who what) =
    composeLine width
      (modePrefix modes <|>
       utf8Bytestring' (withForeColor defAttr blue) who <|> char defAttr ' ')
      what

  renderOne (CompMeta xs) =
     [horizCat (intersperse (char defAttr ' ') (map renderMeta xs))]

  renderMeta (CompJoin who)
    =   char (withForeColor defAttr green) '+'
    <|> utf8Bytestring' defAttr who
  renderMeta (CompPart who)
    =   char (withForeColor defAttr red) '-'
    <|> utf8Bytestring' defAttr who
  renderMeta (CompQuit who)
    =   char (withForeColor defAttr red) 'x'
    <|> utf8Bytestring' defAttr who
  renderMeta (CompKick who)
    =   char (withForeColor defAttr red) '!'
    <|> utf8Bytestring' defAttr who
  renderMeta (CompNick who who')
    =   utf8Bytestring' defAttr who
    <|> char (withForeColor defAttr yellow) '-'
    <|> text' defAttr who'
  renderMeta (CompTopic who)
    =   char (withForeColor defAttr yellow) 'T'
    <|> utf8Bytestring' defAttr who


  conn = view clientConnection st

  prefixes = view (connChanModes . modesPrefixModes) conn

  modePrefix modes =
    string (withForeColor defAttr blue)
           (mapMaybe (`lookup` prefixes) modes)

compressMessages :: [IrcMessage] -> [CompressedMessage]
compressMessages [] = []
compressMessages (x:xs) =
  case view mesgType x of
    NoticeMsgType -> CompNotice (view mesgModes x) nick
                                (view mesgContent x) : compressMessages xs
    PrivMsgType   -> CompChat (view mesgModes x)
                              (view mesgMe    x)
                              nick
                              (view mesgContent x)
                   : compressMessages xs
    ActionMsgType -> CompAction (view mesgModes x)
                                nick (view mesgContent x) : compressMessages xs
    _             -> meta [] (x:xs)

  where
  nick = views mesgSender userNick x

meta :: [CompressedMeta] -> [IrcMessage] -> [CompressedMessage]
meta acc [] = [CompMeta (reverse acc)]
meta acc (x:xs) =
    case view mesgType x of
      JoinMsgType -> meta (CompJoin nick : acc) xs
      QuitMsgType -> meta (CompQuit nick : acc) xs
      PartMsgType -> meta (CompPart nick : acc) xs
      KickMsgType -> meta (CompKick nick : acc) xs
      NickMsgType -> meta (CompNick nick (view mesgContent x) : acc) xs
      TopicMsgType -> meta (CompTopic nick : acc) xs
      _ -> CompMeta (reverse acc) : compressMessages (x:xs)

  where
  nick = views mesgSender userNick x

data CompressedMessage
  = CompChat String Bool ByteString Text
  | CompNotice String ByteString Text
  | CompAction String ByteString Text
  | CompMeta [CompressedMeta]

data CompressedMeta
  = CompJoin ByteString
  | CompQuit ByteString
  | CompPart ByteString
  | CompNick ByteString Text
  | CompKick ByteString
  | CompTopic ByteString
