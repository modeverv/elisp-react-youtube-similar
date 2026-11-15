;;; 404.el --- the page of an address that no file of pages/ has  -*- lexical-binding: t; -*-

(nextel-page NotFoundPage
  :head (lambda (_route _data) (list :title (parens-t 'not-found)))
  :render (lambda (_self) (parens-not-found)))

;;; 404.el ends here
