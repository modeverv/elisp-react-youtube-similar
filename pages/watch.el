;;; watch.el --- the watch page, /watch?v=ID&t=SECONDS  -*- lexical-binding: t; -*-

;; The player, the video's title, channel, actions, description and
;; comments, and videos to play next.  The page loads what it shows itself
;; (not with :load): the player stays while the rest loads, and stays when
;; only the rest changes.

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

(defun parens-watch-start (route)
  "Where ROUTE starts the video: t=90 or t=90s, in seconds, or nil."
  (let ((start (nextel-query route "t")))
    (and start (parens-number (string-remove-suffix "s" start)))))

(defun parens-watch-load (self)
  (let* ((id (nextel-query self "v"))
         (generation parens-generation)
         (current (lambda () (and (equal id (nextel-query self "v")) (not (parens-stale-p generation))))))
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

(defun parens-watch-id (route)
  "The video of ROUTE (?v=ID), if it is a video's id."
  (let ((id (nextel-query route "v")))
    (and id (string-match-p parens-video-id-regexp id) id)))

(nextel-page WatchPage
  :head (lambda (route _data) (list :title (plist-get (parens-video (parens-watch-id route)) :title)))
  :initial-state (lambda (_props) (list :status 'loading :related nil :player-error nil))
  :did-mount (lambda (self) (setq parens-watch-page self) (when (parens-watch-id self) (parens-watch-load self)))
  :did-update (lambda (self previous-props _previous-state)
                (when (and (parens-watch-id self)
                           (or (not (equal (nextel-query self "v") (nextel-query (plist-get previous-props :route) "v")))
                               (parens-source-changed-p self previous-props)))
                  (parens-watch-load self)))
  :will-unmount (lambda (self) (when (eq parens-watch-page self) (setq parens-watch-page nil)))
  :render
  (lambda (self)
    (if (not (parens-watch-id self))
        (parens-not-found)
      (parens-watch-render self))))

(defun parens-watch-render (self)
  "The watch page SELF of a video."
  (let* ((id (parens-watch-id self))
         (video (parens-video id))
         (channel-id (plist-get video :channel-id))
         (channel (parens-channel channel-id))
         (saved (parens-later-p id))
         (status (react-state self :status)))
    (jsx (div (:class "watch")
           (div (:class "watch-main")
             (Player (:id id :start (parens-watch-start self) :title (plist-get video :title) :isolated parens-isolated))
             (and (react-state self :player-error)
                  (parens-note (parens-player-error-text (react-state self :player-error)) "player-error"))
             (h1 (:class "watch-title")
               (or (plist-get video :title) (if (eq status 'failed) "" (jsx (span (:class "skeleton-line wide") "")))))
             (and (eq status 'failed)
                  (parens-failed (react-state self :error) (lambda () (parens-watch-load self))))
             (div (:class "owner")
               (a (:class "owner-avatar" :href (parens-channel-href channel-id)
			  :aria-label (or (parens-channel-name video) ""))
                 (parens-avatar (or channel video)))
               (div (:class "owner-text")
                 (a (:class "owner-name" :href (parens-channel-href channel-id))
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
               (parens-wide-list (react-state self :related) t)))))))

;;; watch.el ends here
