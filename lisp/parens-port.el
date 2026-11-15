;;; parens-port.el --- a channel between Lisp and the page's JavaScript  -*- lexical-binding: t; -*-

;; elisp-react gives Lisp the DOM, events, timers, fetch and localStorage,
;; and nothing else: Lisp cannot read the address of the page, hear the
;; window (keys, hashchange, scrolling), set the document's title, use the
;; clipboard or talk to a YouTube player.  The JavaScript in index.html can.
;; This file is Lisp's side of the channel between the two; it uses only
;; what elisp-react has:
;;
;; - The page talks to Lisp through a hidden input that the `Port'
;;   component renders: the script puts a message (JSON) into its value and
;;   fires an "input" event, which reaches `parens-port--receive'.
;; - Lisp talks to the page by rendering one <data> element per command
;;   (JSON in data-cmd).  The script sees it appear, carries it out, and
;;   answers {"type":"ack","seq":N}; the element then goes away.

(require 'seq)

(defvar parens-port--outbox nil
  "Commands the page has not acknowledged: ((SEQ . PLIST) ...), oldest first.")
(defvar parens-port--seq 0 "The number of the last command.")
(defvar parens-port--instance nil "The mounted `Port'.")
(defvar parens-origin nil
  "The page's origin, from the page's script (Lisp cannot read `location').
The player wants it (origin=) to talk to the page.")
(defvar parens-studio nil
  "Non-nil in elisp-studio's preview: a srcdoc frame, without an address.")

(defvar parens-port-listeners nil
  "What to do with a message from the page: an alist (TYPE . FUNCTION).
TYPE is the message's \"type\" (a string); FUNCTION gets the message, a plist.")

(defun parens-port-on (type function)
  "Call FUNCTION with each message of TYPE (a string) from the page."
  (setf (alist-get type parens-port-listeners nil nil #'equal) function))

(defun parens-port-send (command &rest arguments)
  "Ask the page to carry out COMMAND (a string) with ARGUMENTS (a plist).
The commands are in index.html: navigate, back, title, scroll-top, copy,
player.  Values must be JSON: strings, numbers, t, :false, vectors."
  (setq parens-port--seq (1+ parens-port--seq))
  (setq parens-port--outbox
        (append parens-port--outbox
                (list (cons parens-port--seq (append (list :cmd command) arguments)))))
  (when parens-port--instance
    (react-set-state parens-port--instance :seq parens-port--seq))
  nil)

(defun parens-port--receive (text)
  "A message TEXT (JSON) from the page."
  (let* ((message (ignore-errors
                    (json-parse-string text :object-type 'plist :null-object nil :false-object nil)))
         (type (plist-get message :type)))
    (cond ((null message) (message "parens-port: not JSON: %S" text))
          ((equal type "ack")
           (let ((seq (plist-get message :seq)))
             (setq parens-port--outbox (seq-remove (lambda (item) (<= (car item) seq)) parens-port--outbox))
             (when parens-port--instance
               (react-set-state parens-port--instance :acked seq))))
          (t (let ((listener (alist-get type parens-port-listeners nil nil #'equal)))
               (if listener
                   (funcall listener message)
                 (message "parens-port: nobody listens to %s" type)))))))

(react-define-component 'Port
  :initial-state (lambda (_props) (list :seq 0 :acked 0))
  :did-mount (lambda (self) (setq parens-port--instance self))
  :will-unmount (lambda (self) (when (eq parens-port--instance self) (setq parens-port--instance nil)))
  :render
  (lambda (_self)
    (jsx (div (:id "parens-port" :hidden t)
           (input (:id "parens-port-in" :type "hidden"
                   :on-input (lambda (event) (parens-port--receive (plist-get event :value)))))
           (mapcar (lambda (item)
                     (jsx (data (:key (car item) :data-seq (car item) :data-cmd (parens-json (cdr item))))))
                   parens-port--outbox)))))

(provide 'parens-port)
;;; parens-port.el ends here
