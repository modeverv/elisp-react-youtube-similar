# Parens と elisp-next

[English](elisp-next.md)

Parens は [elisp-next](https://github.com/modeverv/elisp-next) で書かれています。elisp-react のための「ファイルがページになる」層で、React と Next.js の中間に当たります。elisp-next はここで、ブランチ `experiment/next-routing` の実験（elisp-react のアプリケーションをどこまで Next.js の書き方に近づけられるか、それはどんな使い心地か）として書かれ、そのあと切り出されました。リファレンスは elisp-next の README にあります。このページには、Parens での使い方と、実験で分かったことを書きます。

## どこにあるか

```text
vendor/elisp-next/        リリースのコピー（VERSION）。別のものは tools/update-elisp-next.sh で入れる
index.html                <!-- nextel:framework --> と <!-- nextel:pages -->: elisp-next が書くスクリプト
routes.el                 どのページがどのアドレスか。pages/ から書き出す
pages/_layout.el          全ページを囲む: ヘッダー、サイドバー、ダイアログ
pages/index.el            /                    pages/watch.el      /watch?v=ID&t=S
pages/results.el          /results?search_query=TEXT（:load を使う）
pages/channel/[id].el     /channel/ID（:load を使う）
pages/feed/history.el     /feed/history        pages/playlist.el   /playlist?list=WL
pages/404.el              どのファイルにもないアドレス
api/feed.el               GET /api/feed: チャンネルの最新の動画（api/_feeds.el）
api/later.el              GET、POST /api/later。api/later/[id].el は DELETE。「後で見る」をサーバーが持つ
shared/parens-types.el    parens-video、parens-channel、parens-feed、parens-later-entry
server.el                 2行: elisp-next の nextel-server.el が api/ で答える
```

アドレスは elisp-next 以前の Parens と同じです（`#/watch?v=ID`、`#/channel/ID`）。それが保たれるようにファイル名を選んだので、リンクはそのまま使え、`test/e2e.mjs` は変更なしで通りました。ページを足す・消す・名前を変えたあとは、Emacs で `M-x nextel-write-routes`（先に `M-x load-file RET vendor/elisp-next/lisp/nextel-build.el`。elisp-studio のものも同じ）、保存のたびに書くなら `M-x nextel-routes-mode`、または `npm run routes` です。

## 使ってみて

- **構造は Next.js のように読める。** アドレスごとに1ファイル、それを囲むレイアウト、ページの隣にサーバーのルート。`lisp/` の560行が `pages/` に移り、各ページはそのページだけが使う部品と一緒に1ファイルになりました。
- **型は境界で誤りを捕まえるが、その前では捕まえない。** コンパイラはないので、違う型の項目は値が境界を越えたときに、そのパスつきで見つかります。3つ先の関数で黙って壊れている plist よりはずっとよく、入力中に見つける TypeScript には及びません。未定義の関数や引数の数の誤りは、今もバイトコンパイラの警告が捕まえます（下に1つ例があります）。
- **一番効いたのはページ側のデータの読み込み。** `:load` と `:loading`、`:error` が、2つのページで手書きしていた状態・再試行・古い答えの処理を置き換えました。戻るとデータがすぐに出ます。
- **React のまま残る部分。** 伸びていく一覧のページ（トップ、無限スクロール）と動画のページ（残りを読み込む間もプレーヤーを作り直してはいけない）は、Next.js のクライアントコンポーネントと同じく、ページ自身で読み込みます。
- **Next.js にあってこれにないもの:** ページのサーバー描画（ハッシュはサーバーに届きません。`path` 方式なら elisp-studio の `app-server-page-function` で描けるはずですが、未検証）、コード分割（全ページを最初に読み込む）、入れ子のレイアウト、ミドルウェア、型検査器、リンクからページへ飛ぶエディタの支援。

## 実験で分かったこと

- **ページの Emacs はフックを実行していなかった。** wasmacs の評価サービスは Emacs を `kill-emacs` まで走らせて起動しており、その `shut_down_emacs` が `Vrun_hooks` を nil にしていました。そのため `run-hook-with-args` も `run-hooks` もすぐに戻り、elisp-react のすべてのページと elisp-studio のプレビューで動いていませんでした（`elisp-studio-after-load-functions` も呼ばれていませんでした）。2026-11-16 に wasmacs で直しました（[wasmacs#21](https://github.com/modeverv/wasmacs/issues/21)）。ルーターはどちらでも自分で関数を呼びます。
- **スキーマのアクセサはアプリケーションと同じ名前空間にある。** `parens-channel-title` はチャンネルのページの関数でしたが、`parens-channel` の項目 `title` のアクセサと重なりました。バイトコンパイラが指摘しました（インライン関数を2引数で呼んでいる）。スキーマの名前は、項目が自分の関数とぶつからないように付けます。
- **`next-` は Emacs のもの。** フレームワークの最初の名前は、Emacs 自身の `next-match` とぶつかりました。それで `nextel-` にしました。

## テスト

`test/parens-test.el` は、elisp-next を使ったアプリケーションをネイティブの Emacs で動かします（ページ、API を通じた「後で見る」を使うサーバーモード、型の違うフィード、elisp-studio の `app-server.el` の上の実際の `api/`）。`test/e2e.mjs` は Chrome で動かします。elisp-next 自身のテストは、そのリポジトリにあります。
