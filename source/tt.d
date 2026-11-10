module tt;

import core.atomic;
import core.bitop : bsr;
import core.stdc.errno : errno;
import core.stdc.string : strerror;
import core.sys.posix.sys.mman;
import core.sys.linux.sys.mman : MAP_ANONYMOUS, MAP_POPULATE;
import std.format;
import std.stdint;
import std.stdio;
import std.string : fromStringz;
import types;

__gshared private TTEntry[] TT;
__gshared private size_t TT_MASK = 0;

/**
 * hashMb MiB に収まる最大の2のべき乗のエントリ数
 */
size_t ttEntriesFor(long hashMb)
{
    if (hashMb < 1) {
        throw new Exception(format("hash_mb must be positive: %d", hashMb));
    }
    const ulong maxEntries = (cast(ulong) hashMb << 20) / TTEntry.sizeof;
    if (maxEntries == 0) {
        throw new Exception(format("hash_mb is too small: %d", hashMb));
    }
    return cast(size_t) 1 << bsr(maxEntries);
}

/**
 * 置換表を確保する（1回だけ呼ぶ）
 */
void tt_init(long hashMb)
{
    if (TT.length != 0) {
        throw new Exception("tt_init called twice");
    }
    immutable size_t n = ttEntriesFor(hashMb);
    immutable size_t bytes = n * TTEntry.sizeof;
    // MAP_POPULATE でカーネルが mmap 時点で全ページをプリフォルト → 物理RAM を即時確保
    void* p = mmap(null, bytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
    if (p == MAP_FAILED) {
        throw new Exception(format("mmap failed for TT (%,d bytes): %s", bytes, strerror(errno).fromStringz));
    }
    TT = (cast(TTEntry*) p)[0 .. n];
    TT_MASK = n - 1;
}

unittest
{
    assert(ttEntriesFor(16) == 1 << 20);
    assert(ttEntriesFor(100) == 1 << 22);
    assert(ttEntriesFor(262144) == 1L << 34);
    assert(ttEntriesFor(1) == 1 << 16);
}

struct TTEntry
{
    uint64_t key;
    uint16_t move16;
}

Move tt_probe(uint64_t key)
{
    TTEntry e = TT[key & TT_MASK];
    if (e.key == key)
    {
        return cast(Move)(e.move16);
    }
    return cast(Move)(0);
}

void tt_store(uint64_t key, Move m)
{
    const long address = (key & TT_MASK);
    if (TT[address].key == 0 || TT[address].key == key)
    {
        TT[address] = TTEntry(key, m.i);
        return;
    }
}

/**
 * 例："TT: 33,554,432 entries, 268,435,456 bytes"
 */
string tt_info()
{
    return format("TT: %,d entries, %,d bytes", TT.length, TT.length * TTEntry.sizeof);
}
