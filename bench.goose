// The benchmark mode: it times a block of code.
namespace testkit;

import std;
import os;

// The most iterations a benchmark runs. A count above it is a fault.
const MAX_BENCH_ITERS: i64 = 1000000;

// bench times the block. It calls the block once for each iteration,
// with the index of the iteration. It prints the name, the count of
// the iterations and the nanoseconds of one iteration, and it gives
// that number to the caller.
//
// A benchmark is not a test. It does not count in the totals of the
// suite. The run pattern leaves it out, as it leaves a test out.
fn bench<F>(t: T&, name: const u8[:], iters: i64) -> f64 {
    if iters < 1 || iters > MAX_BENCH_ITERS {
        print("testkit: the benchmark ", name, " takes a count of 1 to ", MAX_BENCH_ITERS, " iterations");
        abort("testkit: the count of the iterations of a benchmark is out of range");
    }
    if !matches(t.pat, name) { return 0.0; }
    let t0 = clock_ns();
    for i in iters { F(i); }
    let t1 = clock_ns();
    let total = (t1 - t0) as f64;
    let per = total / (iters as f64);
    print("bench: ", name, ": ", iters, " iterations, ", per, " ns/op");
    return per;
}
