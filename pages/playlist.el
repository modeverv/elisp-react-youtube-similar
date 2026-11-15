;;; playlist.el --- "watch later", /playlist?list=WL  -*- lexical-binding: t; -*-

;; YouTube's address for "watch later"; another list is not here.

(nextel-page PlaylistPage
  :head (lambda (route _data) (and (equal (nextel-query route "list") "WL") (list :title (parens-t 'later))))
  :render (lambda (self)
            (if (equal (nextel-query self "list") "WL")
                (jsx (LibraryPage (:kind 'later :entries (parens-app-state :later))))
              (parens-not-found))))

;;; playlist.el ends here
