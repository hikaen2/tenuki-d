module learn;

import eval;
import movegen;
import parser;
import position;
import std.algorithm;
import std.conv;
import std.datetime.stopwatch;
import std.file;
import std.getopt;
import std.math;
import std.parallelism;
import std.regex;
import std.stdint;
import std.stdio;
import std.string;
import text;
import types;


private enum WINDOW = 256;      // 窓の幅（Bonanza の FV_WINDOW）
private enum A = 0.0273;        // T(x) の傾き
private enum QS_FULL = 4;       // 静止探索で駒を取る手をすべて読む手数
private enum INF = 32000;
private enum FIXED = 1 << 20;   // 勾配の固定小数点の倍率
private enum CHUNK = 4096;      // 棋譜と読み筋を一度に読む対局数。スレッド数が多くても1スレッドに何局も行き渡るようにする
private enum HIRATE = "sfen lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1";

__gshared private TaskPool POOL;
__gshared private int[] GROUP;  // key: a * N + b, value: グループ番号 * 2 + (符号が負なら 1)
__gshared private int[] REP;    // key: グループ番号, value: 符号が正のペア a * N + b
__gshared private bool[] ZERO;  // key: グループ番号, value: 0 に固定するか


/**
 * 棋譜の局面と、そこで指された手
 */
private struct Record
{
    Position pos;
    Move move;
}


int main(string[] args)
{
    uint threads = totalCPUs;
    try {
        getopt(args, "t", &threads);
        if (args.length != 6) {
            throw new Exception("");
        }
    } catch (Exception e) {
        stderr.writeln("usage: tenuki-learn [-t threads] train.txt test.txt pp.bin iterations steps");
        stderr.writeln("  -t  default: number of CPUs");
        return 1;
    }
    const string ppPath = args[3];
    const int iterations = to!int(args[4]);
    const int steps = to!int(args[5]);

    POOL = new TaskPool(threads - 1);
    POOL.isDaemon = true;

    loadPP(ppPath);
    makeGroups();
    if (!checkSymmetry()) {
        stderr.writefln("%s does not satisfy the symmetry", ppPath);
        return 1;
    }
    const string trainPath = args[1];
    const string testPath = args[2];
    const string pvPath = ppPath ~ ".pv";
    countGames(trainPath);
    countGames(testPath);

    writefln("iteration 0  match %.4f", matchRate(testPath));
    foreach (iteration; 1 .. iterations + 1) {
        auto sw = StopWatch(AutoStart.yes);

        // 探索段階：棋譜を CHUNK 局ずつ読んで探索し、読み筋をファイルに書く
        double j = 0;
        File pvFile = File(pvPath, "wb");
        auto reader = GameReader(trainPath);
        for (Record[][] games; (games = reader.next).length > 0; ) {
            auto bufs = new ushort[][games.length];
            auto js = new double[games.length];
            foreach (i, game; POOL.parallel(games, 1)) {
                js[i] = searchGame(game, bufs[i]);
            }
            j += js.sum;
            foreach (buf; bufs) {
                writePv(pvFile, buf);
            }
        }
        pvFile.close();

        // 更新段階
        foreach (step; 0 .. steps) {
            update(gradientSum(pvPath));
        }

        savePP(ppPath);
        writefln("iteration %d  J %.1f  match %.4f  (%.0f sec)",
            iteration, j, matchRate(testPath), sw.peek.total!"msecs" / 1000.0);
        stdout.flush();
    }
    if (pvPath.exists) {
        std.file.remove(pvPath);
    }
    return 0;
}


/**
 * 棋譜ファイルを先頭から CHUNK 局ずつ読む
 * ファイルは1行1局で、CSA 形式の指し手を空白区切りで並べたもの
 */
private struct GameReader
{
    File file;
    long games = 0;
    long positions = 0;
    long skipped = 0;

    this(string path)
    {
        file = File(path);
    }

    /**
     * returns: 次の最大 CHUNK 局。ファイルの終わりでは空
     */
    Record[][] next()
    {
        Record[][] chunk;
        while (chunk.length < CHUNK) {
            string line = file.readln;
            if (line.length == 0) {
                break;
            }
            Record[] game = parseGame(line);
            if (game is null) {
                skipped++;
                continue;
            }
            chunk ~= game;
            games++;
            positions += game.length;
        }
        return chunk;
    }
}

/**
 * 棋譜ファイルの1行を局面と手の列にする
 * returns: 局面と手の列。解析できない手があれば null
 */
private Record[] parseGame(string line)
{
    Record[] game;
    Position p = parsePosition(HIRATE);
    foreach (s; line.split) {
        Move m = toMove(s, p);
        if (m == Move.NULL) {
            return null;
        }
        game ~= Record(p, m);
        p = p.doMove(m);
    }
    return game;
}

/**
 * 棋譜ファイルの対局数と局面数を表示する
 */
private void countGames(string path)
{
    auto reader = GameReader(path);
    while (reader.next.length > 0) {
    }
    writefln("%s: %d games, %d positions (%d games skipped)", path, reader.games, reader.positions, reader.skipped);
}

/**
 * CSA 形式の指し手 s を p での手にする
 * returns: 手。合法手として解析できなければ Move.NULL
 */
private Move toMove(string s, const ref Position p)
{
    if (!s.matchFirst(r"^[+-]\d{4}(FU|KY|KE|GI|KI|KA|HI|OU|TO|NY|NK|NG|UM|RY)$")) {
        return Move.NULL;
    }
    Move m = parseMove(s, p);
    Move[600] moves;
    int length = p.legalMoves(moves);
    if (!moves[0 .. length].canFind(m) || m.toString(p) != s) {
        return Move.NULL;
    }
    return m;
}


/**
 * 静止探索
 * QS_FULL 手までは駒を取る手をすべて読み、それより深いところでは直前の手が動いた升で取り返す手だけを読む
 * returns: 手番のある側から見た評価値
 */
private int qsearch(const Position p, int ply, int a, const int b, ref Move[64] outPv)
{
    outPv[0] = Move.NULL;
    Move[64] pv;

    a = max(a, p.staticValue);
    if (b <= a) return b;

    Move[128] moves;
    int length = p.capturelMoves(moves);
    foreach (Move move; moves[0 .. length]) {
        if (ply >= QS_FULL && move.to != p.previousMove.to) {
            continue;
        }
        int value = -qsearch(p.doMove(move), ply + 1, -b, -a, pv);
        if (a < value) {
            a = value;
            if (b <= a) return b;
            outPv[0] = move;
            outPv[1 .. 64] = pv[0 .. 63];
        }
    }
    return a;
}

/**
 * p で m を指してから静止探索する
 * returns: p の手番側から見た評価値。outPv には m から始まる読み筋が入る
 */
private int searchMove(const ref Position p, Move m, int a, int b, ref Move[64] outPv)
{
    Move[64] pv;
    int value = -qsearch(p.doMove(m), 0, -b, -a, pv);
    outPv[0] = m;
    outPv[1 .. 64] = pv[0 .. 63];
    return value;
}

/**
 * 読み筋の Move.NULL の手前まで
 */
private const(Move)[] line(return ref const Move[64] pv)
{
    long length = pv[].countUntil(Move.NULL);
    return pv[0 .. (length < 0 ? 64 : length)];
}

/**
 * 探索段階
 * 棋譜の手は全幅、それ以外の手は窓 [v(m*) - window, v(m*) + window] で探索する
 * pvs には、棋譜の手の読み筋と、窓の中の手の読み筋が入る
 * returns: J への寄与
 */
private double searchRecord(const ref Record r, ref ushort[] buf, int window = WINDOW)
{
    buf ~= r.move.i;
    const size_t at = buf.length;
    buf ~= 0;

    Move[600] moves;
    int length = r.pos.legalMoves(moves);
    if (length <= 1) {
        return 0;
    }

    Move[64] pv;
    int record = searchMove(r.pos, r.move, -INF, INF, pv);
    appendPv(buf, line(pv));
    int n = 1;

    double j = 0;
    foreach (Move move; moves[0 .. length]) {
        if (move == r.move) {
            continue;
        }
        int x = clamp(searchMove(r.pos, move, record - window, record + window, pv) - record, -WINDOW, WINDOW);
        j += t(x);
        if (abs(x) < WINDOW) {
            appendPv(buf, line(pv));
            n++;
        }
    }
    buf[at] = cast(ushort)n;
    return j;
}

/**
 * 1局の探索段階
 * buf には局面ごとに、棋譜の手、読み筋の数、読み筋（手数と手の列）を並べる。読み筋の1本目は棋譜の手の読み筋
 * returns: この対局の J
 */
private double searchGame(const Record[] game, out ushort[] buf)
{
    double j = 0;
    foreach (ref r; game) {
        j += searchRecord(r, buf);
    }
    return j;
}

static assert(Move.sizeof == ushort.sizeof);

private void appendPv(ref ushort[] buf, const Move[] pv)
{
    buf ~= cast(ushort)pv.length;
    buf ~= cast(const(ushort)[])pv;
}

/**
 * buf の pos から読み筋を1本取り出し、pos を次に進める
 */
private const(Move)[] nextPv(const ushort[] buf, ref size_t pos)
{
    const size_t length = buf[pos];
    auto pv = cast(const(Move)[])buf[pos + 1 .. pos + 1 + length];
    pos += 1 + length;
    return pv;
}

/**
 * 1局分の読み筋をファイルに書く
 */
private void writePv(ref File f, const ushort[] buf)
{
    uint[1] length = [cast(uint)buf.length];
    f.rawWrite(length);
    f.rawWrite(buf);
}

/**
 * returns: ファイルから読んだ次の最大 games 局分の読み筋。ファイルの終わりでは空
 */
private ushort[][] readPvs(ref File f, size_t games = CHUNK)
{
    ushort[][] chunk;
    uint[1] length;
    while (chunk.length < games && f.rawRead(length).length == 1) {
        auto buf = new ushort[length[0]];
        if (f.rawRead(buf).length != buf.length) {
            throw new Exception("truncated pv file: " ~ f.name);
        }
        chunk ~= buf;
    }
    return chunk;
}

private double t(double x)
{
    return 1 / (1 + exp(-A * x));
}

/**
 * p から読み筋 pv を再生した末端局面
 */
private Position leaf(Position p, const Move[] pv)
{
    foreach (Move m; pv) {
        p = p.doMove(m);
    }
    return p;
}

/**
 * p の手番側から見た、末端局面 l の評価値
 */
private int leafValue(const ref Position p, const ref Position l)
{
    return l.sideToMove == p.sideToMove ? l.staticValue : -l.staticValue;
}

/**
 * 更新段階の勾配
 * 保存した読み筋を再生し、末端局面を今の pp で評価し直して、grad に足す
 */
private void gradient(long[] grad, const ref Position p, const ushort[] buf, ref size_t pos, int n)
{
    if (n == 0) {
        return;
    }
    const long s = p.sideToMove == Color.BLACK ? 1 : -1;
    Position recordLeaf = leaf(p, nextPv(buf, pos));
    int record = leafValue(p, recordLeaf);

    long sum = 0;
    foreach (k; 1 .. n) {
        Position l = leaf(p, nextPv(buf, pos));
        int x = leafValue(p, l) - record;
        if (abs(x) >= WINDOW) {
            continue;
        }
        long d = s * lround(A * t(x) * (1 - t(x)) * FIXED);
        accumulate(grad, l, d);
        sum += d;
    }
    accumulate(grad, recordLeaf, -sum);
}

/**
 * 1局分の読み筋 buf（searchGame の形式）の勾配を grad に足す
 */
private void gradientGame(long[] grad, const ushort[] buf)
{
    Position p = parsePosition(HIRATE);
    size_t pos = 0;
    while (pos < buf.length) {
        Move m = Move(buf[pos]);
        int n = buf[pos + 1];
        pos += 2;
        gradient(grad, p, buf, pos, n);
        p = p.doMove(m);
    }
}

/**
 * 読み筋ファイルの全局面の勾配を足し合わせる
 * スレッドごとに勾配を足してから、全スレッドの勾配を足す。整数の和なので、スレッド数によらず同じ結果になる
 */
private long[] gradientSum(string pvPath)
{
    auto grads = new long[][](POOL.size + 1, REP.length);
    File f = File(pvPath, "rb");
    for (ushort[][] bufs; (bufs = readPvs(f)).length > 0; ) {
        foreach (buf; POOL.parallel(bufs, 1)) {
            gradientGame(grads[POOL.workerIndex], buf);
        }
    }
    foreach (g; grads[1 .. $]) {
        grads[0][] += g[];
    }
    return grads[0];
}

/**
 * 局面 l の駒リストに含まれるペアのグループに d を足す
 */
private void accumulate(long[] grad, const ref Position l, long d)
{
    int[40] list;
    int length = pieceList(l, list);
    for (int i = 0; i < length; i++) {
        for (int j = i; j < length; j++) {
            int g = GROUP[list[i] * N + list[j]];
            grad[g >> 1] += (g & 1) ? -d : d;
        }
    }
}

/**
 * 勾配の符号を見て、各グループの値を 1 ずつ動かす
 */
private void update(const long[] grad)
{
    int16_t[] pp = (&PP[0][0])[0 .. N * N];
    auto values = new int16_t[REP.length];
    foreach (g, ref v; values) {
        if (ZERO[g]) {
            v = 0;
            continue;
        }
        int value = pp[REP[g]] - cast(int)sgn(grad[g]);
        v = cast(int16_t)clamp(value, -int16_t.max, int16_t.max);
    }
    foreach (i, ref e; pp) {
        int g = GROUP[i];
        e = (g & 1) ? cast(int16_t)-values[g >> 1] : values[g >> 1];
    }
}

/**
 * 検証用棋譜の一致率
 */
private double matchRate(string path)
{
    long matched = 0;
    long positions = 0;
    auto reader = GameReader(path);
    for (Record[][] games; (games = reader.next).length > 0; ) {
        auto counts = new long[games.length];
        foreach (i, game; POOL.parallel(games, 1)) {
            counts[i] = game.count!(r => bestMove(r.pos) == r.move);
        }
        matched += counts.sum;
        positions += games.map!(g => g.length).sum;
    }
    return cast(double)matched / positions;
}

/**
 * 評価値が最大になる手を返す。同じ値なら先に生成した手を返す
 */
private Move bestMove(const ref Position p)
{
    Move[600] moves;
    Move[64] pv;
    int length = p.legalMoves(moves);
    Move best = Move.NULL;
    int a = -INF;
    foreach (Move move; moves[0 .. length]) {
        int value = searchMove(p, move, a, INF, pv);
        if (a < value) {
            a = value;
            best = move;
        }
    }
    return best;
}


/**
 * 対称性のグループの表を作る
 * ペア (a, b) に、入れ替え・inv・mir を組み合わせた変換をかけたものを1つのグループにする
 * inv を奇数回かけたペアの符号は負。同じペアが正と負の両方で現れるグループは 0 に固定する
 */
private void makeGroups()
{
    int[N] inv;
    int[N] mir;
    // 持ち駒
    for (int t = Type.PAWN; t <= Type.ROOK; t++) {
        for (int c = Color.BLACK; c <= Color.WHITE; c++) {
            for (int i = 0; i < OFFSET_HAND[Color.WHITE][t] - OFFSET_HAND[Color.BLACK][t]; i++) {
                int f = OFFSET_HAND[c][t] + i;
                inv[f] = OFFSET_HAND[c ^ 1][t] + i;
                mir[f] = f;
            }
        }
    }
    // 盤上の駒
    for (ubyte k = 0; k < OFFSET_PP.length; k++) {
        for (int sq = SQ11; sq <= SQ99; sq++) {
            int f = OFFSET_PP[k] + sq;
            inv[f] = OFFSET_PP[Square(k).inv.i] + (SQ99 - sq);
            mir[f] = OFFSET_PP[k] + (8 - sq / 9) * 9 + sq % 9;
        }
    }

    GROUP = new int[N * N];
    GROUP[] = -1;
    REP = null;
    ZERO = null;
    for (int a = 0; a < N; a++) {
        for (int b = 0; b < N; b++) {
            if (GROUP[a * N + b] >= 0) {
                continue;
            }
            int g = cast(int)REP.length;
            bool zero = false;
            for (int k = 0; k < 4; k++) { // bit 0: inv, bit 1: mir
                int x = (k & 2) ? mir[a] : a;
                int y = (k & 2) ? mir[b] : b;
                if (k & 1) {
                    x = inv[x];
                    y = inv[y];
                }
                int[2] pairs = [x * N + y, y * N + x];
                foreach (i; pairs) {
                    zero |= GROUP[i] >= 0 && GROUP[i] != g * 2 + (k & 1);
                    GROUP[i] = g * 2 + (k & 1);
                }
            }
            REP ~= a * N + b;
            ZERO ~= zero;
        }
    }
}

/**
 * pp が対称性を満たすか調べ、グループの数と 0 に固定されるペアの数を表示する
 */
private bool checkSymmetry()
{
    const int16_t[] pp = (&PP[0][0])[0 .. N * N];
    bool ok = true;
    int zeroPairs = 0;
    foreach (i, e; pp) {
        int g = GROUP[i];
        int expected = ZERO[g >> 1] ? 0 : (g & 1) ? -pp[REP[g >> 1]] : pp[REP[g >> 1]];
        ok &= e == expected;
        zeroPairs += ZERO[g >> 1];
    }
    writefln("groups: %d, zero pairs: %d", REP.length, zeroPairs);
    return ok;
}

/**
 * pp.bin を書き出す。書き込みの途中で止まっても前回の pp.bin が壊れないように、tmp に書いてから rename する
 */
private void savePP(string path)
{
    File f = File(path ~ ".tmp", "w");
    f.rawWrite(PP[]);
    f.close();
    rename(path ~ ".tmp", path);
}


version (unittest)
{
    import std.array;
    import std.path;
    import std.random;

    /**
     * 駒割りだけを対角に入れた pp にする（misc/pp_init.rb と同じ値）
     */
    private void setMaterial()
    {
        immutable int[] HAND = [100, 260, 235, 392, 389, 625, 844];
        immutable int[] BOARD = [100, 260, 235, 392, 389, 625, 844, 0, 458, 401, 423, 409, 800, 1164];
        (&PP[0][0])[0 .. N * N] = 0;
        for (int t = Type.PAWN; t <= Type.ROOK; t++) {
            for (int c = Color.BLACK; c <= Color.WHITE; c++) {
                for (int i = 0; i < OFFSET_HAND[Color.WHITE][t] - OFFSET_HAND[Color.BLACK][t]; i++) {
                    int f = OFFSET_HAND[c][t] + i;
                    PP[f][f] = cast(int16_t)((c == Color.BLACK ? 1 : -1) * HAND[t] * FV_SCALE);
                }
            }
        }
        for (ubyte k = 0; k < OFFSET_PP.length; k++) {
            for (int sq = SQ11; sq <= SQ99; sq++) {
                int f = OFFSET_PP[k] + sq;
                PP[f][f] = cast(int16_t)((Square(k).isBlack ? 1 : -1) * BOARD[Square(k).type] * FV_SCALE);
            }
        }
    }

    /**
     * pp をでたらめな値にする
     */
    private void setRandom()
    {
        auto rnd = Random(1);
        foreach (ref e; (&PP[0][0])[0 .. N * N]) {
            e = cast(int16_t)uniform(-200, 201, rnd);
        }
    }

    /**
     * 平手から手をでたらめに選んで指した局面と手
     */
    private Record[] randomRecords(int games, int plies)
    {
        return randomGames(games, plies).join;
    }

    /**
     * 平手から手をでたらめに選んで指した対局
     */
    private Record[][] randomGames(int games, int plies)
    {
        auto rnd = Random(2);
        Record[][] records;
        foreach (g; 0 .. games) {
            Record[] game;
            Position p = parsePosition(HIRATE);
            foreach (ply; 0 .. plies) {
                Move[600] moves;
                int length = p.legalMoves(moves);
                Move m = moves[uniform(0, length, rnd)];
                Position q = p.doMove(m);
                if (q.piecesInHand[Color.BLACK][Type.KING] + q.piecesInHand[Color.WHITE][Type.KING] > 0) {
                    break;
                }
                game ~= Record(p, m);
                p = q;
            }
            records ~= game;
        }
        return records;
    }

    /**
     * 枝刈りも取り返しの制限もない静止探索
     */
    private int naiveQsearch(const Position p)
    {
        int best = p.staticValue;
        Move[128] moves;
        int length = p.capturelMoves(moves);
        foreach (Move move; moves[0 .. length]) {
            best = max(best, -naiveQsearch(p.doMove(move)));
        }
        return best;
    }
}

// 3.3 1手 + 静止探索
unittest
{
    setMaterial();

    // 同じ局面で2回呼ぶと、同じ評価値と読み筋が返る
    foreach (ref r; randomRecords(3, 60)) {
        Move[600] moves;
        int length = r.pos.legalMoves(moves);
        foreach (Move move; moves[0 .. length]) {
            Move[64] pv1, pv2;
            assert(searchMove(r.pos, move, -INF, INF, pv1) == searchMove(r.pos, move, -INF, INF, pv2));
            assert(pv1 == pv2);
        }
    }

    // 5e の龍を、先手は斜めに重ねた龍・馬・角、後手は筋に重ねた飛・香で取り合う
    // 重ねてあるので取る順番が決まり、取る駒の価値が交互に下がっていくので、最後まで取り合う
    Position p = parsePosition("sfen k8/9/4l4/4r4/4+r4/3+R5/2+B6/1B7/8K b - 1");
    Move[64] pv;
    int value = qsearch(p, 0, -INF, INF, pv);
    const(Move)[] l = line(pv);
    writefln("exchange: value %d, pv %s", value, pv.toString(p));
    assert(value == naiveQsearch(p));
    assert(l.length >= 5);
    Position q = leaf(p, l);
    assert(leafValue(p, q) == value);
}

// 3.4 探索段階
unittest
{
    setRandom();
    int stored = 0;
    foreach (ref r; randomRecords(5, 80)) {
        ushort[] buf1, buf2;
        double j1 = searchRecord(r, buf1);
        double j2 = searchRecord(r, buf2, INF);
        assert(j1 == j2);
        assert(buf1 == buf2);
        assert(Move(buf1[0]) == r.move);
        const int n = buf1[1];
        if (n == 0) {
            assert(buf1.length == 2);
            continue;
        }
        // 保存した読み筋を再生した末端の評価値が、探索の評価値と一致する
        size_t pos = 2;
        Move[64] pv;
        int record = searchMove(r.pos, r.move, -INF, INF, pv);
        Position q = leaf(r.pos, nextPv(buf1, pos));
        assert(leafValue(r.pos, q) == record);
        foreach (k; 1 .. n) {
            const(Move)[] l = nextPv(buf1, pos);
            int value = searchMove(r.pos, l[0], -INF, INF, pv);
            q = leaf(r.pos, l);
            assert(leafValue(r.pos, q) == value);
            assert(abs(value - record) < WINDOW);
        }
        assert(pos == buf1.length);
        stored += n;
    }
    writefln("search: %d pvs stored", stored);
}

// 3.6 更新段階の勾配とスレッド並列化
unittest
{
    setRandom();
    makeGroups();
    Record[][] games = randomGames(20, 40);
    auto bufs = new ushort[][games.length];
    string path = tempDir.buildPath("tenuki-learn-unittest.pv");
    File f = File(path, "wb");
    foreach (i, game; games) {
        searchGame(game, bufs[i]);
        writePv(f, bufs[i]);
    }
    f.close();
    scope (exit) std.file.remove(path);

    // 書いた読み筋をそのまま読み戻せる
    f = File(path, "rb");
    assert(readPvs(f, 16) == bufs[0 .. 16]);
    assert(readPvs(f, 16) == bufs[16 .. $]);
    assert(readPvs(f, 16).length == 0);
    f.close();

    POOL = new TaskPool(0);
    long[] g1 = gradientSum(path);
    POOL = new TaskPool(7);
    POOL.isDaemon = true;
    long[] g8 = gradientSum(path);
    writefln("gradient: %d nonzero groups", g1.count!(e => e != 0));
    assert(g1.any!(e => e != 0));
    assert(g1 == g8);
}
