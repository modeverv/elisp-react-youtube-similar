;;; [id].el --- DELETE /api/later/ID  -*- lexical-binding: t; -*-

(nextel-handle "DELETE"
  :returns '(list-of parens-later-entry)
  :handler (lambda (request)
             (parens-later-keep (parens-later-without (plist-get (plist-get request :params) :id)))))

;;; [id].el ends here
