;;; parens-types.el --- what the page and server.el send each other  -*- lexical-binding: t; -*-

;; The page loads this file (index.html) and so does the server
;; (nextel/nextel-server.el loads shared/): a record is checked against the
;; same definition when the server answers and when the page reads the
;; answer, and when the page sends one and the server reads it.  See
;; nextel/nextel-schema.el for the types.

(require 'nextel-schema)

(nextel-defschema parens-video
  "A video, whichever source described it: the Data API, a channel's feed
\(server.el), YouTube's oEmbed.  Every field but the id may be unknown."
  (id string :required t)
  (title string)
  (channel-id string)
  (channel string)
  (channel-url string)
  (published string)                    ; ISO 8601
  (views number)
  (likes number)
  (comment-count number)
  (duration string)                     ; ISO 8601 (PT4M13S)
  (description string)
  (thumbnail string)
  (category string)
  (live (member live upcoming))
  (embeddable (member t :false))        ; :false: YouTube does not allow embedding
  (complete boolean))                   ; everything the Data API knows is here

(nextel-defschema parens-channel
  "A channel."
  (id string :required t)
  (title string)
  (handle string)
  (url string)
  (avatar string)
  (subscribers number)
  (video-count number)
  (description string)
  (uploads string))                     ; the playlist of its uploads

(nextel-defschema parens-feed
  "What GET /api/feed answers: the latest uploads of the chosen channels,
newest first, the channels, and the feeds that could not be read."
  (videos (list-of parens-video))
  (channels (list-of parens-channel))
  (errors (list-of any)))               ; ((CHANNEL-ID . MESSAGE) ...)

(nextel-defschema parens-later-entry
  "A video in \"watch later\" or the history: enough for a card."
  (id string :required t)
  (title string)
  (channel string)
  (channel-id string)
  (thumbnail string)
  (duration string)
  (saved number))                       ; when, `float-time'

(provide 'parens-types)
;;; parens-types.el ends here
