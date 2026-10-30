# coding: utf-8
#
# 対角に駒割りを入れた pp.bin を出力する
# usage: ruby misc/pp_init.rb > pp.bin

N = 2344
FV_SCALE = 16

# [エントリ数, 駒の価値]（先手・後手の順に並ぶ）
HAND = [[18, 100], [4, 260], [4, 235], [4, 392], [4, 389], [2, 625], [2, 844]] # 歩 香 桂 銀 金 角 飛
BOARD = [100, 260, 235, 392, 389, 625, 844, 458, 401, 423, 409, 800, 1164, 0]    # 歩 香 桂 銀 金 角 飛 と 成香 成桂 成銀 馬 龍 玉

diag = []
HAND.each { |n, v| diag += [v] * n + [-v] * n }
BOARD.each { |v| diag += [v] * 81 + [-v] * 81 }
raise unless diag.size == N

pp = Array.new(N * N, 0)
N.times { |i| pp[i * N + i] = diag[i] * FV_SCALE }
$stdout.binmode.write(pp.pack('s<*'))
