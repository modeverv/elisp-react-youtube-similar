;;; later.el --- GET and POST /api/later  -*- lexical-binding: t; -*-

(nextel-handle "GET"
  :returns '(list-of parens-later-entry)
  :handler (lambda (_request) (parens-later)))

;; The body is a `parens-later-entry': the server refuses anything else
;; (400, naming the field), before this function runs.
(nextel-handle "POST"
  :accepts 'parens-later-entry
  :returns '(list-of parens-later-entry)
  :handler (lambda (request)
             (let ((entry (plist-get request :body)))
               (parens-later-keep (cons entry (parens-later-without (plist-get entry :id)))))))

;;; later.el ends here
