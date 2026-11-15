# 調べたこと: elisp-react と elisp-studio で実際のアプリを作るには何が足りないか

[English](findings.md)

Parens は一つの問いに答えるために作りました。[elisp-react](https://github.com/modeverv/elisp-react) で実際のアプリケーションを作り、[elisp-studio](https://github.com/modeverv/elisp-studio) で開発すると、何が足りないか。このページがその答えです。見つかった不足にはすべて、それを直すリポジトリに issue があり、根拠と直し方の案を書いてあります。

## 短い答え

アプリが作れなくなる不足はありませんでした。Parens の機能（ホームの一覧、YouTube のプレーヤーを使う動画ページ、検索、チャンネル、履歴、設定、二つの言語、三つのデータ源、Lisp のサーバー）は、どれも今のままのスタックで、Emacs Lisp 約 2,000 行で作れました。blocker（それが無いと普通の機能が作れない）に当たる不足は一つもありません。

ただし不足は 57 件見つかり、そのうち 20 件は **major** です。どんな実際のアプリでも出会い、回避に大きなコードが要るか、不具合や安全上の危険を伴うものです。major は五つにまとまります。

1. **Lisp からページに手が届かない。** アドレスを読むことも変えることもできず（[R02](https://github.com/modeverv/elisp-react/issues/14)）、ページの JavaScript を呼べず（[R01](https://github.com/modeverv/elisp-react/issues/13)）、イベントの既定動作を止められず（[R04](https://github.com/modeverv/elisp-react/issues/16)）、修飾キーや座標が分からず（[R05](https://github.com/modeverv/elisp-react/issues/17)）、応答のヘッダーやバイナリの本文を受け取れず（[N02](https://github.com/modeverv/elisp-react/issues/8)）、接続を張りっぱなしにできません（[N03](https://github.com/modeverv/elisp-react/issues/9)）。Parens はこのために「port」を書きました。Lisp 約 90 行と、インラインの JavaScript 約 165 行です。
2. **状態と非同期の処理。** context や store がありません（[R07](https://github.com/modeverv/elisp-react/issues/19)）。描画エラーが一つ起きると、更新されなくなる部品が残ります（[R09](https://github.com/modeverv/elisp-react/issues/21)）。`react-async` には取り消したり組み合わせたりできるタスクが無く、すぐ答えが返る await を重ねるとスタックが伸びます（[R10](https://github.com/modeverv/elisp-react/issues/22)）。
3. **公開と運用。** 再訪問した人が、古い react.el に合わせてコンパイルされたコードで動くことがあります（[R19](https://github.com/modeverv/elisp-react/issues/31)）。初回の訪問ではアプリ全体を訪問者の CPU でコンパイルします（[R20](https://github.com/modeverv/elisp-react/issues/32)）。同じオリジンのアプリはすべて保存データを共有し、同じオリジンの別のページがキャッシュされたコードを仕込めます（[R23](https://github.com/modeverv/elisp-react/issues/35)）。版を固定した配布がありません（[X01](https://github.com/modeverv/elisp-react/issues/43)）。タブごとに Emacs 用の線形メモリを 1GiB 確保し、実機のスマートフォンでは試されていません（[X05](https://github.com/modeverv/wasmacs/issues/12)）。
4. **studio での開発の流れ。** プレビューにアドレスが無く（[S01](https://github.com/modeverv/elisp-studio/issues/1)）、プロジェクト自身のファイルを取得できません（[S02](https://github.com/modeverv/elisp-studio/issues/2)）。複数ファイルの変更は最初のエラーで止まり、残りは黙って捨てられます（[S04](https://github.com/modeverv/elisp-studio/issues/4)）。エラーに場所が無く、描画に失敗した変更は新しいコードが入っているのに「適用されなかった」と報告されます（[S07](https://github.com/modeverv/elisp-studio/issues/7)）。studio の中の `server.el` は、アプリのコードを共有できず、CORS の無いサイトにも届きません（[S12](https://github.com/modeverv/elisp-studio/issues/11)）。
5. **テスト。** アプリ用のテストキットがありません（[R26](https://github.com/modeverv/elisp-react/issues/38)）。Parens は偽のページを自分で作りました。

## この一覧の作り方

1. Parens を作り（2026-11-15）、回避策が必要になるたびに書き留めました。
2. 四つのレビューが、四つの面からスタックを見ました。部品の API、studio での開発の流れ、実行と公開、製品として要るものの点検表です。その候補を 51 件にまとめました。
3. 各項目を、否定できないか試す形で確かめ直しました。対象は elisp-react `51f954a`、elisp-studio `c3aee20`、wasmacs `5e676c1`（Parens `c88aa04`）です。主張はコードで読み直し、決め手になる一番安い試験を native Emacs 30.2 と 31.1、headless Chrome 157 で再実行しました。さらにもう一つのレビューが、一覧から漏れているもの（N01〜N06）と、すでにうまくいっていることを探しました。

判定: **確認**（報告どおり）、**一部**（最初の報告が言い過ぎで、issue に成り立つ部分を書いてある）、**否定**（その機能はある）。
重大さ（Parens のようなアプリを作って公開するうえでの）: **major**（どんな実際のアプリでも出会い、回避に大きなコードが要るか、不具合や安全上の危険を伴う）、**minor**（回避が小さいか、まれな場合）、**polish**（見た目や使い勝手）。**blocker** は普通の機能がまったく作れないことを意味しますが、該当はありませんでした。

| | 確認 | 一部 | 否定 | major | minor | polish |
|---|---|---|---|---|---|---|
| 57 件 | 37 | 19 | 1 | 20 | 35 | 2 |

試験は一台の Mac で行い、公開していません。ブラウザについての主張は Chrome でだけ確かめました。

## すでにうまくいっていること

公平に答えるには、うまくいっている点も言う必要があります。どれもコードで確かめるか、測りました。

- **UI のコードが短い。** 部品 15 個と `jsx` の式 64 個で画面全体ができています。動画のカード一つは 28 行です。補助は普通の関数です。
- **描画が軽い。** key 付きの差分計算は動かす必要のあるものだけを動かし、`:pure` は変わらない子を飛ばします。カード 35 枚の上でルートを描き直すと 1.4 ms、DOM 操作は 1 回でした。key 付きの 5,000 行の一覧も 38 ms で描き直せます。
- **入力が追いつく。** 一打鍵の Lisp の時間は 0.3〜1.4 ms で、人の打つ速さではキーを一つも落としませんでした。
- **Lisp がページを止めない。** Emacs は worker で動きます。Lisp が 2 秒計算している間も、ページは 20 ms ごとに描画を続けました。
- **ホットリロードで状態が残る。** 部品を直すと約 0.9 秒で反映され、その状態、ルート、再生中の YouTube のプレーヤーまで残りました。
- **アプリ全体を native Emacs でテストできる。** 12 個のテストがアプリをマウントし、ページの役をして動かします。1.5 秒で終わり、Emacs 29・30・31 で同じ結果になり、CI が push のたびに実行します。描画は「データを入れて操作の列を出す」ものなので、偽のページは小さなリスト処理で済みます。
- **出力は普通の DOM。** CSS、ARIA、DevTools、CDP によるブラウザテスト（22 項目を 8.5 秒）が、どのページとも同じように使えます。
- **Lisp は文字列処理が得意。** 説明文のリンク、プレーヤーを動かすタイムスタンプ、`#tag` を約 30 行で作れます。結果は要素のデータなので、何かを注入される余地がありません。
- **同じ Lisp がサーバーでも動く。** `server.el` は 9 本の RSS を xml.el で並行に読みます。ページは答えを `read-from-string` で読み、JSON との変換を挟みません。
- **二回目からの起動が速い。** コンパイル結果をキャッシュします。速い機械では初回のコンパイルが 463 ms、次回の読み込みが 44 ms でした。負荷のかかった機械では 11.8 秒と 1.2 秒です。
- **Emacs のダウンロードは一度だけ。** 初回に約 5 MB、その後は必要なファイルだけを取ります。キャッシュからの起動は 150〜175 ms です。
- **信頼できないデータも安全に描ける。** ホストは HTML を解析せず、実行可能な属性や `javascript:` の URL を拒否します。
- **不足は Lisp 数行で埋められる。** `Promise.all` は 17 行、await できる `async` もさらに 17 行でした。その代償は下の各 issue に書いてあります。
- **長く開いていても漏れない。** ページ間を 15 往復しても、DOM ノードと部品の記録の数は増えませんでした。
- **ビルドの段階が無い。** 公開は静的ファイルを置くだけです。

## 見つかった不足のすべて

### elisp-react: ページに手を届かせる

| ID | 不足 | 重大さ | 判定 | Issue |
|---|---|---|---|---|
| R01 | ホストを拡張する手段、ページの JavaScript と Lisp が話す公式の手段が無い | **major** | 一部 | [elisp-react#13](https://github.com/modeverv/elisp-react/issues/13) |
| R02 | ページのアドレス・履歴・タイトル・meta を扱う API が無い | **major** | 確認 | [elisp-react#14](https://github.com/modeverv/elisp-react/issues/14) |
| R03 | window や document のイベント、各種 Observer を Lisp から受けられない | minor | 確認 | [elisp-react#15](https://github.com/modeverv/elisp-react/issues/15) |
| R04 | Lisp から preventDefault / stopPropagation を指定できず、リスナーの設定も選べない | **major** | 確認 | [elisp-react#16](https://github.com/modeverv/elisp-react/issues/16) |
| R05 | イベントの plist に修飾キー・code・isComposing・座標・発生元が無い | **major** | 確認 | [elisp-react#17](https://github.com/modeverv/elisp-react/issues/17) |
| R06 | DOM のプロパティ設定、引数付きのメソッド呼び出し、値の読み戻しを公開 API でできない | minor | 一部 | [elisp-react#18](https://github.com/modeverv/elisp-react/issues/18) |
| R11 | インライン SVG が作れない（要素が HTML の名前空間で作られる） | minor | 一部 | [elisp-react#23](https://github.com/modeverv/elisp-react/issues/23) |
| R15 | 無害化した HTML を差し込む手段が無く、ページの Emacs に HTML パーサーも無い | minor | 確認 | [elisp-react#27](https://github.com/modeverv/elisp-react/issues/27) |
| R16 | 属性の出力：リストの :class、数値の style、ARIA の真偽値が正しく出ない | minor | 一部 | [elisp-react#28](https://github.com/modeverv/elisp-react/issues/28) |
| R27 | モーダルとフォーカスの扱いを文書化し、showModal と close を呼べるようにする | minor | 否定 | [elisp-react#39](https://github.com/modeverv/elisp-react/issues/39) |
| N02 | react-fetch は状態と本文の文字列だけ。ヘッダーが無く、バイナリは壊れ、fetch の設定も少ない | **major** | 確認 | [elisp-react#8](https://github.com/modeverv/elisp-react/issues/8) |
| N03 | リアルタイムの経路が無い（WebSocket、Server-Sent Events、ストリーミング） | **major** | 確認 | [elisp-react#9](https://github.com/modeverv/elisp-react/issues/9) |

### elisp-react: 部品、状態、非同期の処理

| ID | 不足 | 重大さ | 判定 | Issue |
|---|---|---|---|---|
| R07 | context・store の購読・公開の強制再描画が無い | **major** | 一部 | [elisp-react#19](https://github.com/modeverv/elisp-react/issues/19) |
| R08 | ライフサイクルの各キーに関数は1つだけ。依存と後始末を持つ再利用可能な effect が無い | minor | 一部 | [elisp-react#20](https://github.com/modeverv/elisp-react/issues/20) |
| R09 | 描画エラーの後に部品が止まったままになり、残りの :did-mount も飛ぶ。エラー境界が無い | **major** | 確認 | [elisp-react#21](https://github.com/modeverv/elisp-react/issues/21) |
| R10 | react-async にタスクの手綱も取り消しも無い。即時の await でスタックが伸びる。generator.el の落とし穴 | **major** | 一部 | [elisp-react#22](https://github.com/modeverv/elisp-react/issues/22) |
| R12 | フォーム：submit にデータが無い、制御された入力が打鍵を落とし得る、制御された select の初期表示が違う | minor | 一部 | [elisp-react#24](https://github.com/modeverv/elisp-react/issues/24) |
| R13 | 先頭が nil の子リストが `<nil>` 要素になる。fragment が無い | minor | 確認 | [elisp-react#25](https://github.com/modeverv/elisp-react/issues/25) |
| R14 | :pure が関数の prop を eq で比べるので、lambda を渡すと効かない | minor | 確認 | [elisp-react#26](https://github.com/modeverv/elisp-react/issues/26) |
| R17 | ref を子へ渡せず、インスタンスの手綱も無い。react-mount はセレクターを返す | minor | 確認 | [elisp-react#29](https://github.com/modeverv/elisp-react/issues/29) |
| R18 | 綴りを間違えたコンポーネントが、黙って未知の HTML 要素として描かれる | minor | 確認 | [elisp-react#30](https://github.com/modeverv/elisp-react/issues/30) |
| N04 | react-storage は起動時の写しなので、別のタブの書き込みが失われる | minor | 確認 | [elisp-react#10](https://github.com/modeverv/elisp-react/issues/10) |
| N05 | 描画に生のバイト列の文字列が1つ混ざると、その回の DOM 操作がまるごと捨てられる | minor | 確認 | [elisp-react#11](https://github.com/modeverv/elisp-react/issues/11) |
| N06 | データ取得の層（キャッシュ、重複の除去、無効化）が無く、アプリごとに書くことになる | minor | 確認 | [elisp-react#12](https://github.com/modeverv/elisp-react/issues/12) |

### elisp-react: 起動、公開、実行

| ID | 不足 | 重大さ | 判定 | Issue |
|---|---|---|---|---|
| R19 | byte code のキャッシュが react.el の変化を見ず、再訪問者が古いマクロ展開で動く | **major** | 確認 | [elisp-react#31](https://github.com/modeverv/elisp-react/issues/31) |
| R20 | 初回訪問のたびに react.el とアプリを訪問者の CPU で byte-compile する。事前ビルドが無い | **major** | 確認 | [elisp-react#32](https://github.com/modeverv/elisp-react/issues/32) |
| R21 | 起動に進捗イベント・タイムアウト・中断が無く、通信エラーがファイル名を言わない | minor | 一部 | [elisp-react#33](https://github.com/modeverv/elisp-react/issues/33) |
| R22 | ページの文字列への描画（SSR）、hydration、head/meta の API が無い | minor | 確認 | [elisp-react#34](https://github.com/modeverv/elisp-react/issues/34) |
| R23 | 保存領域がオリジン全体で共有され、他のアプリのデータが読め、キャッシュされたコードを仕込める | **major** | 確認 | [elisp-react#35](https://github.com/modeverv/elisp-react/issues/35) |
| R24 | ホストの返事ごとに Emacs への要求と flush が1回ずつ。GC が返事の送信前に走る | minor | 一部 | [elisp-react#36](https://github.com/modeverv/elisp-react/issues/36) |
| R28 | Lisp の時間・命令数・DOM 適用時間を測るフックが無い | polish | 一部 | [elisp-react#40](https://github.com/modeverv/elisp-react/issues/40) |
| X01 | elisp-react と eval service に、版を固定した不変の配布が無い | **major** | 確認 | [elisp-react#43](https://github.com/modeverv/elisp-react/issues/43) |
| X02 | 必要な Content-Security-Policy が文書に無い。インラインの style と blob: の worker を不要にしたい | minor | 一部 | [elisp-react#44](https://github.com/modeverv/elisp-react/issues/44) |
| X06 | このスタックが何を保存し、どこへ通信するかの一覧が無い。保存データに期限が無い | minor | 確認 | [elisp-react#45](https://github.com/modeverv/elisp-react/issues/45) |
| N01 | 長い・終わらない Lisp の計算でアプリが黙って固まる。監視も再起動も無い | minor | 確認 | [elisp-react#7](https://github.com/modeverv/elisp-react/issues/7) |

### elisp-react: チームでの開発

| ID | 不足 | 重大さ | 判定 | Issue |
|---|---|---|---|---|
| R25 | ロケール・Intl の橋渡しが無い。ページの Emacs は C ロケールで、タイムゾーン指定を無視する | minor | 確認 | [elisp-react#37](https://github.com/modeverv/elisp-react/issues/37) |
| R26 | アプリ用のテストキットが無い（要素の検索、偽のページ、配布版 Emacs での実行器） | **major** | 一部 | [elisp-react#38](https://github.com/modeverv/elisp-react/issues/38) |
| R29 | jsx と react-define-component の字下げ規則が無く、アプリに lint の段階が無い | polish | 一部 | [elisp-react#41](https://github.com/modeverv/elisp-react/issues/41) |
| R30 | 他人の Lisp は依存順に並べるしかなく、load-path に何も無い | minor | 一部 | [elisp-react#42](https://github.com/modeverv/elisp-react/issues/42) |

### wasmacs: eval service

| ID | 不足 | 重大さ | 判定 | Issue |
|---|---|---|---|---|
| X03 | キャッシュ済みの Emacs がオフラインで起動できず、build id の取得に1回失敗すると全部を再ダウンロードする | minor | 確認 | [wasmacs#10](https://github.com/modeverv/wasmacs/issues/10) |
| X04 | 同じオリジンの2つの eval service ビルドが、互いのキャッシュを消し合う | minor | 確認 | [wasmacs#11](https://github.com/modeverv/wasmacs/issues/11) |
| X05 | タブごとに初期メモリ 1GiB、実機のスマートフォンで未検証。文書の「最大 4GiB」は誤り | **major** | 確認 | [wasmacs#12](https://github.com/modeverv/wasmacs/issues/12) |

### elisp-studio

| ID | 不足 | 重大さ | 判定 | Issue |
|---|---|---|---|---|
| S01 | プレビューにアドレスが無い。ハッシュのリンクで studio が入れ子に読み込まれ、pushState は例外 | **major** | 確認 | [elisp-studio#1](https://github.com/modeverv/elisp-studio/issues/1) |
| S02 | プレビューからプロジェクト自身のファイルを取得できず、相対 URL が studio のファイルに当たる | **major** | 確認 | [elisp-studio#2](https://github.com/modeverv/elisp-studio/issues/2) |
| S03 | ローカルモードでもプレビューが隔離される（COEP）ので、外部の埋め込みに credentialless が要る | minor | 一部 | [elisp-studio#3](https://github.com/modeverv/elisp-studio/issues/3) |
| S04 | 複数ファイルの変更をディレクトリ順に読み込み、最初のエラーで残りを黙って捨てる | **major** | 確認 | [elisp-studio#4](https://github.com/modeverv/elisp-studio/issues/4) |
| S05 | 消した・改名した定義がホットリロード後も生き残り、次の新規起動で失敗する | minor | 確認 | [elisp-studio#5](https://github.com/modeverv/elisp-studio/issues/5) |
| S06 | 補助関数やデータだけの変更は「適用した」と報告されるが、何も描き直されない | minor | 確認 | [elisp-studio#6](https://github.com/modeverv/elisp-studio/issues/6) |
| S07 | 実行時エラーに場所が無く、描画に失敗した変更が「適用されなかった」と報告される | **major** | 確認 | [elisp-studio#7](https://github.com/modeverv/elisp-studio/issues/7) |
| S08 | 式を評価して値を見る手段、部品と状態を調べる手段が無い | minor | 確認 | [elisp-studio#8](https://github.com/modeverv/elisp-studio/issues/8) |
| S09 | エディター支援：ローカルモードで Flymake が偽の警告を出す。M-. がプロジェクトの補助関数と部品に飛べない | minor | 一部 | [elisp-studio#9](https://github.com/modeverv/elisp-studio/issues/9) |
| S11 | ページ内の studio は app.el の無いプロジェクトのファイルを上書きし、既存のリポジトリを開けない | minor | 一部 | [elisp-studio#10](https://github.com/modeverv/elisp-studio/issues/10) |
| S12 | studio の中の server.el は、プロジェクトの他のファイルを読めず、CORS の無いサイトにも届かない | **major** | 確認 | [elisp-studio#11](https://github.com/modeverv/elisp-studio/issues/11) |
| S13 | 同じポートで開いたプロジェクト同士が localStorage とサーバーのデータを共有する | minor | 確認 | [elisp-studio#12](https://github.com/modeverv/elisp-studio/issues/12) |
| S14 | native サーバーのヘッダーが固定で、server.el から Cache-Control や Referrer-Policy を変えられない | minor | 確認 | [elisp-studio#13](https://github.com/modeverv/elisp-studio/issues/13) |
| S15 | native サーバーが別サイトのフロントエンドに答えられない（CORS が無い） | minor | 一部 | [elisp-studio#14](https://github.com/modeverv/elisp-studio/issues/14) |
| S16 | テンプレートに .gitignore・CI・テストが無いのに、ツールが .data/ をプロジェクトに書く | minor | 確認 | [elisp-studio#15](https://github.com/modeverv/elisp-studio/issues/15) |

## 確かめ直して訂正したこと

最初の報告には、誤りや言い過ぎもありました。詳しくは各 issue にあります。主な訂正は次のとおりです。

- **モーダルのダイアログは作れる**（[R27](https://github.com/modeverv/elisp-react/issues/39)、否定）。`command="show-modal"` を持つボタンで開いた `<dialog>` は本物のモーダルです。後ろのページは操作できなくなり、Tab は中に留まり、Esc で閉じると Lisp に `:on-close` が届き、フォーカスはボタンに戻ります。どこにも書かれておらず、Parens はこれをページの JavaScript で作り直していました。
- **ページの JavaScript には届く**（[R01](https://github.com/modeverv/elisp-react/issues/13)、一部）。公開したページでは、`window.fetch` を包むスクリプトで Lisp との要求と返事ができ、カスタム要素で文字列を双方向に渡せます。どちらも studio のプレビューでは使えません。
- **全体の状態は `:pure` の子にも届く**（[R07](https://github.com/modeverv/elisp-react/issues/19)、一部）。prop として渡すか、`:should-update` を使うか、部品を定義し直せば届きます。
- **package.el はページの中で動く**（[R30](https://github.com/modeverv/elisp-react/issues/42)、一部）。ローカルのファイルなら入れられます。ダウンロードはできません。
- **厳しい Content-Security-Policy もかけられる**（[X02](https://github.com/modeverv/elisp-react/issues/44)、一部）。ポリシーをページだけに付け、wasmacs を同じオリジンに置けば、許す必要があるのはインラインの style だけです。
- **返事のたびにアプリ全体を描き直していたのは Parens の作り方でした**（[R24](https://github.com/modeverv/elisp-react/issues/36)、一部）。elisp-react の性質ではありません。
- **`innerHTML` を設定する危ない抜け道がある**（[R15](https://github.com/modeverv/elisp-react/issues/27)）。内部関数 `react--emit` からホストのプロパティ操作に届き、HTML の中のスクリプトが実際に動きました。無害化した API の代わりにはなりません。

文書がコードと逆のことを言っている箇所が四つあります。

- elisp-react の README.md:106 は nil の子は捨てられると書いていますが、先頭が nil のリストは `<nil>` 要素になります（[R13](https://github.com/modeverv/elisp-react/issues/25)）。
- elisp-studio の README.md:68 は失敗した変更は適用されないと書いていますが、描画に失敗したときは新しい定義が入っています（[S07](https://github.com/modeverv/elisp-studio/issues/7)）。
- elisp-studio の README.md:32 は既存のプロジェクトを置き換えないと書いていますが、`app.el` の無いプロジェクトは置き換えられます（[S11](https://github.com/modeverv/elisp-studio/issues/10)）。
- wasmacs の doc/eval-service.md は Emacs のメモリが 4GiB まで増やせると書いていますが、実際の上限は 2GiB です（[X05](https://github.com/modeverv/wasmacs/issues/12)）。

## Parens が不足の回りに書いたもの

| Parens にあるもの | 理由 |
|---|---|
| port：ページからの通知は隠れた `<input>`、ページへの命令は命令ごとの `<data>` 要素（[lisp/parens-port.el](../lisp/parens-port.el)、`index.html`） | [R01](https://github.com/modeverv/elisp-react/issues/13) [R02](https://github.com/modeverv/elisp-react/issues/14) [R03](https://github.com/modeverv/elisp-react/issues/15) [R06](https://github.com/modeverv/elisp-react/issues/18) |
| Lisp で解析するハッシュのルート。studio のプレビューではクリックを横取りし、ルートを localStorage に保つ | [R02](https://github.com/modeverv/elisp-react/issues/14) [S01](https://github.com/modeverv/elisp-studio/issues/1) |
| port のスクリプトを `index.html` にインラインで置く | [S02](https://github.com/modeverv/elisp-studio/issues/2) |
| アイコンを `data:` URL の CSS マスクで描く | [R11](https://github.com/modeverv/elisp-react/issues/23) |
| `parens-class` と文字列の `:class` | [R16](https://github.com/modeverv/elisp-react/issues/28) |
| 自前の store、グローバルな App のインスタンス、すべてのカードに渡す `:lang` | [R07](https://github.com/modeverv/elisp-react/issues/19) |
| `:pure` のカードの prop には lambda ではなく関数のシンボルを渡す | [R14](https://github.com/modeverv/elisp-react/issues/26) |
| `parens-async`、`parens-all`、await のたびの古さの確認 | [R10](https://github.com/modeverv/elisp-react/issues/22) [N06](https://github.com/modeverv/elisp-react/issues/12) |
| モーダルの背景をダイアログの兄弟にし、後に port でフォーカスを閉じ込める | [R04](https://github.com/modeverv/elisp-react/issues/16) [R27](https://github.com/modeverv/elisp-react/issues/39) |
| `json-serialize` の後の `decode-coding-string`、自前のクエリ文字列の解析 | [N05](https://github.com/modeverv/elisp-react/issues/11) |
| `index.html` でファイルを依存順に並べる | [R30](https://github.com/modeverv/elisp-react/issues/42) |
| チャンネルの一覧を `server.el` にもう一度書く | [S12](https://github.com/modeverv/elisp-studio/issues/11) |
| native サーバーから YouTube を再生するための `<meta name="referrer">` と iframe の `referrerpolicy` | [S14](https://github.com/modeverv/elisp-studio/issues/13) |
| ライブラリの項目を 30 日で消す | [X06](https://github.com/modeverv/elisp-react/issues/45) |
| 古いデータ源への答えを捨てるための世代の番号 | [N06](https://github.com/modeverv/elisp-react/issues/12) |
| ERT 用の偽のページ。react.el の内部を 7 つ使う | [R26](https://github.com/modeverv/elisp-react/issues/38) |
