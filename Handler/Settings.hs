{-# LANGUAGE TupleSections, OverloadedStrings #-}
module Handler.Settings where

import           Import
import qualified Data.Text  as T
import           Data.List (sort)
import           System.FilePath ((</>))
import           System.Directory (getDirectoryContents)
import           Data.Foldable as Foldable (forM_)
-------------------------------------------------------------------------------------------------------------------
settingsForm :: [(Text,Text)] -> -- ^ All boards
               [Text] -> -- ^ Ignored boards
               Censorship -> -- ^ Default rating 
               Html   -> -- ^ Extra token
               MForm Handler (FormResult (Int, Text, Maybe Text, Maybe [Text], Censorship), Widget)
settingsForm allBoards ignoredBoards oldRating extra = do
  AppSettings{..} <- appSettings <$> getYesod

  let stylesheetsPath = appStaticDir </> "stylesheets"
  stylesheets <- liftIO ((map ((pack &&& pack). takeWhile ((/=)'.')) . filter (\f -> f/="."&&f/="..") . sort) <$> getDirectoryContents stylesheetsPath)

  oldTimeZone <- lookupSession "timezone"
  oldStyle    <- lookupSession "stylesheet"
  (timezoneRes , timezoneView) <- mreq (selectFieldList timezones  ) "" (Just $ maybe appTimezone (read . unpack) oldTimeZone)
  (styleRes    , styleView   ) <- mreq (selectFieldList stylesheets) "" (Just $ fromMaybe appStylesheet oldStyle)
  (langRes     , langView    ) <- mopt (selectFieldList langs      ) "" Nothing
  (boardResults, boardViews  ) <- mopt (multiSelectFieldList allBoards) "" (Just $ Just ignoredBoards)
  (ratingRes   , ratingView  ) <- mreq (selectFieldList ratings    ) "" (Just oldRating)
  let result = (,,,,) <$> timezoneRes <*> styleRes <*> langRes <*> boardResults <*> ratingRes
      widget = $(widgetFile "settings-form")
  return (result, widget)

postSettingsR :: Handler TypedContent
postSettingsR = do
  mgroup        <- (fmap $ userGroup . entityVal) <$> maybeAuth
  allBoards     <- map ((boardTitle &&& boardName) . entityVal) . filter (not . isBoardHidden mgroup) <$> runDB (selectList ([]::[Filter Board]) [])
  ignoredBoards <- getFeedBoards
  oldRating     <- getCensorshipRating
  ((result, _), _) <- runFormPost $ settingsForm  allBoards ignoredBoards oldRating
  case result of
    FormFailure []                  -> trickyRedirect "error" (Left MsgBadFormData) SettingsR
    FormFailure xs                  -> trickyRedirect "error" (Left $ MsgError $ T.intercalate "; " xs) SettingsR
    FormMissing                     -> trickyRedirect "error" (Left MsgNoFormData)  SettingsR
    FormSuccess (timezone, stylesheet, lang, boards, rating) -> do
      setSession "timezone"   $ tshow timezone
      setSession "stylesheet" stylesheet
      setSession "feed-ignore-boards" $ tshow $ fromMaybe [] boards
      setSession "censorship-rating" $ tshow rating
      Foldable.forM_ lang setLanguage
      trickyRedirect "ok" (Left MsgApplied) SettingsR

getSettingsR :: Handler Html
getSettingsR = do
  mgroup          <- (fmap $ userGroup . entityVal) <$> maybeAuth
  allBoards       <- map ((boardTitle &&& boardName) . entityVal) . filter (not . isBoardHidden mgroup) <$> runDB (selectList ([]::[Filter Board]) [])
  ignoredBoards   <- getFeedBoards
  oldRating       <- getCensorshipRating
  (formWidget, formEnctype) <- generateFormPost $ settingsForm allBoards ignoredBoards oldRating
  hiddenThreads   <- getAllHiddenThreads
  msgrender       <- getMessageRender
  defaultLayout $ do
    defaultTitleMsg MsgSettings
    $(widgetFile "settings")

-------------------------------------------------------------------------------------------------------------------
ratings :: [(Text, Censorship)]
ratings = map (pack . show &&& id) [minBound..maxBound]

langs :: [(Text, Text)]
langs = [("English", "en"), ("Русский","ru"), ("Português Brasil", "br")]

timezones :: [(Text, Int)]
timezones = [("[UTC -11:00] Pacific/Midway",-39600)
            ,("[UTC -10:00] Pacific/Honolulu",-36000)
            ,("[UTC -09:30] Pacific/Marquesas",-34200)
            ,("[UTC -09:00] Pacific/Gambier",-32400)
            ,("[UTC -08:00] America/Anchorage",-28800)
            ,("[UTC -07:00] America/Los_Angeles",-25200)
            ,("[UTC -06:00] America/Costa_Rica",-21600)
            ,("[UTC -06:00] Pacific/Easter",-21600)
            ,("[UTC -05:00] America/Mexico_City",-18000)
            ,("[UTC -05:00] America/Panama",-18000)
            ,("[UTC -04:30] America/Caracas",-16200)
            ,("[UTC -04:00] America/New_York",-14400)
            ,("[UTC -03:00] America/Araguaina",-10800)
            ,("[UTC -03:00] Atlantic/Stanley",-10800)
            ,("[UTC -02:30] America/St_Johns",-9000)
            ,("[UTC -02:00] America/Noronha",-7200)
            ,("[UTC -02:00] Atlantic/South_Georgia",-7200)
            ,("[UTC -01:00] Atlantic/Cape_Verde",-3600)
            ,("[UTC -00:00] Africa/Dakar",0)
            ,("[UTC -00:00] America/Danmarkshavn",0)
            ,("[UTC -00:00] Atlantic/St_Helena",0)
            ,("[UTC -00:00] UTC",0)
            ,("[UTC +01:00] Africa/Tunis",3600)
            ,("[UTC +01:00] Atlantic/Canary",3600)
            ,("[UTC +01:00] Europe/London",3600)
            ,("[UTC +02:00] Africa/Cairo",7200)
            ,("[UTC +02:00] Europe/Berlin",7200)
            ,("[UTC +02:00] Europe/Madrid",7200)
            ,("[UTC +02:00] Europe/Paris",7200)
            ,("[UTC +02:00] Europe/Rome",7200)
            ,("[UTC +03:00] Asia/Damascus",10800)
            ,("[UTC +03:00] Asia/Jerusalem",10800)
            ,("[UTC +03:00] Europe/Kaliningrad",10800)
            ,("[UTC +03:00] Europe/Kiev",10800)
            ,("[UTC +03:00] Europe/Riga",10800)
            ,("[UTC +03:00] Indian/Comoro",10800)
            ,("[UTC +04:00] Europe/Moscow",14400)
            ,("[UTC +04:00] Asia/Tbilisi",14400)
            ,("[UTC +04:00] Indian/Mahe",14400)
            ,("[UTC +04:30] Asia/Kabul",16200)
            ,("[UTC +05:00] Asia/Baku",18000)
            ,("[UTC +06:00] Asia/Yekaterinburg",21600)
            ,("[UTC +06:00] Indian/Chagos",21600)
            ,("[UTC +07:00] Asia/Bangkok",25200)
            ,("[UTC +07:00] Asia/Omsk",25200)
            ,("[UTC +08:00] Asia/Hong_Kong",28800)
            ,("[UTC +08:00] Australia/Perth",28800)
            ,("[UTC +09:00] Asia/Tokyo",32400)
            ,("[UTC +09:00] Pacific/Palau",32400)
            ,("[UTC +09:30] Australia/Darwin",34200)
            ,("[UTC +10:00] Asia/Yakutsk",36000)
            ,("[UTC +10:00] Australia/Sydney",36000)
            ,("[UTC +10:00] Pacific/Guam",36000)
            ,("[UTC +10:30] Australia/Lord_Howe",37800)
            ,("[UTC +11:00] Asia/Vladivostok",39600)
            ,("[UTC +11:00] Pacific/Efate",39600)
            ,("[UTC +12:00] Asia/Kamchatka",43200)
            ,("[UTC +12:00] Pacific/Auckland",43200)
            ,("[UTC +12:45] Pacific/Chatham",45900)
            ,("[UTC +13:00] Pacific/Tongatapu",46800)
            ,("[UTC +14:00] Pacific/Kiritimati",50400)
            ]
