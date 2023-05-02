# 手抜き

手抜きはCSAプロトコルで通信する将棋プログラムです。


## 開発環境

- Debian 11
- LDC


## ビルドのしかた

~~~
$ sudo apt install build-essential llvm-dev ldc dub
$ git clone https://github.com/hikaen2/tenuki-d.git
$ cd tenuki-d
$ make
~~~


## 動かしかた

評価ベクターに[『どうたぬき』(tanuki- 第 1 回世界将棋 AI 電竜戦バージョン)](https://github.com/nodchip/tanuki-/releases/tag/tanuki-denryu1)の評価関数ファイル nn.bin を使っています。
nn.binを作業ディレクトリに置いて実行してください。

~~~
$ ./tenuki hostname username password
~~~

例：
~~~
$ ./tenuki wdoor.c.u-tokyo.ac.jp tenuki floodgate-300-10F
~~~


## 履歴

- 2017-05-03 [第27回世界コンピュータ将棋選手権](http://www2.computer-shogi.org/wcsc27/) 一次予選30位（36チーム中）
- 2018-05-03 [第28回世界コンピュータ将棋選手権](http://www2.computer-shogi.org/wcsc28/) 一次予選23位（40チーム中）
- 2019-05-03 [第29回世界コンピュータ将棋選手権](http://www2.computer-shogi.org/wcsc29/) 一次予選18位（40チーム中）
- 2020-05-03 [世界コンピュータ将棋オンライン大会](http://www2.computer-shogi.org/wcso1.html) 初日19位（27チーム中）
- 2020-11-21 [第一回電竜戦](https://golan.sakura.ne.jp/denryusen/dr1_production/dr1_live.php) 一日目18位（56チーム中）
- 2021-05-03 [第31回世界コンピュータ将棋選手権](http://www2.computer-shogi.org/wcsc31/) 一次予選15位
- 2021-11-20 [第二回電竜戦](https://golan.sakura.ne.jp/denryusen/dr2_production/dr1_live.php) B級16位
- 2022-05-03 [第32回世界コンピュータ将棋選手権](http://www2.computer-shogi.org/wcsc32/) 二次予選28位
