;;; routes.el --- which page is which address  -*- lexical-binding: t; -*-

;; Written by nextel-build.el (elisp-next) from pages/: do not edit,
;; write it again (M-x nextel-write-routes, or bin/nextel-routes).
;;
;; The server's routes, from api/ (nextel-server.el reads that directory itself):
;;   /api/later/[id]  api/later/[id].el
;;   /api/feed        api/feed.el
;;   /api/later       api/later.el

(nextel-define-routes
 '(("/feed/history" . HistoryPage)
   ("/channel/[id]" . ChannelPage)
   ("/playlist" . PlaylistPage)
   ("/results" . ResultsPage)
   ("/watch" . WatchPage)
   ("/" . HomePage))
 :layout 'Layout
 :not-found 'NotFoundPage)

(nextel-start "#app")

;;; routes.el ends here
