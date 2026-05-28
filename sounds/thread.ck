@import "bpm.ck"


public class Thread {

    // here osc means oscillator
    Osc @osc;

    BPM bpm;

    ADSR env => LPF lpf => Chorus chorus => NRev rev;
    lpf.set(800, 1);
    rev.gain(0.5);
    rev.mix(0.2);
    env.set(500::ms, 500::ms, 0.02, 10::ms);
    chorus.baseDelay(10::ms);
    chorus.modDepth(.4);
    chorus.modFreq(1);
    chorus.mix(.2);

    Shred @animateShred;
    Shred @rhythmShred;

    int direction; // 0 = horizontal, 1 = vertical
    float pos;     // store the x (for vertical) and y (for horizontal)
    vec3 color;

    int idx;
    0 => int is_on;

    fun void init(Osc timbre) {
        timbre @=> osc;
        osc => env;
        osc.gain(0.5);
    }

    // using this to help with pitch bend
    Envelope pitch => blackhole;
    0 => pitch.value;


    Shred @pitchShred;

    float targetPitch;

    // this is the slight pitchBend with a bit detune
    fun void set_target_pitch(float bendSemitone, int inputNote) {
        inputNote $ float => pitch.target => targetPitch;
        // current, from below
        (inputNote - bendSemitone) $ float => pitch.value;
        1::second => pitch.duration;

        pitch.keyOn();

        if (pitchShred != null)
            pitchShred.exit();

        spork ~ pitchBend() @=> pitchShred;
    }

    // this is the huge pitchBend from the last pitch
    fun void set_target_pitch(int inputNote) {
        pitch.target() => float initPitch;
        inputNote $ float => pitch.target => targetPitch;
        // current, from below
        initPitch $ float => pitch.value;
        2::second => pitch.duration;

        pitch.keyOn();

        if (pitchShred != null)
            pitchShred.exit();

        spork ~ pitchBend() @=> pitchShred;
    }


    fun void pitchBend() {
        now => time start;
        while (now - start < pitch.duration()) {
            osc.freq(Std.mtof(48 + pitch.value()));
            5::ms => now;
        }
        osc.freq(Std.mtof(48 + targetPitch));
    }


    fun void connect2dac(int chan) { rev => dac.chan(chan % dac.channels()); }

    //    fun void connect2dac(int chan) { rev => dac.chan(chan); }

    fun float gain() { return osc.gain(); }
    fun void gain(float g) { osc.gain(g); }

    fun float freq() { return osc.freq(); }
    fun void freq(float f) { osc.freq(f); }

    fun void on() {
        env.keyOn();
        1 => is_on;
    }

    fun int isOn() { return is_on; }

    fun void off() {
        env.keyOff();
        0 => is_on;
        if (animateShred != null) {
            animateShred.exit();
            null @=> animateShred;
        }
        if (rhythmShred != null) {
            rhythmShred.exit();
            null @=> rhythmShred;
        }
    }

    fun void rhythmicPause(dur segments[]) {
        if (segments.size() <= 1) {
            // env.keyOn();
            return;
        }
        while (true) {
            for (0 => int i; i < segments.size(); i++) {
                env.keyOn();
                segments[i] => now;
                env.keyOff();
                100::ms => now;
            }
        }
    }
}
