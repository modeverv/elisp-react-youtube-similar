;;; parens-state.el --- the application's own state: route, settings, library  -*- lexical-binding: t; -*-

;; The state that many components need (the route, the settings, history
;; and "watch later") lives in the `App' component.  elisp-react has no
;; context and no store, so the mounted App is kept in `parens-app' and
;; the functions below read and change its state from anywhere: a card's
;; button, a message from the page, a keyboard shortcut.

(require 'seq)
(require 'subr-x)

(defvar parens-app nil "The mounted `App' instance.")

(defconst parens-default-settings '(:lang ja :theme dark :autoplay t))

(defun parens-app-state (key)
  (and parens-app (react-state parens-app key)))

(defun parens-app-set (&rest changes)
  (when parens-app (apply #'react-set-state parens-app changes)))

(defun parens-mode-name (mode &optional long)
  (pcase mode
    ('api (parens-t (if long 'mode-api-long 'mode-api)))
    ('server (parens-t (if long 'mode-server-long 'mode-server)))
    (_ (parens-t (if long 'mode-curated-long 'mode-curated)))))

;;;; Routes

(defun parens-route-url (route)
  "The address (a #fragment) of ROUTE, a plist (:page PAGE ...)."
  (pcase (plist-get route :page)
    ('watch (concat "#/watch?v=" (url-hexify-string (plist-get route :v))
                    (let ((start (plist-get route :t)))
                      (if (and start (> start 0)) (format "&t=%d" start) ""))))
    ('results (concat "#/results?search_query=" (url-hexify-string (or (plist-get route :q) ""))))
    ('channel (concat "#/channel/" (url-hexify-string (plist-get route :id))))
    ('history "#/feed/history")
    ('later "#/playlist?list=WL")
    (_ "#/")))

(defun parens-watch-route (id &optional start)
  (list :page 'watch :v id :t start))

(defun parens-channel-route (channel-id)
  (and channel-id (list :page 'channel :id channel-id)))

(defconst parens-video-id-regexp "\\`[A-Za-z0-9_-]\\{11\\}\\'")
(defconst parens-channel-id-regexp "\\`UC[A-Za-z0-9_-]\\{22\\}\\'")

(defun parens-query (text)
  "The parameters of the query string TEXT: ((NAME . VALUE) ...)."
  (mapcar (lambda (pair)
            (let ((cut (string-search "=" pair)))
              (if cut
                  (cons (parens-decode (substring pair 0 cut)) (parens-decode (substring pair (1+ cut))))
                (cons (parens-decode pair) ""))))
          (split-string text "&" t)))

(defun parens-route-parse (url)
  "The route of URL (\"#/watch?v=ID\"); the home page for anything else."
  (let* ((text (string-remove-prefix "#" (or url "")))
         (question (string-search "?" text))
         (path (split-string (if question (substring text 0 question) text) "/" t))
         (query (and question (parens-query (substring text (1+ question)))))
         (parameter (lambda (name) (cdr (assoc name query)))))
    (pcase path
      (`("watch")
       (let ((id (funcall parameter "v")))
         (if (and id (string-match-p parens-video-id-regexp id))
             (parens-watch-route id (parens-number (string-remove-suffix "s" (or (funcall parameter "t") ""))))
           '(:page home))))
      (`("results")
       (let ((query (string-trim (or (funcall parameter "search_query") ""))))
         (if (string-empty-p query) '(:page home) (list :page 'results :q query))))
      (`("channel" ,id)
       (if (string-match-p parens-channel-id-regexp id) (list :page 'channel :id id) '(:page home)))
      (`("feed" "history") '(:page history))
      (`("playlist") (if (equal (funcall parameter "list") "WL") '(:page later) '(:page home)))
      (_ '(:page home)))))

(defun parens-show (route)
  "Show ROUTE (the page's address has changed already, or there is none)."
  (unless (equal route (parens-app-state :route))
    (parens-app-set :route route :dialog nil :sidebar nil)
    (parens-port-send "scroll-top")
    ;; The studio's preview has no address: remember where it was, so that
    ;; restarting the application (a change of index.html) comes back here.
    (when parens-studio (react-storage-set "parens/studio-route" route))))

(defun parens-go (route)
  "Go to ROUTE: change the page's address (the page's script) and show it."
  (parens-port-send "navigate" :url (parens-route-url route))
  (parens-show route))

;;;; Settings

(defun parens-setting (key)
  (plist-get (parens-app-state :settings) key))

(defun parens-set-setting (key value)
  (let ((settings (react-plist-with (parens-app-state :settings) key value)))
    (when (eq key :lang) (setq parens-lang value))
    (react-storage-set "parens/settings" settings)
    (parens-app-set :settings settings)))

(defun parens-use-key (key)
  "Use the Data API with KEY from now on; nil: without a key."
  (let ((key (and key (not (string-empty-p key)) key)))
    (if key (react-storage-set "parens/api-key" key) (react-storage-remove "parens/api-key"))
    (parens-forget-everything)
    (setq parens-api-key key
          parens-mode (and key 'api))
    (parens-library-remember (parens-app-state :history))
    (parens-library-remember (parens-app-state :later))
    (parens-start-source)
    (parens-app-set :dialog nil)
    (parens-changed)))

(defun parens-start-source ()
  "Begin to load what every page needs in the current mode."
  (if (eq parens-mode 'api)
      (funcall (parens-api-fill-channels (mapcar #'car parens-curated-channels)) #'ignore #'ignore)
    (funcall (parens-catalogue-ready) #'ignore #'ignore)))

;;;; History and "watch later"

(defconst parens-library-days 30
  "Entries older than this many days are dropped.  YouTube's API terms
allow keeping data fetched without signing in for 30 days.")

(defun parens--entry (id)
  "What the library keeps of the video ID: enough for a card."
  (let ((video (parens-video id)))
    (list :id id :title (plist-get video :title) :channel (parens-channel-name video)
          :channel-id (plist-get video :channel-id) :thumbnail (plist-get video :thumbnail)
          :duration (plist-get video :duration) :saved (float-time))))

(defun parens-library-remember (entries)
  (dolist (entry entries)
    (parens-remember-video (list :id (plist-get entry :id) :title (plist-get entry :title)
                                 :channel (plist-get entry :channel) :channel-id (plist-get entry :channel-id)
                                 :thumbnail (plist-get entry :thumbnail) :duration (plist-get entry :duration)))))

(defun parens-library-load (name)
  "The entries kept under NAME, without old ones; remembered as videos."
  (let* ((cutoff (- (float-time) (* parens-library-days 86400)))
         (entries (seq-filter (lambda (entry) (> (or (plist-get entry :saved) 0) cutoff))
                              (react-storage-get (concat "parens/" name)))))
    (parens-library-remember entries)
    entries))

(defun parens--library-store (key entries)
  (react-storage-set (concat "parens/" (substring (symbol-name key) 1)) entries)
  (parens-app-set key entries))

(defun parens--library-without (entries id)
  (seq-remove (lambda (entry) (equal (plist-get entry :id) id)) entries))

(defun parens-watched (id)
  "Put the video ID at the top of the history."
  (parens--library-store :history (seq-take (cons (parens--entry id)
                                                  (parens--library-without (parens-app-state :history) id))
                                            100)))

(defun parens-forget-watched (id)
  (parens--library-store :history (parens--library-without (parens-app-state :history) id)))

(defun parens-later-p (id)
  (seq-some (lambda (entry) (equal (plist-get entry :id) id)) (parens-app-state :later)))

(defun parens-toggle-later (id)
  (if (parens-later-p id)
      (parens--library-store :later (parens--library-without (parens-app-state :later) id))
    (parens--library-store :later (cons (parens--entry id) (parens-app-state :later)))
    (parens-toast (parens-t 'saved-later))))

(defun parens-clear-library (kind)
  (parens--library-store (if (eq kind 'history) :history :later) nil))

;;;; Dialogs and messages

(defvar parens--toast-timer nil)

(defun parens-open-dialog (name) (parens-app-set :dialog name))
(defun parens-close-dialog () (parens-app-set :dialog nil))

(defun parens-toast (text)
  "Show TEXT for a moment."
  (parens-app-set :toast text)
  (when parens--toast-timer (react-clear-timer parens--toast-timer))
  (setq parens--toast-timer
        (react-set-timeout 2500 (lambda ()
                                  (setq parens--toast-timer nil)
                                  (parens-app-set :toast nil)))))

(provide 'parens-state)
;;; parens-state.el ends here
