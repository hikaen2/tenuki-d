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
    Record[] train = readRecords(args[1]);
    Record[] test = readRecords(args[2]);

    writefln("iteration 0  match %.4f", matchRate(test));
    foreach (iteration; 1 .. iterations + 1) {
        auto sw = StopWatch(AutoStart.yes);

        // 探索段階
        auto pvs = new Move[][][train.length];
        auto js = new double[train.length];
        foreach (i, ref r; POOL.parallel(train)) {
            js[i] = searchRecord(r, pvs[i]);
        }

        // 更新段階
        foreach (step; 0 .. steps) {
            update(gradientSum(train, pvs));
        }

        savePP(ppPath);
        writefln("iteration %d  J %.1f  match %.4f  (%.0f sec)",
            iteration, js.sum, matchRate(test), sw.peek.total!"msecs" / 1000.0);
        stdout.flush();
    }
    return 0;
}


/**
 * 学習用棋譜ファイルを読む
 * ファイルは1行1局で、CSA 形式の指し手を空白区切りで並べたもの
 */
private Record[] readRecords(string path)
{
    Record[] records;
    int games = 0;
    int skipped = 0;
    foreach (line; File(path).byLineCopy) {
        Record[] game;
        Position p = parsePosition(HIRATE);
        foreach (s; line.split) {
            Move m = toMove(s, p);
            if (m == Move.NULL) {
                game = null;
                break;
            }
            game ~= Record(p, m);
            p = p.doMove(m);
        }
        if (game is null) {
            skipped++;
            continue;
        }
        records ~= game;
        games++;
    }
    writefln("%s: %d games, %d positions (%d games skipped)", path, games, records.length, skipped);
    return records;
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
 * 読み筋を Move.NULL の手前までの配列にする
 */
private Move[] line(const ref Move[64] pv)
{
    long length = pv[].countUntil(Move.NULL);
    return pv[0 .. (length < 0 ? 64 : length)].dup;
}

/**
 * 探索段階
 * 棋譜の手は全幅、それ以外の手は窓 [v(m*) - window, v(m*) + window] で探索する
 * pvs には、棋譜の手の読み筋と、窓の中の手の読み筋が入る
 * returns: J への寄与
 */
private double searchRecord(const ref Record r, out Move[][] pvs, int window = WINDOW)
{
    Move[600] moves;
    int length = r.pos.legalMoves(moves);
    if (length <= 1) {
        return 0;
    }

    Move[64] pv;
    int record = searchMove(r.pos, r.move, -INF, INF, pv);
    pvs ~= line(pv);

    double j = 0;
    foreach (Move move; moves[0 .. length]) {
        if (move == r.move) {
            continue;
        }
        int x = clamp(searchMove(r.pos, move, record - window, record + window, pv) - record, -WINDOW, WINDOW);
        j += t(x);
        if (abs(x) < WINDOW) {
            pvs ~= line(pv);
        }
    }
    return j;
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
private void gradient(long[] grad, const ref Position p, const Move[][] pvs)
{
    if (pvs.length == 0) {
        return;
    }
    const long s = p.sideToMove == Color.BLACK ? 1 : -1;
    Position recordLeaf = leaf(p, pvs[0]);
    int record = leafValue(p, recordLeaf);

    long sum = 0;
    foreach (pv; pvs[1 .. $]) {
        Position l = leaf(p, pv);
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
 * 全局面の勾配を足し合わせる
 * スレッドごとに勾配を足してから、全スレッドの勾配を足す。整数の和なので、スレッド数によらず同じ結果になる
 */
private long[] gradientSum(const Record[] records, const Move[][][] pvs)
{
    auto grads = new long[][](POOL.size + 1, REP.length);
    foreach (i, ref r; POOL.parallel(records)) {
        gradient(grads[POOL.workerIndex], r.pos, pvs[i]);
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
private double matchRate(const Record[] records)
{
    auto matched = new bool[records.length];
    foreach (i, ref r; POOL.parallel(records)) {
        matched[i] = bestMove(r.pos) == r.move;
    }
    return cast(double)matched.count(true) / records.length;
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
        auto rnd = Random(2);
        Record[] records;
        foreach (g; 0 .. games) {
            Position p = parsePosition(HIRATE);
            foreach (ply; 0 .. plies) {
                Move[600] moves;
                int length = p.legalMoves(moves);
                Move m = moves[uniform(0, length, rnd)];
                Position q = p.doMove(m);
                if (q.piecesInHand[Color.BLACK][Type.KING] + q.piecesInHand[Color.WHITE][Type.KING] > 0) {
                    break;
                }
                records ~= Record(p, m);
                p = q;
            }
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
    Move[] l = line(pv);
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
        Move[][] pvs1, pvs2;
        double j1 = searchRecord(r, pvs1);
        double j2 = searchRecord(r, pvs2, INF);
        assert(j1 == j2);
        assert(pvs1 == pvs2);
        if (pvs1.length == 0) {
            continue;
        }
        // 保存した読み筋を再生した末端の評価値が、探索の評価値と一致する
        Move[64] pv;
        int record = searchMove(r.pos, r.move, -INF, INF, pv);
        Position q = leaf(r.pos, pvs1[0]);
        assert(leafValue(r.pos, q) == record);
        foreach (l; pvs1[1 .. $]) {
            int value = searchMove(r.pos, l[0], -INF, INF, pv);
            q = leaf(r.pos, l);
            assert(leafValue(r.pos, q) == value);
            assert(abs(value - record) < WINDOW);
        }
        stored += pvs1.length;
    }
    writefln("search: %d pvs stored", stored);
}

// 3.6 更新段階の勾配とスレッド並列化
unittest
{
    setRandom();
    makeGroups();
    Record[] records = randomRecords(5, 80);
    auto pvs = new Move[][][records.length];
    foreach (i, ref r; records) {
        searchRecord(r, pvs[i]);
    }
    POOL = new TaskPool(0);
    long[] g1 = gradientSum(records, pvs);
    POOL = new TaskPool(7);
    POOL.isDaemon = true;
    long[] g8 = gradientSum(records, pvs);
    writefln("gradient: %d nonzero groups", g1.count!(e => e != 0));
    assert(g1.any!(e => e != 0));
    assert(g1 == g8);
}
