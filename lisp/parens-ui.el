;;; parens-ui.el --- cards, avatars, icons, chips  -*- lexical-binding: t; -*-

;; Small pieces that the pages put together.  The cards are `:pure': a grid
;; of 24 renders again only where a video changed.  So they get no lambda
;; as a prop (a new lambda at every render would defeat :pure): what they do
;; on a click is a global function, named by its symbol.

(require 'seq)
(require 'subr-x)

;;;; Pictures

(defun parens-icon (name)
  "The icon NAME (see style.css).  A CSS mask: elisp-react makes every
element with createElement, in the HTML namespace, so inline SVG does not
draw."
  (list 'span (list :class (concat "icon icon-" name) :aria-hidden "true")))

(defun parens-avatar (channel &optional size)
  "The picture of CHANNEL, or its first letter on a colour of its own."
  (let ((title (or (plist-get channel :title) (plist-get channel :channel) "?")))
    (if (plist-get channel :avatar)
        (jsx (img (:class (parens-class "avatar" size) :src (plist-get channel :avatar) :alt ""
                   :loading "lazy" :referrerpolicy "no-referrer")))
      (jsx (span (:class (parens-class "avatar" "letter" size) :aria-hidden "true"
                  :style (list :background-color (format "hsl(%d 45%% 42%%)" (parens-hue title))))
             (parens-initial title))))))

(defun parens-thumbnail (video &optional wide)
  "The picture of VIDEO with its length on it."
  (let ((duration (parens-duration (plist-get video :duration))))
    (jsx (span (:class (parens-class "thumb" (and wide "wide")))
           (img (:src (or (plist-get video :thumbnail) (parens-thumbnail-url (plist-get video :id)))
                 :alt "" :loading "lazy" :width "320" :height "180"))
           (cond ((plist-get video :live) (jsx (span (:class "badge live") (parens-t 'live))))
                 (duration (jsx (span (:class "badge") duration))))))))

(defun parens-meta (video)
  "\"12万 回視聴 • 3 日前\" for VIDEO, or nil when nothing is known."
  (let ((parts (delq nil (list (parens-views (plist-get video :views))
                               (parens-ago (plist-get video :published))))))
    (and parts (string-join parts " • "))))

;;;; Cards

(react-define-component 'VideoCard
  :pure t
  :render
  (lambda (self)
    (let* ((video (react-props self :video))
           (id (plist-get video :id))
           (href (parens-route-url (parens-watch-route id)))
           (channel-href (parens-route-url (or (parens-channel-route (plist-get video :channel-id)) '(:page home))))
           (saved (react-props self :saved))
           (title (plist-get video :title)))
      (jsx (article (:class "card" :data-video id)
             (a (:class "card-thumb" :href href :tabindex "-1" :aria-hidden "true")
               (parens-thumbnail video))
             (div (:class "card-body")
               (a (:class "card-avatar" :href channel-href :tabindex "-1" :aria-hidden "true")
                 (parens-avatar (or (react-props self :channel) video)))
               (div (:class "card-text")
                 (h3 (:class "card-title")
                   (a (:href href :title (or title ""))
                     (or title (jsx (span (:class "skeleton-line") "")))))
                 (a (:class "card-channel" :href channel-href) (or (parens-channel-name video) ""))
                 (div (:class "card-meta") (or (parens-meta video) "")))
               (button (:class (parens-class "icon-button" "card-later" (and saved "saved")) :type "button"
                        :title (parens-t (if saved 'saved-later 'save-later))
                        :aria-label (parens-t (if saved 'saved-later 'save-later))
                        :aria-pressed (if saved "true" "false")
                        :on-click (lambda (_event) (funcall (react-props self :on-later) id)))
                 (parens-icon (if saved "check" "later")))))))))

(react-define-component 'WideCard
  :pure t
  :render
  (lambda (self)
    (let* ((video (react-props self :video))
           (id (plist-get video :id))
           (href (parens-route-url (parens-watch-route id)))
           (description (plist-get video :description))
           (remove (react-props self :on-remove)))
      (jsx (article (:class (parens-class "wide-card" (and (react-props self :compact) "compact")) :data-video id)
             (a (:class "wide-thumb" :href href :tabindex "-1" :aria-hidden "true")
               (parens-thumbnail video t))
             (div (:class "wide-text")
               (h3 (:class "card-title")
                 (a (:href href :title (or (plist-get video :title) ""))
                   (or (plist-get video :title) (jsx (span (:class "skeleton-line") "")))))
               (div (:class "card-meta") (or (parens-meta video) ""))
               (a (:class "card-channel" :href (parens-route-url (or (parens-channel-route (plist-get video :channel-id))
                                                                     '(:page home))))
                 (or (parens-channel-name video) ""))
               (and description (not (react-props self :compact))
                    (jsx (p (:class "wide-description") (truncate-string-to-width description 160 nil nil "…")))))
             (and remove
                  (jsx (button (:class "icon-button wide-remove" :type "button"
                                :title (parens-t 'remove) :aria-label (parens-t 'remove)
                                :on-click (lambda (_event) (funcall (react-props self :on-remove) id)))
                         (parens-icon "close")))))))))

(defun parens-card (id &optional saved-p)
  "A grid card for the video ID."
  (let ((video (parens-video id)))
    (jsx (VideoCard (:key id :video video :channel (parens-channel (plist-get video :channel-id))
                     :lang parens-lang :saved (and saved-p (funcall saved-p id))
                     :on-later #'parens-toggle-later)))))

(defun parens-grid (ids)
  (jsx (div (:class "grid")
         (mapcar (lambda (id) (parens-card id #'parens-later-p)) ids))))

(defun parens-skeleton-grid (count)
  (jsx (div (:class "grid" :aria-busy "true")
         (mapcar (lambda (n)
                   (jsx (div (:key n :class "card skeleton")
                          (div (:class "thumb"))
                          (div (:class "skeleton-line"))
                          (div (:class "skeleton-line short")))))
                 (number-sequence 1 count)))))

(defun parens-wide-list (ids &optional compact on-remove)
  (jsx (div (:class (parens-class "wide-list" (and compact "compact")))
         (mapcar (lambda (id)
                   (jsx (WideCard (:key id :video (parens-video id) :lang parens-lang
                                   :compact compact :on-remove on-remove))))
                 ids))))

;;;; Chips, notes, loading

(defun parens-chips (chips selected on-select)
  "A row of CHIPS ((VALUE . LABEL) ...); ON-SELECT gets the VALUE."
  (jsx (div (:class "chips" :role "tablist")
         (mapcar (lambda (chip)
                   (let ((chosen (equal (car chip) selected)))
                     (jsx (button (:key (format "%s" (car chip)) :type "button" :role "tab"
                                   :class (parens-class "chip" (and chosen "selected"))
                                   :aria-selected (if chosen "true" "false")
                                   :on-click (lambda (_event) (funcall on-select (car chip))))
                            (cdr chip)))))
                 chips))))

(defun parens-note (text &optional class)
  (jsx (p (:class (parens-class "note" class)) text)))

(defun parens-failed (text retry)
  "The message TEXT with a button that calls RETRY."
  (jsx (div (:class "failed" :role "alert")
         (p text)
         (button (:class "button" :type "button" :on-click (lambda (_event) (funcall retry)))
           (parens-t 'retry)))))

(defun parens-sentinel (name count)
  "An element the page's script watches: when it scrolls into view,
Lisp hears {\"type\":\"near-end\",\"name\":NAME}.  elisp-react has no
IntersectionObserver; the key changes with COUNT, so each page of results
gets a new one."
  (jsx (div (:key (format "sentinel-%s-%d" name count) :class "sentinel" :data-sentinel name))))

(provide 'parens-ui)
;;; parens-ui.el ends here
