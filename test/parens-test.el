;;; parens-test.el --- Parens in a native Emacs, without a browser  -*- lexical-binding: t; -*-

;; test/run-ert.sh runs this.  react.el comes from a checkout of
;; elisp-react next to this repository (../elisp-react) or $ELISP_REACT.
;;
;; The application is mounted as in the page; this file plays the page:
;; it answers the port's commands, fires DOM events at elements found by
;; their attributes, and answers fetches with made-up YouTube data (no
;; network; the made-up ids are not real videos).

(require 'ert)
(require 'bytecomp)   ; before let-binding its variables (else: "already lexical")
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defconst parens-test-root
  (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))

(defvar parens-test-build (make-temp-file "parens-test-" t))

(defconst parens-test-files
  '("parens-util" "parens-port" "parens-data" "parens-source" "parens-state" "parens-ui" "parens-pages" "parens-app"))

(defun parens-test-load-library ()
  "Load react.el and the application's files, compiled, as the page does."
  (let ((byte-compile-dest-file-function
         (lambda (file) (expand-file-name (concat (file-name-nondirectory file) "c") parens-test-build))))
    (dolist (name parens-test-files)
      (let ((file (expand-file-name (concat "lisp/" name ".el") parens-test-root)))
        (unless (byte-compile-file file) (error "%s does not compile" file))
        (load (funcall byte-compile-dest-file-function file) nil t)))))

;;;; The page, played by the test

(defvar parens-test-ops nil "Every DOM operation so far, oldest first.")
(defvar parens-test-pending nil "Host calls not answered: ((REQUEST COMMAND ARGUMENT) ...).")
(defvar parens-test-commands nil "Port commands carried out: plists, oldest first.")

(defun parens-test-apply (ops)
  "What the page does with OPS: keep them, carry out port commands."
  (setq ops (append ops nil))
  (setq parens-test-ops (append parens-test-ops ops))
  (dolist (op ops)
    (pcase (append op nil)
      (`("call" ,request ,command ,argument) (setq parens-test-pending (append parens-test-pending (list (list request command argument)))))
      (`("cancel" ,request) (setq parens-test-pending (seq-remove (lambda (call) (eql (car call) request)) parens-test-pending)))))
  (parens-test-run-port))

(defun parens-test-host (predicate)
  "The DOM id of the first mounted element whose props satisfy PREDICATE."
  (let (found)
    (maphash (lambda (id host)
               (when (and (not found) (funcall predicate (react--host-props host) host))
                 (setq found id)))
             react--hosts)
    found))

(defun parens-test-hosts (predicate)
  (let (found)
    (maphash (lambda (id host) (when (funcall predicate (react--host-props host) host) (push id found))) react--hosts)
    (sort found #'<)))

(defun parens-test-event (dom-id name &rest event)
  (parens-test-apply (react-dispatch-event dom-id name event)))

(defun parens-test-message (message)
  "Send MESSAGE (a plist) to Lisp through the port, as index.html does."
  (let ((input (parens-test-host (lambda (props _host) (equal (plist-get props :id) "parens-port-in")))))
    (should input)
    (parens-test-event input "input" :type "input" :value (parens-json message))))

(defvar parens-test-done 0)

(defun parens-test-run-port ()
  "Carry out the port's <data> commands that are new, and acknowledge them."
  (let ((ran nil))
    (dolist (id (parens-test-hosts (lambda (props host) (and (eq (react--host-tag host) 'data) (plist-get props :data-cmd)))))
      (let* ((props (react--host-props (gethash id react--hosts)))
             (seq (plist-get props :data-seq)))
        (when (> seq parens-test-done)
          (setq parens-test-done seq ran t)
          (setq parens-test-commands
                (append parens-test-commands
                        (list (json-parse-string (plist-get props :data-cmd) :object-type 'plist)))))))
    (when ran (parens-test-message (list :type "ack" :seq parens-test-done)))))

(defun parens-test-reply (predicate value &optional ok)
  "Answer the first pending host call whose argument satisfies PREDICATE."
  (let ((call (seq-find (lambda (call) (funcall predicate (nth 1 call) (nth 2 call))) parens-test-pending)))
    (should call)
    (setq parens-test-pending (remq call parens-test-pending))
    (parens-test-apply (react-host-reply (car call) (if (eq ok :failed) nil t) value))))

(defun parens-test-fetch-p (pattern)
  (lambda (command argument) (and (equal command "fetch") (string-match-p pattern (plist-get argument :url)))))

(defun parens-test-respond (pattern status text)
  (parens-test-reply (parens-test-fetch-p pattern) (list :status status :ok (< status 400) :text text)))

(defun parens-test-pending-urls ()
  (delq nil (mapcar (lambda (call) (and (equal (nth 1 call) "fetch") (plist-get (nth 2 call) :url))) parens-test-pending)))

(defun parens-test-html () (react-html "#app"))

(defun parens-test-start (&optional storage)
  "Mount the application afresh with localStorage STORAGE (an alist of key . value)."
  (react-reset)
  (setq parens-test-ops nil parens-test-pending nil parens-test-commands nil parens-test-done 0
        parens-port--outbox nil parens-port--seq 0 parens-port--instance nil parens--sent-title nil
        parens-app nil parens-header nil parens-watch-page nil parens-near-end-function nil
        parens-mode nil parens-api-key nil parens-lang 'ja)
  (parens-forget-everything)
  (react--storage-load (vconcat (mapcar (lambda (entry) (vector (car entry) (prin1-to-string (cdr entry)))) storage)))
  (parens-test-apply (progn (react-mount (jsx (App)) "#app") (react-flush))))

(defun parens-test-hello (&optional url studio)
  (parens-test-message (list :type "hello" :url (or url "#/") :origin "https://example.test"
                             :studio (if studio t :false) :light :false)))

(defun parens-test-oembed (id)
  (json-serialize (list :title (format "Video %s" id) :author_name (format "Channel of %s" id)
                        :author_url "https://www.youtube.com/@example")))

(defun parens-test-answer-oembeds ()
  (dolist (url (parens-test-pending-urls))
    (when (string-match "oembed.*watch%3Fv%3D\\([A-Za-z0-9_-]+\\)" url)
      (parens-test-respond (regexp-quote url) 200 (parens-test-oembed (match-string 1 url))))))

(defun parens-test-api-video (id channel &optional embeddable)
  (list :kind "youtube#video" :id id
        :snippet (list :publishedAt "2026-11-10T09:00:00Z" :channelId channel :title (format "API video %s" id)
                       :description (format "About %s. https://example.com/more 1:05 #lisp" id)
                       :thumbnails (list :medium (list :url (format "https://i.ytimg.com/vi/%s/mqdefault.jpg" id)))
                       :channelTitle (format "API channel %s" channel) :categoryId "28" :liveBroadcastContent "none")
        :contentDetails (list :duration "PT12M3S")
        :statistics (list :viewCount "123456" :likeCount "789" :commentCount "12")
        :status (list :embeddable (if (eq embeddable :no) :false t))))

(defun parens-test-json (object) (parens-json object))

;;;; Words, numbers, dates

(ert-deftest parens-short-numbers ()
  (let ((parens-lang 'ja))
    (should (equal (parens-short-number 999) "999"))
    (should (equal (parens-short-number 12345) "1.2万"))
    (should (equal (parens-short-number 10000) "1万"))
    (should (equal (parens-short-number 123456) "12万"))
    (should (equal (parens-short-number 123456789) "1.2億"))
    (should (equal (parens-views 0) "視聴回数なし")))
  (let ((parens-lang 'en))
    (should (equal (parens-short-number 1534) "1.5K"))
    (should (equal (parens-short-number 1000000) "1M"))
    (should (equal (parens-short-number 25300000000) "25B"))
    (should (equal (parens-views 1200) "1.2K views"))))

(ert-deftest parens-times ()
  (let ((now (encode-time (iso8601-parse "2026-11-15T10:00:00Z"))))
    (let ((parens-lang 'ja))
      (should (equal (parens-ago "2026-11-12T10:00:00Z" now) "3 日前"))
      (should (equal (parens-ago "2026-11-15T09:59:30Z" now) "30 秒前"))
      (should (equal (parens-ago "2026-11-15T10:00:00Z" now) "たった今"))
      (should (equal (parens-ago "2025-11-01T10:00:00Z" now) "1 年前")))
    (let ((parens-lang 'en))
      (should (equal (parens-ago "2026-11-14T10:00:00Z" now) "1 day ago"))
      (should (equal (parens-ago "2026-10-01T10:00:00Z" now) "1 month ago"))
      (should (equal (parens-ago "2026-11-01T10:00:00Z" now) "2 weeks ago"))))
  (should (null (parens-ago "not a date")))
  (should (equal (parens-duration "PT4M13S") "4:13"))
  (should (equal (parens-duration "PT1H2M5S") "1:02:05"))
  (should (equal (parens-duration "PT45S") "0:45"))
  (should (equal (parens-duration "P1DT2H") "26:00:00"))
  (should (null (parens-duration "P0D")))
  (should (null (parens-duration nil))))

(ert-deftest parens-text ()
  (should (equal (parens-class "a" nil "b") "a b"))
  (let ((parts (parens-linkify "see https://example.com/a?b=1. at 1:23, #emacs" #'identity)))
    (should (equal (car parts) "see "))
    (should (equal (nth 1 parts) '(a (:href "https://example.com/a?b=1" :target "_blank" :rel "noopener")
                                    "https://example.com/a?b=1")))
    (should (equal (nth 2 parts) ". at "))
    (should (eq (car (nth 3 parts)) 'button))
    (should (equal (car (last (nth 3 parts))) "1:23"))
    (should (equal (funcall (plist-get (nth 1 (nth 3 parts)) :on-click) nil) 83))
    (should (equal (nth 1 (nth 5 parts)) '(:class "hashtag" :href "#/results?search_query=%23emacs"))))
  ;; Without ON-TIME a timestamp stays text.
  (should (equal (parens-linkify "at 1:23") '("at " "1:23")))
  ;; Nothing but http(s) becomes a link.
  (should (equal (parens-linkify "javascript:alert(1)") '("javascript:alert(1)"))))

(ert-deftest parens-routes ()
  (should (equal (parens-route-parse "#/") '(:page home)))
  (should (equal (parens-route-parse "") '(:page home)))
  (should (equal (parens-route-parse "#/watch?v=8V4ZyEL_i-s") '(:page watch :v "8V4ZyEL_i-s" :t nil)))
  (should (equal (parens-route-parse "#/watch?v=8V4ZyEL_i-s&t=90s") '(:page watch :v "8V4ZyEL_i-s" :t 90)))
  (should (equal (parens-route-parse "#/watch?v=bad\"id") '(:page home)))
  (should (equal (parens-route-parse "#/results?search_query=%E6%95%B0%E5%AD%A6+emacs")
                 '(:page results :q "数学 emacs")))
  (should (equal (parens-route-parse "#/results?search_query=数学%20emacs")
                 '(:page results :q "数学 emacs")))
  (should (equal (parens-route-parse "#/channel/UC0uTPqBCFIpZxlz_Lv1tk_g")
                 '(:page channel :id "UC0uTPqBCFIpZxlz_Lv1tk_g")))
  (should (equal (parens-route-parse "#/channel/../../x") '(:page home)))
  (should (equal (parens-route-parse "#/feed/history") '(:page history)))
  (should (equal (parens-route-parse "#/playlist?list=WL") '(:page later)))
  (dolist (route '((:page home) (:page watch :v "8V4ZyEL_i-s" :t 30) (:page results :q "数学 emacs")
                   (:page channel :id "UC0uTPqBCFIpZxlz_Lv1tk_g") (:page history) (:page later)))
    (should (equal (parens-route-parse (parens-route-url route))
                   (if (eq (plist-get route :page) 'watch) route route)))))

(ert-deftest parens-api-records ()
  (let ((video (parens-video-from-api (parens-test-api-video "abcdefghijk" "UCxxxxxxxxxxxxxxxxxxxxxx"))))
    (should (equal (plist-get video :views) 123456))
    (should (equal (plist-get video :duration) "PT12M3S"))
    (should (eq (plist-get video :embeddable) t)))
  ;; JSON false is nil after parsing, as react-response-json reads it.
  (should (eq (plist-get (parens-video-from-api
                          (json-parse-string (parens-test-json (parens-test-api-video "abcdefghijk" "UC" :no))
                                             :object-type 'plist :null-object nil :false-object nil))
                         :embeddable)
              :false))
  (should (equal (parens-failure-text '(react-async-error (react-async-error (:status 403 :reason "quotaExceeded" :message "x"))))
                 (let ((parens-lang 'ja)) (parens-t 'quota)))))

;;;; The application

(ert-deftest parens-boot-without-key ()
  (parens-test-start)
  ;; Before the page says hello, a skeleton.
  (should (string-match-p "aria-busy" (parens-test-html)))
  (parens-test-hello)
  ;; server.el is asked first; a static site answers 404.
  (should (member "api/feed" (parens-test-pending-urls)))
  (parens-test-respond "\\`api/feed\\'" 404 "<!doctype html>Not found")
  (should (eq parens-mode 'curated))
  (should-not parens-mode-note)
  (should (= (length (seq-filter (lambda (url) (string-match-p "oembed" url)) (parens-test-pending-urls)))
             (length parens-curated-videos)))
  ;; Cards are there at once, with pictures; titles come with oEmbed.
  (should (= (length (parens-test-hosts (lambda (props host) (and (eq (react--host-tag host) 'article)
                                                                  (plist-get props :data-video)))))
             (length parens-curated-videos)))
  (parens-test-answer-oembeds)
  (should (string-match-p "Video 8V4ZyEL_i-s" (parens-test-html)))
  (should (string-match-p "i.ytimg.com/vi/8V4ZyEL_i-s/mqdefault.jpg" (parens-test-html)))
  ;; The title was asked for, and every command was acknowledged.
  (should (seq-find (lambda (command) (equal (plist-get command :cmd) "title")) parens-test-commands))
  (should (null parens-port--outbox))
  ;; A chip: only the space videos.
  (let ((chip (parens-test-host (lambda (props host) (and (eq (react--host-tag host) 'button)
                                                          (equal (plist-get props :role) "tab")
                                                          (equal (react-html-of host) "宇宙"))))))
    (should chip)
    (parens-test-event chip "click" :type "click")
    (should (= (length (parens-test-hosts (lambda (props host) (and (eq (react--host-tag host) 'article)
                                                                    (plist-get props :data-video)))))
               4))))

(defun react-html-of (host)
  "The text of HOST's children."
  (mapconcat (lambda (child) (if (react--text-p child) (react--text-text child) "")) (react--host-children host) ""))

(ert-deftest parens-watch-page ()
  (parens-test-start)
  (parens-test-hello "#/watch?v=JJPokfFxyFo&t=30")
  (parens-test-respond "\\`api/feed\\'" 404 "")
  (parens-test-answer-oembeds)
  (let ((html (parens-test-html)))
    (should (string-match-p "youtube-nocookie.com/embed/JJPokfFxyFo\\?" html))
    (should (string-match-p "start=30" html))
    ;; Emacs 29's url-build-query-string escapes ":" and "/", 30 does not.
    (should (string-match-p "origin=https\\(://\\|%3A%2F%2F\\)example.test" html))
    (should (string-match-p "credentialless" html))
    (should (string-match-p "referrerpolicy=\"strict-origin-when-cross-origin\"" html))
    (should (string-match-p "Video JJPokfFxyFo" html)))
  ;; Related: the same channel first.
  (let ((related (parens-test-hosts (lambda (props host) (and (eq (react--host-tag host) 'article)
                                                              (string-match-p "wide-card" (or (plist-get props :class) "")))))))
    (should (>= (length related) 5))
    (should (equal (plist-get (react--host-props (gethash (car related) react--hosts)) :data-video) "-9rpQA6O3aM")))
  ;; It went into the history (and localStorage).
  (should (equal (plist-get (car (parens-app-state :history)) :id) "JJPokfFxyFo"))
  (should (react-storage-get "parens/history"))
  ;; The player ended: autoplay goes to the next video.
  (parens-test-message (list :type "player" :id "JJPokfFxyFo" :state 0))
  (should (equal (parens-app-state :route) '(:page watch :v "-9rpQA6O3aM" :t nil)))
  (should (equal (plist-get (seq-find (lambda (command) (equal (plist-get command :cmd) "navigate"))
                                     (reverse parens-test-commands))
                           :url)
                 "#/watch?v=-9rpQA6O3aM"))
  ;; A player error is shown.
  (parens-test-message (list :type "player-error" :id "-9rpQA6O3aM" :code 150))
  (should (string-match-p "エラー 150" (parens-test-html))))

(ert-deftest parens-search-and-keys ()
  (parens-test-start)
  (parens-test-hello)
  (parens-test-respond "\\`api/feed\\'" 404 "")
  (parens-test-answer-oembeds)
  (let ((input (parens-test-host (lambda (props _host) (equal (plist-get props :ref) "search"))))
        (form (parens-test-host (lambda (props _host) (equal (plist-get props :role) "search")))))
    (parens-test-event input "input" :type "input" :value "  Video 8V4  ")
    (parens-test-event form "submit" :type "submit")
    (should (equal (parens-app-state :route) '(:page results :q "Video 8V4")))
    (should (string-match-p "data-video=\"8V4ZyEL_i-s\"" (parens-test-html)))
    (should-not (string-match-p "data-video=\"yH0Gan6xMTo\"" (parens-test-html))))
  ;; "/" focuses the search field.
  (let ((before (length parens-test-ops)))
    (parens-test-message (list :type "key" :key "/" :field :false))
    (should (seq-find (lambda (op) (equal (append op nil) (list "invoke" (parens-test-host (lambda (props _host) (equal (plist-get props :ref) "search"))) "focus")))
                      (nthcdr before parens-test-ops))))
  ;; "?" opens the help; Escape closes it.
  (parens-test-message (list :type "key" :key "?" :field :false))
  (should (eq (parens-app-state :dialog) 'shortcuts))
  (parens-test-message (list :type "key" :key "Escape" :field :false))
  (should-not (parens-app-state :dialog)))

(ert-deftest parens-server-mode ()
  (parens-test-start)
  (parens-test-hello)
  (parens-test-respond "\\`api/feed\\'" 200
                       (prin1-to-string
                        (list :videos (list (list :id "aaaaaaaaaaa" :title "From the feed" :channel-id "UC0uTPqBCFIpZxlz_Lv1tk_g"
                                                  :channel "Prot" :views 1234 :published "2026-11-01T00:00:00+00:00"
                                                  :description "Long text" :thumbnail "https://i.ytimg.com/vi/aaaaaaaaaaa/hqdefault.jpg"))
                              :channels (list (list :id "UC0uTPqBCFIpZxlz_Lv1tk_g" :title "Prot")))))
  (should (eq parens-mode 'server))
  (should-not (seq-find (lambda (url) (string-match-p "oembed" url)) (parens-test-pending-urls)))
  (should (string-match-p "From the feed" (parens-test-html)))
  (should (string-match-p "1234 回視聴" (parens-test-html))))

(ert-deftest parens-server-failure-falls-back ()
  (parens-test-start)
  (parens-test-hello)
  ;; In elisp-studio the tab's server cannot read the feeds (CORS): 502.
  (parens-test-respond "\\`api/feed\\'" 502 (prin1-to-string "fetch failed: Failed to fetch"))
  (should (eq parens-mode 'curated))
  (should (string-match-p "Failed to fetch" parens-mode-note)))

(ert-deftest parens-api-mode ()
  (parens-test-start '(("parens/api-key" . "TEST-KEY")))
  (should (eq parens-mode 'api))
  (parens-test-hello)
  ;; The channels of the sidebar, then the chart and the categories.
  (should (seq-find (lambda (url) (string-match-p "googleapis.com/youtube/v3/channels\\?" url)) (parens-test-pending-urls)))
  (let ((chart (seq-find (lambda (url) (string-match-p "chart=mostPopular" url)) (parens-test-pending-urls))))
    (should chart)
    (should (string-match-p "key=TEST-KEY" chart))
    (should (string-match-p "regionCode=JP" chart)))
  (parens-test-respond "chart=mostPopular" 200
                       (parens-test-json (list :items (vector (parens-test-api-video "AAAAAAAAAAA" "UCaaaaaaaaaaaaaaaaaaaaaa")
                                                              (parens-test-api-video "BBBBBBBBBBB" "UCaaaaaaaaaaaaaaaaaaaaaa" :no))
                                               :nextPageToken "PAGE2")))
  ;; The one that cannot be embedded is not shown.
  (should (string-match-p "API video AAAAAAAAAAA" (parens-test-html)))
  (should-not (string-match-p "BBBBBBBBBBB" (parens-test-html)))
  (should (string-match-p "12万 回視聴" (parens-test-html)))
  (should (string-match-p "12:03" (parens-test-html)))
  ;; Quota: a sentence, not JSON.
  (parens-test-respond "videoCategories" 403
                       (parens-test-json '(:error (:code 403 :message "quota" :errors [(:reason "quotaExceeded")]))))
  ;; The sentinel asks for the next page.
  (parens-test-respond "youtube/v3/channels\\?.*UCaaaa" 200 (parens-test-json '(:items [])))
  (parens-test-message (list :type "near-end" :name "home"))
  (should (seq-find (lambda (url) (string-match-p "pageToken=PAGE2" url)) (parens-test-pending-urls))))

(ert-deftest parens-library-and-settings ()
  (parens-test-start)
  (parens-test-hello)
  (parens-test-respond "\\`api/feed\\'" 404 "")
  (parens-test-answer-oembeds)
  (let ((later (parens-test-host (lambda (props _host) (string-match-p "card-later" (or (plist-get props :class) ""))))))
    (parens-test-event later "click" :type "click"))
  (should (= (length (parens-app-state :later)) 1))
  (should (equal (react-storage-get "parens/later") (parens-app-state :later)))
  (should (string-match-p "toast" (parens-test-html)))
  ;; English: every word, including the pure cards (they get :lang).
  (parens-set-setting :lang 'en)
  (parens-test-apply (react-flush))
  (should (string-match-p "Watch later" (parens-test-html)))
  (should-not (string-match-p "後で見る" (parens-test-html)))
  ;; Old entries are dropped when the page starts again.
  (let ((old (list :id "8V4ZyEL_i-s" :title "old" :saved (- (float-time) (* 40 86400)))))
    (parens-test-start (list (cons "parens/later" (list old))))
    (should (null (parens-app-state :later)))))

(provide 'parens-test)
;;; parens-test.el ends here
