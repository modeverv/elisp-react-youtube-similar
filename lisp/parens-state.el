;;; parens-state.el --- the application's own state: route, settings, library  -*- lexical-binding: t; -*-

;; The state that many components need (the settings, history and "watch
;; later") lives in the `Layout' component (pages/_layout.el), which stays
;; mounted from one page to the next.  The mounted Layout is kept in
;; `parens-app' and the functions below read and change its state from
;; anywhere: a card's button, a message from the page, a keyboard shortcut.
;; The route is the router's (nextel/nextel.el): the address is the truth.

(require 'seq)
(require 'subr-x)

(defvar parens-app nil "The mounted `Layout' instance.")

(defconst parens-default-settings '(:lang ja :theme dark :autoplay t))

(defvar parens-narrow nil
  "Non-nil when the window is narrow (the page's script says so): the
sidebar is then a drawer over the page.  Lisp cannot ask the window.")

(defun parens-settings (stored)
  "`parens-default-settings' with what STORED says, nil values included
\(autoplay turned off is (:autoplay nil))."
  (let ((settings (copy-sequence parens-default-settings)))
    (dolist (key '(:lang :theme :autoplay) settings)
      (when (plist-member stored key)
        (setq settings (plist-put settings key (plist-get stored key)))))))

(defun parens-app-state (key)
  (and parens-app (react-state parens-app key)))

(defun parens-app-set (&rest changes)
  (when parens-app (apply #'react-set-state parens-app changes)))

(defun parens-mode-name (mode &optional long)
  (pcase mode
    ('api (parens-t (if long 'mode-api-long 'mode-api)))
    ('server (parens-t (if long 'mode-server-long 'mode-server)))
    (_ (parens-t (if long 'mode-curated-long 'mode-curated)))))

;;;; Addresses

;; A page's address is its file (pages/): these build the links.

(defconst parens-video-id-regexp "\\`[A-Za-z0-9_-]\\{11\\}\\'")
(defconst parens-channel-id-regexp "\\`UC[A-Za-z0-9_-]\\{22\\}\\'")

(defun parens-watch-href (id &optional start)
  "The address of the watch page of the video ID, from START seconds."
  (nextel-href "/watch" :v id :t (and start (> start 0) start)))

(defun parens-channel-href (channel-id)
  "The address of the page of CHANNEL-ID, or of the home page without one."
  (if channel-id (nextel-href "/channel/[id]" :id channel-id) (nextel-href "/")))

(defun parens-navigated (_route)
  "A new page is shown (`nextel-navigate-functions')."
  (when parens-app
    (parens-app-set :dialog nil)
    ;; A drawer closes when a page is chosen; a sidebar beside the page stays.
    (when parens-narrow (parens-app-set :sidebar nil))
    ;; The keyboard starts again at the top of the new page.
    (react-focus parens-app "content"))
  (parens-port-send "scroll-top"))

(add-hook 'nextel-navigate-functions #'parens-navigated)

;;;; Settings

(defun parens-setting (key)
  (plist-get (parens-app-state :settings) key))

(defun parens-set-setting (key value)
  (let ((settings (react-plist-with (parens-app-state :settings) key value)))
    (when (eq key :lang) (setq parens-lang value))
    (react-storage-set "parens/settings" settings)
    (parens-app-set :settings settings)))

(defun parens-use-key (key &optional remember)
  "Use the Data API with KEY from now on; nil: without a key.
With REMEMBER the key is kept in localStorage, where every page of the
origin can read it (all of modeverv.github.io on GitHub Pages); without
it, only until the page is closed."
  (let ((key (and key (not (string-empty-p key)) key)))
    (if (and key remember)
        (react-storage-set "parens/api-key" key)
      (react-storage-remove "parens/api-key"))
    (parens-forget-everything)
    (setq parens-api-key key
          parens-mode (and key 'api))
    (parens-library-remember (parens-app-state :history))
    (parens-library-remember (parens-app-state :later))
    (parens-start-source)
    (parens-app-set :dialog nil)
    ;; What the pages loaded came from the old source.
    (nextel-reload)
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
    (make-parens-later-entry
     :id id :title (plist-get video :title) :channel (parens-channel-name video)
     :channel-id (plist-get video :channel-id) :thumbnail (plist-get video :thumbnail)
     :duration (plist-get video :duration) :saved (float-time))))

(defun parens-library-remember (entries)
  (dolist (entry entries)
    (parens-remember-video (list :id (plist-get entry :id) :title (plist-get entry :title)
                                 :channel (plist-get entry :channel) :channel-id (plist-get entry :channel-id)
                                 :thumbnail (plist-get entry :thumbnail) :duration (plist-get entry :duration)))))

(defun parens-library-load (name)
  "The entries kept under NAME, without old ones; remembered as videos.
Old ones are removed from localStorage too, not only from the page."
  (let* ((cutoff (- (float-time) (* parens-library-days 86400)))
         (stored (react-storage-get (concat "parens/" name)))
         (entries (seq-filter (lambda (entry) (> (or (plist-get entry :saved) 0) cutoff)) stored)))
    (unless (= (length entries) (length stored))
      (react-storage-set (concat "parens/" name) entries))
    (parens-library-remember entries)
    entries))

(defun parens--library-store (key entries)
  (react-storage-set (concat "parens/" (substring (symbol-name key) 1)) entries)
  (parens-app-set key entries))

;; With server.el, "watch later" is the server's (api/later.el): the same
;; in every browser.  The page asks it and sends it changes, and the
;; entries cross as `parens-later-entry' records (shared/parens-types.el),
;; checked on both sides.  localStorage keeps a copy.

(defun parens--later-answer (entries)
  (parens-library-remember entries)
  (parens--library-store :later entries))

(defun parens-later-sync ()
  "In the server mode, take the list of \"watch later\" from the server."
  (when (eq parens-mode 'server)
    (funcall (nextel-request "GET" "/api/later" :returns '(list-of parens-later-entry))
             #'parens--later-answer
             (lambda (failure) (message "parens: watch later: %s" (parens-failure-text failure))))))

(defun parens--later-send (request)
  "In the server mode, send REQUEST (a `nextel-request') to the server."
  (when (eq parens-mode 'server)
    (funcall request #'parens--later-answer
             (lambda (failure) (parens-toast (parens-failure-text failure))))))

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
      (progn
        (parens--library-store :later (parens--library-without (parens-app-state :later) id))
        (parens--later-send (nextel-request "DELETE" "/api/later/[id]" :id id
                                          :returns '(list-of parens-later-entry))))
    (let ((entry (parens--entry id)))
      (parens--library-store :later (cons entry (parens-app-state :later)))
      (parens-toast (parens-t 'saved-later))
      (parens--later-send (nextel-request "POST" "/api/later" :body entry :sends 'parens-later-entry
                                        :returns '(list-of parens-later-entry))))))

(defun parens-clear-library (kind)
  (if (eq kind 'history)
      (parens--library-store :history nil)
    (dolist (entry (parens-app-state :later)) (parens-toggle-later (plist-get entry :id)))))

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
