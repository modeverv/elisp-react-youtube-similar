;;; results.el --- the search results, /results?search_query=TEXT  -*- lexical-binding: t; -*-

;; The first part of the results comes from :load (nextel/nextel.el): the
;; router waits for it, shows :loading meanwhile and :error if it fails,
;; and keeps it for Back.  The page adds the parts after it itself.

(defun parens-results-query (route)
  (string-trim (or (nextel-query route "search_query") "")))

(defun parens-results-more (self)
  (let ((query (parens-results-query self)))
    (parens-list-load self query (lambda (token) (parens-load-search query token)) t)))

(nextel-page ResultsPage
  :load (lambda (route)
          (let ((query (parens-results-query route)))
            (if (string-empty-p query)
                (lambda (resolve _reject) (funcall resolve nil))
              (parens-load-search query nil))))
  :head (lambda (route _data) (list :title (parens-results-query route)))
  :loading (lambda (route)
             (jsx (div (:class "results")
                    (h1 (:class "page-title") (parens-t 'results-for (parens-results-query route)))
                    (parens-note (parens-t 'loading)))))
  :error (lambda (route error retry)
           (jsx (div (:class "results")
                  (h1 (:class "page-title") (parens-t 'results-for (parens-results-query route)))
                  (parens-failed (parens-failure-text error) retry))))
  :initial-state (lambda (props) (parens-list-state (parens-results-query (plist-get props :route)) (plist-get props :data)))
  :did-mount (lambda (self) (parens-more-function self "results" (lambda () (parens-results-more self))))
  :did-update (lambda (self previous-props _previous-state)
                (unless (eq (react-props self :data) (plist-get previous-props :data))
                  (apply #'react-set-state self (parens-list-state (parens-results-query self) (react-props self :data)))))
  :will-unmount (lambda (_self) (parens-forget-more-function "results"))
  :render
  (lambda (self)
    (let ((ids (react-state self :ids)))
      (jsx (div (:class "results")
             (h1 (:class "page-title") (parens-t 'results-for (parens-results-query self)))
             (and (not (eq parens-mode 'api)) (parens-note (parens-t 'results-local)))
             (if ids (parens-wide-list ids) (parens-note (parens-t 'no-results)))
             (parens-more-row self "results" (lambda () (parens-results-more self))))))))

;;; results.el ends here
