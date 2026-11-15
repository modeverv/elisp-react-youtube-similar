;;; parens-pages.el --- home, watch, results, channel, library, dialogs  -*- lexical-binding: t; -*-

;; Each page loads what it shows when it is mounted and when its route
;; changes (:did-update), and keeps it in its state.  Loading is
;; `react-async' around the awaitables of parens-source.el.  An async body
;; cannot be cancelled, so each one checks, after every await, that the
;; page still shows what it was loading for.

(require 'seq)
(require 'subr-x)

(defvar parens-near-end-function nil
  "What to do when the page's sentinel scrolls into view (more results).")

;;;; Home

(defun parens-home-load (self filter &optional more)
  "Load the home page SELF for FILTER; with MORE, the next page of it."
  (let ((token (and more (react-state self :next))))
    (if more
        (react-set-state self :status 'more)
      (react-set-state self :filter filter :status 'loading :error nil :ids nil :next nil))
    (react-async
      (condition-case failure
          (let ((answer (react-await (parens-load-home filter token))))
            (when (equal filter (react-state self :filter))
              (react-set-state self :status 'ready :next (plist-get answer :next)
                               :ids (if more
                                        (seq-uniq (append (react-state self :ids) (plist-get answer :ids)))
                                      (plist-get answer :ids)))))
        (error (when (equal filter (react-state self :filter))
                 (react-set-state self :status 'failed :error (parens-failure-text failure))))))))

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

(defun parens-more-function (self loader)
  "Make the sentinel load more of SELF with LOADER, when there is more."
  (setq parens-near-end-function
        (lambda ()
          (when (and (react-state self :next) (eq (react-state self :status) 'ready))
            (funcall loader)))))

(react-define-component 'HomePage
  :initial-state (lambda (_props) (list :filter nil :status 'loading :ids nil :next nil :categories nil))
  :did-mount (lambda (self)
               (parens-home-load self nil)
               (parens-home-chips self)
               (parens-more-function self (lambda () (parens-home-load self (react-state self :filter) t))))
  :did-update (lambda (self previous-props _previous-state)
                (unless (eq (react-props self :mode) (plist-get previous-props :mode))
                  (parens-home-load self nil)
                  (parens-home-chips self)))
  :will-unmount (lambda (_self) (setq parens-near-end-function nil))
  :render
  (lambda (self)
    (let ((status (react-state self :status))
          (ids (react-state self :ids)))
      (jsx (div (:class "home")
             (parens-chips (parens-home-chip-list self)
                           (react-state self :filter)
                           (lambda (filter) (parens-home-load self filter)))
             (pcase status
               ('loading (parens-skeleton-grid 12))
               ('failed (parens-failed (react-state self :error)
                                       (lambda () (parens-home-load self (react-state self :filter)))))
               (_ (if ids (parens-grid ids) (parens-note (parens-t 'no-results)))))
             (and (react-state self :next) (memq status '(ready more))
                  (jsx (div (:class "more-row")
                         (parens-sentinel "home" (length ids))
                         (button (:class "button" :type "button" :disabled (eq status 'more)
                                  :on-click (lambda (_event) (parens-home-load self (react-state self :filter) t)))
                           (if (eq status 'more) (parens-t 'loading) (parens-t 'more)))))))))))

;;;; Watch

(defvar parens-watch-page nil "The mounted watch page, for messages from the player.")

(defun parens-embed-url (id start)
  "The player's address for the video ID, starting at START seconds."
  (concat "https://www.youtube-nocookie.com/embed/" (url-hexify-string id) "?"
          (url-build-query-string
           (delq nil (list '("autoplay" "1") '("rel" "0") '("playsinline" "1") '("enablejsapi" "1")
                           (and parens-origin (list "origin" parens-origin))
                           (and start (> start 0) (list "start" (number-to-string start))))))))

(defun parens-seek (seconds)
  "Play the video on the page from SECONDS (a timestamp in a description)."
  (parens-port-send "player" :func "seekTo" :args (vector seconds t))
  (parens-port-send "scroll-top"))

(react-define-component 'Player
  :pure t
  :render
  (lambda (self)
    (let ((id (react-props self :id)))
      (jsx (div (:class "player")
             ;; credentialless: the elisp-studio preview is cross-origin isolated
             ;; (COEP), and YouTube's player sends no COEP header.  referrerpolicy:
             ;; the player refuses to play without a Referer (error 153), and a
             ;; server may send Referrer-Policy: same-origin.
             (iframe (:key id :class "player-frame" :data-player id
                      :src (parens-embed-url id (react-props self :start))
                      :title (or (react-props self :title) "YouTube")
                      :allow "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                      :allowfullscreen t :credentialless t
                      :referrerpolicy "strict-origin-when-cross-origin")))))))

(react-define-component 'Description
  :initial-state (lambda (_props) (list :open nil))
  :render
  (lambda (self)
    (let* ((video (react-props self :video))
           (open (react-state self :open))
           (text (string-trim (or (plist-get video :description) "")))
           (facts (delq nil (list (parens-views (plist-get video :views))
                                  (parens-date (plist-get video :published))
                                  (and (plist-get video :likes) (parens-t 'likes (parens-short-number (plist-get video :likes))))))))
      (jsx (section (:class (parens-class "description" (and open "open")))
             (and facts (jsx (div (:class "description-facts") (string-join facts "　"))))
             (cond ((not (string-empty-p text))
                    (jsx (div (:class "description-text") (parens-linkify text #'parens-seek))))
                   ((memq parens-mode '(api server)) (parens-note (parens-t 'no-description)))
                   (t (parens-note (parens-t 'description-need-more))))
             (and (> (length text) 200)
                  (jsx (button (:class "text-button" :type "button" :aria-expanded (if open "true" "false")
                                :on-click (lambda (_event) (react-set-state self :open (not (react-state self :open)))))
                         (parens-t (if open 'less 'more))))))))))

(defun parens-comments-load (self &optional more)
  (let ((id (react-props self :video-id))
        (token (and more (react-state self :next))))
    (react-set-state self :status (if more 'more 'loading) :error nil)
    (react-async
      (condition-case failure
          (let ((answer (react-await (parens-load-comments id token))))
            (react-set-state self :status 'ready :next (plist-get answer :next)
                             :comments (append (and more (react-state self :comments))
                                               (plist-get answer :comments))))
        (error (react-set-state self :status 'failed :error (parens-failure-text failure)))))))

(react-define-component 'Comments
  :initial-state (lambda (_props) (list :status 'idle :comments nil :next nil))
  :did-mount (lambda (self) (when (eq parens-mode 'api) (parens-comments-load self)))
  :render
  (lambda (self)
    (let ((status (react-state self :status))
          (count (react-props self :count)))
      (jsx (section (:class "comments")
             (h2 (:class "section-title")
               (if count (parens-t 'comments (parens-short-number count)) (parens-t 'comments-title)))
             (cond ((not (eq parens-mode 'api)) (parens-note (parens-t 'comments-need-key)))
                   ((eq status 'loading) (parens-note (parens-t 'loading)))
                   ((eq status 'failed) (parens-note (react-state self :error))))
             (ul (:class "comment-list")
               (mapcar (lambda (comment)
                         (jsx (li (:key (plist-get comment :id) :class "comment")
                                (parens-avatar (list :title (plist-get comment :author)
                                                     :avatar (plist-get comment :avatar))
                                               "small")
                                (div (:class "comment-body")
                                  (div (:class "comment-head")
                                    (strong (plist-get comment :author))
                                    (span (:class "muted") (or (parens-ago (plist-get comment :published)) "")))
                                  (div (:class "comment-text") (parens-linkify (plist-get comment :text) #'parens-seek))
                                  (div (:class "comment-foot muted")
                                    (parens-icon "like")
                                    (span (or (parens-short-number (plist-get comment :likes)) "0"))
                                    (and (plist-get comment :replies) (> (plist-get comment :replies) 0)
                                         (jsx (span (format "↳ %d" (plist-get comment :replies))))))))))
                       (react-state self :comments)))
             (and (react-state self :next)
                  (jsx (button (:class "button" :type "button" :disabled (eq status 'more)
                                :on-click (lambda (_event) (parens-comments-load self t)))
                         (parens-t 'more)))))))))

(defun parens-watch-load (self)
  (let ((id (react-props self :v)))
    (react-set-state self :status 'loading :error nil :related nil :player-error nil)
    (react-async
      (condition-case failure
          (progn
            (react-await (parens-load-video id))
            (when (equal id (react-props self :v))
              (react-set-state self :status 'ready)
              (parens-watched id)
              (let ((related (condition-case nil (react-await (parens-load-related id)) (error nil))))
                (when (equal id (react-props self :v))
                  (react-set-state self :related related)))))
        (error (when (equal id (react-props self :v))
                 (react-set-state self :status 'failed :error (parens-failure-text failure))))))))

(defun parens-next-video ()
  "The video the watch page would play next, or nil."
  (and parens-watch-page (car (react-state parens-watch-page :related))))

(react-define-component 'WatchPage
  :initial-state (lambda (_props) (list :status 'loading :related nil :player-error nil))
  :did-mount (lambda (self) (setq parens-watch-page self) (parens-watch-load self))
  :did-update (lambda (self previous-props _previous-state)
                (unless (and (equal (react-props self :v) (plist-get previous-props :v))
                             (eq (react-props self :mode) (plist-get previous-props :mode)))
                  (parens-watch-load self)))
  :will-unmount (lambda (self) (when (eq parens-watch-page self) (setq parens-watch-page nil)))
  :render
  (lambda (self)
    (let* ((id (react-props self :v))
           (video (parens-video id))
           (channel-id (plist-get video :channel-id))
           (channel (parens-channel channel-id))
           (saved (parens-later-p id))
           (status (react-state self :status)))
      (jsx (div (:class "watch")
             (div (:class "watch-main")
               (Player (:id id :start (react-props self :t) :title (plist-get video :title)))
               (and (react-state self :player-error)
                    (parens-note (parens-t 'cannot-play (react-state self :player-error)) "player-error"))
               (h1 (:class "watch-title")
                 (or (plist-get video :title) (if (eq status 'failed) "" (jsx (span (:class "skeleton-line wide") "")))))
               (and (eq status 'failed)
                    (parens-failed (react-state self :error) (lambda () (parens-watch-load self))))
               (div (:class "owner")
                 (a (:class "owner-avatar" :href (parens-route-url (or (parens-channel-route channel-id) '(:page home))))
                   (parens-avatar (or channel video)))
                 (div (:class "owner-text")
                   (a (:class "owner-name" :href (parens-route-url (or (parens-channel-route channel-id) '(:page home))))
                     (or (parens-channel-name video) ""))
                   (div (:class "muted")
                     (if (plist-get channel :subscribers)
                         (parens-t 'subscribers (parens-short-number (plist-get channel :subscribers)))
                       "")))
                 (div (:class "actions")
                   (and (plist-get video :likes)
                        (jsx (span (:class "pill") (parens-icon "like") (parens-short-number (plist-get video :likes)))))
                   (button (:class (parens-class "pill" (and saved "selected")) :type "button" :aria-pressed (if saved "true" "false")
                            :on-click (lambda (_event) (parens-toggle-later id)))
                     (parens-icon (if saved "check" "later")) (parens-t (if saved 'saved-later 'save-later)))
                   (button (:class "pill" :type "button"
                            :on-click (lambda (_event) (parens-port-send "copy" :text (parens-watch-url id))))
                     (parens-icon "share") (parens-t 'share))
                   (a (:class "pill" :href (parens-watch-url id) :target "_blank" :rel "noopener")
                     (parens-icon "external") (parens-t 'open-youtube))))
               (Description (:key id :video video :lang parens-lang :mode parens-mode))
               (Comments (:key (format "%s-%s" id parens-mode) :video-id id :count (plist-get video :comment-count))))
             (aside (:class "watch-side")
               (div (:class "up-next")
                 (h2 (:class "section-title") (parens-t 'up-next))
                 (label (:class "switch")
                   (input (:type "checkbox" :checked (parens-setting :autoplay)
                           :on-change (lambda (event) (parens-set-setting :autoplay (plist-get event :checked)))))
                   (span (parens-t 'autoplay))))
               (if (and (null (react-state self :related)) (eq status 'loading))
                   (parens-note (parens-t 'loading))
                 (parens-wide-list (react-state self :related) t))))))))

;;;; Results

(defun parens-results-load (self &optional more)
  (let ((query (react-props self :q))
        (token (and more (react-state self :next))))
    (if more
        (react-set-state self :status 'more)
      (react-set-state self :status 'loading :error nil :ids nil :next nil))
    (react-async
      (condition-case failure
          (let ((answer (react-await (parens-load-search query token))))
            (when (equal query (react-props self :q))
              (react-set-state self :status 'ready :next (plist-get answer :next)
                               :ids (if more
                                        (seq-uniq (append (react-state self :ids) (plist-get answer :ids)))
                                      (plist-get answer :ids)))))
        (error (when (equal query (react-props self :q))
                 (react-set-state self :status 'failed :error (parens-failure-text failure))))))))

(react-define-component 'ResultsPage
  :initial-state (lambda (_props) (list :status 'loading :ids nil :next nil))
  :did-mount (lambda (self)
               (parens-results-load self)
               (parens-more-function self (lambda () (parens-results-load self t))))
  :did-update (lambda (self previous-props _previous-state)
                (unless (and (equal (react-props self :q) (plist-get previous-props :q))
                             (eq (react-props self :mode) (plist-get previous-props :mode)))
                  (parens-results-load self)))
  :will-unmount (lambda (_self) (setq parens-near-end-function nil))
  :render
  (lambda (self)
    (let ((status (react-state self :status))
          (ids (react-state self :ids)))
      (jsx (div (:class "results")
             (h1 (:class "page-title") (parens-t 'results-for (react-props self :q)))
             (and (not (eq parens-mode 'api)) (parens-note (parens-t 'results-local)))
             (pcase status
               ('loading (parens-note (parens-t 'loading)))
               ('failed (parens-failed (react-state self :error) (lambda () (parens-results-load self))))
               (_ (if ids (parens-wide-list ids) (parens-note (parens-t 'no-results)))))
             (and (react-state self :next) (eq status 'ready)
                  (parens-sentinel "results" (length ids))))))))

;;;; Channel

(defun parens-channel-load (self &optional more)
  (let ((channel-id (react-props self :id))
        (token (and more (react-state self :next))))
    (if more
        (react-set-state self :status 'more)
      (react-set-state self :status 'loading :error nil :ids nil :next nil))
    (react-async
      (condition-case failure
          (let ((answer (react-await (parens-load-channel channel-id token))))
            (when (equal channel-id (react-props self :id))
              (react-set-state self :status 'ready :next (plist-get answer :next)
                               :ids (append (and more (react-state self :ids)) (plist-get answer :ids)))))
        (error (when (equal channel-id (react-props self :id))
                 (react-set-state self :status 'failed :error (parens-failure-text failure))))))))

(react-define-component 'ChannelPage
  :initial-state (lambda (_props) (list :status 'loading :ids nil :next nil))
  :did-mount (lambda (self)
               (parens-channel-load self)
               (parens-more-function self (lambda () (parens-channel-load self t))))
  :did-update (lambda (self previous-props _previous-state)
                (unless (and (equal (react-props self :id) (plist-get previous-props :id))
                             (eq (react-props self :mode) (plist-get previous-props :mode)))
                  (parens-channel-load self)))
  :will-unmount (lambda (_self) (setq parens-near-end-function nil))
  :render
  (lambda (self)
    (let* ((channel-id (react-props self :id))
           (channel (parens-channel channel-id))
           (ids (react-state self :ids))
           (title (or (plist-get channel :title)
                      (and ids (parens-channel-name (parens-video (car ids))))
                      channel-id))
           (facts (delq nil (list (plist-get channel :handle)
                                  (and (plist-get channel :subscribers)
                                       (parens-t 'subscribers (parens-short-number (plist-get channel :subscribers))))
                                  (and (plist-get channel :video-count)
                                       (parens-t 'videos-count (plist-get channel :video-count)))))))
      (jsx (div (:class "channel")
             (header (:class "channel-head")
               (parens-avatar (or channel (list :title title)) "large")
               (div
                 (h1 (:class "page-title") title)
                 (and facts (jsx (p (:class "muted") (string-join facts " • "))))
                 (a (:class "text-button" :href (concat "https://www.youtube.com/channel/" channel-id)
                     :target "_blank" :rel "noopener")
                   (parens-t 'open-youtube))))
             (pcase (react-state self :status)
               ('loading (parens-skeleton-grid 8))
               ('failed (parens-failed (react-state self :error) (lambda () (parens-channel-load self))))
               (_ (if ids (parens-grid ids) (parens-note (parens-t 'no-results)))))
             (and (react-state self :next) (eq (react-state self :status) 'ready)
                  (parens-sentinel "channel" (length ids))))))))

;;;; History and watch later

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
  :initial-state (lambda (_props) (list :draft (or parens-api-key "")))
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
                 (format "%s: %s" (parens-mode-name parens-mode t) (or parens-mode-note "")))
               (form (:class "key-form" :on-submit (lambda (_event) (parens-use-key (string-trim (react-state self :draft)))))
                 (input (:ref "key" :type "password" :autocomplete "off" :spellcheck "false" :value draft
                         :placeholder "AIza…" :aria-label (parens-t 'api-key)
                         :on-input (lambda (event) (react-set-state self :draft (plist-get event :value)))))
                 (button (:class "button" :type "submit" :disabled (string-empty-p (string-trim draft)))
                   (parens-t 'api-key-save)))
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
