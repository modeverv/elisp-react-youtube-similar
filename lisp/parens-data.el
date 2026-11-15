;;; parens-data.el --- the videos the site shows without an API key  -*- lexical-binding: t; -*-

;; Only identifiers are kept here.  Titles and channel names are asked of
;; YouTube (oEmbed) when the page runs; a server Emacs (server.el) reads the
;; channels' feeds for views, dates and descriptions.  Every video below was
;; checked to allow embedding (oEmbed answered 200) on 2026-11-15.

(defconst parens-topics
  '((emacs "Emacs" "Emacs")
    (programming "プログラミング" "Programming")
    (math "数学" "Math")
    (science "科学" "Science")
    (space "宇宙" "Space"))
  "The chips of the home page without an API key: (TOPIC JAPANESE ENGLISH).")

(defconst parens-curated-channels
  '(("UC0uTPqBCFIpZxlz_Lv1tk_g" emacs)          ; Protesilaos
    ("UCAiiOTio8Yu69c3XnR7nQBQ" emacs)          ; System Crafters
    ("UC9-y-6csu5WGm29I7JiwpnA" programming)    ; Computerphile
    ("UCnUYZLuoy1rq1aVMwx4aTzw" programming)    ; Chrome for Developers
    ("UC_x5XG1OV2P6uZZ5FSM9Ttw" programming)    ; Google for Developers
    ("UCYO_jab_esuFRV4b17AJtAw" math)           ; 3Blue1Brown
    ("UCoxcjq-8xIDTYp3uz647V5A" math)           ; Numberphile
    ("UCsXVk37bltHxD1rDPwtNM8Q" science)        ; Kurzgesagt
    ("UCLA_DiR1FfKNvjuUpBHmylQ" space))         ; NASA
  "Channels whose videos the site shows without a key: (CHANNEL-ID TOPIC).
server.el keeps its own copy: the studio's server Emacs cannot read the
application's files.")

(defconst parens-curated-videos
  '(("8V4ZyEL_i-s" "UC0uTPqBCFIpZxlz_Lv1tk_g")
    ("yH0Gan6xMTo" "UC0uTPqBCFIpZxlz_Lv1tk_g")
    ("x3rqjpNm3e0" "UC0uTPqBCFIpZxlz_Lv1tk_g")
    ("Crn6x3RmmyQ" "UC0uTPqBCFIpZxlz_Lv1tk_g")
    ("D99GB591Vgo" "UC0uTPqBCFIpZxlz_Lv1tk_g")
    ("JJPokfFxyFo" "UCAiiOTio8Yu69c3XnR7nQBQ")
    ("-9rpQA6O3aM" "UCAiiOTio8Yu69c3XnR7nQBQ")
    ("SCPoF1PTZpI" "UCAiiOTio8Yu69c3XnR7nQBQ")
    ("pxu7m2oCmyA" "UCAiiOTio8Yu69c3XnR7nQBQ")
    ("K7-wrGpnqUM" "UCAiiOTio8Yu69c3XnR7nQBQ")
    ("XRL3J6rfb3w" "UCAiiOTio8Yu69c3XnR7nQBQ")
    ("BHOw09O3ZsI" "UC9-y-6csu5WGm29I7JiwpnA")
    ("BmBw827GgFA" "UC9-y-6csu5WGm29I7JiwpnA")
    ("h6j_ixGnpiY" "UC9-y-6csu5WGm29I7JiwpnA")
    ("WqrwAFs-fq0" "UC9-y-6csu5WGm29I7JiwpnA")
    ("StAhZk_YVkE" "UCnUYZLuoy1rq1aVMwx4aTzw")
    ("SxHnHFwjpI0" "UCnUYZLuoy1rq1aVMwx4aTzw")
    ("mogYbZ4CFB8" "UCnUYZLuoy1rq1aVMwx4aTzw")
    ("vLAegkGGWrM" "UC_x5XG1OV2P6uZZ5FSM9Ttw")
    ("ID6vEy94j7c" "UC_x5XG1OV2P6uZZ5FSM9Ttw")
    ("LOP8ul3KqQI" "UC_x5XG1OV2P6uZZ5FSM9Ttw")
    ("GlYgs6v2YfU" "UCYO_jab_esuFRV4b17AJtAw")
    ("l6DKRf-fAAM" "UCYO_jab_esuFRV4b17AJtAw")
    ("ldxFjLJ3rVY" "UCYO_jab_esuFRV4b17AJtAw")
    ("fsLh-NYhOoU" "UCYO_jab_esuFRV4b17AJtAw")
    ("LxVW3b8jVdE" "UCoxcjq-8xIDTYp3uz647V5A")
    ("EgnAN0ZUl08" "UCoxcjq-8xIDTYp3uz647V5A")
    ("Uvy5Cs9FDLg" "UCoxcjq-8xIDTYp3uz647V5A")
    ("_y9JuojAIg0" "UCsXVk37bltHxD1rDPwtNM8Q")
    ("QW_jlUn4gA8" "UCsXVk37bltHxD1rDPwtNM8Q")
    ("PXbVn-f_wuM" "UCsXVk37bltHxD1rDPwtNM8Q")
    ("eXrd5sNdacA" "UCLA_DiR1FfKNvjuUpBHmylQ")
    ("Zezt6EsG9WE" "UCLA_DiR1FfKNvjuUpBHmylQ")
    ("5b3n-u_0QAI" "UCLA_DiR1FfKNvjuUpBHmylQ")
    ("ErAqN6gXqZQ" "UCLA_DiR1FfKNvjuUpBHmylQ"))
  "(VIDEO-ID CHANNEL-ID) of the videos shown without a key, in this order.")

(defun parens-topic-of (channel-id)
  "The topic of CHANNEL-ID (a symbol), or nil."
  (cadr (assoc channel-id parens-curated-channels)))

(defun parens-topic-name (topic)
  (let ((entry (alist-get topic parens-topics)))
    (if (eq parens-lang 'en) (cadr entry) (car entry))))

(provide 'parens-data)
;;; parens-data.el ends here
