;;; parens-util.el --- words, numbers, dates and text for Parens  -*- lexical-binding: t; -*-

;; Pure functions: no components here, so they run (and are tested) in a
;; native Emacs as well as in the page.

(require 'seq)
(require 'subr-x)
(require 'iso8601)
(require 'url-util)

;;;; Words

(defvar parens-lang 'ja
  "The language of the interface, `ja' or `en'.
A global: elisp-react has no context, so components read it while they
render.  Components that skip renders (`:pure') get it as a prop too.")

(defconst parens-words
  '((home "ホーム" "Home")
    (history "履歴" "History")
    (later "後で見る" "Watch later")
    (channels "チャンネル" "Channels")
    (search "検索" "Search")
    (search-placeholder "検索" "Search")
    (settings "設定" "Settings")
    (all "すべて" "All")
    (views "%s 回視聴" "%s views")
    (no-views "視聴回数なし" "No views")
    (subscribers "チャンネル登録者数 %s人" "%s subscribers")
    (videos-count "動画 %s 本" "%s videos")
    (likes "高評価 %s" "%s likes")
    (comments "コメント %s 件" "%s comments")
    (comments-title "コメント" "Comments")
    (comments-off "コメントは表示できません。" "Comments are not available.")
    (comments-need-key "コメントの表示には YouTube Data API のキーが必要です（設定）。"
                       "Comments need a YouTube Data API key (Settings).")
    (more "もっと見る" "Show more")
    (less "一部を表示" "Show less")
    (open-youtube "YouTube で開く" "Open on YouTube")
    (share "共有" "Share")
    (copied "リンクをコピーしました" "Link copied")
    (copy-failed "コピーできませんでした" "Could not copy")
    (save-later "後で見る" "Watch later")
    (saved-later "保存済み" "Saved")
    (autoplay "自動再生" "Autoplay")
    (up-next "次の動画" "Up next")
    (related "関連動画" "Related")
    (loading "読み込み中…" "Loading…")
    (retry "再試行" "Retry")
    (error "読み込めませんでした: %s" "Could not load: %s")
    (no-results "見つかりませんでした。" "Nothing found.")
    (results-for "「%s」の検索結果" "Results for “%s”")
    (results-local "（このサイトの動画一覧から検索）" "(searched in this site's list of videos)")
    (history-empty "まだ何も見ていません。" "Nothing watched yet.")
    (later-empty "「後で見る」に保存した動画はありません。" "No videos saved for later.")
    (clear "すべて削除" "Clear all")
    (remove "削除" "Remove")
    (live "ライブ" "LIVE")
    (upcoming "配信予定" "UPCOMING")
    (menu "メニュー" "Menu")
    (api-key-remember "このブラウザに保存する" "Remember in this browser")
    (cannot-play "この動画はここでは再生できません（エラー %s）。" "This video cannot be played here (error %s).")
    (player-100 "動画が見つかりません。削除されたか非公開です（エラー 100）。"
                "The video is not there: removed or private (error 100).")
    (player-150 "投稿者が他のサイトでの再生を許可していません（エラー %s）。「YouTube で開く」から見られます。"
                "Its owner does not allow playback on other sites (error %s). Open it on YouTube.")
    (player-153 "プレーヤーが参照元（Referer）を受け取れませんでした（エラー 153）。"
                "The player got no Referer from this page (error 153).")
    (not-found "動画が見つかりません（削除されたか、非公開です）。" "Video not found (removed or private).")
    (no-description "説明はありません。" "No description.")
    (description-need-more "説明・再生回数・日付は API キーを設定するか、サーバーモードで表示されます。"
                           "Descriptions, views and dates need an API key or the server mode.")
    (mode-api "API" "API")
    (mode-server "サーバー" "Server")
    (mode-curated "キーなし" "No key")
    (mode-api-long "YouTube Data API（あなたのキー）" "YouTube Data API (your key)")
    (mode-server-long "サーバーの Emacs がフィードを読みます" "The server's Emacs reads the feeds")
    (mode-curated-long "選んだ動画 + oEmbed（キー不要）" "Chosen videos + oEmbed (no key)")
    (api-key "YouTube Data API キー" "YouTube Data API key")
    (api-key-help "保存しなければ、キーはこのタブを閉じるまでしか使われません。保存すると localStorage に残り、同じオリジン（modeverv.github.io）の他のページからも読めます。HTTP リファラーと YouTube Data API v3 に制限したキーを使ってください。"
                  "Unless you remember it, the key is used until this tab closes. Remembered, it stays in localStorage, where every page of the same origin (modeverv.github.io) can read it. Use a key restricted to HTTP referrers and to the YouTube Data API v3.")
    (api-key-save "保存" "Save")
    (api-key-remove "キーを削除" "Remove key")
    (language "言語" "Language")
    (theme "テーマ" "Theme")
    (theme-dark "ダーク" "Dark")
    (theme-light "ライト" "Light")
    (close "閉じる" "Close")
    (shortcuts "キーボードショートカット" "Keyboard shortcuts")
    (shortcut-search "検索欄へ" "Go to search")
    (shortcut-play "再生 / 一時停止" "Play / pause")
    (shortcut-seek "10 秒戻る / 進む" "Back / forward 10 s")
    (shortcut-help "このヘルプ" "This help")
    (shortcut-close "閉じる" "Close")
    (quota "API の割り当て（クォータ）を使い切りました。明日まで待つか、別のキーを設定してください。"
           "The API quota is used up. Wait until tomorrow or set another key.")
    (chart-missing "このカテゴリのランキングはありません。" "There is no chart for this category.")
    (fallback "サーバーからフィードを取得できなかったため、キーなしモードで表示しています: %s"
              "The server could not get the feeds, so this is the no-key mode: %s")
    (about "このサイトについて" "About")
    (about-text "Parens は Emacs Lisp（elisp-react）で書いた動画ブラウザの実験です。動画とデータは YouTube から来ます。YouTube・Google とは関係ありません。"
                "Parens is an experiment: a video browser written in Emacs Lisp (elisp-react). Videos and data come from YouTube. Not affiliated with YouTube or Google.")
    (source "ソース" "Source")
    (terms "YouTube 利用規約" "YouTube Terms of Service")
    (privacy "Google プライバシー ポリシー" "Google Privacy Policy")
    (studio-note "elisp-studio のプレビュー: URL はありません（戻るボタンなし）。" "elisp-studio preview: no URL (no Back button).")
    (just-now "たった今" "just now"))
  "The interface's words: (KEY JAPANESE ENGLISH).")

(defun parens-t (key &rest arguments)
  "The text KEY in `parens-lang', formatted with ARGUMENTS."
  (let* ((entry (alist-get key parens-words))
         (text (if (eq parens-lang 'en) (cadr entry) (car entry))))
    (cond ((null text) (symbol-name key))
          (arguments (apply #'format text arguments))
          (t text))))

;;;; Numbers

(defun parens--short (n units)
  "N with the largest of UNITS ((SIZE . SUFFIX) ...) it reaches."
  (let ((unit (seq-find (lambda (unit) (>= n (car unit))) units)))
    (if (not unit)
        (number-to-string n)
      (let ((value (/ (float n) (car unit))))
        (concat (if (< value 10)
                    ;; One decimal, cut (not rounded) as YouTube does: 1.29万 -> 1.2万.
                    (let ((tenths (floor (* value 10))))
                      (if (zerop (% tenths 10))
                          (number-to-string (/ tenths 10))
                        (format "%d.%d" (/ tenths 10) (% tenths 10))))
                  (number-to-string (floor value)))
                (cdr unit))))))

(defun parens-short-number (n)
  "N in a few characters: 1.2万 / 1.2K.  Nil for nil."
  (cond ((null n) nil)
        ((eq parens-lang 'en)
         (parens--short n '((1000000000 . "B") (1000000 . "M") (1000 . "K"))))
        (t (parens--short n '((100000000 . "億") (10000 . "万"))))))

(defun parens-views (n)
  (cond ((null n) nil)
        ((zerop n) (parens-t 'no-views))
        (t (parens-t 'views (parens-short-number n)))))

(defun parens-number (value)
  "VALUE (a number or a string of digits, as the Data API sends them) as a number."
  (cond ((numberp value) value)
        ((and (stringp value) (string-match-p "\\`[0-9]+\\'" value)) (string-to-number value))))

;;;; Time

(defun parens-time (iso)
  "The time ISO (an ISO 8601 string) as a Lisp time, or nil."
  (and (stringp iso) (ignore-errors (encode-time (iso8601-parse iso)))))

(defun parens-ago (iso &optional now)
  "How long ago ISO was, in words: \"3 日前\", \"3 days ago\".
NOW (a Lisp time) is for tests."
  (let ((time (parens-time iso)))
    (when time
      (let* ((seconds (max 0 (floor (float-time (time-subtract (or now (current-time)) time)))))
             (units '((31536000 "年" "year") (2592000 "か月" "month") (604800 "週間" "week")
                      (86400 "日" "day") (3600 "時間" "hour") (60 "分" "minute") (1 "秒" "second")))
             (unit (seq-find (lambda (unit) (>= seconds (car unit))) units)))
        (if (not unit)
            (parens-t 'just-now)
          (let ((count (/ seconds (car unit))))
            (if (eq parens-lang 'en)
                (format "%d %s%s ago" count (nth 2 unit) (if (= count 1) "" "s"))
              (format "%d %s前" count (nth 1 unit)))))))))

(defun parens-date (iso)
  "The day of ISO: 2026/11/15 or Nov 15, 2026."
  (let ((time (parens-time iso)))
    (and time (format-time-string (if (eq parens-lang 'en) "%b %-d, %Y" "%Y/%m/%d") time))))

(defun parens-duration-seconds (duration)
  "The length of the ISO 8601 DURATION (\"PT4M13S\") in seconds, or nil."
  (let ((parts (and (stringp duration) (ignore-errors (iso8601-parse-duration duration)))))
    (when parts
      (+ (or (nth 0 parts) 0) (* 60 (or (nth 1 parts) 0)) (* 3600 (or (nth 2 parts) 0))
         (* 86400 (or (nth 3 parts) 0))))))

(defun parens-clock (seconds)
  "SECONDS as 4:13 or 1:02:05."
  (if (>= seconds 3600)
      (format "%d:%02d:%02d" (/ seconds 3600) (/ (% seconds 3600) 60) (% seconds 60))
    (format "%d:%02d" (/ seconds 60) (% seconds 60))))

(defun parens-duration (duration)
  "DURATION (ISO 8601) as the badge on a thumbnail, or nil (unknown, or live: P0D)."
  (let ((seconds (parens-duration-seconds duration)))
    (and seconds (> seconds 0) (parens-clock seconds))))

;;;; Text

(defun parens-class (&rest names)
  "A class attribute of the NAMES that are not nil.
elisp-react prints a list as it is, (a b), so classes are joined here."
  (string-join (delq nil names) " "))

(defun parens-decode (text)
  "TEXT with %XX escapes decoded as UTF-8.
Bytes that are not UTF-8 (a link cut in the middle of a character)
become U+FFFD: a raw byte would make `json-serialize' fail later."
  ;; As bytes first: a hash typed by hand may hold raw characters too.
  (let ((decoded (decode-coding-string
                  (url-unhex-string (encode-coding-string (replace-regexp-in-string "\\+" " " text) 'utf-8))
                  'utf-8)))
    (apply #'string (mapcar (lambda (char) (if (>= char #x3fff80) #xfffd char)) decoded))))

(defun parens-json (object)
  "OBJECT as JSON text, as characters.
`json-serialize' gives UTF-8 bytes; the DOM wants characters."
  (let ((json (json-serialize object)))
    (if (multibyte-string-p json) json (decode-coding-string json 'utf-8))))

(defun parens-timestamp-seconds (text)
  "The seconds of a timestamp such as \"1:23\" or \"1:02:03\"."
  (let ((parts (mapcar #'string-to-number (split-string text ":"))))
    (seq-reduce (lambda (total part) (+ (* total 60) part)) parts 0)))

(defconst parens--token-regexp
  ;; A URL is ASCII: Japanese text right after a link is not part of it.
  (concat "\\(?1:https?://[-A-Za-z0-9._~:/?#@!$&'()*+,;=%]*[-A-Za-z0-9_~/#@$&*+=%]\\)"   ; a URL
          "\\|\\(?2:\\b\\(?:[0-9]?[0-9]:\\)?[0-5]?[0-9]:[0-5][0-9]\\b\\)" ; a timestamp
          "\\|\\(?3:#[[:alnum:]_]+\\)")                              ; a hashtag
  "What `parens-linkify' turns into links.")

(defun parens-linkify (text &optional on-time)
  "TEXT as a list of strings and elements: links for URLs and #tags.
Timestamps (1:23) become buttons that call ON-TIME with the seconds, when
ON-TIME is given.  There is no raw HTML in elisp-react, so a description
is taken apart here."
  (let ((start 0) parts)
    (while (string-match parens--token-regexp text start)
      (let ((beginning (match-beginning 0)) (end (match-end 0)))
        (when (> beginning start) (push (substring text start beginning) parts))
        (let ((token (match-string 0 text)))
          (push (cond ((match-beginning 1)
                       (list 'a (list :href token :target "_blank" :rel "noopener") token))
                      ((and (match-beginning 2) on-time)
                       (let ((seconds (parens-timestamp-seconds token)))
                         (list 'button (list :class "timestamp" :type "button"
                                             :on-click (lambda (_event) (funcall on-time seconds)))
                               token)))
                      ((match-beginning 3)
                       (list 'a (list :class "hashtag"
                                      :href (nextel-href "/results" :search_query token))
                             token))
                      (t token))
                parts))
        (setq start end)))
    (when (< start (length text)) (push (substring text start) parts))
    (nreverse parts)))

(defun parens-initial (name)
  "The letter of a channel's avatar when there is no picture."
  (if (and (stringp name) (> (length name) 0)) (upcase (substring name 0 1)) "?"))

(defun parens-hue (text)
  "A colour for TEXT, the same every time (letter avatars)."
  (% (string-to-number (substring (secure-hash 'md5 (or text "")) 0 6) 16) 360))

(provide 'parens-util)
;;; parens-util.el ends here
