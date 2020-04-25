# gserver.computer-shogi.orgに指し手のパケットを分割して送信すると受理されない

## 現象

gserver.computer-shogi.orgに指し手を送信するときに，指し手のパケットを分割して送信すると受理されない。
たとえば "+7776FU\n" を "+7776FU" と "\n" に分割して送信すると受理されない。

期待する現象は受理される。


テストプログラム test.rb:
```
#!/usr/bin/ruby
# coding: utf-8
require "socket"

def main
  sock = TCPSocket.open(ARGV[0], 4081)

  sock.write("LOGIN %s %s\n" % [ARGV[1], ARGV[2]])
  sock.gets_expect(/^LOGIN:.+ OK$/)

  sock.gets_expect(/^BEGIN Game_Summary$/)
  us = sock.gets_until(/^Your_Turn:(\+|-)$/)[1]
  sock.gets_until(/^END Game_Summary$/)

  sock.write("AGREE\n")
  sock.gets_expect(/^START:/)

  sock.gets if us == '-'

  sock.write("+7776FU")
  sock.write("\n")  # ←分割する
  sock.gets_until(/^\+7776FU,T\d+$/)
end

# TCPSocket extension
class TCPSocket
  alias_method :__write__, :write
  alias_method :__gets__, :gets

  def write(s)
    self.__write__(s)
    STDERR.puts("> %s" % s.inspect)
  end

  def gets
    STDERR.puts("< %s" % (s = self.__gets__).inspect)
    s
  end

  def gets_expect(re)
    s = self.gets
    raise "unexpected response" until re === s
    re.match(s)
  end

  def gets_until(re)
    until re === (s = self.gets)
      return nil if s == nil
    end
    re.match(s)
  end
end

main
```

実行結果:
```
$ ./test.rb gserver.computer-shogi.org tenuki2 dOFRBq83
> "LOGIN tenuki2 dOFRBq83\n"
< "LOGIN:tenuki2 OK\n"
< "BEGIN Game_Summary\n"
< "Protocol_Version:1.2\n"
< "Protocol_Mode:Server\n"
< "Format:Shogi 1.0\n"
< "Declaration:Jishogi 1.1\n"
< "Game_ID:CSAg20200425101923_035\n"
< "Name+:tenuki2\n"
< "Name-:tenuki\n"
< "Your_Turn:+\n"
< "Rematch_On_Draw:NO\n"
< "To_Move:+\n"
< "Max_Moves:320\n"
< "BEGIN Time\n"
< "Time_Unit:1sec\n"
< "Total_Time:900\n"
< "Increment:5\n"
< "END Time\n"
< "BEGIN Position\n"
< "P1-KY-KE-GI-KI-OU-KI-GI-KE-KY\n"
< "P2 * -HI *  *  *  *  * -KA * \n"
< "P3-FU-FU-FU-FU-FU-FU-FU-FU-FU\n"
< "P4 *  *  *  *  *  *  *  *  * \n"
< "P5 *  *  *  *  *  *  *  *  * \n"
< "P6 *  *  *  *  *  *  *  *  * \n"
< "P7+FU+FU+FU+FU+FU+FU+FU+FU+FU\n"
< "P8 * +KA *  *  *  *  * +HI * \n"
< "P9+KY+KE+GI+KI+OU+KI+GI+KE+KY\n"
< "P+\n"
< "P-\n"
< "+\n"
< "END Position\n"
< "END Game_Summary\n"
> "AGREE\n"
< "START:CSAg20200425101923_035\n"
> "+7776FU"
> "\n"
< "\n"
```

期待する結果:
```
（略）
> "+7776FU"
> "\n"
< "+7776FU,T0\n"
```
