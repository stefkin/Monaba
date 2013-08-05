{-# LANGUAGE TupleSections, OverloadedStrings, ExistentialQuantification #-}
module Handler.Api where

import           Import
import           Yesod.Auth
import           Control.Arrow ((***))
import           Database.Persist.Sql    (SqlBackend)
--------------------------------------------------------------------------------------------------------- 
getPostsHelper :: YesodDB App [Entity Post] -> Text -> Int -> Text -> HandlerT App IO TypedContent
getPostsHelper selectPosts board thread errorString = do
  muser   <- maybeAuth
  mgroup  <- case muser of
    Just (Entity _ u) -> runDB $ getBy $ GroupUniqName $ userGroup u
    _                 -> return Nothing
  let permissions = maybe [] (groupPermissions . entityVal) mgroup

  checkAccess muser board
  let selectFiles p = runDB $ selectList [AttachedfileParentId ==. entityKey p] []
  postsAndFiles <- reverse <$> (runDB selectPosts) >>= mapM (\p -> do
    files <- selectFiles p
    return (p, files))
  t <- runDB $ count [PostBoard ==. board, PostLocalId ==. thread, PostParent ==. 0]
  case () of
    _ | t == 0              -> selectRep $ do
          provideRep  $ bareLayout [whamlet|No such thread|]
          provideJson $ object [("error", toJSON ("No such thread"::Text))]
      | null postsAndFiles -> selectRep $ do
          provideRep  $ bareLayout [whamlet|#{errorString}|]
          provideJson $ object [("error", toJSON errorString)]
      | otherwise          -> selectRep $ do
          provideRep  $ bareLayout [whamlet|
                               $forall (post, files) <- postsAndFiles
                                   ^{replyPostWidget muser post files True permissions}
                               |]
          provideJson $ map (entityVal *** (map entityVal)) postsAndFiles

getApiDeletedPostsR :: Text -> Int -> Handler TypedContent
getApiDeletedPostsR board thread = getPostsHelper selectPosts board thread errorString
  where selectPosts = selectList [PostDeletedByOp ==. True, PostBoard ==. board, PostParent ==. thread] [Desc PostDate]
        errorString = "No such posts"

getApiAllPostsR :: Text -> Int -> Handler TypedContent
getApiAllPostsR board thread = getPostsHelper selectPosts board thread errorString
  where selectPosts = selectList [PostDeletedByOp ==. False, PostBoard ==. board, PostParent ==. thread] [Desc PostDate]
        errorString = "No posts in this thread"

getApiNewPostsR :: Text -> Int -> Int -> Handler TypedContent
getApiNewPostsR board thread postId = getPostsHelper selectPosts board thread errorString
  where selectPosts = selectList [PostDeletedByOp ==. False, PostBoard ==. board, PostParent ==. thread, PostLocalId >. postId] [Desc PostDate]
        errorString = "No new posts"

getApiLastPostsR :: Text -> Int -> Int -> Handler TypedContent
getApiLastPostsR board thread postCount = getPostsHelper selectPosts board thread errorString
  where selectPosts = selectList [PostDeletedByOp ==. False, PostBoard ==. board, PostParent ==. thread] [Desc PostDate, LimitTo postCount]
        errorString = "No such posts"
---------------------------------------------------------------------------------------------------------
getApiPostR :: Text -> Int -> Handler TypedContent
getApiPostR board postId = do
  muser   <- maybeAuth
  mgroup  <- case muser of
    Just (Entity _ u) -> runDB $ getBy $ GroupUniqName $ userGroup u
    _                 -> return Nothing
  let permissions = maybe [] (groupPermissions . entityVal) mgroup

  checkAccess muser board
  maybePost <- runDB $ selectFirst [PostBoard ==. board, PostLocalId ==. postId] []
  when (isNothing maybePost) notFound
  let post    = fromJust maybePost
      postKey = entityKey $ fromJust maybePost
  files <- runDB $ selectList [AttachedfileParentId ==. postKey] []
  let postAndFiles = (entityVal post, map entityVal files)
      widget       = if (postParent (entityVal $ fromJust maybePost)) == 0
                       then opPostWidget muser post files False True permissions
                       else replyPostWidget muser post files True permissions
  selectRep $ do
    provideRep $ bareLayout widget
    provideJson postAndFiles
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
-- checkAccess :: forall site.
--                (YesodPersist site,
--                 PersistUnique (YesodPersistBackend site (HandlerT site IO)),
--                 PersistMonadBackend (YesodPersistBackend site (HandlerT site IO))
--                 ~ SqlBackend) =>
--                Maybe (Entity Person) -> Text -> HandlerT site IO ()
checkAccess muser board = do
  maybeBoard <- runDB $ getBy $ BoardUniqName board
  when (isNothing maybeBoard) notFound
  mgroup  <- case muser of
    Just (Entity _ u) -> runDB $ getBy $ GroupUniqName $ userGroup u
    _                 -> return Nothing
  let group  = (groupName . entityVal) <$> mgroup
      access = boardViewAccess $ entityVal $ fromJust maybeBoard
   in when (isJust access && access /= group) notFound
