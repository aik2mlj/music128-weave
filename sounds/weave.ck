@import "noteProvider.ck"
@import "bpm.ck"
@import "chords.ck"
@import "scales.ck"
@import "../lib/gametrak.ck"
@import "../lib/global.ck"

GWindow.title("weave");
// GWindow.windowed(1280, 960);
// GWindow.center();
GWindow.fullscreen();

NoteProvider provider;
BPM bpm;
Chords chords;
Scales scales;

// Globals
Global.gt @=> GameTrak @gt;

scales.majorScale @=> provider.notes;

// one person can weave up to six threads (one hemi)
6 => int CHANNELS;
0 => int CHAN_OFFSET;

-2 * 16 / 9 => float MIN_X;
2 * 16 / 9 => float MAX_X;
-2 => float MIN_Y;
2 => float MAX_Y;
fun float gt2x(float gt) { return Math.map2(gt, 0., 1., MIN_X, MAX_X); }
fun float gt2y(float gt) { return Math.map2(gt, 0., 1., MIN_Y, MAX_Y); }

class Thread {
    TriOsc osc => ADSR env => LPF lpf => NRev rev;
    osc.gain(0.5);
    lpf.set(800, 1);
    rev.gain(0.5);
    rev.mix(0.1);
    env.set(300::ms, 500::ms, 0.2, 400::ms);

    fun void connect2dac(int chan) { rev => dac.chan(chan); }

    fun float gain() { return osc.gain(); }
    fun void gain(float g) { osc.gain(g); }

    fun float freq() { return osc.freq(); }
    fun void freq(float f) { osc.freq(f); }

    fun void on() { env.keyOn(); }
    fun int isOn() { return env.value() > 0.; }
    fun void off() { env.keyOff(); }
}

Thread threads[CHANNELS];
for (0 => int i; i < CHANNELS; ++i) {
    threads[i].connect2dac(i);
}

1::second => now;

// 0: left handle's x
// 1: left handle's y
// 2: left handle's z
// 3: right handle's x
// 4: right handle's y
// 5: right handle's z


public class State {
    0 => static int NONE;
    1 => static int LEFT;
    2 => static int RIGHT;
    3 => static int CENTER;
}

State.NONE => int stateX;
State.NONE => int stateY;

// the state within this round of weaving.
// 0 = none, 1 = left seen, 2 = center seen, 3 = right seen
0 => int roundStage;
0 => int threadNum;


fun addLine(int direction) {
    GLines line --> GG.scene();
    line.color(Color.WHITE);
    line.width(0.01);

    if (direction == 0) {
        line.posY(gt2y(gt.axis[2]));
    } else {
        line.posX(gt2x(gt.axis[5]));
    }

    now => time start;
    0.5::second => dur transTime;
    while (now - start < transTime) {
        GG.nextFrame() => now;
        (now - start) / transTime => float t;
        if (direction == 0) {
            line.positions([@(5, 0), @(5 - t * 10, 0)]);
        } else {
            line.positions([@(0, 5), @(0, 5 - t * 10)]);
        }
    }
}

fun void addThread(int direction) {
    threads[threadNum++ % CHANNELS] @=> Thread thread;
    if (thread.isOn())
        thread.off();

    int note;
    if (direction == 0)
        provider.getNote(gt.axis[2]) => note;
    else
        provider.getNote(gt.axis[5]) => note;
    // convert it to freq, starting from C
    Std.mtof(48 + note) => float freq;

    thread.freq(freq);

    spork ~ addLine(direction);
    thread.on();
    <<< "thread added:", threadNum >>>;
}

fun void stateHandler() {
    while (true) {
        // X
        State.NONE => int newState;
        if (gt.axis[0] < -0.05)
            State.LEFT => newState;
        else if (gt.axis[0] > 0.05)
            State.RIGHT => newState;
        else
            State.CENTER => newState;

        // only act on state transitions
        if (newState != stateX) {
            newState => stateX;

            if (stateX == State.LEFT && roundStage == 0)
                1 => roundStage;
            else if (stateX == State.CENTER && roundStage == 1)
                2 => roundStage;
            else if (stateX == State.RIGHT && roundStage == 2)
                3 => roundStage;
            else if (stateX == State.CENTER && roundStage == 3) {
                addThread(0);
                0 => roundStage;
            }
        }

        // Y
        State.NONE => newState;
        if (gt.axis[4] < -0.05)
            State.LEFT => newState;
        else if (gt.axis[4] > 0.05)
            State.RIGHT => newState;
        else
            State.CENTER => newState;

        // only act on state transitions
        if (newState != stateY) {
            newState => stateY;

            if (stateY == State.LEFT && roundStage == 0)
                1 => roundStage;
            else if (stateY == State.CENTER && roundStage == 1)
                2 => roundStage;
            else if (stateY == State.RIGHT && roundStage == 2)
                3 => roundStage;
            else if (stateY == State.CENTER && roundStage == 3) {
                addThread(1);
                0 => roundStage;
            }
        }

        10::ms => now;
    }
}
spork ~ stateHandler();


fun void print() {
    while (true) {
        <<< "axes:", gt.axis[0], gt.axis[1], gt.axis[2], gt.axis[3], gt.axis[4], gt.axis[5] >>>;
        100::ms => now;
    }
}
// spork ~ print();


// main loop
while (true) {
    GG.nextFrame() => now;
}
