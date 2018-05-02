# coding: utf-8

require 'curses'
require 'listen'
require './pos'

STR = <<EOS
後手の持駒：
  9   8   7   6   5   4   3   2   1
+---+---+---+---+---+---+---+---+---+
|   |   |   |   |   |   |   |   |   |一
+---+---+---+---+---+---+---+---+---+
|   |   |   |   |   |   |   |   |   |二
+---+---+---+---+---+---+---+---+---+
|   |   |   |   |   |   |   |   |   |三
+---+---+---+---+---+---+---+---+---+
|   |   |   |   |   |   |   |   |   |四
+---+---+---+---+---+---+---+---+---+
|   |   |   |   |   |   |   |   |   |五
+---+---+---+---+---+---+---+---+---+
|   |   |   |   |   |   |   |   |   |六
+---+---+---+---+---+---+---+---+---+
|   |   |   |   |   |   |   |   |   |七
+---+---+---+---+---+---+---+---+---+
|   |   |   |   |   |   |   |   |   |八
+---+---+---+---+---+---+---+---+---+
|   |   |   |   |   |   |   |   |   |九
+---+---+---+---+---+---+---+---+---+
先手の持駒：飛2 角2 金4 銀4 桂4 香4 歩18
EOS

def pos(file, rank)
  [(1 + rank * 2), (37 - file * 4)]
end

moves = IO.readlines('recv.log').select{|e| /^[+-]\d{4}\D{2}/ === e}.map {|e| Move.parse(e)}
p moves

pos = Position.new
moves.each do |e|
  pos.do_move(e)
end

listener = Listen.to('.', only: /^tenuki\.log$/) do |modified, added, removed|
  puts "modified absolute path: #{modified}"
  puts "added absolute path: #{added}"
  puts "removed absolute path: #{removed}"
end
listener.start # not blocking


Curses.init_screen
begin

  Curses.curs_set(0)

  status = Curses::Window.new(1, 110, 26, 0)
  status.attron(Curses::A_STANDOUT)
  status.box('|', '-', '-')
  status.setpos(0, 0)
  status.addstr("-UUU:----F1  *scratch*      All L5     (Lisp Interaction)")
  status.refresh

  log = Curses::Window.new(24, 40, 1, 50)
  log.scrollok(25)
  log.box('|', '-', '+')
  log.setpos(0, 0)
  log.addstr(moves.map.with_index{|e,i| sprintf("%3d %s\n", i + 1, e) }.join)
  log.refresh

  win1 = Curses::Window.new(25, 40, 1, 1)
  #win1.box('|', '-')
  win1.refresh
  win1.setpos(0, 0)
  win1.addstr(STR)

  win1.attron(Curses::A_BOLD)
  pos.pieces.each do |e|
    win1.setpos(*pos(e.file, e.rank));  win1.addstr(e.to_s)
  end
  win1.attroff(Curses::A_BOLD)

  win1.attron(Curses::A_STANDOUT | Curses::A_BOLD)
  m = moves.last
  win1.setpos(*pos(m.file_to, m.rank_to));  win1.addstr(m.to_t)
  win1.attroff(Curses::A_STANDOUT | Curses::A_BOLD)


  win1.getch


  # Curses.crmode
  # Curses.setpos((Curses.lines - 1) / 2, (Curses.cols - 11) / 2)
  # Curses.addstr("Hit any key")
  #Curses.refresh
  #Curses.getch
  # show_message("Hello, World!")
ensure
  Curses.close_screen
end
