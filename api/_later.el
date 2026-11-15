;;; _later.el --- "watch later", kept by the server  -*- lexical-binding: t; -*-

;; A helper of api/later.el and api/later/[id].el.  With a server the list
;; is the server's, so it is the same in every browser; without one the
;; page keeps it in localStorage (lisp/parens-state.el).

(require 'cl-lib)
(require 'seq)

(defconst parens-later-limit 200 "The most entries the server keeps.")

(defun parens-later ()
  "The entries, newest first."
  (app-server-read "later" nil))

(defun parens-later-without (id)
  (cl-remove id (parens-later) :key (lambda (entry) (plist-get entry :id)) :test #'equal))

(defun parens-later-keep (entries)
  "Keep ENTRIES (at most `parens-later-limit'); they are the answer."
  (app-server-write "later" (seq-take entries parens-later-limit)))

(provide 'parens-later)
;;; _later.el ends here
