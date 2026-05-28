public class ThreadCut {
    StifKarp karp => ADSR karpEnv => NRev karpRev => dac;

    fun void cut(int inputNote) {
        karpRev.gain(0.5);
        karpRev.mix(0.2);
        Math.random2f(0, 1) => karp.pickupPosition;
        Math.random2f(0, 0.5) => karp.sustain;
        Math.random2f(0, 1) => karp.stretch;
        karpEnv.keyOn();
        karpEnv.gain(1.0);

        Std.mtof(inputNote) => karp.freq;
        Math.random2f(0.8, 1.0) => karp.pluck;
    }
}
