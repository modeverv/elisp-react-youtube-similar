;;; server.el --- Parens' server side: the channels' feeds  -*- lexical-binding: t; -*-

;; GET /api/feed  ->  (:videos (VIDEO ...) :channels (CHANNEL ...) :errors ((ID . MESSAGE) ...))
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

(require 'seq)
(require 'subr-x)
(require 'xml)                          ; Lisp; the browser's Emacs has no libxml

(defconst parens-server-channels
  '("UC0uTPqBCFIpZxlz_Lv1tk_g" "UCAiiOTio8Yu69c3XnR7nQBQ" "UC9-y-6csu5WGm29I7JiwpnA"
    "UCnUYZLuoy1rq1aVMwx4aTzw" "UC_x5XG1OV2P6uZZ5FSM9Ttw" "UCYO_jab_esuFRV4b17AJtAw"
    "UCoxcjq-8xIDTYp3uz647V5A" "UCsXVk37bltHxD1rDPwtNM8Q" "UCLA_DiR1FfKNvjuUpBHmylQ")
  "The channels of `parens-curated-channels' (lisp/parens-data.el).
A copy: the studio's server Emacs has server.el only, not the application's files.")

(defconst parens-server-max-age 900 "Seconds a reading of the feeds is used.")

(defvar parens-server-cache nil "(TIME . ANSWER): the last reading that found videos.")
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
          (push (list :id id
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
as answered, so a reading always ends."
  (setq parens-server-reading t)
  (let* ((round (setq parens-server-round (1+ parens-server-round)))
         (left (length parens-server-channels))
         (found nil) (channels nil) (errors nil)
         (finish
          (lambda ()
            ;; Once per reading: the last answer or the deadline, whichever first.
            (when (and parens-server-reading (= round parens-server-round))
              (if (null found)
                  (parens-server--settle nil (format "no feed could be read: %s"
                                                     (or (cdr (car errors)) "no answer in time")))
                (let ((answer (list :videos (sort (copy-sequence found)
                                                  (lambda (a b) (string> (plist-get a :published)
                                                                         (plist-get b :published))))
                                    :channels channels
                                    :errors errors)))
                  (setq parens-server-cache (cons (float-time) answer))
                  (parens-server--settle t answer))))))
         (done (lambda () (when (zerop (setq left (1- left))) (funcall finish)))))
    (app-server-after parens-server-deadline finish)
    (dolist (channel parens-server-channels)
      (condition-case err
          (app-server-fetch
           (concat "https://www.youtube.com/feeds/videos.xml?playlist_id=UULF" (substring channel 2))
           :then (lambda (response)
                   (condition-case err
                       (if (not (plist-get response :ok))
                           (push (cons channel (format "HTTP %s" (plist-get response :status))) errors)
                         (let ((videos (parens-server-entries (plist-get response :text))))
                           (setq found (append found videos))
                           (when videos
                             (push (list :id channel :title (plist-get (car videos) :channel)
                                         :url (plist-get (car videos) :channel-url))
                                   channels))))
                     (error (push (cons channel (error-message-string err)) errors)))
                   (funcall done))
           :catch (lambda (message)
                    (push (cons channel (format "fetch failed: %s" message)) errors)
                    (funcall done)))
        (error (push (cons channel (error-message-string err)) errors)
               (funcall done))))))

(defun parens-server-feed ()
  "The answer to /api/feed: at once from the cache, or later."
  (if (and parens-server-cache (< (- (float-time) (car parens-server-cache)) parens-server-max-age))
      (cdr parens-server-cache)
    (app-server-defer
     (lambda (respond fail)
       (push (cons respond fail) parens-server-waiting)
       (unless parens-server-reading
         (parens-server-read-feeds))))))

(defun app-server-handle (method path _body)
  (pcase (list method path)
    ('("GET" "/api/feed") (parens-server-feed))
    (_ (signal 'file-missing (list "No such API" path)))))

;;; server.el ends here
