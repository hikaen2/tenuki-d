# 手抜き
手抜きはCSAプロトコルで通信する将棋プログラムです。

## 開発環境
- Debian 9
- LDC

## ビルドのしかた
~~~
$ git clone https://github.com/hikaen2/tenuki-d.git
$ cd tenuki-d
$ dub build -b release
~~~

## 動かしかた
評価ベクターにApery, commit 3221627のKK_synthesized.bin, KKP_synthesized.bin, KPP_synthesized.binを使っています。
KK_synthesized.bin, KKP_synthesized.bin, KPP_synthesized.binを作業ディレクトリに置いて実行してください。

~~~
$ ./tenuki hostname username password
~~~

例：
~~~
$ ./tenuki wdoor.c.u-tokyo.ac.jp tenuki floodgate-300-10F
~~~
