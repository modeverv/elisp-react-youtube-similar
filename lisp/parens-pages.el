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

(defun parens-source-changed-p (self previous-props)
  (not (and (eql (react-props self :generation) (plist-get previous-props :generation))
            (eq (react-props self :mode) (plist-get previous-props :mode)))))

;;;; Home

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

(react-define-component 'HomePage
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

;;;; Watch

(defun parens-player-error-text (code)
  "What the YouTube player's error CODE means for the visitor."
  (pcase code
    (100 (parens-t 'player-100))
    ((or 101 150) (parens-t 'player-150 code))
    (153 (parens-t 'player-153))
    (_ (parens-t 'cannot-play code))))

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
             ;; (COEP), and YouTube's player sends no COEP header; the attribute
             ;; also signs the player out, so only there.  referrerpolicy: the
             ;; player refuses to play without a Referer (error 153), and a
             ;; server may send Referrer-Policy: same-origin.
             (iframe (:key id :class "player-frame" :data-player id
                      :src (parens-embed-url id (react-props self :start))
                      :title (or (react-props self :title) "YouTube")
                      :allow "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                      :allowfullscreen t :credentialless (react-props self :isolated)
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
  (let* ((id (react-props self :v))
         (generation parens-generation)
         (current (lambda () (and (equal id (react-props self :v)) (not (parens-stale-p generation))))))
    (react-set-state self :status 'loading :error nil :related nil :player-error nil)
    (react-async
      (condition-case failure
          (progn
            (react-await (parens-load-video id))
            (when (funcall current)
              (react-set-state self :status 'ready)
              (parens-watched id)
              (let ((related (condition-case nil (react-await (parens-load-related id)) (error nil))))
                (when (funcall current)
                  (react-set-state self :related related)))))
        (error (when (funcall current)
                 (react-set-state self :status 'failed :error (parens-failure-text failure))))))))

(defun parens-next-video ()
  "The video to play when this one ends: the first related one not watched
lately (else two videos of a channel would take turns forever)."
  (when parens-watch-page
    (let* ((related (react-state parens-watch-page :related))
           (recent (mapcar (lambda (entry) (plist-get entry :id)) (seq-take (parens-app-state :history) 20))))
      (or (seq-find (lambda (id) (not (member id recent))) related)
          (car related)))))

(react-define-component 'WatchPage
  :initial-state (lambda (_props) (list :status 'loading :related nil :player-error nil))
  :did-mount (lambda (self) (setq parens-watch-page self) (parens-watch-load self))
  :did-update (lambda (self previous-props _previous-state)
                (when (or (not (equal (react-props self :v) (plist-get previous-props :v)))
                          (parens-source-changed-p self previous-props))
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
               (Player (:id id :start (react-props self :t) :title (plist-get video :title) :isolated parens-isolated))
               (and (react-state self :player-error)
                    (parens-note (parens-player-error-text (react-state self :player-error)) "player-error"))
               (h1 (:class "watch-title")
                 (or (plist-get video :title) (if (eq status 'failed) "" (jsx (span (:class "skeleton-line wide") "")))))
               (and (eq status 'failed)
                    (parens-failed (react-state self :error) (lambda () (parens-watch-load self))))
               (div (:class "owner")
                 (a (:class "owner-avatar" :href (parens-route-url (or (parens-channel-route channel-id) '(:page home)))
                     :aria-label (or (parens-channel-name video) ""))
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
               (Comments (:key (format "%s-%s-%s" id parens-mode parens-generation)
                          :video-id id :count (plist-get video :comment-count))))
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
  (let ((query (react-props self :q)))
    (parens-list-load self query (lambda (token) (parens-load-search query token)) more)))

(react-define-component 'ResultsPage
  :initial-state (lambda (_props) (list :key nil :status 'loading :ids nil :next nil))
  :did-mount (lambda (self)
               (parens-results-load self)
               (parens-more-function self "results" (lambda () (parens-results-load self t))))
  :did-update (lambda (self previous-props _previous-state)
                (when (or (not (equal (react-props self :q) (plist-get previous-props :q)))
                          (parens-source-changed-p self previous-props))
                  (parens-results-load self)))
  :will-unmount (lambda (_self) (parens-forget-more-function "results"))
  :render
  (lambda (self)
    (let ((ids (react-state self :ids)))
      (jsx (div (:class "results")
             (h1 (:class "page-title") (parens-t 'results-for (react-props self :q)))
             (and (not (eq parens-mode 'api)) (parens-note (parens-t 'results-local)))
             (pcase (react-state self :status)
               ('loading (parens-note (parens-t 'loading)))
               ('failed (parens-failed (react-state self :error) (lambda () (parens-results-load self))))
               (_ (if ids (parens-wide-list ids) (parens-note (parens-t 'no-results)))))
             (parens-more-row self "results" (lambda () (parens-results-load self t))))))))

;;;; Channel

(defun parens-channel-load (self &optional more)
  (let ((channel-id (react-props self :id)))
    (parens-list-load self channel-id (lambda (token) (parens-load-channel channel-id token)) more)))

(react-define-component 'ChannelPage
  :initial-state (lambda (_props) (list :key nil :status 'loading :ids nil :next nil))
  :did-mount (lambda (self)
               (parens-channel-load self)
               (parens-more-function self "channel" (lambda () (parens-channel-load self t))))
  :did-update (lambda (self previous-props _previous-state)
                (when (or (not (equal (react-props self :id) (plist-get previous-props :id)))
                          (parens-source-changed-p self previous-props))
                  (parens-channel-load self)))
  :will-unmount (lambda (_self) (parens-forget-more-function "channel"))
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
             (parens-more-row self "channel" (lambda () (parens-channel-load self t))))))))

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
