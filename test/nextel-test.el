;;; nextel-test.el --- the framework of nextel/, without Parens  -*- lexical-binding: t; -*-

;; test/run-ert.sh runs this with parens-test.el.  The page side runs on
;; react-testing.el's page; the server side on elisp-studio's app-server.el
;; ($ELISP_STUDIO, or a checkout next to this repository), skipped without it.

(require 'ert)
(require 'cl-lib)
(require 'react-testing)
(require 'nextel)

(defconst nextel-test-root
  (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name))))
  "The repository.")

;;;; Types

(nextel-defschema nextel-test-item
  "An item."
  (id string :required t)
  (count integer)
  (tags (list-of string))
  (kind (member book film))
  (owner nextel-test-person))

(nextel-defschema nextel-test-person
  (name string :required t))

(ert-deftest nextel-schema ()
  (let ((item (make-nextel-test-item :id "a" :count 2 :tags '("x") :kind 'book :owner '(:name "N"))))
    (should (equal (nextel-test-item-count item) 2))
    (should (nextel-test-item-p item))
    (should (equal (nextel-test-person-name (nextel-test-item-owner item)) "N")))
  ;; What is wrong is named, with where it is.
  (let ((wrong (lambda (value) (cadr (should-error (nextel-check 'nextel-test-item value) :type 'nextel-type-error)))))
    (should (equal (funcall wrong '(:count 2)) "nextel-test-item.id is required"))
    (should (equal (funcall wrong '(:id "a" :count "2")) "nextel-test-item.count: expected integer, got \"2\""))
    (should (equal (funcall wrong '(:id "a" :tags ("x" 3))) "nextel-test-item.tags[1]: expected string, got 3"))
    (should (equal (funcall wrong '(:id "a" :kind song)) "nextel-test-item.kind: expected (member book film), got song"))
    (should (equal (funcall wrong '(:id "a" :owner (:nick "n"))) "nextel-test-item.owner: no field :nick in nextel-test-person"))
    (should (equal (funcall wrong "a") "nextel-test-item: expected nextel-test-item, got \"a\"")))
  (should (nextel-type-p '(vector-of (or integer string)) [1 "a"]))
  (should-not (nextel-type-p '(vector-of integer) '(1)))
  (should-error (make-nextel-test-item :count 1) :type 'nextel-type-error))

;;;; Patterns

(ert-deftest nextel-patterns ()
  (should (equal (nextel-pattern-of-file "index.el") "/"))
  (should (equal (nextel-pattern-of-file "channel/[id].el") "/channel/[id]"))
  (should (equal (nextel-pattern-of-file "api/feed/index.el") "/api/feed"))
  (should (eq (nextel-match "/" "/") t))
  (should (eq (nextel-match "/watch" "/watch") t))
  (should (equal (nextel-match "/channel/[id]" "/channel/UC%E3%81%82") '(:id "UCあ")))
  (should-not (nextel-match "/channel/[id]" "/channel"))
  (should-not (nextel-match "/channel/[id]" "/channel/a/b"))
  (should (equal (nextel-match "/docs/[...path]" "/docs/a/b") '(:path ("a" "b"))))
  (should-not (nextel-match "/docs/[...path]" "/docs"))
  (should (equal (sort (list "/[x]" "/docs/[...path]" "/docs/new" "/docs/[id]" "/") #'nextel-pattern<)
                 '("/docs/new" "/docs/[id]" "/docs/[...path]" "/[x]" "/")))
  (should (equal (nextel-fill "/channel/[id]" '(:id "a b")) "/channel/a%20b"))
  (should (equal (nextel-fill "/watch" '(:v "x" :t 30 :empty nil)) "/watch?v=x&t=30"))
  (should (equal (nextel-fill "/docs/[...path]" '(:path ("a" "b"))) "/docs/a/b"))
  (should-error (nextel-fill "/channel/[id]" nil)))

;;;; The router

(defvar nextel-test-log nil)

(defmacro nextel-test-with-app (&rest body)
  "Run BODY with the framework's settings its own, as they were before
an application set them (Parens' are put back afterwards)."
  (declare (indent 0))
  `(let ((nextel-routes nil) (nextel-layout nil) (nextel-not-found nil)
         (nextel-url-mode 'hash) (nextel-base-path "")
         (nextel-title-function (lambda (title) (or title "")))
         (nextel-loading-function (lambda (_route) ""))
         (nextel-page-props-function nil) (nextel-navigate-functions nil)
         (nextel--route nil))
     ,@body))

(nextel-layout NextelTestLayout
  :render (lambda (self)
            (jsx (div (:class "layout")
                   (nav (Link (:href (nextel-href "/") :class "home") "home")
                        (Link (:href (nextel-href "/items/[id]" :id "b") :class "to-b") "b"))
                   (main (react-props self :children))))))

(nextel-page NextelTestHome
  :head (lambda (_route _data) (list :title "Home" :description "The start"))
  :render (lambda (_self) (jsx (p (:class "home-page") "welcome"))))

(nextel-page NextelTestItem
  :load (lambda (route)
          (let ((id (nextel-param route :id)))
            (push id nextel-test-log)
            (lambda (resolve reject)
              (react-set-timeout 10 (lambda ()
                                      (if (equal id "bad")
                                          (funcall reject (list :message "no such item"))
                                        (funcall resolve (list :title (upcase id)))))))))
  :head (lambda (route data) (list :title (plist-get data :title) :meta `(("og:url" . ,(nextel-param route :id)))))
  :loading (lambda (route) (jsx (p (:class "loading") (nextel-param route :id))))
  :render (lambda (self) (jsx (h1 (:class "item") (plist-get (nextel-data self) :title) (nextel-query self "x")))))

(nextel-page NextelTestMissing
  :render (lambda (_self) (jsx (p (:class "missing") "nothing here"))))

(defun nextel-test-app (href &optional mode)
  "Mount the test's application at HREF (inside `nextel-test-with-app')."
  (react-testing-reset)
  (setq nextel-test-log nil
        nextel-url-mode (or mode 'hash)
        nextel-base-path (if (eq mode 'path) "/app" ""))
  (nextel-define-routes '(("/" . NextelTestHome) ("/items/[id]" . NextelTestItem))
                        :layout 'NextelTestLayout :not-found 'NextelTestMissing)
  (react--location-set (nextel-test-location href))
  (react-mount '(nextel-router) "#app")
  (react-testing-flush))

(defun nextel-test-location (href)
  (if (string-prefix-p "#" href)
      (list :href href :pathname "/" :search "" :hash href)
    (let ((question (string-search "?" href)))
      (list :href href :pathname (if question (substring href 0 question) href)
            :search (if question (substring href question) "") :hash ""))))

(defun nextel-test-go (href)
  (react-testing--apply (react--location-changed (nextel-test-location href))))

(defun nextel-test-told (command)
  (mapcar #'cadr (cl-remove-if-not (lambda (told) (equal (car told) command)) react-testing-told)))

(ert-deftest nextel-router-pages ()
  (nextel-test-with-app
        (nextel-test-app "#/")
        (should (equal (react-testing-html) "<div class=\"layout\"><nav><a href=\"#/\" class=\"home\">home</a><a href=\"#/items/b\" class=\"to-b\">b</a></nav><main><p class=\"home-page\">welcome</p></main></div>"))
        (should (equal (car (last (nextel-test-told "title"))) '(:text "Home")))
        (should (equal (car (last (nextel-test-told "meta"))) '(:name "description" :content "The start")))
        ;; A page with :load: :loading, then the page with the data and its head.
        (let ((layout (car (react-testing-find-all :class "layout"))))
          (nextel-test-go "#/items/a?x=!")
          (should (equal (react-testing-text (react-testing-find :class "loading")) "a"))
          (react-testing-time-passes)
          (should (equal (react-testing-text (react-testing-find :class "item")) "A!"))
          (should (equal (car (last (nextel-test-told "title"))) '(:text "A")))
          (should (equal (car (last (nextel-test-told "meta"))) '(:name "og:url" :content "a")))
          ;; The layout stayed: the same node.
          (should (equal (car (react-testing-find-all :class "layout")) layout)))
        ;; Back at a page whose data came before: no loading, no new request.
        (nextel-test-go "#/")
        (nextel-test-go "#/items/a?x=!")
        (should (equal (react-testing-text (react-testing-find :class "item")) "A!"))
        (should (equal nextel-test-log '("a")))
        ;; A failure: the default :error, with a retry that loads again.
        (nextel-test-go "#/items/bad")
        (react-testing-time-passes)
        (should (string-match-p "no such item" (react-testing-html)))
        (react-testing-click (react-testing-find :tag 'button :text "Retry"))
        (should (equal (react-testing-text (react-testing-find :class "loading")) "bad"))
        (should (equal nextel-test-log '("bad" "bad" "a")))
        ;; No page for the address: the 404 page, in the layout.
        (nextel-test-go "#/items")
        (should (react-testing-find :class "missing"))
        (should (react-testing-find :class "layout"))
        ;; The hook ran for every new address.
        (let ((seen nil))
          (add-hook 'nextel-navigate-functions (lambda (route) (push (plist-get route :path) seen)))
          (nextel-test-go "#/items/b")
          (react-testing-time-passes)
          (should (equal seen '("/items/b"))))))

(ert-deftest nextel-router-path-mode ()
  (nextel-test-with-app
        (nextel-test-app "/app/items/c" 'path)
        (react-testing-time-passes)
        (should (equal (react-testing-text (react-testing-find :class "item")) "C"))
        (should (equal (react-testing-attribute (react-testing-find :class "home") "href") "/app/"))
        ;; A link is followed by Lisp, not by the browser (which would load the page).
        (react-testing-click (react-testing-find :class "home"))
        (should (equal (car (last (nextel-test-told "navigate"))) '(:url "/app/" :replace nil)))))

;;;; Writing the routes

(ert-deftest nextel-build-routes ()
  "nextel-build.el writes routes.el and the page's scripts from pages/,
through a buffer that visits a file, and at a save with `nextel-routes-mode'."
  (load (expand-file-name "nextel/nextel-build.el" nextel-test-root) nil t)
  (let* ((root (file-name-as-directory (make-temp-file "nextel-build" t)))
         (file (lambda (name) (expand-file-name name root)))
         (write (lambda (name text)
                  (make-directory (file-name-directory (funcall file name)) t)
                  (with-temp-file (funcall file name) (insert text))))
         (routes (lambda () (nextel--file-text (funcall file "nextel/routes.el")))))
    (funcall write "index.html" "<html>\n  <body>\n    <!-- nextel:framework -->\n    <!-- /nextel:framework -->\n    <script type=\"text/emacs-lisp\" src=\"lisp/app.el\"></script>\n    <!-- nextel:pages -->\n    <!-- /nextel:pages -->\n  </body>\n</html>\n")
    (funcall write "pages/index.el" ";;; -*- lexical-binding: t; -*-\n(nextel-page Home\n  :render (lambda (_self) \"home\"))\n")
    (funcall write "pages/items/[id].el" "(nextel-page\n  ItemPage)")
    (funcall write "pages/_layout.el" "(nextel-layout Frame)")
    (funcall write "pages/404.el" "(nextel-page Missing)")
    (funcall write "pages/_parts/card.el" "(defun card ())")
    (funcall write "pages/.#index.el" "a lock file")
    (funcall write "api/items.el" "")
    (funcall write "api/_db.el" "")
    (funcall write "shared/types.el" "")
    (make-directory (funcall file "nextel") t)
    (should (equal (nextel-write-routes root) '("nextel/routes.el" "index.html")))
    (should (equal (nextel--file-text (funcall file "index.html")) "<html>
  <body>
    <!-- nextel:framework -->
    <script type=\"text/emacs-lisp\" src=\"nextel/nextel-schema.el\"></script>
    <script type=\"text/emacs-lisp\" src=\"nextel/nextel-route.el\"></script>
    <script type=\"text/emacs-lisp\" src=\"nextel/nextel.el\"></script>
    <script type=\"text/emacs-lisp\" src=\"shared/types.el\"></script>
    <!-- /nextel:framework -->
    <script type=\"text/emacs-lisp\" src=\"lisp/app.el\"></script>
    <!-- nextel:pages -->
    <script type=\"text/emacs-lisp\" src=\"pages/_layout.el\"></script>
    <script type=\"text/emacs-lisp\" src=\"pages/_parts/card.el\"></script>
    <script type=\"text/emacs-lisp\" src=\"pages/404.el\"></script>
    <script type=\"text/emacs-lisp\" src=\"pages/index.el\"></script>
    <script type=\"text/emacs-lisp\" src=\"pages/items/[id].el\"></script>
    <script type=\"text/emacs-lisp\" src=\"nextel/routes.el\"></script>
    <!-- /nextel:pages -->
  </body>
</html>
"))
    (should (string-match-p (regexp-quote "(nextel-define-routes
 '((\"/items/[id]\" . ItemPage)
   (\"/\" . Home))
 :layout 'Frame
 :not-found 'Missing)

(nextel-start \"#app\")") (funcall routes)))
    (should (string-match-p ";;   /api/items +api/items.el" (funcall routes)))
    (should-not (string-match-p "_db" (funcall routes)))
    ;; Nothing to write the second time.
    (should (null (nextel-write-routes root)))
    ;; A buffer that visits index.html follows; one with changes that are
    ;; not saved is left alone.
    (let ((buffer (find-file-noselect (funcall file "index.html"))))
      (funcall write "pages/about.el" "(nextel-page About)")
      (nextel-write-routes root)
      (with-current-buffer buffer
        (should (string-match-p "pages/about.el" (buffer-string)))
        (should-not (buffer-modified-p)))
      (funcall write "pages/contact.el" "(nextel-page Contact)")
      (with-current-buffer buffer (goto-char (point-max)) (insert "<!-- mine -->"))
      (should-error (nextel-write-routes root))
      (should-not (string-match-p "contact" (nextel--file-text (funcall file "index.html"))))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer))
    ;; With the mode, a page is written in when it is saved.
    (nextel-routes-mode 1)
    (unwind-protect
        (with-current-buffer (find-file-noselect (funcall file "pages/news.el"))
          (insert "(nextel-page News)")
          (save-buffer)
          (kill-buffer))
      (nextel-routes-mode -1))
    (should (string-match-p "(\"/news\" . News)" (funcall routes)))
    (should (string-match-p "(\"/contact\" . Contact)" (funcall routes)))
    ;; Two files of one address, and a page that names no component.
    (funcall write "pages/news/index.el" "(nextel-page News2)")
    (should (string-match-p "pages/news.el and pages/news/index.el are both /news"
                            (cadr (should-error (nextel-write-routes root)))))
    (delete-file (funcall file "pages/news/index.el"))
    (funcall write "pages/broken.el" "(defun broken ())")
    (should (string-match-p "pages/broken.el has no (nextel-page NAME" (cadr (should-error (nextel-write-routes root)))))))

;;;; Requests

(ert-deftest nextel-request ()
  (react-testing-reset)
  (let (value failure)
    (funcall (nextel-request "POST" "/api/items/[id]" :id "a b" :q "x" :body '(:id "a") :sends 'nextel-test-item
                             :returns 'nextel-test-item)
             (lambda (v) (setq value v)) (lambda (f) (setq failure f)))
    (react-testing-flush)
    (let ((request (react-testing-answer-fetch 200 "(:id \"a\" :count 3)")))
      (should (equal (plist-get request :url) "api/items/a%20b?q=x"))
      (should (equal (plist-get request :method) "POST"))
      (should (equal (plist-get request :body) "(:id \"a\")")))
    (should (equal value '(:id "a" :count 3)))
    ;; An answer of the wrong type fails the request, naming the field.
    (funcall (nextel-request "GET" "/api/items/[id]" :id "a" :returns 'nextel-test-item)
             (lambda (v) (setq value v)) (lambda (f) (setq failure f)))
    (react-testing-flush)
    (react-testing-answer-fetch 200 "(:id \"a\" :count \"3\")")
    (should (equal failure '(:status nil :message "GET /api/items/[id].count: expected integer, got \"3\"")))
    ;; The server's refusal: its status and message.
    (funcall (nextel-request "GET" "/api/items/[id]" :id "a")
             (lambda (v) (setq value v)) (lambda (f) (setq failure f)))
    (react-testing-flush)
    (react-testing-answer-fetch 400 "\"body.id is required\"")
    (should (equal failure '(:status 400 :message "body.id is required")))
    ;; What the page would send wrongly does not leave it.
    (should-error (nextel-request "POST" "/api/items" :body '(:count 1) :sends 'nextel-test-item)
                  :type 'nextel-type-error)))

;;;; The server

(defconst nextel-test-studio
  (expand-file-name "lisp/app-server.el" (or (getenv "ELISP_STUDIO") (expand-file-name "../elisp-studio" nextel-test-root)))
  "elisp-studio's app-server.el, which the server side needs.")

(ert-deftest nextel-server ()
  (skip-unless (file-readable-p nextel-test-studio))
  (load nextel-test-studio nil t)
  (load (expand-file-name "nextel/nextel-server.el" nextel-test-root) nil t)
  (let* ((project (make-temp-file "nextel-test-project" t))
         (app-server-data-directory (expand-file-name ".data/" project)))
    (make-directory (expand-file-name "api/items" project) t)
    (make-directory (expand-file-name "shared" project) t)
    (with-temp-file (expand-file-name "shared/types.el" project)
      (insert ";;; -*- lexical-binding: t; -*-\n(nextel-defschema nextel-test-thing (id string :required t) (n integer))"))
    (with-temp-file (expand-file-name "api/_store.el" project)
      (insert "(defvar nextel-test-things nil)"))
    (with-temp-file (expand-file-name "api/items.el" project)
      (insert "(nextel-handle \"GET\" :returns '(list-of nextel-test-thing) :handler (lambda (_r) nextel-test-things))
(nextel-handle \"POST\" :accepts 'nextel-test-thing :returns '(list-of nextel-test-thing)
  :handler (lambda (r) (push (plist-get r :body) nextel-test-things)))"))
    (with-temp-file (expand-file-name "api/items/[id].el" project)
      (insert "(nextel-handle \"GET\" :returns 'nextel-test-thing
  :handler (lambda (r) (if (equal (plist-get (plist-get r :params) :id) \"broken\") '(:id 1)
                         (or (car nextel-test-things) (app-server-refuse \"none\" 404)))))
(nextel-handle \"PUT\" :returns 'nextel-test-thing
  :handler (lambda (_r) (app-server-defer (lambda (respond _fail) (funcall respond '(:id \"x\" :n \"later\"))))))"))
    (should (equal (mapcar (lambda (route) (list (car route) (cadr route))) (nextel-server-load project))
                   '(("/api/items/[id]" "GET") ("/api/items/[id]" "PUT") ("/api/items" "GET") ("/api/items" "POST"))))
    (let* ((later nil)
           (call (lambda (method path &optional body)
                   (setq later nil)
                   (let ((answer (app-server-respond method path (or body "")
                                                     (lambda (status text _headers) (setq later (list status text))))))
                     (if answer (list (aref answer 0) (aref answer 1)) later)))))
      (should (equal (funcall call "GET" "/api/items") '(200 "nil")))
      (should (equal (funcall call "POST" "/api/items" "(:id \"t\" :n 2)") '(200 "((:id \"t\" :n 2))")))
      (should (equal (funcall call "POST" "/api/items" "(:n 2)") '(400 "\"body.id is required\"")))
      (should (equal (funcall call "POST" "/api/items" "(:id \"t\" :n \"2\")") '(400 "\"body.n: expected integer, got \\\"2\\\"\"")))
      (should (equal (funcall call "GET" "/api/items/t") '(200 "(:id \"t\" :n 2)")))
      ;; An answer of the wrong type is the server's mistake.
      (should (equal (car (funcall call "GET" "/api/items/broken")) 500))
      ;; Also one that comes later.
      (should (equal (car (funcall call "PUT" "/api/items/t")) 500))
      (should (equal (car (funcall call "DELETE" "/api/items")) 405))
      (should (equal (car (funcall call "GET" "/api/other")) 404)))))

(provide 'nextel-test)
;;; nextel-test.el ends here
