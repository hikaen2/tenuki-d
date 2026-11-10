## Why

NNUE (nn.bin) は外部の評価関数ファイルに依存している。自前で学習できる単純な評価関数として、全駒2駒関係 (PP) の評価関数を Bonanza メソッドで作りたい。

## What Changes

- 評価関数ファイル pp.bin の形式を定義する
- pp.bin を読み込む PP 評価関数を追加する
- Bonanza メソッドで pp.bin を学習する学習器を追加する（仕様は今後追加）

## Capabilities

### New Capabilities
- `pp-bin-format`: 評価関数ファイル pp.bin のバイナリ形式、インデックス体系、対称性
- `pp-eval`: pp.bin を使った局面評価（先手視点・1pass、i<=j の和、手番視点への変換）

### Modified Capabilities

## Impact

- `source/eval.d`（PP 評価関数への差し替え）
- 学習器（新規）
- 実行時に pp.bin を作業ディレクトリに置く必要がある
