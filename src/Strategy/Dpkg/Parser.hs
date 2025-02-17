module Strategy.Dpkg.Parser (
  DpkgEntry (..),
  dpkgEntriesParser,
  -- | For testing
  dpkgEntryParser,
) where

import Control.Monad (void)
import Data.Map (Map)
import Data.Map qualified as Map
import Data.String.Conversion (toText)
import Data.Text (Text)
import Data.Void (Void)
import Text.Megaparsec (
  MonadParsec (eof, notFollowedBy, takeWhileP),
  Parsec,
  anySingle,
  chunk,
  empty,
  many,
  manyTill,
  single,
  some,
  someTill,
  try,
  (<|>),
 )
import Text.Megaparsec.Char.Lexer (lexeme)
import Text.Megaparsec.Char.Lexer qualified as Lexer

type Parser = Parsec Void Text

-- | An entry in the dpkg database, consisting of the architecture, package, and version.
data DpkgEntry = DpkgEntry
  { dpkgEntryArch :: Text
  , dpkgEntryPackage :: Text
  , dpkgEntryVersion :: Text
  }
  deriving (Eq, Ord, Show)

-- | Parses a dpkg status file.
dpkgEntriesParser :: Parser [DpkgEntry]
dpkgEntriesParser = many dpkgEntryParser <* eof

-- | Parses a dpkg status entry.
dpkgEntryParser :: Parser DpkgEntry
dpkgEntryParser = do
  properties <- propertiesParser
  let package = Map.lookup "Package" properties
  let version = Map.lookup "Version" properties
  let arch = Map.lookup "Architecture" properties

  case (package, version, arch) of
    (Just package', Just version', Just arch') -> pure $ DpkgEntry arch' package' version'
    _ -> fail $ buildFailure package version arch
  where
    buildFailure :: Maybe Text -> Maybe Text -> Maybe Text -> String
    buildFailure package version arch =
      "parse all of required 'Package', 'Version', 'Architecture' keys."
        <> " Package: "
        <> show package
        <> "; Version: "
        <> show version
        <> "; Arch: "
        <> show arch

    -- Collect Key: Value pairs into a map.
    -- Each entry is separated by a blank line.
    propertiesParser :: Parser (Map Text Text)
    propertiesParser = Map.fromList <$> manyTill (lexeme sc propertyParser) eov

    -- Collect Key: Value pairs into actual tuples.
    propertyParser :: Parser (Text, Text)
    propertyParser = (,) <$> (keyParser <* symbol ":") <*> valueParser

    -- Keys are easy: just parse anything up to the ':' literal.
    keyParser :: Parser Text
    keyParser = takeWhileP Nothing (/= ':')

    -- Value fields are either single line or multi line.
    -- There's no documentation I could find on this,
    -- but from observeration it appears that a single space indent is used
    -- to form a multi-line value, with intentionally blank lines consisting
    -- of a single literal dot after the space.
    valueParser :: Parser Text
    valueParser = toText <$> someTill anySingle eov

    -- The end of a value: A newline not followed by a space, or the end of the input.
    eov :: Parser ()
    eov = try (eol <* notFollowedBy (single ' ')) <|> eof

    -- The end of a line.
    eol :: Parser ()
    eol = try (void (chunk "\r\n")) <|> void (chunk "\n")

-- | Consume spaces, not including newlines.
sc :: Parser ()
sc = Lexer.space (void $ some (single ' ' <|> single '\t')) empty empty

-- | Parse for the provided symbol, then consume any trailing spaces.
symbol :: Text -> Parser Text
symbol = Lexer.symbol sc
