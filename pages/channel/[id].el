;;; [id].el --- a channel's page, /channel/ID  -*- lexical-binding: t; -*-

;; The first videos come from :load; the page adds more itself.  The
;; header is there while they load, and when they failed.

(defun parens-channel-more (self)
  (let ((channel-id (nextel-param self :id)))
    (parens-list-load self channel-id (lambda (token) (parens-load-channel channel-id token)) t)))

(defun parens-channel-head (channel-id ids)
  "The head of the page of CHANNEL-ID: picture, name, facts, a link."
  (let* ((channel (parens-channel channel-id))
         (title (parens-channel-page-title channel-id ids))
         (facts (delq nil (list (plist-get channel :handle)
                                (and (plist-get channel :subscribers)
                                     (parens-t 'subscribers (parens-short-number (plist-get channel :subscribers))))
                                (and (plist-get channel :video-count)
                                     (parens-t 'videos-count (plist-get channel :video-count)))))))
    (jsx (header (:class "channel-head")
           (parens-avatar (or channel (list :title title)) "large")
           (div
             (h1 (:class "page-title") title)
             (and facts (jsx (p (:class "muted") (string-join facts " • "))))
             (a (:class "text-button" :href (concat "https://www.youtube.com/channel/" channel-id)
                 :target "_blank" :rel "noopener")
               (parens-t 'open-youtube)))))))

(defun parens-channel-page-title (channel-id &optional ids)
  (or (plist-get (parens-channel channel-id) :title)
      (and ids (parens-channel-name (parens-video (car ids))))
      channel-id))

(nextel-page ChannelPage
  :load (lambda (route) (parens-load-channel (nextel-param route :id) nil))
  :head (lambda (route data) (list :title (parens-channel-page-title (nextel-param route :id) (plist-get data :ids))))
  :loading (lambda (route)
             (jsx (div (:class "channel")
                    (parens-channel-head (nextel-param route :id) nil)
                    (parens-skeleton-grid 8))))
  :error (lambda (route error retry)
           (jsx (div (:class "channel")
                  (parens-channel-head (nextel-param route :id) nil)
                  (parens-failed (parens-failure-text error) retry))))
  :initial-state (lambda (props) (parens-list-state (nextel-param (plist-get props :route) :id) (plist-get props :data)))
  :did-mount (lambda (self) (parens-more-function self "channel" (lambda () (parens-channel-more self))))
  :did-update (lambda (self previous-props _previous-state)
                (unless (eq (react-props self :data) (plist-get previous-props :data))
                  (apply #'react-set-state self (parens-list-state (nextel-param self :id) (react-props self :data)))))
  :will-unmount (lambda (_self) (parens-forget-more-function "channel"))
  :render
  (lambda (self)
    (let ((ids (react-state self :ids)))
      (jsx (div (:class "channel")
             (parens-channel-head (nextel-param self :id) ids)
             (if ids (parens-grid ids) (parens-note (parens-t 'no-results)))
             (parens-more-row self "channel" (lambda () (parens-channel-more self))))))))

;;; [id].el ends here
