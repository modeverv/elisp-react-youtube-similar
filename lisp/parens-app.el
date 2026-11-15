;;; parens-app.el --- the application: header, sidebar, pages, messages  -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)

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
             (a (:class "logo" :href "#/" :aria-label "Parens")
               (span (:class "logo-mark" :aria-hidden "true") "(▶)")
               (span (:class "logo-text") "Parens")))
           (form (:class "search" :role "search"
                  :on-submit (lambda (_event)
                               (let ((query (string-trim (react-state self :draft))))
                                 (unless (string-empty-p query)
                                   (parens-go (list :page 'results :q query))
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

(defun parens-nav-item (icon label route selected)
  (jsx (a (:class (parens-class "nav-item" (and selected "selected")) :href (parens-route-url route)
           :aria-current (and selected "page"))
         (parens-icon icon)
         (span (:class "nav-label") (parens-t label)))))

(defun parens-sidebar (route)
  (let ((page (plist-get route :page)))
    (jsx (nav (:class "sidebar" :aria-label "Parens")
           (parens-nav-item "home" 'home '(:page home) (eq page 'home))
           (parens-nav-item "history" 'history '(:page history) (eq page 'history))
           (parens-nav-item "later" 'later '(:page later) (eq page 'later))
           (hr)
           (h2 (:class "sidebar-heading") (parens-t 'channels))
           (mapcar (lambda (entry)
                     (let* ((id (car entry))
                            (channel (parens-channel id)))
                       (jsx (a (:key id :href (parens-route-url (parens-channel-route id))
                                :class (parens-class "nav-item" (and (eq page 'channel) (equal (plist-get route :id) id)
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

;;;; The application

(defvar parens--sent-title nil "The document title last asked for.")

(defun parens--title (route)
  (let* ((name "Parens")
         (part (pcase (plist-get route :page)
                 ('watch (plist-get (parens-video (plist-get route :v)) :title))
                 ('results (plist-get route :q))
                 ('channel (plist-get (parens-channel (plist-get route :id)) :title))
                 ('history (parens-t 'history))
                 ('later (parens-t 'later)))))
    (if part (concat part " - " name) name)))

(defun parens--bump ()
  "Something new is known: render the application again."
  (parens-app-set :version (1+ (or (parens-app-state :version) 0))))

(react-define-component 'App
  :initial-state
  (lambda (_props)
    (let ((settings (parens-settings (react-storage-get "parens/settings"))))
      (setq parens-lang (plist-get settings :lang)
            parens-api-key (react-storage-get "parens/api-key")
            parens-mode (and parens-api-key 'api))
      (list :route nil :settings settings :dialog nil :sidebar nil :toast nil :version 0
            :history (parens-library-load "history") :later (parens-library-load "later"))))
  :did-mount
  (lambda (self)
    (setq parens-app self
          parens-changed-function #'parens--bump)
    (parens-start-source))
  :did-update
  (lambda (_self _previous-props _previous-state)
    (let ((title (parens--title (parens-app-state :route))))
      (unless (equal title parens--sent-title)
        (setq parens--sent-title title)
        (parens-port-send "title" :text title))))
  :will-unmount (lambda (self) (when (eq parens-app self) (setq parens-app nil)))
  :render
  (lambda (self)
    (let* ((route (react-state self :route))
           (page (plist-get route :page))
           (dialog (react-state self :dialog)))
      (jsx (div (:class (parens-class "app" (format "theme-%s" (plist-get (react-state self :settings) :theme))
                                      (format "page-%s" (or page 'none))
                                      (and (react-state self :sidebar) "sidebar-toggled"))
                 :lang (symbol-name parens-lang))
             (Port)
             (Header (:query (and (eq page 'results) (plist-get route :q)) :mode parens-mode :lang parens-lang
                      :sidebar (react-state self :sidebar)))
             (div (:class "layout")
               (parens-sidebar route)
               (main (:class "content" :id "content" :ref "content" :tabindex "-1")
                 (and parens-mode-note (parens-note (parens-mode-note-text) "mode-note"))
                 (pcase page
                   ('nil (parens-skeleton-grid 12))
                   ('watch (jsx (WatchPage (:v (plist-get route :v) :t (plist-get route :t) :mode parens-mode :generation parens-generation))))
                   ('results (jsx (ResultsPage (:q (plist-get route :q) :mode parens-mode :generation parens-generation))))
                   ('channel (jsx (ChannelPage (:id (plist-get route :id) :mode parens-mode :generation parens-generation))))
                   ('history (jsx (LibraryPage (:kind 'history :entries (react-state self :history)))))
                   ('later (jsx (LibraryPage (:kind 'later :entries (react-state self :later)))))
                   (_ (jsx (HomePage (:mode parens-mode :generation parens-generation :lang parens-lang)))))))
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
   (parens-show (or (and parens-studio (react-storage-get "parens/studio-route"))
                    (parens-route-parse (plist-get message :url))))
   ;; Globals changed (there is no context to carry them): render again.
   (parens-changed)))

(parens-port-on "route" (lambda (message) (parens-show (parens-route-parse (plist-get message :url)))))

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
              (equal (plist-get message :id) (react-props parens-watch-page :v))
              (parens-setting :autoplay))
     (let ((next (parens-next-video)))
       (when next (parens-go (parens-watch-route next)))))))

(parens-port-on
 "player-error"
 (lambda (message)
   (when (and parens-watch-page (equal (plist-get message :id) (react-props parens-watch-page :v)))
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

(react-mount (jsx (App)) "#app")

;;; parens-app.el ends here
