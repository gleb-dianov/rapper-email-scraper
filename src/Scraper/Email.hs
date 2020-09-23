module Scraper.Email
  ( extractEmails

  -- * exported for testing purposes only
  , Email(..)
  , findEmailInText
  )
  where

import Scraper.Duplicates
import Scraper.Unmatched

import Control.Lens
import Protolude
import Text.Regex.Posix (Regex)

import qualified Data.Text         as Txt
import qualified System.Directory  as Dir
import qualified Text.Regex.Lens   as Regex
import qualified Text.Regex.Quote  as Regex
import qualified Web.Twitter.Types as Twitter


extractEmails :: MonadIO m => [Twitter.Status] -> m ()
extractEmails feed = do
  let tweets = feed <&> \Twitter.Status{..} ->
        (statusId, statusText)

      maybeEmails
        = removeDuplicateEmails
        $ zipWith (\(id, text) email -> (id, text, email)) tweets
        $ findEmailInText . snd <$> tweets

      filePath = "rapper-emails.txt"

  fileExists <- liftIO $ Dir.doesFileExist filePath

  savedEmails <-
    if fileExists
    then liftIO $ fmap Email . Txt.lines <$> readFile filePath
    else pure []

  emails <-
    (\accumulator -> foldM accumulator [] maybeEmails) $ \accumulated -> \case
      (_, _, Just email) ->
        pure $ email : accumulated

      (statusId, tweetText, Nothing) -> do
        saveUnmatchedTweet UnmatchedTweet{..}

        pure accumulated


  void $ forM (filter (not . flip elem savedEmails) emails) $ \(Email email) ->
    liftIO $ appendFile filePath $ email <> "\n"


newtype Email
  = Email Text
  deriving newtype (Show, Eq)

findEmailInText :: Text -> Maybe Email
findEmailInText text
  =   Email . Txt.toLower . decodeUtf8 . Regex._matchedString
  <$> encodeUtf8 text ^? Regex.regex emailRegex

  where
    emailRegex
      = [Regex.r|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|]