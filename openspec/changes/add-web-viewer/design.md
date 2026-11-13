## Context

- tenuki は接続ごとに `log/<ローカル時刻のISO基本形式>.log`（例 `20261113T202200.log`）を作り、サーバから受信した行をそのまま 1 行ずつ書いて毎回 flush する（`source/main.d:91`, `readLine`）。送信行（`LOGIN user pass` を含む）は書かないので、ログにパスワードは入らない。
- ログに現れる行: `LOGIN:... OK`、Game_Summary（`Name+:`, `Name-:`, `Your_Turn:`, `BEGIN Position` 内の `P1`〜`P9`・`P+`・`P-`・手番行・ブイの指し手 `+2726FU,T12`）、`START:...`、指し手 `+7776FU,T3`（自分の手もサーバのエコーとして届く）、`%TORYO,T5`、終局理由 `#RESIGN` 等、結果 `#WIN`/`#LOSE`/`#DRAW`/`#CENSORED`/`#CHUDAN`。
- EC2 は対局のときだけ起動し、`misc/loop.sh` で連続対局する。追加のサーバ・依存は入れないことが決まっている（proposal 参照）。

## Goals / Non-Goals

**Goals:**
- `viewer/index.html` 1 ファイルで完結し、Python 標準の `http.server` だけで動く
- 状態と描画を分け、後から機能を足しやすい形にしておく

**Non-Goals:**
- `BEGIN Position` の `P1`〜`P9` を読んで任意の開始局面に対応すること（開始局面は常に平手とする。tenuki 本体も平手前提）
- 指し手の合法性チェック（ログはサーバが受理した手だけなので信用する）
- 古いブラウザ対応（ES2020 程度と CSS grid が使える前提）

## Decisions

### 1. 配信は `http.server -d viewer` とシンボリックリンク
`viewer/log -> ../log` をコミットし、`viewer/` だけを配信する。`http.server` はシンボリックリンクを辿り、`..` を含むパスは配信ルートの外に出ないよう正規化する。
- 代替: リポジトリ直下を配信 → `tenuki.conf`（パスワード）や `*.bin` が漏れるので不可。Caddy/nginx → 追加インストールが要るので見送り。

### 2. 一覧は `http.server` のディレクトリ一覧 HTML を解析する
`fetch('log/')` の HTML から `href="...\.log"` を正規表現で抜き出す（`DOMParser` でも可）。名前を `decodeURIComponent` してから降順ソートする。ファイル名が ISO 基本形式なので文字列順 = 時刻順。
- 代替: `index.json` を書く同期スクリプト → 常駐プロセスが増えるので不採用。
- 「対局中」の印は一覧の各ログの中身を見ないと分からない。全ログを毎回取るのは無駄なので、**一度終局を確認したログ名を記憶し、未確認のログだけを取り直す**。終局済みログは二度と取らない。対局中のログは通常 1 つなので、1 周期あたりのリクエストは一覧 + 数本に収まる。

### 3. 状態と描画
```
state = {
  files:    ["20261113T210512.log", ...],   // 降順
  finished: Set<file>,                       // 終局を確認したログ
  follow:   true | false,                    // 最新を追うか（ハッシュなし = true）
  current:  file | null,                     // 表示中のログ
  game:     { moves, names, yourTurn, endReason, result } | null,
  ply:      number,                          // 表示中の手数（0 = 開始局面）
}
render(state)  // 毎回全体を描き直す。81 マス程度なので差分更新は不要
```
- `game` はログ全文から毎回作り直す（ログは数十 KB 以内なので差分読みや Range リクエストは不要）。
- 局面は `replay(moves, ply)` で平手から毎回再生する。キャッシュしない。
- フレームワークは使わない。画面が増えたら Preact + htm（ビルドなし）へ移す余地を残す。

### 4. 再生
- 盤は `board[file][rank]`（1 始まり、CSA の筋・段）に `{side, kind}` を置く。指し手 `±FFTTKK`: `FF==00` なら持ち駒から打つ、そうでなければ `FF` の駒を取り除く。`TT` に相手の駒があれば成りを戻した種類で手番側の持ち駒に加える。`TT` に `KK` を置く。
- 成り判定は不要（CSA の指し手は移動後の駒種を持つ）。
- 漢字の対応: `FU歩 KY香 KE桂 GI銀 KI金 KA角 HI飛 OU玉 TOと NY杏 NK圭 NG全 UM馬 RY竜`。成りを戻す対応: `TO→FU NY→KY NK→KE NG→GI UM→KA RY→HI`。

### 5. 追従とポーリング
- 2 秒ごとの `setTimeout` ループ（前回の取得が終わってから次を予約し、重ならないようにする）。`fetch(url, {cache: 'no-store'})`。
- 取得前に `atLatest = (ply === moves.length)` を覚え、取得後に `atLatest` なら `ply = moves.length`。
- `follow` のとき `current = files[0]`。`current` が変わったら `ply = 新しい moves.length`。
- 表示中ログが終局済みなら、そのログは取り直さない（決定 2 の `finished` で判断）。
- 取得失敗時は state を変えずに次周期へ。

### 6. 選択と URL
- `hashchange` を監視し、ハッシュ → `follow`/`current` を決める。一覧での選択はハッシュを書き換えるだけにし、状態の更新は `hashchange` 側の 1 か所に集める。
- ハッシュが一覧にないファイル名なら最新を追う扱い（ただし一覧取得前はハッシュを保留し、最初の一覧取得後に判定する）。

### 7. 結果の表示
- `#WIN`/`#LOSE` と `Your_Turn` から勝者の手番を求める（`#WIN` なら自分、`#LOSE` なら相手）。`#DRAW` は引き分け、`#CENSORED`/`#CHUDAN` は中断。直前の `#RESIGN`・`#TIME_UP`・`#ILLEGAL_MOVE`・`#SENNICHITE`・`#OUTE_SENNICHITE`・`#JISHOGI`・`#MAX_MOVES` を理由として添える。

### 8. 見た目
- 白地固定（ダークモード非対応）、マスは CSS grid 9×9 の正方形、細い黒線。後手の駒は `transform: rotate(180deg)`。最終手の移動先は薄い黄色系の背景。
- マスの大きさは画面の高さに収まる大きさと、一覧・指し手欄を除いた幅に収まる大きさの小さい方にする（Full HD で約 80px、最小 28px）。筋・段・持ち駒・対局者名の文字もマスに比例させ、ページ全体が縦にスクロールしないよう指し手欄の高さを画面に合わせる。
- 持ち駒の並び順は 飛・角・金・銀・桂・香・歩（一般的な棋譜表記の順）。形式は「角 歩3」。
- レイアウト: 左に対局一覧、中央に盤（上に後手の持ち駒、下に先手の持ち駒、上部に対局者名と結果）、右（狭い画面では下）に指し手リスト。指し手リストの表記は CSA のまま（`+7776FU`）でよい。
- キー操作: 上下キー（↑↓）で前後の手。指し手リスト以外にフォーカスがあっても効くよう `document` で受ける。

## Risks / Trade-offs

- [`http.server` をインターネットに直接公開する（本番非推奨、スキャナーが来る）] → 配信対象を `viewer/` に限定。インスタンスは対局中しか動かない。公開されるのは HTML と受信ログだけ（パスワードは含まれない）。受け入れ済み。
- [閲覧者が多いと EC2 にリクエストが来る] → 1 人あたり 2 秒に数 KB。探索 192 スレッドに対して誤差と判断。終局済みログを取り直さないことで抑える。
- [ログ一覧が長くなると一覧 HTML が大きくなる] → インスタンスごとに `log/` は対局分しか増えないので問題にならない。
- [ファイル名はローカル時刻（EC2 では通常 UTC）] → ファイル名をそのまま表示する。JST 変換はしない。
- [`log/` が存在しないとシンボリックリンクが壊れる] → `log/.keep` がコミット済みなので clone すれば存在する。

## Migration Plan

- 追加のみ。EC2 で `git pull` し、`python3 -m http.server 8000 -d viewer &` を起動、SG で 8000/tcp を `0.0.0.0/0` に開ける。
- ロールバックは http.server を止めて SG を閉じるだけ。tenuki 本体には影響しない。
