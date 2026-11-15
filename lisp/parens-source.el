;;; parens-source.el --- where the videos come from  -*- lexical-binding: t; -*-

;; Three sources, one shape of data: a video is a `parens-video' and a
;; channel a `parens-channel' (shared/parens-types.el, which server.el
;; uses too), made with `make-parens-video', which checks the fields.
;;
;; - `api': the YouTube Data API v3 with the visitor's key, called from the
;;   page (Google's API answers other sites' pages: CORS).
;; - `server': server.el reads the RSS feeds of the channels in
;;   parens-data.el (a page may not: the feeds do not allow other sites).
;; - `curated': the list in parens-data.el; titles and channel names from
;;   YouTube's oEmbed, which allows other sites.
;;
;; `server' and `curated' load a "catalogue" once and answer everything
;; (home, search, related, a channel) from it; `api' asks for each page.
;;
;; Every loader here is an awaitable (see `react-await').  The pages await
;; them and keep what they get in their state; videos and channels
;; themselves are kept here, in two hash tables, so that a card, the watch
;; page and the history all show the same thing.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'url-util)

(declare-function parens-later-sync "parens-state")

;;;; What is known

(defvar parens-mode nil
  "Where the data comes from: `api', `server' or `curated'; nil until known.")
(defvar parens-mode-note nil
  "Why the mode is not the richer one: the failure, or nil.
`parens-mode-note-text' says it in words.")
(defvar parens-generation 0
  "Changes whenever the source changes (a key saved or removed): answers to
requests made before belong to an old source and are dropped.  The pages
get it as a prop and load again when it changes.")
(defvar parens-api-key nil "The visitor's YouTube Data API key, or nil.")
(defvar parens-videos (make-hash-table :test #'equal) "Video id -> what is known about it.")
(defvar parens-channels (make-hash-table :test #'equal) "Channel id -> what is known about it.")
(defvar parens-catalogue nil "The ids of the videos of the `server' and `curated' modes.")
(defvar parens-catalogue-status nil "nil, `loading' or `ready'.")
(defvar parens-catalogue-waiting nil "(RESOLVE . REJECT) of the loaders waiting for the catalogue.")
(defvar parens-changed-function nil
  "Called without arguments when something new is known (the application renders).")

(defun parens-changed ()
  (when parens-changed-function (funcall parens-changed-function)))

(defun parens--merge (old new)
  "A new plist: OLD with the values of NEW that are not nil."
  (let ((merged (copy-sequence old)))
    (while new
      (when (cadr new) (setq merged (plist-put merged (car new) (cadr new))))
      (setq new (cddr new)))
    merged))

(defun parens-remember-video (video)
  "Add what VIDEO says to what is known.  Returns its id.
The plist kept is a new one, so `:pure' cards see the change."
  (let ((id (plist-get video :id)))
    (puthash id (parens--merge (gethash id parens-videos) video) parens-videos)
    id))

(defun parens-remember-channel (channel)
  (let ((id (plist-get channel :id)))
    (puthash id (parens--merge (gethash id parens-channels) channel) parens-channels)
    id))

(defun parens-video (id) (and id (gethash id parens-videos)))
(defun parens-channel (id) (and id (gethash id parens-channels)))

(defun parens-channel-name (video)
  (or (plist-get video :channel)
      (plist-get (parens-channel (plist-get video :channel-id)) :title)))

(defun parens-thumbnail-url (id)
  (format "https://i.ytimg.com/vi/%s/mqdefault.jpg" id))

(defun parens-watch-url (id)
  (concat "https://www.youtube.com/watch?v=" id))

(defun parens-forget-everything ()
  "Forget all videos, channels and the catalogue (the source changed)."
  (clrhash parens-videos)
  (clrhash parens-channels)
  (setq parens-generation (1+ parens-generation)
        parens-catalogue nil parens-catalogue-status nil parens-catalogue-waiting nil
        parens-mode-note nil))

(defun parens-mode-note-text ()
  "Why the mode is not the richer one, in `parens-lang', or nil."
  (and parens-mode-note (parens-t 'fallback (parens-failure-text parens-mode-note))))

(defun parens-stale-p (generation)
  "Non-nil if GENERATION is not the current source's."
  (/= generation parens-generation))

;;;; Waiting

(defmacro parens-async (&rest body)
  "An awaitable whose value is BODY's.  BODY may use `react-await'.
An error in BODY rejects it with the error (a failure, see
`parens-failure-text').  Like `react-async', BODY may not await inside a
`lambda'."
  (declare (indent 0))
  (let ((resolve (make-symbol "resolve")) (reject (make-symbol "reject"))
        (outcome (make-symbol "outcome")))
    `(lambda (,resolve ,reject)
       (react-async
         (let ((,outcome (condition-case failure
                             (cons t (progn ,@body))
                           (error (cons nil failure)))))
           (if (car ,outcome)
               (funcall ,resolve (cdr ,outcome))
             (funcall ,reject (cdr ,outcome))))))))

(defun parens-all (awaitables)
  "An awaitable for all of AWAITABLES at once (elisp-react has no Promise.all).
Its value is the list of their values; nil for one that failed."
  (lambda (resolve _reject)
    (let* ((left (length awaitables))
           (values (make-vector left nil)))
      (if (zerop left)
          (funcall resolve nil)
        (seq-do-indexed
         (lambda (awaitable index)
           (let ((settle (lambda (value)
                           (aset values index value)
                           (when (zerop (cl-decf left))
                             (funcall resolve (append values nil))))))
             (funcall awaitable settle (lambda (_failure) (funcall settle nil)))))
         awaitables)))))

(defun parens--reason (failure)
  "What FAILURE comes down to: a plist from a request, a string, or an error."
  (while (eq (car-safe failure) 'react-async-error)
    (setq failure (cadr failure)))
  failure)

(defun parens-failure-text (failure)
  "A sentence for the visitor about FAILURE."
  (let ((reason (parens--reason failure)))
    ;; The Data API's messages contain HTML (<code>playlistId</code>).
    (when (and (consp reason) (keywordp (car reason)) (stringp (plist-get reason :message)))
      (setq reason (react-plist-with reason :message
                                     (replace-regexp-in-string "<[^>]*>" "" (plist-get reason :message)))))
    (cond ((and (consp reason) (keywordp (car reason)))
           (pcase (plist-get reason :reason)
             ((or "quotaExceeded" "dailyLimitExceeded" "rateLimitExceeded") (parens-t 'quota))
             ("videoChartNotFound" (parens-t 'chart-missing))
             ("commentsDisabled" (parens-t 'comments-off))
             (_ (if (memql (plist-get reason :status) '(401 403 404))
                    ;; oEmbed: 404 for no such video, 401/403 for a private one.
                    (if (plist-get reason :reason)
                        (parens-t 'error (plist-get reason :message))
                      (parens-t 'not-found))
                  (parens-t 'error (or (plist-get reason :message)
                                       (format "HTTP %s" (plist-get reason :status))))))))
          ((stringp reason) (parens-t 'error reason))
          ((and (consp reason) (symbolp (car reason)))
           (parens-t 'error (error-message-string reason)))
          (t (parens-t 'error (format "%S" reason))))))

(defun parens-failure-status (failure)
  (let ((reason (parens--reason failure)))
    (and (consp reason) (keywordp (car reason)) (plist-get reason :status))))

;;;; Requests

(defun parens-in-background (awaitable)
  "Start AWAITABLE and forget it: what it learns is shown when it comes
(`parens-changed'), and nobody waits for it (pictures, for instance)."
  (funcall awaitable #'ignore #'ignore))

(defun parens-json-request (url)
  "An awaitable: the JSON at URL, as plists and vectors."
  (lambda (resolve reject)
    (react-fetch url
                 :then (lambda (response)
                         (let* ((data (ignore-errors (react-response-json response)))
                                (problem (plist-get data :error)))
                           (if (plist-get response :ok)
                               (funcall resolve data)
                             (funcall reject
                                      (let ((first (and (vectorp (plist-get problem :errors))
                                                        (> (length (plist-get problem :errors)) 0)
                                                        (aref (plist-get problem :errors) 0))))
                                        (list :status (plist-get response :status)
                                              :reason (plist-get first :reason)
                                              :message (or (plist-get problem :message)
                                                           (format "HTTP %s" (plist-get response :status)))))))))
                 :catch reject)))

(defun parens-oembed (id)
  "An awaitable: YouTube's oEmbed answer about the video ID."
  (parens-json-request (concat "https://www.youtube.com/oembed?format=json&url="
                               (url-hexify-string (parens-watch-url id)))))

(defun parens-hl ()
  (if (eq parens-lang 'en) "en" "ja"))

(defun parens-api (endpoint &rest parameters)
  "An awaitable: the Data API's answer at ENDPOINT to PARAMETERS (a plist).
Parameters whose value is nil are left out."
  (let (query)
    (while parameters
      (when (cadr parameters)
        (push (list (substring (symbol-name (car parameters)) 1) (cadr parameters)) query))
      (setq parameters (cddr parameters)))
    (push (list "key" parens-api-key) query)
    (parens-json-request (concat "https://www.googleapis.com/youtube/v3/" endpoint "?"
                                 (url-build-query-string (nreverse query))))))

;;;; The Data API's records as ours

(defconst parens-video-parts "snippet,contentDetails,statistics,status")

(defun parens-video-from-api (item)
  (let* ((snippet (plist-get item :snippet))
         (statistics (plist-get item :statistics))
         (details (plist-get item :contentDetails))
         (status (plist-get item :status))
         (id (plist-get item :id)))
    (make-parens-video
          :id id
          ;; hl= translates only `localized', not the title itself.
          :title (or (plist-get (plist-get snippet :localized) :title) (plist-get snippet :title))
          :channel-id (plist-get snippet :channelId)
          :channel (plist-get snippet :channelTitle)
          :published (plist-get snippet :publishedAt)
          :description (or (plist-get (plist-get snippet :localized) :description) (plist-get snippet :description))
          :thumbnail (or (plist-get (plist-get (plist-get snippet :thumbnails) :medium) :url)
                         (parens-thumbnail-url id))
          :category (plist-get snippet :categoryId)
          :live (pcase (plist-get snippet :liveBroadcastContent)
                  ("live" 'live)
                  ("upcoming" 'upcoming))
          :views (parens-number (plist-get statistics :viewCount))
          :likes (parens-number (plist-get statistics :likeCount))
          :comment-count (parens-number (plist-get statistics :commentCount))
          :duration (plist-get details :duration)
          ;; JSON false and a missing field are both nil after parsing.
          :embeddable (if (and status (not (plist-get status :embeddable))) :false t)
          :complete t)))

(defun parens-channel-from-api (item)
  (let* ((snippet (plist-get item :snippet))
         (statistics (plist-get item :statistics))
         (pictures (plist-get snippet :thumbnails)))
    (make-parens-channel
          :id (plist-get item :id)
          :title (plist-get snippet :title)
          :handle (plist-get snippet :customUrl)
          :avatar (plist-get (or (plist-get pictures :medium) (plist-get pictures :default)) :url)
          :subscribers (and (not (plist-get statistics :hiddenSubscriberCount))
                            (parens-number (plist-get statistics :subscriberCount)))
          :video-count (parens-number (plist-get statistics :videoCount))
          :description (plist-get snippet :description)
          :uploads (plist-get (plist-get (plist-get item :contentDetails) :relatedPlaylists) :uploads))))

(defun parens-comment-from-api (item)
  (let* ((thread (plist-get item :snippet))
         (comment (plist-get (plist-get thread :topLevelComment) :snippet)))
    (list :id (plist-get item :id)
          :author (plist-get comment :authorDisplayName)
          :avatar (plist-get comment :authorProfileImageUrl)
          :author-url (plist-get comment :authorChannelUrl)
          :text (or (plist-get comment :textOriginal) (plist-get comment :textDisplay) "")
          :likes (parens-number (plist-get comment :likeCount))
          :published (plist-get comment :publishedAt)
          :replies (parens-number (plist-get thread :totalReplyCount)))))

(defun parens-video-from-oembed (id answer)
  (make-parens-video :id id
                     :title (plist-get answer :title)
                     :channel (plist-get answer :author_name)
                     :channel-url (plist-get answer :author_url)))

(defun parens-playable-p (id)
  (not (eq (plist-get (parens-video id) :embeddable) :false)))

(defun parens-remember-api-videos (answer)
  "Remember the videos of a videos.list ANSWER.
The value is the ids of those that can be played here."
  (seq-filter #'parens-playable-p
              (mapcar (lambda (item) (parens-remember-video (parens-video-from-api item)))
                      (plist-get answer :items))))

(defun parens-api-videos (ids)
  "An awaitable: details of the videos IDS (videos.list, one request for 50)."
  (parens-async
    (if (null ids)
        nil
      (parens-remember-api-videos
       (react-await (parens-api "videos" :part parens-video-parts :id (string-join ids ",")
                                :hl (parens-hl) :maxResults "50"))))))

(defun parens-api-fill-channels (channel-ids)
  "An awaitable: make sure the channels CHANNEL-IDS are known (avatars...).
A failure here only costs pictures: it is ignored."
  (parens-async
    (let ((missing (seq-uniq (seq-remove (lambda (id) (or (null id) (plist-get (parens-channel id) :avatar)))
                                         channel-ids)))
          (answer nil))
      (when missing
        (setq answer (condition-case nil
                         (react-await (parens-api "channels" :part "snippet,statistics,contentDetails"
                                                  :id (string-join (seq-take missing 50) ",")))
                       (error nil)))
        (mapc (lambda (item) (parens-remember-channel (parens-channel-from-api item)))
              (plist-get answer :items))
        (parens-changed))
      t)))

(defun parens-channels-of (ids)
  (mapcar (lambda (id) (plist-get (parens-video id) :channel-id)) ids))

;;;; The catalogue (server and curated modes)

(defun parens--settle-catalogue (ok value)
  (let ((waiting (nreverse parens-catalogue-waiting)))
    (setq parens-catalogue-waiting nil)
    (dolist (pair waiting)
      (funcall (if ok (car pair) (cdr pair)) value))))

(defun parens-catalogue-ready ()
  "An awaitable: the catalogue's ids, loading it the first time."
  (lambda (resolve reject)
    (if (eq parens-catalogue-status 'ready)
        (funcall resolve parens-catalogue)
      (push (cons resolve reject) parens-catalogue-waiting)
      (unless (eq parens-catalogue-status 'loading)
        (setq parens-catalogue-status 'loading)
        (funcall (parens-catalogue-load)
                 (lambda (ids) (setq parens-catalogue-status 'ready) (parens--settle-catalogue t ids))
                 (lambda (failure) (setq parens-catalogue-status nil) (parens--settle-catalogue nil failure)))))))

(defun parens-catalogue-load ()
  "An awaitable: ask server.el for the feeds, or else take the curated list."
  (parens-async
    (let* ((generation parens-generation)
           (problem nil)
           (answer (condition-case failure
                       ;; A `parens-feed', checked as it comes (api/feed.el checks it too).
                       (react-await (nextel-request "GET" "/api/feed" :returns 'parens-feed))
                     (error (setq problem failure) nil))))
      ;; A key was saved meanwhile: this answer is for a source that is gone.
      (when (parens-stale-p generation) (error "Stale"))
      ;; A static site has no server (404): that is the curated mode, not a
      ;; problem.  Anything else is worth saying.
      (when (and problem (not (eql (parens-failure-status problem) 404)))
        (setq parens-mode-note problem))
      (if (plist-get answer :videos)
          (progn
            (setq parens-mode 'server)
            (dolist (channel (plist-get answer :channels)) (parens-remember-channel channel))
            (setq parens-catalogue (mapcar #'parens-remember-video (plist-get answer :videos)))
            (parens-later-sync))
        (setq parens-mode 'curated)
        (setq parens-catalogue
              (mapcar (lambda (entry)
                        (parens-remember-video (make-parens-video :id (car entry) :channel-id (cadr entry)
                                                                  :thumbnail (parens-thumbnail-url (car entry)))))
                      parens-curated-videos))
        (parens-curated-titles))
      (parens-changed)
      parens-catalogue)))

(defun parens-curated-titles ()
  "Ask oEmbed about every curated video; each answer is shown when it comes."
  (dolist (id parens-catalogue)
    (funcall (parens-oembed id)
             (lambda (answer)
               (parens-remember-video (parens-video-from-oembed id answer))
               (let ((channel-id (plist-get (parens-video id) :channel-id)))
                 (unless (plist-get (parens-channel channel-id) :title)
                   (parens-remember-channel (list :id channel-id :title (plist-get answer :author_name)
                                                  :url (plist-get answer :author_url)))))
               (parens-changed))
             #'ignore)))

(defun parens--video-text (id)
  (let ((video (parens-video id)))
    (downcase (string-join (delq nil (list (plist-get video :title) (plist-get video :channel)
                                           (plist-get video :description)))
                           " "))))

(defun parens-catalogue-search (query)
  "The catalogue's videos that have every word of QUERY."
  (let ((words (split-string (downcase query) "[ \t　]+" t)))
    (seq-filter (lambda (id)
                  (let ((text (parens--video-text id)))
                    (seq-every-p (lambda (word) (string-search word text)) words)))
                parens-catalogue)))

(defun parens-catalogue-related (id)
  "Other videos for the watch page of ID: its channel first, then its topic."
  (let* ((channel (plist-get (parens-video id) :channel-id))
         (topic (parens-topic-of channel))
         (others (remove id parens-catalogue))
         (same-channel (seq-filter (lambda (other) (equal (plist-get (parens-video other) :channel-id) channel))
                                   others))
         (same-topic (seq-filter (lambda (other)
                                   (and (not (member other same-channel))
                                        (eq (parens-topic-of (plist-get (parens-video other) :channel-id)) topic)))
                                 others)))
    (seq-take (append same-channel same-topic (seq-difference others (append same-channel same-topic)))
              20)))

;;;; What the pages ask for

(defun parens-load-categories ()
  "An awaitable: ((ID . TITLE) ...), the chips of the home page in the `api' mode."
  (parens-async
    (let ((answer (react-await (parens-api "videoCategories" :part "snippet" :regionCode "JP" :hl (parens-hl)))))
      (delq nil (mapcar (lambda (item)
                          (let ((snippet (plist-get item :snippet)))
                            (and (plist-get snippet :assignable)
                                 (cons (plist-get item :id) (plist-get snippet :title)))))
                        (plist-get answer :items))))))

(defun parens-load-home (filter token)
  "An awaitable: (:ids IDS :next TOKEN), the videos of the home page.
FILTER is a category id (`api') or a topic (the others), nil for all."
  (if (eq parens-mode 'api)
      (parens-async
        (let* ((answer (react-await (parens-api "videos" :part parens-video-parts :chart "mostPopular"
                                                :regionCode "JP" :hl (parens-hl) :maxResults "24"
                                                :videoCategoryId filter :pageToken token)))
               (ids (parens-remember-api-videos answer)))
          (parens-in-background (parens-api-fill-channels (parens-channels-of ids)))
          (list :ids ids :next (plist-get answer :nextPageToken))))
    (parens-async
      (react-await (parens-catalogue-ready))
      (list :ids (if filter
                     (seq-filter (lambda (id) (eq (parens-topic-of (plist-get (parens-video id) :channel-id)) filter))
                                 parens-catalogue)
                   parens-catalogue)))))

(defun parens-load-video (id)
  "An awaitable: the video ID with what can be known about it."
  (parens-async
    (if (eq parens-mode 'api)
        (progn
          (unless (plist-get (parens-video id) :complete)
            (react-await (parens-api-videos (list id))))
          (parens-in-background (parens-api-fill-channels (list (plist-get (parens-video id) :channel-id)))))
      (react-await (parens-catalogue-ready))
      (unless (plist-get (parens-video id) :title)
        ;; Not one of ours (a link from elsewhere): oEmbed still knows it.
        (let ((answer (react-await (parens-oembed id))))
          (parens-remember-video (parens-video-from-oembed id answer)))))
    (or (parens-video id) (error "No such video: %s" id))))

(defun parens-load-related (id)
  "An awaitable: ids of videos to show next to the video ID."
  (parens-async
    (if (not (eq parens-mode 'api))
        (progn (react-await (parens-catalogue-ready))
               (parens-catalogue-related id))
      ;; search.list's relatedToVideoId is gone (2023): the channel's
      ;; uploads and the chart of the video's category stand in.  Either
      ;; may fail (no chart for a category): what there is is shown.
      (let* ((video (parens-video id))
             (known (or (plist-get (parens-channel (plist-get video :channel-id)) :uploads)
                        ;; Reached by its address, the channel may not be known yet.
                        (react-await (parens-api-fill-channels (list (plist-get video :channel-id))))))
             (uploads (and known (plist-get (parens-channel (plist-get video :channel-id)) :uploads)))
             (from-channel (and uploads
                                (condition-case nil
                                    (react-await (parens-api-playlist uploads 12 nil))
                                  (error nil))))
             (chart (condition-case nil
                        (react-await (parens-api "videos" :part parens-video-parts :chart "mostPopular"
                                                 :regionCode "JP" :hl (parens-hl) :maxResults "12"
                                                 :videoCategoryId (plist-get video :category)))
                      (error nil)))
             (from-chart (parens-remember-api-videos chart))
             (ids (seq-take (remove id (seq-uniq (append (plist-get from-channel :ids) from-chart))) 20)))
        (parens-in-background (parens-api-fill-channels (parens-channels-of ids)))
        ids))))

(defun parens-api-playlist (playlist count token)
  "An awaitable: (:ids IDS :next TOKEN), COUNT videos of PLAYLIST with details."
  (parens-async
    (let* ((answer (react-await (parens-api "playlistItems" :part "contentDetails" :playlistId playlist
                                            :maxResults (number-to-string count) :pageToken token)))
           (found (delq nil (mapcar (lambda (item) (plist-get (plist-get item :contentDetails) :videoId))
                                    (plist-get answer :items))))
           (ids (react-await (parens-api-videos found))))
      (list :ids ids :next (plist-get answer :nextPageToken)))))

(defun parens-load-comments (id token)
  "An awaitable: (:comments COMMENTS :next TOKEN) of the video ID (`api' only)."
  (parens-async
    (let ((answer (react-await (parens-api "commentThreads" :part "snippet" :videoId id :maxResults "20"
                                           :order "relevance" :textFormat "plainText" :pageToken token))))
      (list :comments (mapcar #'parens-comment-from-api (plist-get answer :items))
            :next (plist-get answer :nextPageToken)))))

(defun parens-load-search (query token)
  "An awaitable: (:ids IDS :next TOKEN), the videos found for QUERY."
  (if (eq parens-mode 'api)
      (parens-async
        (let* ((answer (react-await (parens-api "search" :part "snippet" :q query :type "video"
                                                :videoEmbeddable "true" :maxResults "20" :regionCode "JP"
                                                :pageToken token)))
               (found (delq nil (mapcar (lambda (item) (plist-get (plist-get item :id) :videoId))
                                        (plist-get answer :items))))
               (ids (react-await (parens-api-videos found))))
          (parens-in-background (parens-api-fill-channels (parens-channels-of ids)))
          (list :ids ids :next (plist-get answer :nextPageToken))))
    (parens-async
      (react-await (parens-catalogue-ready))
      (list :ids (parens-catalogue-search query)))))

(defun parens-load-channel (channel-id token)
  "An awaitable: (:ids IDS :next TOKEN), the videos of the channel CHANNEL-ID."
  (if (eq parens-mode 'api)
      (parens-async
        (react-await (parens-api-fill-channels (list channel-id)))
        (let ((uploads (or (plist-get (parens-channel channel-id) :uploads) (error "No such channel"))))
          (react-await (parens-api-playlist uploads 24 token))))
    (parens-async
      (react-await (parens-catalogue-ready))
      (list :ids (seq-filter (lambda (id) (equal (plist-get (parens-video id) :channel-id) channel-id))
                             parens-catalogue)))))

(provide 'parens-source)
;;; parens-source.el ends here
