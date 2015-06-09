module Handler.Home where

import Import

getHomeR :: Handler Html
getHomeR = do
  AppSettings{..} <- appSettings <$> getYesod
  group  <- (fmap $ userGroup . entityVal) <$> maybeAuth
  boards <- runDB $ selectList ([]::[Filter Board]) []
  config <- getConfigEntity
  let boardCategories = configBoardCategories config
      newsBoard       = configNewsBoard       config
      showNews        = configShowNews        config
      homeContent     = configHome            config
      selectFiles p   = runDB $ selectList [AttachedfileParentId ==. entityKey p] []
      selectNews      = selectList [PostBoard ==. newsBoard, PostParent ==. 0, PostDeleted ==. False]
                                   [Desc PostLocalId, LimitTo showNews]
  newsAndFiles <- runDB selectNews >>= mapM (\p -> selectFiles p >>= (\files -> return (p, files)))
  timeZone     <- getTimeZone
  defaultLayout $ do
    setTitle $ toHtml appSiteName
    $(widgetFile "homepage")
