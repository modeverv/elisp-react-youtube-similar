;;; history.el --- the history, /feed/history  -*- lexical-binding: t; -*-

(nextel-page HistoryPage
  :head (lambda (_route _data) (list :title (parens-t 'history)))
  :render (lambda (_self) (jsx (LibraryPage (:kind 'history :entries (parens-app-state :history))))))

;;; history.el ends here
