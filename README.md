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
評価ベクターになのはminiのfv_mini.binを使っています。
fv_mini.binを作業ディレクトリに置いて実行してください。
~~~
$ ./tenuki host port username password
~~~
例：
~~~
$ ./tenuki wdoor.c.u-tokyo.ac.jp 4081 tenuki floodgate-300-10F
~~~
