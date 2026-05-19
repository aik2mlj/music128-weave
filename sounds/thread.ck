@import "bpm.ck"


public class Thread {

    // here osc means oscillator
    Osc @osc;

    BPM bpm;

    ADSR env => LPF lpf => NRev rev;
    lpf.set(800, 1);
    rev.gain(0.5);
    rev.mix(0.1);
    env.set(300::ms, 500::ms, 0.2, 400::ms);

    Shred @animateShred;

    float pos;

    fun void init(Osc timbre) {
        timbre @=> osc;
        osc => env;
        osc.gain(0.5);
    }


    fun void connect2dac(int chan) { rev => dac.chan(chan % dac.channels()); }

    //    fun void connect2dac(int chan) { rev => dac.chan(chan); }

    fun float gain() { return osc.gain(); }
    fun void gain(float g) { osc.gain(g); }

    fun float freq() { return osc.freq(); }
    fun void freq(float f) { osc.freq(f); }

    fun void on() { env.keyOn(); }
    fun int isOn() { return env.value() > 0.; }
    fun void off() {
        env.keyOff();
        if (animateShred != null)
            animateShred.exit();
    }

    // using LFO maybe a smarter way
    // but then also how do you control the rate?
    fun void rhythmicPause(dur length) {
        while (true) {
            env.keyOn();
            length => now;
            env.keyOff();
            length => now;
        }
    }
}
