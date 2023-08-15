{-# Language TemplateHaskell, OverloadedStrings, BangPatterns #-}

{-|
Module      : Client.WhoReply
Description : Parsed replies from WHO
Copyright   : (c) TheDaemoness, 2023
License     : ISC
Maintainer  : emertens@gmail.com

Because WHOX allows for a LOT of fiddliness regarding parameters,
this is extracted from Client.State.Network and given its own module.
-}

module Client.WhoReply
  ( WhoReply
  , WhoReplyItem
  , newWhoReply
  , finishWhoReply
  , recordWhoReply
  , recordWhoXReply
  
  -- Lenses
  , whoQuery
  , whoFields
  , whoToken
  , whoDone
  , whoItems
  , whoChan
  , whoUserInfo
  , whoIp
  , whoServer
  , whoAway
  , whoMiscFlags
  , whoHops
  , whoIdleSecs
  , whoAcct
  , whoOpLvl
  , whoRealname
  ) where

import           Control.Lens
import           Control.Lens.Unsound (lensProduct) -- Don't worry about it. Ctrl+F SOUNDNESS.
import           Data.List (sort)
import           Data.Set (Set)
import qualified Data.Set as Set
import           Data.Text (Text)
import qualified Data.Text as Text
import           Irc.Identifier
import           Irc.UserInfo
import           Text.Read (readMaybe)
  
data WhoReply = WhoReply
  { _whoQuery  :: !(Text, Maybe Text)
  , _whoFields :: !(Set Char)
  , _whoToken  :: !String
  , _whoDone   :: !Bool
  , _whoItems  :: ![WhoReplyItem]
  }

data WhoReplyItem = WhoReplyItem
  { _whoChan      :: !Identifier
  , _whoUserInfo  :: !UserInfo
  , _whoIp        :: !Text -- We don't have iproute; (Maybe IP) would be nice here.
  , _whoServer    :: !Identifier
  , _whoAway      :: !(Maybe Bool)
  , _whoMiscFlags :: !Text
  , _whoHops      :: !(Maybe Int)
  , _whoIdleSecs  :: !String -- This can be a Maybe Int, but prettyTime takes a String.
  , _whoAcct      :: !Identifier
  , _whoOpLvl     :: !Text
  , _whoRealname  :: !Text
  } deriving (Eq, Ord)

makeLenses ''WhoReply
makeLenses ''WhoReplyItem

newWhoReply :: Text -> String -> WhoReply
newWhoReply query "" = WhoReply
  { _whoQuery = (query, Nothing)
  , _whoToken = ""
  , _whoFields = Set.empty
  , _whoDone = False
  , _whoItems = []
  }
newWhoReply query ('%':arg) = WhoReply
  { _whoQuery = (query, Just $ Text.pack ('%':arg))
  , _whoToken = token
  , _whoFields = fieldSet
  , _whoDone = False
  , _whoItems = []
  }
  where
    fieldSet = Set.fromList fields
    (fields, token) = break (== ',') arg
newWhoReply query arg = WhoReply
  { _whoQuery = (query, Just $ Text.pack arg)
  , _whoToken = ""
  , _whoFields = Set.empty
  , _whoDone = False
  , _whoItems = []
  }

splitFlags :: String -> (Maybe Bool, Text)
splitFlags ('G':rest) = (Just True,  Text.pack rest)
splitFlags ('H':rest) = (Just False, Text.pack rest)
splitFlags rest       = (Nothing,    Text.pack rest)

newWhoReplyItem :: WhoReplyItem
newWhoReplyItem = WhoReplyItem
  { _whoChan      = mkId "*"
  , _whoUserInfo  = UserInfo
    { userNick = mkId ""
    , userName = ""
    , userHost = ""
    }
  , _whoIp        = "255.255.255.255"
  , _whoServer    = ""
  , _whoAway      = Nothing
  , _whoMiscFlags = ""
  , _whoHops      = Nothing
  , _whoIdleSecs  = ""
  , _whoAcct      = "0"
  , _whoOpLvl     = "n/a"
  , _whoRealname  = ""
  }

finishWhoReply :: WhoReply -> WhoReply
finishWhoReply wr = wr { _whoDone = True, _whoItems = reverse $ sort (_whoItems wr) }

recordWhoReply :: [Text] -> WhoReply -> WhoReply
recordWhoReply [_, chan, uname, host, server, nick, flags, hcrn] reply
  | _whoDone reply = reply
  | otherwise = reply { _whoItems = wri:_whoItems reply}
  where
    wri = newWhoReplyItem
      { _whoChan = mkId chan
      , _whoUserInfo = UserInfo { userNick = mkId nick, userName = uname, userHost = host }
      , _whoServer = mkId server
      , _whoAway = away
      , _whoMiscFlags = miscFlags
      , _whoHops = readMaybe $ Text.unpack hops
      , _whoRealname = Text.stripStart realname
      }
    (hops, realname) = Text.break (== ' ') hcrn
    (away, miscFlags) = splitFlags $ Text.unpack flags
recordWhoReply _ reply = reply

-- | Field names for WHOX replies in order, excluding 't'.
whoXReplyFields :: [Char]
whoXReplyFields = "cuihsnfdlaor"

recordWhoXReply :: [Text] -> WhoReply -> WhoReply
recordWhoXReply []       reply = reply
recordWhoXReply (_:args) reply
  | _whoDone reply = reply
  | _whoToken reply == "" = withWri args
  | null args = reply
  | _whoToken reply == Text.unpack (head args) = withWri $ tail args
  | otherwise = reply
  where
    fields = filter ((flip Set.member) (_whoFields reply)) whoXReplyFields
    withWri args' = reply { _whoItems = recordWhoXReply' (zip args' fields) newWhoReplyItem:_whoItems reply}

recordWhoXReply' :: [(Text, Char)] -> WhoReplyItem -> WhoReplyItem
recordWhoXReply' [] = id
recordWhoXReply' ((arg, kind):rest) = recordWhoXReply' rest . updateFn
  where
    updateFn = case kind of
      'a' -> set whoAcct (mkId arg)
      'c' -> set whoChan (mkId arg)
      'd' -> set whoHops (readMaybe $ Text.unpack arg)
      -- SOUNDNESS: whoAway and whoMiscFlags project disjoint parts of WhoReplyItem
      'f' -> set (lensProduct whoAway whoMiscFlags) flagsSplit
      'h' -> set (whoUserInfo . uiHost) arg
      'i' -> set whoIp arg
      'l' -> set whoIdleSecs (Text.unpack arg)
      'n' -> set (whoUserInfo . uiNick) (mkId arg)
      'o' -> set whoOpLvl arg
      'r' -> set whoRealname arg
      's' -> set whoServer (mkId arg)
      'u' -> set (whoUserInfo . uiName) arg
      _   -> id
    flagsSplit = splitFlags $ Text.unpack arg
