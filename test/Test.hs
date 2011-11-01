{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Time.Parsers
import Data.Time.Parsers.Types
import Data.Time.Parsers.Tables         (timezones)

import Control.Applicative              ((<$>),(<*>))
import Data.Attoparsec.Char8
import qualified Data.ByteString.Char8  as B
import Data.Fixed                       (Pico)
import Data.Map                         (elems)
import qualified Data.Set               as Set
import Data.Time
import Data.Time.Clock.POSIX            (posixSecondsToUTCTime)
import System.Locale                    (defaultTimeLocale)
import Test.QuickCheck

main :: IO ()
main = do dateTests
          timeTests
          timezoneTests
          timestampTests

formatAs :: FormatTime a => String -> a -> B.ByteString
formatAs = (B.pack .) . formatTime defaultTimeLocale

parseFormats :: (FormatTime a, Eq a) =>
                Options -> OptionedParser a -> [String] -> a -> Bool
parseFormats options parser outputFormats value =
    let bytestrings = map (flip formatAs value) outputFormats
        parses = mapM (maybeResult . debugParse options parser) bytestrings
    in  maybe False (and . map (value==)) parses


dateTests :: IO ()
dateTests = do
    putStrLn "Date Tests -----------"
    putStr "fourTwoTwo test:        "
    quickCheck fourTwoTwoTest
    putStr "twoTwoTwo test:         "
    quickCheck twoTwoTwoTest
    putStr "charSeparated test 1:   "
    quickCheck charSeparatedTest1
    putStr "charSeparated test 2:   "
    quickCheck charSeparatedTest2
    putStr "charSeparated test 3:   "
    quickCheck charSeparatedTest3
    putStr "charSeparated test 4:   "
    quickCheck charSeparatedTest4
    putStr "fullDate Test1:         "
    quickCheck fullDateTest1
    putStr "fullDate Test2:         "
    quickCheck fullDateTest2
    putStr "year, day of year test: "
    quickCheck yearDayOfYearTest
    putStr "julian day test:        "
    quickCheck julianDayTest
    putStr "default date test:      "
    quickCheck defaultDateTest

dayFromYearRange :: Integer -> Integer -> Gen Day
dayFromYearRange miny maxy = fromGregorian      <$>
                             choose (miny,maxy) <*>
                             choose (1,12)      <*>
                             choose (1,31)

unambiguousDayUnder :: Integer -> Gen Day
unambiguousDayUnder year = fromGregorian    <$>
                           choose (32,year) <*>
                           choose (1,12)    <*>
                           choose (13,31)

fourTwoTwoTest :: Property
fourTwoTwoTest =
    forAll ( dayFromYearRange 0 9999 ) $
    parseFormats defaultOptions fourTwoTwo ["%C%y%m%d"]

twoTwoTwoTest :: Property
twoTwoTwoTest =
    forAll ( dayFromYearRange 1970 2069 ) $
    parseFormats defaultOptions twoTwoTwo ["%y%m%d"]

charSeparatedTest1 :: Property
charSeparatedTest1 =
    forAll ( dayFromYearRange 0 20000 ) $
    parseFormats customOptions charSeparated outputFormats
  where
    customOptions = defaultOptions {formats = [DMY]}
    outputFormats = [ "%d/%m/%C%y"
                    , "%d-%m-%C%y"
                    , "%d.%m.%C%y"
                    , "%d %m %C%y"
                    , "%d-%B-%C%y"
                    , "%d-%b-%C%y"
                    ]

charSeparatedTest2 :: Property
charSeparatedTest2 =
    forAll ( dayFromYearRange 1970 2069 ) $
    parseFormats customOptions charSeparated outputFormats
  where
    customOptions = defaultOptions {formats = [MDY]}
    outputFormats = [ "%m/%d/%y"
                    , "%m-%d-%y"
                    , "%m.%d.%y"
                    , "%m %d %y"
                    , "%B %d %y"
                    , "%b %d %y"
                    ]

charSeparatedTest3 :: Property
charSeparatedTest3 =
    forAll ( dayFromYearRange 1 999 ) $
    parseFormats customOptions charSeparated outputFormats
  where
    customOptions = defaultOptions{ flags = Set.empty
                                  , formats = [YMD]
                                  }
    outputFormats = [ "%Y/%m/%d"
                    , "%Y-%m-%d"
                    , "%Y.%m.%d"
                    , "%Y %m %d"
                    , "%Y %B %d"
                    , "%Y %b %d"
                    ]

charSeparatedTest4 :: Property
charSeparatedTest4 =
    forAll ( unambiguousDayUnder 1500 ) $
    parseFormats customOptions charSeparated outputFormats
  where
    customOptions = defaultOptions{formats = [DMY,MDY,YMD]}
    outputFormats = ["%C%y-%m-%d"]

fullDateTest1 :: Property
fullDateTest1 =
    forAll ( dayFromYearRange 1 9999 ) $
    parseFormats defaultOptions fullDate outputFormats
  where
    outputFormats = [ "%B %d, %C%y"
                    , "%b %d, %C%y"
                    ]

fullDateTest2 :: Property
fullDateTest2 =
    forAll ( dayFromYearRange 1970 2069 ) $
    parseFormats defaultOptions fullDate outputFormats
  where
    outputFormats = [ "%B %d, %y"
                    , "%b %d, %y"
                    ]

yearDayOfYearTest :: Property
yearDayOfYearTest =
    forAll ( dayFromYearRange 1 9999 ) $
    parseFormats defaultOptions yearDayOfYear outputFormats
  where
    outputFormats = [ "%f%y/%j"
                    , "%f%y %j"
                    , "%f%y.%j"
                    , "%f%y-%j"
                    , "%f%y%j"
                    ]

julianDayTest :: Property
julianDayTest =
    let duck = flip (B.append) . B.pack . show . toModifiedJulianDay
        beef day = maybe False (day ==) . maybeResult .
                   debugParse defaultOptions julianDay . duck day
        pants day = and $ map (beef day) ["J", "JD", "Julian"]
    in  forAll ( dayFromYearRange (-9999) 9999 ) pants

defaultDateTest :: Property
defaultDateTest =
    forAll (unambiguousDayUnder 9999) $
    parseFormats customOptions defaultDate outputFormats
  where
    customOptions = defaultOptions{formats = [DMY,MDY,YMD]}
    outputFormats = [ "%C%y-%m-%d"
                    , "%C%y%m%d"
                    , "%B %d, %C%y"
                    , "%f%y%j"
                    ]

arbitraryPico :: Gen Pico
arbitraryPico = (cast .) . (+)  <$>
                choose (0,59)   <*>
                choose (0.0,1.0)
  where
    cast :: Double -> Pico
    cast = realToFrac

timeTests :: IO ()
timeTests = do
    putStrLn "Time Tests ------------"
    putStr   "twentyFourHour test 1: "
    quickCheck twentyFourHourTest1
    putStr   "twentyFourHour test 2: "
    quickCheck twentyFourHourTest2
    putStr   "twentyFourHour test 3: "
    quickCheck twentyFourHourTest3
    putStr   "twentyFourHour test 4: "
    quickCheck twentyFourHourTest4
    putStr   "twelveHour test 1:     "
    quickCheck twelveHourTest1
    putStr   "twelveHour test 2:     "
    quickCheck twelveHourTest2
    putStr   "twelveHour test 3:     "
    quickCheck twelveHourTest3
    putStr   "twelveHour test 4:     "
    quickCheck twelveHourTest4

twentyFourHourTest1 :: Property
twentyFourHourTest1 =
    forAll timeOfDay $ parseFormats defaultOptions twentyFourHour outputFormats
  where
    timeOfDay = TimeOfDay     <$>
                choose (0,23) <*>
                choose (0,59) <*>
                arbitraryPico
    outputFormats = [ "%H:%M:%S%Q"
                    , "%H%M%S%Q"
                    ]

twentyFourHourTest2 :: Property
twentyFourHourTest2 =
    forAll timeOfDay $ parseFormats defaultOptions twentyFourHour outputFormats
  where
    timeOfDay = TimeOfDay     <$>
                choose (0,23) <*>
                choose (0,59) <*>
                (fromInteger <$> choose (0,60))
    outputFormats = [ "%H:%M:%S"
                    , "%H%M%S"
                    ]

twentyFourHourTest3 :: Property
twentyFourHourTest3 =
    forAll timeOfDay $ parseFormats defaultOptions twentyFourHour outputFormats
  where
    timeOfDay = TimeOfDay     <$>
                choose (0,23) <*>
                choose (0,59) <*>
                return 0
    outputFormats = [ "%H:%M"
                    , "%H%M"
                    ]

twentyFourHourTest4 :: Property
twentyFourHourTest4 =
    forAll timeOfDay $ parseFormats defaultOptions twentyFourHour ["%H"]
  where
    timeOfDay = TimeOfDay     <$>
                choose (0,23) <*>
                return 0      <*>
                return 0

twelveHourTest1 :: Property
twelveHourTest1 =
    forAll timeOfDay $ parseFormats defaultOptions twelveHour outputFormats
  where
    timeOfDay = TimeOfDay     <$>
                choose (0,23) <*>
                choose (0,59) <*>
                arbitraryPico
    outputFormats = [ "%I:%M:%S%Q %P"
                    , "%I:%M:%S%Q %p"
                    , "%I:%M:%S%Q%P"
                    , "%I:%M:%S%Q%p"
                    ]

twelveHourTest2 :: Property
twelveHourTest2 =
    forAll timeOfDay $ parseFormats defaultOptions twelveHour outputFormats
  where
    timeOfDay = TimeOfDay     <$>
                choose (0,23) <*>
                choose (0,59) <*>
                (fromInteger <$> choose (0,60))
    outputFormats = [ "%I:%M:%S %P"
                    , "%I:%M:%S %p"
                    , "%I:%M:%S%P"
                    , "%I:%M:%S%p"
                    ]

twelveHourTest3 :: Property
twelveHourTest3 =
    forAll timeOfDay $ parseFormats defaultOptions twelveHour outputFormats
  where
    timeOfDay = TimeOfDay     <$>
                choose (0,23) <*>
                choose (0,59) <*>
                return 0
    outputFormats = [ "%I:%M %P"
                    , "%I:%M %p"
                    , "%I:%M%P"
                    , "%I:%M%p"
                    ]

twelveHourTest4 :: Property
twelveHourTest4 =
    forAll timeOfDay $ parseFormats defaultOptions twelveHour outputFormats
  where
    timeOfDay = TimeOfDay     <$>
                choose (0,23) <*>
                return 0      <*>
                return 0
    outputFormats = [ "%I %P"
                    , "%I %p"
                    , "%I%P"
                    , "%I%p"
                    ]

timezoneTests :: IO ()
timezoneTests = do
    putStrLn "Timezone Tests -------"
    putStr   "Offset timezone test: "
    quickCheck offsetTimezoneTest
    putStr   "Named timezone test:  "
    quickCheck namedTimezoneTest

namedTimezoneTest :: Property
namedTimezoneTest =
    forAll timezones' $ parseFormats defaultOptions defaultTimezone ["%Z"]
  where
    timezones' = elements $ elems timezones

offsetTimezoneTest :: Property
offsetTimezoneTest =
    forAll timezones' $ parseFormats defaultOptions offsetTimezone ["%z"]
  where
    timezones' = TimeZone              <$>
                 choose (- 1439, 1439) <*>
                 return False          <*>
                 return ""

timestampTests :: IO ()
timestampTests = do
    putStrLn "Timestamp Tests ---"
    putStr   "Local Time test 1: "
    quickCheck localTimeTest1
    putStr   "Local Time test 2: "
    quickCheck localTimeTest2
    putStr   "Zoned Time test 1: "
    quickCheck zonedTimeTest1
    putStr   "Zoned Time test 2: "
    quickCheck zonedTimeTest2
    putStr   "Zoned Time test 3: "
    quickCheck zonedTimeTest3
    putStr   "Posix Time test 1: "
    quickCheck posixTimeTest1
    putStr   "Posix Time test 2: "
    quickCheck posixTimeTest2

localTimeTest1 :: Property
localTimeTest1 =
    forAll timestamps $ parseFormats defaultOptions localTime' outputFormats
  where
    localTime' = localTime defaultDate defaultTime
    timestamps = LocalTime <$>
                 dayFromYearRange 1970 2069 <*>
                 times
    times = TimeOfDay <$> choose (0,23) <*> choose (0,59) <*> return 0
    outputFormats = [ "%Y-%m-%d %H:%M"
                    , "%C%y%m%dT%H%M"
                    , "%y%m%d %I:%M %P"
                    , "%B %d, %YT%H%M"
                    ]

localTimeTest2 :: Property
localTimeTest2 =
    forAll timestamps $ parseFormats defaultOptions localTime' outputFormats
  where
    localTime' = localTime defaultDate defaultTime
    timestamps = LocalTime <$>
                 dayFromYearRange 1970 2069 <*>
                 return midnight
    outputFormats = [ "%Y-%m-%d"
                    , "%C%y%m%d"
                    , "%y%m%d"
                    , "%B %d, %Y"
                    ]

instance Eq ZonedTime where
    (ZonedTime d tz) == (ZonedTime d' tz') = d == d' && tz == tz'

zonedTimeTest1 :: Property
zonedTimeTest1 =
    forAll timestamps $ parseFormats defaultOptions zonedTime' outputFormats
  where
    zonedTime' = anyFromZoned defaultDate defaultTime defaultTimezone
    timestamps = ZonedTime <$> localTimes <*> timezones'
    localTimes = LocalTime <$> dayFromYearRange 1970 2069 <*> times
    times = TimeOfDay <$> choose (0,23) <*> choose (0,59) <*> return 0
    timezones' = elements $ elems timezones
    outputFormats = [ "%Y-%m-%d %H:%M %Z"
                    , "%C%y%m%dT%H%M%Z"
                    , "%y%m%d %I:%M %P %Z"
                    , "%B %d, %YT%H%M%Z"
                    ]

zonedTimeTest2 :: Property
zonedTimeTest2 =
    forAll timestamps $ parseFormats defaultOptions zonedTime' outputFormats
  where
    zonedTime' = zonedTime defaultDate defaultTime defaultTimezone
    timestamps = ZonedTime <$> localTimes <*> timezones'
    localTimes = LocalTime <$> dayFromYearRange 1970 2069 <*> times
    times = TimeOfDay <$> choose (0,23) <*> choose (0,59) <*> return 0
    timezones' = minutesToTimeZone <$> choose (-1439, 1439)
    outputFormats = [ "%Y-%m-%d %H:%M %z"
                    , "%C%y%m%dT%H%M%z"
                    , "%y%m%d %I:%M %P %z"
                    , "%B %d, %YT%H%M%z"
                    ]

zonedTimeTest3 :: Property
zonedTimeTest3 =
    forAll timestamps $ parseFormats defaultOptions zonedTime' outputFormats
  where
    zonedTime' = anyFromZoned defaultDate defaultTime defaultTimezone
    timestamps = ZonedTime <$> localTimes <*> return utc
    localTimes = LocalTime <$> dayFromYearRange 1970 2069 <*> times
    times = TimeOfDay <$> choose (0,23) <*> choose (0,59) <*> return 0
    outputFormats = [ "%Y-%m-%d %H:%M"
                    , "%C%y%m%dT%H%M"
                    , "%y%m%d %I:%M %P"
                    , "%B %d, %YT%H%M"
                    ]

posixTimeTest1 :: Property
posixTimeTest1 =
    forAll timestamps $ parseFormats defaultOptions anyFromPosix ["%s"]
  where
    timestamps = posixSecondsToUTCTime . realToFrac <$> (arbitrary::Gen Integer)

posixTimeTest2 :: Property
posixTimeTest2 =
    forAll timestamps $ parseFormats defaultOptions anyFromPosix ["%s%Q"]
  where
    timestamps = posixSecondsToUTCTime . realToFrac . abs <$>
                 (arbitrary::Gen Double)