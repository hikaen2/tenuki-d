# coding: utf-8
#
# floodgate の CSA 棋譜から学習用棋譜を作る
# 平手・両者のレーティングが指定値以上・投了で終わった対局だけを、1行1局で出力する
# usage: ruby misc/csa2kifu.rb <最低レーティング> <CSA ファイル群> > games.txt

HIRATE = [
  'P1-KY-KE-GI-KI-OU-KI-GI-KE-KY',
  'P2 * -HI *  *  *  *  * -KA * ',
  'P3-FU-FU-FU-FU-FU-FU-FU-FU-FU',
  'P4 *  *  *  *  *  *  *  *  * ',
  'P5 *  *  *  *  *  *  *  *  * ',
  'P6 *  *  *  *  *  *  *  *  * ',
  'P7+FU+FU+FU+FU+FU+FU+FU+FU+FU',
  'P8 * +KA *  *  *  *  * +HI * ',
  'P9+KY+KE+GI+KI+OU+KI+GI+KE+KY',
]

def hirate?(lines)
  pos = lines.select { |l| l.start_with?('P') }
  pos == ['PI'] || pos == HIRATE
end

min_rate = Float(ARGV.shift)
count = Hash.new(0)

ARGV.each do |path|
  lines = File.binread(path).lines.map(&:chomp)
  rates = lines.grep(/\A'(black|white)_rate:/).map { |l| l.split(':').last.to_f }
  moves = lines.grep(/\A[+-]\d{4}[A-Z]{2}/).map { |l| l[0, 7] }
  result = lines.grep(/\A%/).first.to_s

  reason = if !hirate?(lines) || lines.include?('-') then 'not hirate'
           elsif rates.size != 2 || rates.min < min_rate then 'rating'
           elsif !result.start_with?('%TORYO') then 'not toryo'
           elsif moves.empty? then 'no moves'
           end
  if reason
    count[reason] += 1
  else
    count['ok'] += 1
    puts moves.join(' ')
  end
end

warn count.map { |k, v| "#{k}: #{v}" }.join(', ')
