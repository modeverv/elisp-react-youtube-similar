# nextel: ファイルがページになる elisp-react

[English](nextel.md)

ブランチ `experiment/next-routing` での実験です。elisp-react のアプリケーションを、自前の層（Lisp で約660行と、160行の生成スクリプト）でどこまで Next.js の書き方に近づけられるか、そしてそれがどんな使い心地かを試します。Parens をこれで書き直しました。

| | Next.js | nextel |
|---|---|---|
| ページ | `app/watch/page.js` がコンポーネントを export | `pages/watch.el` に `(nextel-page WatchPage ...)` |
| そのアドレス | ファイルのパス | ファイルのパス: `pages/channel/[id].el` は `/channel/ID` |
| 全ページを囲むもの | `layout.js` | `pages/_layout.el`、`(nextel-layout Layout ...)`。マウントされたまま |
| 見つからないとき | `not-found.js` | `pages/404.el` |
| ページのデータ | サーバーコンポーネントと、その中の `fetch` | ページの `:load`（awaitable）。待つ間は `:loading`、失敗は `:error` |
| タイトルと meta | `generateMetadata` | `:head` |
| リンク | `<Link href>` | `(Link (:href (nextel-href "/watch" :v id)) ...)` |
| API | `app/api/later/route.js` が `GET`、`POST` を export | `api/later.el` に `(nextel-handle "GET" ...)`、`(nextel-handle "POST" ...)` |
| 両側で共有する型 | 共有ファイルの TypeScript の型 | `shared/*.el` の `nextel-defschema`。両側で実行時に検査 |
| ルートの発見 | 開発サーバーが `app/` を監視 | `node tools/nextel.mjs [--watch]` が `nextel/routes.el` と `<script>` タグを書く |

## ページ

```elisp
;;; pages/channel/[id].el --- /channel/ID
(nextel-page ChannelPage
  :load (lambda (route) (parens-load-channel (nextel-param route :id) nil))
  :head (lambda (route data) (list :title (parens-channel-page-title (nextel-param route :id))))
  :loading (lambda (route) (jsx (div (:class "channel") (parens-skeleton-grid 8))))
  :error (lambda (route error retry) (parens-failed (parens-failure-text error) retry))
  :render (lambda (self)
            (jsx (div (:class "channel") (parens-grid (plist-get (nextel-data self) :ids))))))
```

`nextel-page` は `react-define-component` に4つのキーを足したものです。ページは props として `:route`（`:page :pattern :path :params :query`）と `:data` を受け取ります。`:load` の答えはルートごとに保存されます（elisp-react の `react-query`）。戻るとすぐに表示され、`(nextel-reload)` で全ページを読み込み直します。`:load` を待つ間と、失敗のあと読み込み直す間は、ルーターが `:loading` を表示します。

アドレスは既定ではハッシュに入ります（`#/channel/UC...`）。どの静的ホストでも、elisp-studio のプレビューでも動きます。`nextel-url-mode` を `path` にすると `/channel/UC...` になります（そのときリンクは Lisp が辿り、サーバーはどのルートにも `index.html` を返す必要があります）。

`tools/nextel.mjs` は `pages/` を読み、どのパターンがどのページか（`nextel/routes.el`）と、`index.html` の `<!-- nextel:pages -->` と `<!-- /nextel:pages -->` の間の `<script>` タグを書きます。ページはディレクトリを一覧できないので、書き出しが必要です。`--watch` は作業中に書き続け、`--check` は古いときに CI で失敗させます。ページのファイルは自分のコンポーネントに名前を付けます（`(nextel-page WatchPage`）。Next.js のファイルが export するのと同じです。elisp-react は各ファイルを URL から作った名前で読み込むので、ファイルは自分のパスを知ることができません。

## サーバー

```elisp
;;; api/later.el --- GET と POST /api/later
(nextel-handle "GET"
  :returns '(list-of parens-later-entry)
  :handler (lambda (_request) (parens-later)))

(nextel-handle "POST"
  :accepts 'parens-later-entry
  :returns '(list-of parens-later-entry)
  :handler (lambda (request) (parens-later-keep (cons (plist-get request :body) ...))))
```

`server.el` は2行です。`(load ".../nextel/nextel-server.el")` と `(nextel-server-load)`。サーバーはディレクトリを一覧できるので、`api/` には何も書き出しません。各ファイルがルートになります（`_` で始まるファイルとディレクトリは補助）。`:accepts` に合わない body は、どの項目が違うかを添えて断ります（400、`body.id is required`）。`:returns` に合わない答えはサーバーの誤りです（500、ログに出ます）。あとで返す答え（`app-server-defer`）も同じです。同じファイルが、ネイティブの Emacs（`run.sh`）でも elisp-studio のタブの中でも動きます。

## 型

```elisp
;;; shared/parens-types.el --- ページとサーバーの両方が読み込む
(nextel-defschema parens-later-entry
  (id string :required t)
  (title string)
  (saved number))
```

これで `make-parens-later-entry`（検査つき）、`parens-later-entry-p`、`parens-later-entry-title` などが定義されます。レコードは plist なので、印字した Lisp としてそのまま行き来します。ページは同じ型で問い合わせます。

```elisp
(nextel-request "POST" "/api/later" :body entry :sends 'parens-later-entry
                :returns '(list-of parens-later-entry))
```

答えが違えば、その場所を添えてリクエストが失敗します（`POST /api/later[0].id: expected string, got 42`）。Parens はすべての動画とチャンネルを `make-parens-video` と `make-parens-channel` で作ります。Data API、oEmbed、サーバーのフィードのどれから来ても同じです。

## 使ってみて

- **構造は Next.js のように読める。** アドレスごとに1ファイル、それを囲むレイアウト、ページの隣にサーバーのルート。`lisp/` の560行が `pages/` に移り、各ページはそのページだけが使う部品と一緒に1ファイルになりました。
- **型は境界で誤りを捕まえるが、その前では捕まえない。** コンパイラはないので、違う型の項目は値が境界を越えたときに、そのパスつきで見つかります。3つ先の関数で黙って壊れている plist よりはずっとよく、入力中に見つける TypeScript には及びません。未定義の関数や引数の数の誤りは、今もバイトコンパイラの警告が捕まえます（下に1つ例があります）。
- **一番効いたのはページ側のデータの読み込み。** `:load` と `:loading`、`:error` が、2つのページで手書きしていた状態・再試行・古い答えの処理を置き換えました。戻るとデータがすぐに出ます。
- **React のまま残る部分。** 伸びていく一覧のページ（トップ、無限スクロール）と動画のページ（残りを読み込む間もプレーヤーを作り直してはいけない）は、Next.js のクライアントコンポーネントと同じく、ページ自身で読み込みます。
- **Next.js にあってこれにないもの:** ページのサーバー描画（ハッシュはサーバーに届きません。`path` 方式なら elisp-studio の `app-server-page-function` で描けるはずですが、未検証）、コード分割（全ページを最初に読み込む）、入れ子のレイアウト、ミドルウェア、型検査器、リンクからページへ飛ぶエディタの支援。

## 実験で分かったこと

- **ページの Emacs はフックを実行しない。** wasmacs の評価サービスでは `run-hook-with-args` も `run-hooks` もすぐに戻ります。そこでは `Vrun_hooks` が nil です（通常の Emacs はダンプから復元します）。ルーターは自分で関数を呼んでいます。elisp-studio がプレビューで `run-hook-with-args` で呼ぶ `elisp-studio-after-load-functions` も、同じ理由で動いていません。
- **スキーマのアクセサはアプリケーションと同じ名前空間にある。** `parens-channel-title` はチャンネルのページの関数でしたが、`parens-channel` の項目 `title` のアクセサと重なりました。バイトコンパイラが指摘しました（インライン関数を2引数で呼んでいる）。スキーマの名前は、項目が自分の関数とぶつからないように付けます。
- **`next-` は Emacs のもの。** フレームワークの最初の名前は、Emacs 自身の `next-match` とぶつかりました。それで `nextel-` にしました。

## テスト

`test/nextel-test.el`: 型、パターン、ルーター（ページ、`:load`、`:loading`、`:error` と再試行、head、404、フック、`path` 方式とそのリンク）、`nextel-request`、そして elisp-studio の `app-server.el` を使ったサーバー側（ファイルからのルート、`:accepts`、すぐの答えとあとの答えの `:returns`、404、405）。`test/parens-test.el` には Parens のサーバーモード（API を通じた「後で見る」、型の違うフィード）と実際の `api/` を足しました。`test/e2e.mjs` は変更なしで Chrome で通ります。旧 Parens のアドレスが、新しい Parens のファイル名になっています。
