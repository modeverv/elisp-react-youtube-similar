;;; _feeds.el --- the channels' feeds, for api/feed.el  -*- lexical-binding: t; -*-

;; A helper of api/ (its name starts with _: no route).  GET /api/feed
;; answers a `parens-feed' (shared/parens-types.el).
;;
;; YouTube's channel feeds (RSS) send no CORS headers: a page cannot read
;; them, a server can.  They have what oEmbed has not: views, likes, dates
;; and descriptions.  So when the application finds this server (elisp-studio's
;; run.sh, tools/serve-project.sh), it shows the latest long-form uploads
;; (the playlist UULF...) of the channels below instead of its fixed list.
;;
;; In elisp-studio's browser tab, a server's request is the page's fetch and
;; the browser refuses it (CORS): /api/feed then answers 502 and the
;; application falls back to its list, saying why.
;;
;; The feeds are read at most every 15 minutes (they say max-age=900), and
;; requests that come while they are being read wait for that reading.
;; The last good reading is kept (`app-server-write': a file, or MySQL on a
;; shared host), and a job reads them again every 15 minutes
;; (`app-server-defjob'): run.sh runs it by itself, a shared host from
;; cron.  There each request is a new Emacs that is gone after its answer
;; (elisp-studio's serve-cgi.el), so a request never reads the feeds: it
;; answers what the job kept, or 503 before the first reading.

(require 'seq)
(require 'subr-x)
;; xml.el (Lisp; the browser's Emacs has no libxml) is loaded when a feed is
;; read: a request that answers what is kept does not need it, and loading
;; it is half of a CGI request's start (8 ms of 17 on Sakura).
(eval-when-compile (require 'xml))
(declare-function xml-parse-region "xml")
(declare-function xml-get-children "xml")
(declare-function xml-get-attribute-or-nil "xml")

(defconst parens-server-channels
  '("UC0uTPqBCFIpZxlz_Lv1tk_g" "UCAiiOTio8Yu69c3XnR7nQBQ" "UC9-y-6csu5WGm29I7JiwpnA"
    "UCnUYZLuoy1rq1aVMwx4aTzw" "UC_x5XG1OV2P6uZZ5FSM9Ttw" "UCYO_jab_esuFRV4b17AJtAw"
    "UCoxcjq-8xIDTYp3uz647V5A" "UCsXVk37bltHxD1rDPwtNM8Q" "UCLA_DiR1FfKNvjuUpBHmylQ")
  "The channels of `parens-curated-channels' (lisp/parens-data.el).
A copy: lisp/ is the page's; the server loads shared/ and api/.")

(defconst parens-server-max-age 900 "Seconds a reading of the feeds is used.")

(defvar parens-server-cache nil
  "(TIME . ANSWER): the last reading that found videos, as it is kept.")
(defvar parens-server-waiting nil
  "(RESPOND . FAIL) of the requests waiting for the reading in progress, or nil.")
(defvar parens-server-reading nil "Non-nil while the feeds are being read.")
(defvar parens-server-round 0 "The number of the latest reading; older answers are dropped.")
(defconst parens-server-deadline 20 "Seconds a reading may take; then what has come is used.")

(defun parens-server--text (node)
  (let ((text (car (xml-node-children node))))
    (and (stringp text) (string-trim text))))

(defun parens-server--child (node &rest path)
  "The descendant of NODE along PATH (element names), or nil."
  (dolist (name path node)
    (setq node (and node (car (xml-get-children node name))))))

(defun parens-server-entries (text)
  "The videos of the Atom feed TEXT, as plists the application understands."
  (require 'xml)
  (let* ((feed (with-temp-buffer
                 (insert text)
                 (car (xml-parse-region (point-min) (point-max)))))
         (videos nil))
    (dolist (entry (xml-get-children feed 'entry))
      (let* ((id (parens-server--text (parens-server--child entry 'yt:videoId)))
             (group (parens-server--child entry 'media:group))
             (community (parens-server--child group 'media:community))
             (views (xml-get-attribute-or-nil (parens-server--child community 'media:statistics) 'views))
             (likes (xml-get-attribute-or-nil (parens-server--child community 'media:starRating) 'count)))
        (when (and id (string-match-p "\\`[A-Za-z0-9_-]\\{11\\}\\'" id))
          (push (make-parens-video :id id
                      :title (parens-server--text (parens-server--child entry 'title))
                      :channel-id (parens-server--text (parens-server--child entry 'yt:channelId))
                      :channel (parens-server--text (parens-server--child entry 'author 'name))
                      :channel-url (parens-server--text (parens-server--child entry 'author 'uri))
                      :published (parens-server--text (parens-server--child entry 'published))
                      :description (let ((description (parens-server--text (parens-server--child group 'media:description))))
                                     (and description (truncate-string-to-width description 5000)))
                      :views (and views (string-to-number views))
                      :likes (and likes (string-to-number likes))
                      :thumbnail (format "https://i.ytimg.com/vi/%s/mqdefault.jpg" id))
                videos))))
    (nreverse videos)))

(defun parens-server--settle (ok value)
  (let ((waiting (nreverse parens-server-waiting)))
    (setq parens-server-waiting nil parens-server-reading nil)
    (dolist (pair waiting)
      (if ok (funcall (car pair) value) (funcall (cdr pair) value 502)))))

(defun parens-server-read-feeds ()
  "Read every channel's feed at once; settle the waiting requests when all
have answered, or after `parens-server-deadline' with what has come.
A feed that fails, even at once (no network: url-retrieve signals), counts
as answered, so a reading always ends.  YouTube's feeds fail now and then
(404 or 500 for a feed that is there): a failed feed is asked once more,
and a channel that still fails keeps its videos of the last reading."
  (setq parens-server-reading t)
  (let* ((round (setq parens-server-round (1+ parens-server-round)))
         (left (length parens-server-channels))
         (found nil) (channels nil) (errors nil)
         (finish
          (lambda ()
            ;; Once per reading: the last answer or the deadline, whichever first.
            (when (and parens-server-reading (= round parens-server-round))
              ;; What the channels that failed had the last time.
              (let ((previous (cdr (parens-server-kept))))
                (dolist (video (plist-get previous :videos))
                  (when (assoc (plist-get video :channel-id) errors) (push video found)))
                (dolist (channel (plist-get previous :channels))
                  (when (assoc (plist-get channel :id) errors) (push channel channels))))
              (if (null found)
                  (parens-server--settle nil (format "no feed could be read: %s"
                                                     (or (cdr (car errors)) "no answer in time")))
                (let ((answer (list :videos (sort (copy-sequence found)
                                                  (lambda (a b) (string> (plist-get a :published)
                                                                         (plist-get b :published))))
                                    :channels channels
                                    :errors errors)))
                  (setq parens-server-cache (cons (float-time) answer))
                  (ignore-errors (app-server-write "feed" parens-server-cache))
                  (parens-server--settle t answer))))))
         (done (lambda () (when (zerop (setq left (1- left))) (funcall finish))))
         (read nil))
    (setq read
          (lambda (channel again)
            (let ((failure (lambda (problem)
                             (if again
                                 (funcall read channel nil)
                               (push (cons channel problem) errors)
                               (funcall done)))))
              (condition-case err
                  (app-server-fetch
                   (concat "https://www.youtube.com/feeds/videos.xml?playlist_id=UULF" (substring channel 2))
                   :then (lambda (response)
                           (if (not (plist-get response :ok))
                               (funcall failure (format "HTTP %s" (plist-get response :status)))
                             (condition-case err
                                 (let ((videos (parens-server-entries (plist-get response :text))))
                                   (setq found (append found videos))
                                   (when videos
                                     (push (make-parens-channel :id channel :title (plist-get (car videos) :channel)
                                                                :url (plist-get (car videos) :channel-url))
                                           channels)))
                               (error (push (cons channel (error-message-string err)) errors)))
                             (funcall done)))
                   :catch (lambda (message) (funcall failure (format "fetch failed: %s" message))))
                (error (push (cons channel (error-message-string err)) errors)
                       (funcall done))))))
    (app-server-after parens-server-deadline finish)
    (dolist (channel parens-server-channels)
      (funcall read channel t))))

(defun parens-server-kept ()
  "(TIME . ANSWER), the last good reading: this Emacs's, or a newer one
that was kept (by the job, or by another process)."
  (unless (and parens-server-cache (< (- (float-time) (car parens-server-cache)) parens-server-max-age))
    (let ((kept (app-server-read "feed" nil)))
      (when (and kept (or (null parens-server-cache) (> (car kept) (car parens-server-cache))))
        (setq parens-server-cache kept))))
  parens-server-cache)

(defun parens-server-wait (respond fail)
  "Call RESPOND with the answer of the next reading, or FAIL with why not;
start one unless it is under way."
  (push (cons respond fail) parens-server-waiting)
  (unless parens-server-reading
    (parens-server-read-feeds)))

(defun parens-server-feed ()
  "The answer to /api/feed: at once from what is kept, or later."
  (let ((kept (parens-server-kept)))
    (cond
     ((and kept (< (- (float-time) (car kept)) parens-server-max-age))
      (cdr kept))
     ;; A process for this request only: the job reads the feeds.
     ((bound-and-true-p app-server-single-request)
      (if kept
          (cdr kept)
        (app-server-refuse "The feeds have not been read yet; try again in a few minutes" 503)))
     ;; Stale: read them again; if that fails, the older reading will do.
     (t (app-server-defer
         (lambda (respond fail)
           (parens-server-wait respond
                               (lambda (message &optional status)
                                 (if kept (funcall respond (cdr kept)) (funcall fail message status))))))))))

;; Every 15 minutes, read the feeds and keep them; the job ends with the
;; reading (`:later').
(app-server-defjob 'parens-feeds :every parens-server-max-age :later t
  :function (lambda (done)
              (parens-server-wait (lambda (_answer) (funcall done))
                                  (lambda (message &optional _status) (funcall done message)))))

(provide 'parens-feeds)
;;; _feeds.el ends here
