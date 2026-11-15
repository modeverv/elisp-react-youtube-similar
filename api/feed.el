;;; feed.el --- GET /api/feed  -*- lexical-binding: t; -*-

;; The latest long-form uploads of the chosen channels, read from their
;; feeds (api/_feeds.el): a page may not read those (no CORS), a server may.

(nextel-handle "GET"
  :returns 'parens-feed
  :handler (lambda (_request) (parens-server-feed)))

;;; feed.el ends here
