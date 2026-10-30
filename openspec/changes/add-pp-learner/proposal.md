## Why

add-pp-eval で PP 評価関数と、対角に駒割りだけを入れた pp.bin ができた。2駒の関係を棋譜から学習して、評価関数を強くしたい。

## What Changes

- floodgate の CSA 棋譜から、学習に使う棋譜を選んで変換するスクリプトを追加する
- Bonanza メソッドで pp.bin を学習する学習器を追加する（`tenuki` とは別の実行ファイル）
- 学習器から使えるように、評価関数の駒リスト作成と pp の値を公開する（`staticValue` の振る舞いは変えない）

## Capabilities

### New Capabilities
- `pp-learner`: 学習用棋譜の作成と、Bonanza メソッドによる pp.bin の学習

### Modified Capabilities

## Impact

- `source/eval.d`（駒リスト作成と pp 配列の公開）
- `source/learn.d`（新規）、`dub.json`（学習器のビルド構成を追加）
- `misc/`（棋譜変換スクリプトを新規追加）
- floodgate の棋譜アーカイブは利用者が手動でダウンロードする
