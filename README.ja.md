# elisp-react-youtube-similar

**Parens**（パレンズ）: YouTube のトップ画面と動画画面の形をした動画ブラウザです。[elisp-react](https://github.com/modeverv/elisp-react) を使って Emacs Lisp で書き、[elisp-studio](https://github.com/modeverv/elisp-studio) で開発しました。動画とそのデータは YouTube から来ます。

目的は問いに答えることです: **elisp-react と elisp-studio で実際のアプリケーションを開発するには、何が足りないか。** 答えは [doc/findings.ja.md](doc/findings.ja.md)（[English](doc/findings.md)）にあります。

公開版: <https://modeverv.github.io/elisp-react-youtube-similar/>。初回は Emacs（約 5 MB）をダウンロードします。GNU Emacs 30.2 が WebAssembly としてページの中で動き（[wasmacs](https://github.com/modeverv/wasmacs)）、アプリケーションは Emacs Lisp です。

[English](README.md)

> YouTube・Google とは関係ありません。Parens は YouTube の埋め込みプレーヤーと公開されているエンドポイントを使います。[YouTube 利用規約](https://www.youtube.com/t/terms)と [Google プライバシー ポリシー](https://policies.google.com/privacy)をご覧ください。名前・ロゴ・配色は独自のもので、どの動画も YouTube へのリンクを持ちます。

## できること

- トップ画面: サムネイル・長さ・チャンネル・再生回数・日付のある動画の一覧、絞り込みのチップ、スクロールで続きを読み込み。
- 動画画面: プレーヤー、タイトル、チャンネル、「後で見る」、共有（リンクをコピー）、「YouTube で開く」、説明（リンク、プレーヤーを移動するタイムスタンプ、検索になる #タグ）、コメント、次の動画の列（終わると自動再生）。
- 検索、チャンネルごとのページ、履歴と「後で見る」（ブラウザに最長 30 日）、設定（API キー、日本語/英語、ダーク/ライト）、キーボードショートカット（`/` `k` `j` `l` `?` `Esc`）。
- すべてに URL がある（`#/watch?v=…`、`#/results?search_query=…`）: リンクを共有でき、戻るボタンが効きます。

## 動画の出どころ

| モード | いつ | 何があるか |
|---|---|---|
| キーなし（`curated`） | 既定（GitHub Pages など） | 選んだ 35 本（ID は [lisp/parens-data.el](lisp/parens-data.el)）。タイトルとチャンネルは YouTube の oEmbed から。再生回数・日付・説明・コメントはなし。 |
| API（`api`） | 訪問者が設定で YouTube Data API v3 のキーを入れたとき | 日本の人気動画、カテゴリ、検索、説明、チャンネル、コメント。キーはそのブラウザの localStorage にだけ残ります。Google の API は他サイトのページからの呼び出しを許します（CORS）。 |
| サーバー（`server`） | [server.el](server.el) を動かすネイティブ Emacs がページを配信するとき | 選んだチャンネルの最新の通常動画（再生回数・高評価数・日付・説明つき）を RSS フィードから。ページはフィードを読めません（CORS なし）が、サーバーは読めます。 |

API キーは HTTP リファラーと YouTube Data API v3 に制限してください。リポジトリは公開なので、キーをコミットしてはいけません。

## 動かし方

```sh
node tools/serve.mjs          # GitHub Pages と同じ静的な配信: http://localhost:8941/
```

隣に wasmacs のチェックアウト（`../wasmacs/docs`）があればその Emacs を、なければ公開サイトの Emacs を使います。`127.0.0.1` ではなく `localhost` で開いてください。YouTube のプレーヤーは Referer が `http://127.0.0.1:…` のページでは再生しません。

サーバーつき（フィード、キー不要）: 隣の elisp-studio のチェックアウトから

```sh
../elisp-studio/tools/serve-project.sh . 8931     # http://localhost:8931/
```

自分のマシンの elisp-studio で（好きなエディタでファイルを編集すると、ページが追従します）:

```sh
node ../elisp-studio/tools/studio.mjs .           # http://127.0.0.1:5190/elisp-studio/?project=local が開きます
```

プレーヤーを再生したいときは、表示される `127.0.0.1` ではなく `http://localhost:5190/...` で開いてください。

## ファイル

```text
index.html                ページ: Lisp ファイルの読み込み順と「ポート」のスクリプト（下記）
lisp/parens-util.el       言葉（日英）、数（1.2万 / 1.2K）、日付、長さ、テキスト中のリンク
lisp/parens-port.el       ポートの Lisp 側: ページからのメッセージ、ページへのコマンド
lisp/parens-data.el       選んだ動画とチャンネル（ID のみ）
lisp/parens-source.el     3 つの出どころ（oEmbed、Data API、server.el）を 1 つのデータの形に
lisp/parens-state.el      ルート、設定、履歴と「後で見る」: アプリケーションの状態
lisp/parens-ui.el         カード、アバター、アイコン、チップ
lisp/parens-pages.el      トップ、動画、検索結果、チャンネル、ライブラリ、ダイアログ
lisp/parens-app.el        ヘッダー、サイドバー、アプリケーション本体、メッセージの処理
server.el                 サーバー側: /api/feed（elisp-studio のサーバー、ネイティブ Emacs）
style.css                 見た目。アイコンは CSS マスク（elisp-react は SVG を描けない）
test/parens-test.el       アプリケーション全体をネイティブ Emacs で（ブラウザなし、ERT）
test/e2e.mjs              ヘッドレス Chrome でページを。YouTube はフィクスチャが答える
```

### ポート

elisp-react が Lisp に与えるのは DOM とそのイベント、タイマー、fetch、localStorage だけです。Lisp はページの URL を読めず、自分の要素の外で押されたキーや戻るボタンを聞けず、タイトルを変えられず、クリップボードも YouTube のプレーヤーも使えません。`index.html` のスクリプトにはできるので、両者は Lisp が描く要素を通じて話します（[lisp/parens-port.el](lisp/parens-port.el)）:

- ページ → Lisp: 隠れた `<input>`。スクリプトが JSON のメッセージを value に入れて `input` イベントを起こす。
- Lisp → ページ: コマンドごとに 1 つの `<data data-cmd="JSON">` 要素。スクリプトが現れたのを見て（MutationObserver）実行し、受け取りを返す。

スクリプトにアプリケーションの論理はありません。ルートの解析、キーの解釈、プレーヤーの操作は Lisp がします。インラインなのは、elisp-studio のプレビューがプロジェクト自身のスクリプトファイルを読み込めないからです。

## テスト

```sh
npm run test:lisp    # test/run-ert.sh: ネイティブ Emacs でアプリケーション全体（react.el は ../elisp-react か $ELISP_REACT）
npm run test:e2e     # test/e2e.mjs: ヘッドレス Chrome、オフライン（YouTube はフィクスチャ）
```

## ライセンス

MIT（[LICENSE](LICENSE)）。Lisp ファイルは GNU Emacs（GPL-3.0-or-later）の中で動きます。MIT は GPL と両立します。このリポジトリに Emacs は含まれません。ページは wasmacs のサイトから Emacs をダウンロードします（ライセンスとソースは wasmacs の [NOTICE.md](https://github.com/modeverv/wasmacs/blob/master/NOTICE.md)）。`test/lib/cdp.mjs` は elisp-react（MIT、同じ作者）からの複製です。
