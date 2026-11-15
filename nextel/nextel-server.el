;;; nextel-server.el --- files as API routes, for server.el  -*- lexical-binding: t; -*-

;; server.el:
;;
;;   (load (expand-file-name "nextel/nextel-server.el" app-server-project-directory) nil t)
;;   (nextel-server-load)
;;
;; loads nextel-schema.el and nextel-route.el, the files of shared/ (the types
;; that the page loads too), the helpers of api/ (files and directories
;; whose name starts with _), and then every other file of api/ as a
;; route: api/feed.el is /api/feed, api/later/[id].el is /api/later/ID.
;; The server reads the directory itself, so a new file is a new route at
;; the next start.  In such a file, `nextel-handle' says what a method does:
;;
;;   (nextel-handle "POST"
;;     :accepts 'parens-later-entry          ; the body, checked
;;     :returns '(list-of parens-later-entry) ; the answer, checked
;;     :handler (lambda (request) ...))
;;
;; REQUEST is a plist (:method :path :params :body): :params are the
;; [names] of the route, :body the data the page sent (read with
;; `app-server-data', never evaluated).  The query is
;; (app-server-parameter NAME).  A body that is not of :accepts is refused
;; (400, with the field that is wrong); an answer that is not of :returns
;; is the server's mistake (500, and the log says which field).  A handler
;; may refuse (`app-server-refuse') and answer later (`app-server-defer').
;;
;; The same files run in elisp-studio's tab, which has a copy of the
;; project's text files in `app-server-project-directory'.

;;; Code:

(require 'cl-lib)

(defconst nextel-server--here (file-name-directory (or load-file-name buffer-file-name default-directory))
  "The directory of nextel-server.el, where its companions are.")

(load (expand-file-name "nextel-schema.el" nextel-server--here) nil t)
(load (expand-file-name "nextel-route.el" nextel-server--here) nil t)

(defvar nextel-server-routes nil
  "((PATTERN METHOD . SPEC) ...), in the order they are tried.")
(defvar nextel-server--loading nil "The pattern of the api/ file being loaded.")

(defun nextel-handle (method &rest spec)
  "In a file of api/: answer METHOD (\"GET\", \"POST\" ...) at its route.
SPEC: :handler (REQUEST) -> data, :accepts TYPE, :returns TYPE.  See the
commentary of nextel-server.el."
  (unless nextel-server--loading
    (error "nextel-handle belongs in a file of api/, loaded by `nextel-server-load'"))
  (unless (functionp (plist-get spec :handler))
    (error "%s %s has no :handler" method nextel-server--loading))
  (push (cl-list* nextel-server--loading method spec) nextel-server-routes)
  nil)

(defun nextel-server--private-p (relative)
  "Non-nil if RELATIVE (a path under api/) is a helper, not a route."
  (cl-some (lambda (part) (string-prefix-p "_" part)) (split-string relative "/" t)))

(defun nextel-server-load (&optional directory)
  "Load shared/ and api/ of DIRECTORY (the project), and answer /api/ with them."
  (let* ((root (file-name-as-directory
                (expand-file-name (or directory (and (boundp 'app-server-project-directory) app-server-project-directory)
                                      default-directory))))
         (shared (expand-file-name "shared/" root))
         (api (expand-file-name "api/" root))
         (files (and (file-directory-p api) (sort (directory-files-recursively api "\\.el\\'") #'string<))))
    (when (file-directory-p shared)
      (dolist (file (sort (directory-files-recursively shared "\\.el\\'") #'string<))
        (load file nil t)))
    (setq nextel-server-routes nil)
    (dolist (file files)
      (when (nextel-server--private-p (file-relative-name file api))
        (load file nil t)))
    (dolist (file files)
      (let ((relative (file-relative-name file root)))
        (unless (nextel-server--private-p (file-relative-name file api))
          (let ((nextel-server--loading (nextel-pattern-of-file relative)))
            (load file nil t)))))
    (setq nextel-server-routes
          (sort (nreverse nextel-server-routes) (lambda (a b) (nextel-pattern< (car a) (car b)))))
    (defalias 'app-server-handle #'nextel-server-handle)
    nextel-server-routes))

(defun nextel-server--checked (answer returns what)
  "ANSWER (data, or what `app-server-defer' returned), checked against RETURNS."
  (cond
   ((null returns) answer)
   ;; An answer that comes later is checked when it comes.
   ((and (fboundp 'app-server--deferred-p) (app-server--deferred-p answer))
    (let ((function (app-server--deferred-function answer)))
      (app-server-defer
       (lambda (respond fail)
         (funcall function
                  (lambda (data)
                    (condition-case failure
                        (funcall respond (nextel-check returns data what))
                      (nextel-type-error
                       (message "nextel-server: %s answered wrongly: %s" what (cadr failure))
                       (funcall fail (format "The server's answer is wrong: %s" (cadr failure)) 500))))
                  fail)))))
   (t (condition-case failure
          (nextel-check returns answer what)
        (nextel-type-error
         (message "nextel-server: %s answered wrongly: %s" what (cadr failure))
         (app-server-refuse (format "The server's answer is wrong: %s" (cadr failure)) 500))))))

(defun nextel-server-handle (method path body)
  "Answer METHOD at PATH with the route of api/ that it matches."
  (let ((matching (cl-remove-if-not (lambda (route) (nextel-match (car route) path)) nextel-server-routes)))
    (unless matching
      (signal 'file-missing (list "No such API" path)))
    (let ((route (cl-find method matching :key #'cadr :test #'equal)))
      (unless route
        (app-server-refuse (format "%s is not allowed at %s" method path) 405))
      (let* ((pattern (car route))
             (spec (cddr route))
             (params (nextel-match pattern path))
             (what (format "%s %s" method pattern))
             (data (app-server-data body))
             (accepts (plist-get spec :accepts)))
        (when accepts
          (condition-case failure
              (nextel-check accepts data "body")
            (nextel-type-error (app-server-refuse (cadr failure) 400))))
        (nextel-server--checked
         (funcall (plist-get spec :handler)
                  (list :method method :path path :params (and (listp params) params) :body data))
         (plist-get spec :returns)
         what)))))

(provide 'nextel-server)
;;; nextel-server.el ends here
