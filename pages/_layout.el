;;; _layout.el --- around every page: header, sidebar, dialogs, messages  -*- lexical-binding: t; -*-

;; The layout (elisp-next) stays mounted from one page to the next: it
;; holds what every page needs (the settings, history and "watch later")
;; and gets the page of the address as its :children.  Which page that is
;; comes from the file names of pages/ (elisp-next's nextel-build.el).

(require 'seq)
(require 'subr-x)

;; pages/watch.el, loaded after this file.
(defvar parens-watch-page)
(declare-function parens-next-video "watch")

;;;; Header

(defvar parens-header nil "The mounted `Header' (the search field is its ref \"search\").")

(react-define-component 'Header
  :initial-state (lambda (props) (list :draft (or (plist-get props :query) "")))
  :did-mount (lambda (self) (setq parens-header self))
  :did-update (lambda (self previous-props _previous-state)
                (unless (equal (react-props self :query) (plist-get previous-props :query))
                  (react-set-state self :draft (or (react-props self :query) ""))))
  :will-unmount (lambda (self) (when (eq parens-header self) (setq parens-header nil)))
  :render
  (lambda (self)
    (jsx (header (:class "topbar")
           (div (:class "topbar-start")
             (button (:class "icon-button" :type "button" :aria-label (parens-t 'menu)
                      :aria-expanded (if (react-props self :sidebar) "true" "false")
                      :on-click (lambda (_event) (parens-app-set :sidebar (not (parens-app-state :sidebar)))))
               (parens-icon "menu"))
             (a (:class "logo" :href (nextel-href "/") :aria-label "Parens")
               (span (:class "logo-mark" :aria-hidden "true") "(▶)")
               (span (:class "logo-text") "Parens")))
           (form (:class "search" :role "search"
                  :on-submit (lambda (_event)
                               (let ((query (string-trim (react-state self :draft))))
                                 (unless (string-empty-p query)
                                   (nextel-go "/results" :search_query query)
                                   (react-invoke self "search" "blur")))))
             (input (:ref "search" :type "search" :name "search_query" :autocomplete "off"
                     :value (react-state self :draft)
                     :placeholder (parens-t 'search-placeholder) :aria-label (parens-t 'search)
                     :on-input (lambda (event) (react-set-state self :draft (plist-get event :value)))))
             (button (:class "search-button" :type "submit" :aria-label (parens-t 'search))
               (parens-icon "search")))
           (div (:class "topbar-end")
             (button (:class (parens-class "mode-badge" (format "mode-%s" (or (react-props self :mode) 'loading)))
                      :type "button" :title (parens-mode-name (react-props self :mode) t)
                      :on-click (lambda (_event) (parens-open-dialog 'settings)))
               (parens-mode-name (react-props self :mode)))
             (button (:class "icon-button" :type "button" :aria-label (parens-t 'shortcuts) :title (parens-t 'shortcuts)
                      :on-click (lambda (_event) (parens-open-dialog 'shortcuts)))
               (parens-icon "keyboard"))
             (button (:class "icon-button" :type "button" :aria-label (parens-t 'settings) :title (parens-t 'settings)
                      :on-click (lambda (_event) (parens-open-dialog 'settings)))
               (parens-icon "settings")))))))

;;;; Sidebar

(defun parens-nav-item (icon label href selected)
  (jsx (a (:class (parens-class "nav-item" (and selected "selected")) :href href
           :aria-current (and selected "page"))
         (parens-icon icon)
         (span (:class "nav-label") (parens-t label)))))

(defun parens-sidebar (route)
  (let ((page (parens-page-name route)))
    (jsx (nav (:class "sidebar" :aria-label "Parens")
           (parens-nav-item "home" 'home (nextel-href "/") (eq page 'home))
           (parens-nav-item "history" 'history (nextel-href "/feed/history") (eq page 'history))
           (parens-nav-item "later" 'later (nextel-href "/playlist" :list "WL") (eq page 'later))
           (hr)
           (h2 (:class "sidebar-heading") (parens-t 'channels))
           (mapcar (lambda (entry)
                     (let* ((id (car entry))
                            (channel (parens-channel id)))
                       (jsx (a (:key id :href (parens-channel-href id)
                                :class (parens-class "nav-item" (and (eq page 'channel) (equal (nextel-param route :id) id)
                                                                     "selected")))
                              (parens-avatar (or channel (list :title "…")) "small")
                              (span (:class "nav-label") (or (plist-get channel :title) "…"))))))
                   parens-curated-channels)
           (hr)
           (div (:class "sidebar-footer")
             (p (parens-t 'about-text))
             (p (a (:href "https://www.youtube.com/t/terms" :target "_blank" :rel "noopener") (parens-t 'terms))
                " · "
                (a (:href "https://policies.google.com/privacy" :target "_blank" :rel "noopener") (parens-t 'privacy)))
             (p (a (:href "https://github.com/modeverv/elisp-react-youtube-similar" :target "_blank" :rel "noopener")
                  (parens-t 'source))
                " · "
                (a (:href "https://github.com/modeverv/elisp-react" :target "_blank" :rel "noopener") "elisp-react")))))))

;;;; The layout

(defun parens-page-name (route)
  "The name of ROUTE's page for the stylesheet and the sidebar: home,
watch, results, channel, history, later; nil for none."
  (pcase (plist-get route :pattern)
    ("/" 'home) ("/watch" 'watch) ("/results" 'results) ("/channel/[id]" 'channel)
    ("/feed/history" 'history) ("/playlist" (and (equal (nextel-query route "list") "WL") 'later))))

;; What every page gets as props besides its route: what the whole
;; application knows.  A page loads again when :mode or :generation
;; changed (a key was saved).
(setq nextel-page-props-function
      (lambda (_route) (list :mode parens-mode :generation parens-generation :lang parens-lang)))

;; The title of every page: "PART - Parens", or "Parens".
(setq nextel-title-function (lambda (part) (if part (concat part " - Parens") "Parens")))

;; While a page loads (and has no :loading of its own): cards to come.
(setq nextel-loading-function (lambda (_route) (parens-skeleton-grid 12)))

(nextel-layout Layout
  :initial-state
  (lambda (_props)
    (let ((settings (parens-settings (react-storage-get "parens/settings"))))
      (setq parens-lang (plist-get settings :lang)
            parens-api-key (react-storage-get "parens/api-key")
            parens-mode (and parens-api-key 'api))
      (list :settings settings :dialog nil :sidebar nil :toast nil
            :history (parens-library-load "history") :later (parens-library-load "later"))))
  :did-mount
  (lambda (self)
    (setq parens-app self
          ;; Something new is known: the router renders the page again.
          parens-changed-function #'nextel-refresh)
    (parens-start-source))
  :will-unmount (lambda (self) (when (eq parens-app self) (setq parens-app nil)))
  :render
  (lambda (self)
    (let* ((route (react-props self :route))
           (page (parens-page-name route))
           (dialog (react-state self :dialog)))
      (jsx (div (:class (parens-class "app" (format "theme-%s" (plist-get (react-state self :settings) :theme))
                                      (format "page-%s" (or page 'none))
                                      (and (react-state self :sidebar) "sidebar-toggled"))
                 :lang (symbol-name parens-lang))
             (Port)
             (Header (:query (and (eq page 'results) (nextel-query route "search_query")) :mode parens-mode :lang parens-lang
                      :sidebar (react-state self :sidebar)))
             (div (:class "layout")
               (parens-sidebar route)
               (main (:class "content" :id "content" :ref "content" :tabindex "-1")
                 (and parens-mode-note (parens-note (parens-mode-note-text) "mode-note"))
                 (react-props self :children)))
             ;; The backdrop is beside the dialog, not around it: a click
             ;; inside the dialog would reach a parent's handler too (Lisp
             ;; cannot stop an event, nor tell where it started).
             (and dialog (jsx (div (:class "backdrop" :on-click (lambda (_event) (parens-close-dialog))))))
             (pcase dialog
               ('settings (jsx (SettingsDialog)))
               ('shortcuts (jsx (ShortcutsDialog))))
             ;; The live region is always there: one that appears together
             ;; with its text may not be read out.
             (div (:class (parens-class "toast" (and (react-state self :toast) "shown")) :role "status")
               (or (react-state self :toast) "")))))))

;;;; Messages from the page

(parens-port-on
 "hello"
 (lambda (message)
   ;; The first message: where the page is, and whether it is a preview.
   (setq parens-origin (plist-get message :origin)
         parens-studio (plist-get message :studio)
         parens-isolated (plist-get message :isolated)
         parens-narrow (plist-get message :narrow))
   (when (and (plist-get message :light) (not (react-storage-get "parens/settings")))
     (parens-set-setting :theme 'light))
   ;; Globals changed (there is no context to carry them): render again.
   (parens-changed)))

(parens-port-on "media" (lambda (message) (setq parens-narrow (plist-get message :narrow)) (parens-changed)))

(parens-port-on "near-end"
                (lambda (message)
                  ;; A late message from a list that is gone is not for this page.
                  (when (and parens-near-end-function
                             (equal (plist-get message :name) (car parens-near-end-function)))
                    (funcall (cdr parens-near-end-function)))))

(parens-port-on "copied" (lambda (message) (parens-toast (parens-t (if (plist-get message :ok) 'copied 'copy-failed)))))

(parens-port-on
 "player"
 (lambda (message)
   ;; 0 is "ended": play what is next, as YouTube does.
   (when (and (eql (plist-get message :state) 0)
              parens-watch-page
              (equal (plist-get message :id) (nextel-query parens-watch-page "v"))
              (parens-setting :autoplay))
     (let ((next (parens-next-video)))
       (when next (nextel-navigate (parens-watch-href next)))))))

(parens-port-on
 "player-error"
 (lambda (message)
   (when (and parens-watch-page (equal (plist-get message :id) (nextel-query parens-watch-page "v")))
     (react-set-state parens-watch-page :player-error (plist-get message :code)))))

(parens-port-on
 "key"
 (lambda (message)
   (pcase (plist-get message :key)
     ("/" (when parens-header (react-focus parens-header "search")))
     ("?" (parens-open-dialog 'shortcuts))
     ("Escape" (cond ((parens-app-state :dialog) (parens-close-dialog))
                     ((and (plist-get message :field) parens-header) (react-invoke parens-header "search" "blur"))))
     ;; The player's keys, unless a dialog is open.
     ("k" (when (and parens-watch-page (not (parens-app-state :dialog)))
            (parens-port-send "player" :func "toggle")))
     ("j" (when (and parens-watch-page (not (parens-app-state :dialog)))
            (parens-port-send "player" :func "seekBy" :args [-10])))
     ("l" (when (and parens-watch-page (not (parens-app-state :dialog)))
            (parens-port-send "player" :func "seekBy" :args [10]))))))

;;; _layout.el ends here
