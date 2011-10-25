{-# LANGUAGE OverloadedStrings #-}
module Data.Time.Parsers where

import Data.Time.Parsers.Types
import Data.Time.Parsers.Util

import Control.Applicative                  ((<$>),(<*>),(<|>))
import Control.Monad.Reader
import Data.Attoparsec.Char8                as A
import Data.Attoparsec.FastSet
import Data.Fixed
import Data.Time                            hiding (parseTime)
import qualified Data.ByteString.Char8      as B

--Utility Parsers

nDigit :: (Read a, Num a) => Int -> Parser a
nDigit n = read <$> count n digit

count2 :: Parser DateToken
count2 = Any <$> nDigit 2

count4 :: Parser DateToken
count4 = Year <$> nDigit 4

parsePico :: Parser Pico
parsePico = (+) <$> (fromInteger <$> decimal) <*> (option 0 postradix)
  where
  postradix = do
    _ <- char '.'
    bs <- A.takeWhile isDigit
    let i = fromInteger . read . B.unpack $ bs
        l = B.length bs
    return (i/10^l)

parseDateToken :: FastSet -> Parser DateToken
parseDateToken seps' = readDateToken =<< (takeTill $ flip memberChar seps')

--Date Parsers

fourTwoTwo :: ReaderT Options Parser Day
fourTwoTwo = lift fourTwoTwo'

fourTwoTwo' :: Parser Day
fourTwoTwo' = ($ YMD) =<< (makeDate <$> count4 <*> count2 <*> count2)

twoTwoTwo :: ReaderT Options Parser Day
twoTwoTwo = (asks formats) >>= (lift . twoTwoTwo')

twoTwoTwo' :: [DateFormat] -> Parser Day
twoTwoTwo' fs = tryFormats fs =<<
                (makeDate <$> count2 <*> count2 <*> count2)

charSeparated :: ReaderT Options Parser Day
charSeparated = do
    s <- asks seps
    f <- asks formats
    m <- asks makeRecent
    lift $ charSeparated' s f m

charSeparated' :: FastSet -> [DateFormat] -> Bool -> Parser Day
charSeparated' seps' formats' makeRecent' = do
    a   <- parseDateToken seps'
    sep <- satisfy $ flip memberChar seps'
    b   <- parseDateToken seps'
    _   <- satisfy (==sep)
    c   <- readDateToken =<< A.takeWhile isDigit
    let noYear (Year _) = False
        noYear _        = True
        noExplicitYear  = and . map noYear $ [a,b,c]
    date <- tryFormats formats' =<< (return $ makeDate a b c)
    if (makeRecent' && noExplicitYear)
    then return $ forceRecent date
    else return date

fullDate :: ReaderT Options Parser Day
fullDate = asks makeRecent >>= lift . fullDate'

fullDate' :: Bool -> Parser Day
fullDate' makeRecent' = do
    month <- maybe mzero (return . Month) <$>
             lookupMonth =<< (A.takeWhile isAlpha_ascii)
    _ <- space
    day <- Any . read . B.unpack <$> A.takeWhile isDigit
    _ <- string ", "
    year <- readDateToken =<< A.takeWhile isDigit
    let forceRecent' = if (noYear year && makeRecent')
                       then forceRecent
                       else id
    forceRecent' <$> makeDate month day year MDY
  where
    noYear (Year _) = False
    noYear _        = True

yearDayOfYear :: ReaderT Options Parser Day
yearDayOfYear = do
    s <- asks seps
    lift $ yearDayOfYear' s

yearDayOfYear' :: FastSet -> Parser Day
yearDayOfYear' seps' = do
    year <- nDigit 4
    day  <- maybeSep >> nDigit 3
    yearDayToDate year day
  where
    maybeSep = option () $ satisfy (flip memberChar seps') >> return ()

julianDay :: ReaderT Options Parser Day
julianDay = lift julianDay'

julianDay' :: Parser Day
julianDay' = (string "Julian" <|> string "JD" <|> string "J") >>
             ModifiedJulianDay <$> signed decimal

--Time Parsers

twelveHour :: ReaderT Options Parser TimeOfDay
twelveHour = do leapSec <- asks allowLeapSeconds
                th <- lift twelveHour'
                let seconds = timeOfDayToTime th
                if (not leapSec && seconds >= 86400)
                then mzero
                else return th


twelveHour' :: Parser TimeOfDay
twelveHour' = do
    h' <- (nDigit 2 <|> nDigit 1)
    m  <- option 0 $ char ':' >> nDigit 2
    s  <- option 0 $ char ':' >> parsePico
    ampm <- skipSpace >> (string "AM" <|> string "PM")
    h <- case ampm of
      "AM" -> make24 False h'
      "PM" -> make24 True h'
      _    -> fail "Should be impossible."
    maybe (fail "Invalid Time Range") return $
      makeTimeOfDayValid h m s
  where
    make24 pm h = case compare h 12 of
        LT -> return $ if pm then (h+12) else h
        EQ -> return $ if pm then 12 else 0
        GT -> mzero

twentyFourHour :: ReaderT Options Parser TimeOfDay
twentyFourHour = do leapSec <- asks allowLeapSeconds
                    tfh <- lift twentyFourHour'
                    let seconds = timeOfDayToTime tfh
                    if (not leapSec && seconds >= 86400)
                    then mzero
                    else return tfh

twentyFourHour' :: Parser TimeOfDay
twentyFourHour' = maybe (fail "Invalid Time Range") return =<<
                  (colon <|> nocolon)
  where
    colon = makeTimeOfDayValid <$>
            (nDigit 2 <|> nDigit 1) <*>
            (char ':' >> nDigit 2) <*>
            (option 0 $ char ':' >> parsePico)
    nocolon = makeTimeOfDayValid <$>
              nDigit 2 <*>
              option 0 (nDigit 2) <*>
              option 0 parsePico

--TimeZone Parsers

timezone :: ReaderT Options Parser TimeZone
timezone = lift timezone'

timezone' :: Parser TimeZone
timezone' =  (char 'Z' >> return utc) <|> ((plus <|> minus) <*> timezone'')
  where
    plus  = char '+' >> return minutesToTimeZone
    minus = char '-' >> return (minutesToTimeZone . negate)
    hour p = p >>= (\n -> if (n < 12) then (return $ 60*n) else mzero)
    minute  p = option () (char ':' >> return ()) >> p >>=
                (\n -> if (n < 60) then return n else mzero)
    timezone'' = choice [ (+) <$> (hour $ nDigit 2) <*> (minute $ nDigit 2)
                        , (+) <$> (hour $ nDigit 1) <*> (minute $ nDigit 2)
                        , hour $ nDigit 2
                        , hour $ nDigit 1
                        ]

namedTimezone :: ReaderT Options Parser TimeZone
namedTimezone = asks australianTimezones >>= lift . namedTimezone'

namedTimezone' :: Bool -> Parser TimeZone
namedTimezone' aussie = (lookup' <$> A.takeWhile isAlpha_ascii) >>=
                        maybe (fail "Invalid Timezone") return
  where
    lookup' = if aussie then lookupAusTimezone else lookupTimezone

--Defaults and Debugging

defaultOptions :: Options
defaultOptions = Options { formats = [YMD,DMY,MDY]
                         , makeRecent = True
                         , minDate = Nothing
                         , maxDate = Nothing
                         , seps = (set ". /-")
                         , allowLeapSeconds = False
                         , australianTimezones = False
                         }

defaultDate :: ReaderT Options Parser Day
defaultDate = charSeparated <|>
              fourTwoTwo    <|>
              twoTwoTwo     <|>
              fullDate      <|>
              yearDayOfYear <|>
              julianDay

defaultTime :: ReaderT Options Parser TimeOfDay
defaultTime = twelveHour <|> twentyFourHour

defaultTimeZone :: ReaderT Options Parser TimeZone
defaultTimeZone = timezone <|> namedTimezone

debugParse :: Options -> ReaderT Options Parser a ->
              B.ByteString -> Result a
debugParse opt p = flip feed B.empty . parse (runReaderT p opt)