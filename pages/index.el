;;; index.el --- the home page, /  -*- lexical-binding: t; -*-

;; The videos of the source, with chips to filter them and more as the end
;; of the list comes into view.  The list is the page's own state (it
;; grows), so the page loads it itself rather than with :load.

(defun parens-home-load (self filter &optional more)
  (parens-list-load self filter (lambda (token) (parens-load-home filter token)) more))

(defun parens-home-chips (self)
  "With a key, ask for the Data API's categories (the chips; else topics)."
  (react-set-state self :categories nil)
  (when (eq parens-mode 'api)
    (react-async
      (condition-case nil
          (let ((categories (react-await (parens-load-categories))))
            (react-set-state self :categories categories))
        (error nil)))))

(defun parens-home-chip-list (self)
  "((VALUE . LABEL) ...): all, then categories or topics in `parens-lang'."
  (cons (cons nil (parens-t 'all))
        (if (eq parens-mode 'api)
            (react-state self :categories)
          (mapcar (lambda (topic) (cons (car topic) (parens-topic-name (car topic)))) parens-topics))))

(nextel-page HomePage
  ;; No :head: the title is "Parens".
  :initial-state (lambda (_props) (list :key nil :status 'loading :ids nil :next nil :categories nil))
  :did-mount (lambda (self)
               (parens-home-load self nil)
               (parens-home-chips self)
               (parens-more-function self "home" (lambda () (parens-home-load self (react-state self :key) t))))
  :did-update (lambda (self previous-props _previous-state)
                (cond ((parens-source-changed-p self previous-props)
                       (parens-home-load self nil)
                       (parens-home-chips self))
                      ;; The Data API names the categories in the language asked for.
                      ((not (eq (react-props self :lang) (plist-get previous-props :lang)))
                       (parens-home-chips self))))
  :will-unmount (lambda (_self) (parens-forget-more-function "home"))
  :render
  (lambda (self)
    (let ((ids (react-state self :ids)))
      (jsx (div (:class "home")
             (h1 (:class "visually-hidden") "Parens")
             (parens-chips (parens-home-chip-list self)
                           (react-state self :key)
                           (lambda (filter) (parens-home-load self filter)))
             (pcase (react-state self :status)
               ('loading (parens-skeleton-grid 12))
               ('failed (parens-failed (react-state self :error)
                                       (lambda () (parens-home-load self (react-state self :key)))))
               (_ (if ids (parens-grid ids) (parens-note (parens-t 'no-results)))))
             (parens-more-row self "home" (lambda () (parens-home-load self (react-state self :key) t))))))))

;;; index.el ends here
