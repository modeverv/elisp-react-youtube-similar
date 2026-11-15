;;; parens-pages.el --- what the pages share: lists, the library, dialogs  -*- lexical-binding: t; -*-

;; The pages themselves are files of pages/ (nextel/nextel.el), one per
;; address.  A page that loads a list keeps it in its state and adds to
;; it: `parens-list-load' with `react-async' around the awaitables of
;; parens-source.el.  An async body checks, after every await, that the
;; page still shows what it was loading for.

(require 'seq)
(require 'subr-x)

(defvar parens-near-end-function nil
  "What to do when the page's sentinel scrolls into view (more results).")

;;;; Lists: home, results, channel

(defun parens-list-load (self key loader &optional more)
  "Load the list page SELF: LOADER gets a page token and returns an
awaitable of (:ids IDS :next TOKEN).  KEY is what the list is for (a
filter, a query, a channel); an answer that comes after KEY or the source
changed is dropped.  With MORE, the next page is added: if that fails,
what is shown stays and a retry is offered under it."
  (let* ((token (and more (react-state self :next)))
         (generation parens-generation)
         (current (lambda () (and (equal key (react-state self :key)) (not (parens-stale-p generation))))))
    (if more
        (react-set-state self :status 'more :more-error nil)
      (react-set-state self :key key :status 'loading :error nil :more-error nil :ids nil :next nil))
    (react-async
      (condition-case failure
          (let ((answer (react-await (funcall loader token))))
            (when (funcall current)
              (react-set-state self :status 'ready :next (plist-get answer :next)
                               :ids (if more
                                        (seq-uniq (append (react-state self :ids) (plist-get answer :ids)))
                                      (plist-get answer :ids)))))
        (error (when (funcall current)
                 (if more
                     (react-set-state self :status 'ready :more-error (parens-failure-text failure))
                   (react-set-state self :status 'failed :error (parens-failure-text failure)))))))))

(defun parens-more-function (self name more)
  "When the sentinel NAME scrolls into view, call MORE (if there is more)."
  (setq parens-near-end-function
        (cons name (lambda ()
                     (when (and (react-state self :next) (eq (react-state self :status) 'ready)
                                (not (react-state self :more-error)))
                       (funcall more))))))

(defun parens-forget-more-function (name)
  (when (equal (car parens-near-end-function) name)
    (setq parens-near-end-function nil)))

(defun parens-more-row (self name more)
  "Under a list: a retry after a failure, or the sentinel and a button."
  (let ((status (react-state self :status)))
    (cond ((react-state self :more-error)
           (jsx (div (:class "more-row") (parens-failed (react-state self :more-error) more))))
          ((and (react-state self :next) (memq status '(ready more)))
           (jsx (div (:class "more-row")
                  (parens-sentinel name (length (react-state self :ids)))
                  (button (:class "button" :type "button" :disabled (eq status 'more)
                           :on-click (lambda (_event) (funcall more)))
                    (parens-t (if (eq status 'more) 'loading 'more)))))))))

(defun parens-list-state (key data)
  "The state of a list page for KEY whose first part, DATA (:ids :next),
came from its :load."
  (list :key key :status 'ready :error nil :more-error nil
        :ids (plist-get data :ids) :next (plist-get data :next)))

(defun parens-source-changed-p (self previous-props)
  (not (and (eql (react-props self :generation) (plist-get previous-props :generation))
            (eq (react-props self :mode) (plist-get previous-props :mode)))))

;;;; History and watch later

(defun parens-not-found ()
  "What a page shows for an address that has nothing."
  (jsx (div (:class "not-found")
         (h1 (:class "page-title") (parens-t 'not-found))
         (p (a (:href (nextel-href "/")) (parens-t 'home))))))

(react-define-component 'LibraryPage
  :render
  (lambda (self)
    (let* ((kind (react-props self :kind))
           (entries (react-props self :entries))
           (ids (mapcar (lambda (entry) (plist-get entry :id)) entries)))
      (jsx (div (:class "library")
             (div (:class "library-head")
               (h1 (:class "page-title") (parens-t (if (eq kind 'history) 'history 'later)))
               (and entries
                    (jsx (button (:class "text-button" :type "button"
                                  :on-click (lambda (_event) (parens-clear-library kind)))
                           (parens-t 'clear)))))
             (if entries
                 (parens-wide-list ids nil (if (eq kind 'history) #'parens-forget-watched #'parens-toggle-later))
               (parens-note (parens-t (if (eq kind 'history) 'history-empty 'later-empty)))))))))

;;;; Dialogs

(react-define-component 'SettingsDialog
  :initial-state (lambda (_props) (list :draft (or parens-api-key "")
                                        :remember (and (react-storage-get "parens/api-key") t)))
  :did-mount (lambda (self) (react-focus self "key"))
  :render
  (lambda (self)
    (let ((draft (react-state self :draft)))
      (jsx (div (:class "dialog" :role "dialog" :aria-modal "true" :aria-labelledby "settings-title")
             (div (:class "dialog-head")
               (h2 (:id "settings-title") (parens-t 'settings))
               (button (:class "icon-button" :type "button" :aria-label (parens-t 'close)
                        :on-click (lambda (_event) (parens-close-dialog)))
                 (parens-icon "close")))
             (section (:class "setting")
               (h3 (parens-t 'api-key))
               (p (:class "muted mode-line")
                 (format "%s: %s" (parens-mode-name parens-mode t) (or (parens-mode-note-text) "")))
               (form (:class "key-form"
                      :on-submit (lambda (_event) (parens-use-key (string-trim (react-state self :draft))
                                                                  (react-state self :remember))))
                 (input (:ref "key" :type "password" :autocomplete "off" :spellcheck "false" :value draft
                         :placeholder "AIza…" :aria-label (parens-t 'api-key)
                         :on-input (lambda (event) (react-set-state self :draft (plist-get event :value)))))
                 (button (:class "button" :type "submit" :disabled (string-empty-p (string-trim draft)))
                   (parens-t 'api-key-save)))
               (label (:class "switch")
                 (input (:type "checkbox" :checked (react-state self :remember)
                         :on-change (lambda (event) (react-set-state self :remember (plist-get event :checked)))))
                 (span (parens-t 'api-key-remember)))
               (and parens-api-key
                    (jsx (button (:class "text-button" :type "button" :on-click (lambda (_event) (parens-use-key nil)))
                           (parens-t 'api-key-remove))))
               (p (:class "muted small") (parens-t 'api-key-help)))
             (section (:class "setting")
               (h3 (parens-t 'language))
               (parens-chips '((ja . "日本語") (en . "English")) parens-lang
                             (lambda (lang) (parens-set-setting :lang lang))))
             (section (:class "setting")
               (h3 (parens-t 'theme))
               (parens-chips (list (cons 'dark (parens-t 'theme-dark)) (cons 'light (parens-t 'theme-light)))
                             (parens-setting :theme)
                             (lambda (theme) (parens-set-setting :theme theme))))
             (section (:class "setting")
               (h3 (parens-t 'about))
               (p (:class "small") (parens-t 'about-text))))))))

(react-define-component 'ShortcutsDialog
  :render
  (lambda (_self)
    (jsx (div (:class "dialog" :role "dialog" :aria-modal "true" :aria-labelledby "shortcuts-title")
           (div (:class "dialog-head")
             (h2 (:id "shortcuts-title") (parens-t 'shortcuts))
             (button (:class "icon-button" :type "button" :aria-label (parens-t 'close)
                      :on-click (lambda (_event) (parens-close-dialog)))
               (parens-icon "close")))
           (table (:class "shortcuts")
             (tbody
               (mapcar (lambda (row)
                         (jsx (tr (:key (car row)) (td (kbd (car row))) (td (parens-t (cdr row))))))
                       '(("/" . shortcut-search) ("k" . shortcut-play) ("j / l" . shortcut-seek)
                         ("?" . shortcut-help) ("Esc" . shortcut-close)))))))))

(provide 'parens-pages)
;;; parens-pages.el ends here
