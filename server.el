;;; server.el --- Parens' server side: the files of api/  -*- lexical-binding: t; -*-

;; Each file of api/ answers the address that its path is (elisp-next,
;; vendor/elisp-next/lisp/nextel-server.el):
;;
;;   api/feed.el        GET /api/feed         the channels' latest uploads
;;   api/later.el       GET, POST /api/later  "watch later", kept by the server
;;   api/later/[id].el  DELETE /api/later/ID
;;
;; with the types of shared/parens-types.el, which the page checks too.
;; elisp-studio's server (run.sh, tools/serve-project.sh) and its browser
;; tab both run this file; `app-server-project-directory' is the project.

(declare-function nextel-server-load "nextel-server")   ; defined by the file loaded here
(load (expand-file-name "vendor/elisp-next/lisp/nextel-server.el" app-server-project-directory) nil t)
(nextel-server-load)

;;; server.el ends here
