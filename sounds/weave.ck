@import "noteProvider.ck"
@import "bpm.ck"
@import "chords.ck"
@import "scales.ck"
@import "../lib/gametrak.ck"
@import "../lib/global.ck"
@import "thread.ck"

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


// one person can weave up to six threads (one hemi)
6 => int CHANNELS;
0 => int CHAN_OFFSET;

0.01 => float LINE_WIDTH;
@(0.2, 0.2, 0.2) => vec3 LINE_COLOR;

-2 * 16 / 9 => float MIN_X;
2 * 16 / 9 => float MAX_X;
-2 => float MIN_Y;
2 => float MAX_Y;
fun float gt2x(float gt) { return Math.map2(gt, 0., 1., MIN_X, MAX_X); }
fun float gt2y(float gt) { return Math.map2(gt, 0., 1., MIN_Y, MAX_Y); }


// instantiate sound threads
Thread threads[CHANNELS];

for (0 => int i; i < CHANNELS; ++i) {
    threads[i].connect2dac(i);
    threads[i].init(SinOsc sin);
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


fun addLine(int direction, Thread @thread) {
    GLines line --> GG.scene();

    line.color(LINE_COLOR);
    line.width(LINE_WIDTH);

    if (direction == 0) {
        line.posY(gt2y(gt.axis[2]));
    } else {
        line.posX(gt2x(gt.axis[5]));
    }

    spork ~ drawLine(direction, line);
    spork ~ animate(line) @=> Shred @animateShred;
    animateShred @=> thread.animateShred;
}

fun void drawLine(int direction, GLines @line) {
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

fun void animate(GLines @line) {
    now => time t0;
    1 => float speed;
    0.2 => float dcolor;
    while (true) {
        GG.nextFrame() => now;
        (now - t0) / 1::second => float t;
        <<< t >>>;
        Math.sin(t * speed * 5) => float inc;
        LINE_WIDTH + inc * 0.005 => line.width;
        @(LINE_COLOR.x + (inc + Math.randomf()) * dcolor,
          LINE_COLOR.y + (inc + Math.randomf()) * dcolor,
          LINE_COLOR.z + (inc + Math.randomf()) * dcolor) => line.color;
    }
}

fun void addThread(int direction) {
    threads[threadNum++ % CHANNELS] @=> Thread thread;
    if (thread.isOn()) {
        thread.off();
    }

    float pos; // pos to be stored and thus can be reinterpreted during chord change
    int note;

    if (direction == 0) // horizontal
        gt.axis[2] => pos;
    else // vertical
        gt.axis[5] => pos;

    pos => thread.pos;

    provider.getNote(pos) => note;

    // convert it to freq, starting from C
    thread.freq(Std.mtof(48 + note));

    addLine(direction, thread);
    thread.on();
    <<< "thread added:", threadNum >>>;
}

// default chord
chords.c_major @=> provider.notes;

// for changing the entire chord/ scale scope
fun void chordChanger(int input[]) {
    input @=> provider.notes;

    // search for existing threads
    for (0 => int i; i < CHANNELS; i++) {
        if (threads[i].isOn()) {
            // update the frequency
            threads[i].freq(Std.mtof(48 + provider.getNote(threads[i].pos)));
        }
    }
}

// for adding new chord on the context of existing chord(s)
fun void chordAdder(int input[]) { input @=> provider.notes; }


fun void chordSequencer() {
    0 => int step;
    while (true) {
        if (gt.buttonPressed) {
            if (step == 0)
                chordChanger(chords.d_minor);
            else if (step == 1)
                chordAdder(chords.e_minor);
            else if (step == 2)
                chordChanger(chords.f_minor);

            // loop for now
            (step + 1) % 3 => step;
        }
        10::ms => now;
    }
}

spork ~ chordSequencer();


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
spork ~ print();


// main loop
while (true) {
    GG.nextFrame() => now;
}
