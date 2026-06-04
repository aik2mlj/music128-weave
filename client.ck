@import "sounds/noteProvider.ck"
@import "sounds/bpm.ck"
@import "sounds/chords.ck"
@import "sounds/scales.ck"
@import "lib/gametrak.ck"
@import "lib/global.ck"
@import "lib/meshlines.ck"
@import "lib/lib.ck"
@import "sounds/thread.ck"
@import "sounds/thread_cut.ck"

Chords chords;
Scales scales;

// Globals
Global.gt @=> GameTrak @gt;

// one person can weave up to six threads (one hemi)
12 => int CHANNELS;
0 => int CHAN_OFFSET;

0.01 => float LINE_WIDTH;
// random color for each client
@(Math.random2f(0.2, 0.9), Math.random2f(0.2, 0.9), Math.random2f(0.2, 0.9)) => vec3 color;

-2 * 16 / 9 => float MIN_X;
2 * 16 / 9 => float MAX_X;
-2 => float MIN_Y;
2 => float MAX_Y;

// instantiate sound threads
Thread threads[CHANNELS];
ThreadCut threadCut;
float allLinePos[0];
int allLineDir[0];

0 => int threadNum;

for (0 => int i; i < CHANNELS; ++i) {
    threads[i].connect2dac(i);
}

1::second => now;


// cycle is synced with server
dur cycle;

// OscIn from clients
// create our OSC receiver
OscIn oin;
// create our OSC message
OscMsg msg;
// use port 6449 (or whatever)
36449 => oin.port;
// create an address in the receiver, expect an int and a float
oin.addAddress("/server/cycle");
oin.addAddress("/server/segs");
oin.addAddress("/server/chord");
oin.addAddress("/server/stage");
oin.addAddress("/server/cutlines");

"localhost" => string hostname;
0 => int ID;
if (me.args()) {
    me.arg(0) => Std.atoi => ID;
    me.arg(1) => hostname;
}
// OscOut to server
// destination port number
36448 => int port;
// sender object
OscOut xmit;
// aim the transmitter at destination
xmit.dest(hostname, port);


@(0.820, 0.937, 0.980, 1) => vec4 textColor;
GText @currentInstruction;
null @=> currentInstruction;
GText @currentInstruction2;
null @=> currentInstruction2;

fun void addInstruction(string instruction) {
    if (currentInstruction != null)
        currentInstruction --< GG.scene();
    if (currentInstruction2 != null) {
        currentInstruction2 --< GG.scene();
        null @=> currentInstruction2;
    }
    GText text;
    text.size(0.2);
    text.text(instruction);
    text.color(textColor);
    text.pos(@(0, 0, 0));
    text --> GG.scene();
    text @=> currentInstruction;
}

// multiple line version
fun void addInstruction(string line1, string line2) {
    if (currentInstruction != null)
        currentInstruction --< GG.scene();
    if (currentInstruction2 != null)
        currentInstruction2 --< GG.scene();
    GText text1;
    text1.size(0.15);
    text1.text(line1);
    text1.color(textColor);
    text1.pos(@(0, 0.15, 0));
    text1 --> GG.scene();
    text1 @=> currentInstruction;

    GText text2;
    text2.size(0.15);
    text2.text(line2);
    text2.color(textColor);
    text2.pos(@(0, -0.15, 0));
    text2 --> GG.scene();
    text2 @=> currentInstruction2;
}

// initiate
if (ID == 0) {
    addInstruction("Slowly, intentionally", "Draw 5 horizontal threads");
} else if (ID >= 1 && ID <= 4) {
    addInstruction("No action right now. Just know that",
                   "left-tether for horizontal thread, right for vertical, y-axis for pitch");
}


0 => int STEP;
0 => int STAGE;
0 => int CUTCOUNT;

fun void serverListener() {
    while (true) {
        oin => now;

        while (oin.recv(msg)) {
            // chout <= "received message: " <= msg.address <= IO.newline();
            if (msg.address == "/server/cycle") {
                if (msg.typetag == "f") {
                    if (msg.getFloat(0)::second != cycle) {
                        msg.getFloat(0)::second => cycle;
                        // update cycle
                        <<< "cycle updated:", cycle / second, "s" >>>;
                    }
                }
            } else if (msg.address == "/server/stage") {
                msg.getInt(0) => int stage;
                // new not equal to old
                if (stage != STAGE) {
                    if (stage == 1) {
                        if (ID == 0) {
                            addInstruction("Again, slowly, intentionally",
                                           "Draw 5 horizontal threads");
                        } else if (ID == 1) {
                            addInstruction(
                                "Wait til drawer 0 is done with her five lines",
                                "Then slowly, draw 3 vertical threads at different pitches");
                        } else {
                            addInstruction("Wait");
                        }
                    }

                    else if (stage == 2) {
                        if (ID == 0 || ID == 2 || ID == 4) {
                            addInstruction(
                                "About every 3 seconds, draw one horizontal thread",
                                "Try placing each at a different pitch; draw with intention");
                        } else {
                            addInstruction(
                                "About every 3 seconds, draw one vertical thread",
                                "Try to placing each at a different pitch; draw with intention");
                        }
                    }

                    else if (stage == 3) {
                        addInstruction("Slowly release your tether ; Then kneel down with one knee",
                                       "No further action is needed");
                    }

                    else if (stage == 4) {
                        for (0 => int i; i < CHANNELS; i++) {
                            spork ~ threads[i].fadeout(25::second);
                        }
                    }

                    stage => STAGE;
                }


            } else if (msg.address == "/server/chord") {
                msg.getInt(0) => int step;
                if (step != STEP) {
                    msg.getInt(1) => int randomRot;
                    // randomRot == pitchBend
                    if (step == 0)
                        chordChanger(chords.b_maj9, randomRot);
                    else if (step == 1)
                        chordChanger(chords.fsharp_maj9, randomRot);
                    else if (step == 2)
                        chordChanger(chords.csharp_maj7, randomRot);
                    else if (step == 3)
                        chordChanger(chords.aflat_sus2, randomRot);
                    else if (step == 4)
                        chordChanger(chords.bflat_9sus4, randomRot);
                    else if (step == 5)
                        chordChanger(chords.chordInverter(chords.bflat_9sus4, 2, 0), randomRot);
                    else if (step == 6)
                        chordChanger(chords.chordInverter(chords.bflat_9sus4, 1, 0), randomRot);
                    step => STEP;
                }
            } else if (msg.address == "/server/segs") {
                // reconstruct the array from however many args came in
                msg.getInt(0) => int numX;
                msg.getInt(1) => int numY;
                dur segXs[numX];
                dur segYs[numY];
                for (int n; n < numX; n++)
                    msg.getFloat(2 + n) * 1::samp => segXs[n];
                for (int n; n < numY; n++)
                    msg.getFloat(2 + numX + n) * 1::samp => segYs[n];
                <<< "received segs: ", segXs.size(), segYs.size() >>>;
                // <<< "segXs:" >>>;
                // for (int n; n < numX; ++n)
                //     <<< "\t", segXs[n] / 1::samp >>>;
                // <<< "segYs:" >>>;
                // for (int n; n < numY; ++n)
                //     <<< "\t", segYs[n] / 1::samp >>>;
                updateExistingRhythms(segXs, segYs);
            } else if (msg.address == "/server/cutlines") {
                msg.getInt(0) => int cutCount;
                if (cutCount != CUTCOUNT) {
                    cutCount => CUTCOUNT;
                    msg.getInt(1) => int size;
                    int ids[size], idxs[size];
                    for (int i; i < size; ++i) {
                        msg.getInt(2 + i * 2) => ids[i];
                        msg.getInt(2 + i * 2 + 1) => idxs[i];
                        // cut Thread sound here if id matches this client
                        if (ids[i] == ID) {
                            cutThread(idxs[i]);
                        }
                    }
                }
            }
        }
    }
}
spork ~ serverListener();

/// ---------- RHYTHM ---------- /////

fun void updateExistingRhythms(dur segXs[], dur segYs[]) {
    <<< "updateExistingRhythms" >>>;
    for (0 => int i; i < CHANNELS; i++) {
        if (!threads[i].isOn())
            continue;

        if (threads[i].rhythmShred != null)
            threads[i].rhythmShred.exit();
        // TODO: check direction
        if (threads[i].direction == 0)
            spork ~ threads[i].rhythmicPause(segXs) @=> threads[i].rhythmShred;
        else
            spork ~ threads[i].rhythmicPause(segYs) @=> threads[i].rhythmShred;
    }
}

fun void cutThread(int idx) {
    // this idx is the index in allLinePos etc.
    // so need to iterate threads to see if if any of them have this idx
    NP.getNote(Math.randomf()) => int targetNote;
    threadCut.cut(targetNote);
    for (0 => int i; i < CHANNELS; i++) {
        if (threads[i].idx == idx && threads[i].isOn()) {
            threads[i].off();
            <<< "cut thread", idx >>>;
        }
    }
}

// fun void cutThread(int direction) {
//     int targetNote;
//     if (direction == 0)
//         provider.getNote(gt.axis[5]) => targetNote;
//     else if (direction == 1)
//         provider.getNote(gt.axis[2]) => targetNote;
//
//     1000 => int minDiff;
//     -1 => int minN;
//     // get the thread that is closest to the target note
//     for (0 => int i; i < CHANNELS; i++) {
//         if (threads[i].isOn() && threads[i].direction == direction) {
//             if (Math.abs(provider.getNote(threads[i].pos) - targetNote) < minDiff) {
//                 Math.abs(provider.getNote(threads[i].pos) - targetNote) => minDiff;
//                 i => minN;
//             }
//         }
//     }
//     if (minN >= 0) {
//         threads[minN].off();
//         threadCut.cut(targetNote);
//         1 => allCuts[threads[minN].idx];
//         // send to server which line to cut
//         sendCutLine(threads[minN].idx, direction);
//     } else {
//         1000 => minDiff;
//         -1 => minN;
//         // then find the closest line from allLinePos
//         for (0 => int i; i < allLinePos.size(); ++i) {
//             if (allCuts[i] == 0 && allLineDir[i] == direction) {
//                 allLinePos[i] => float pos;
//                 if (Math.abs(provider.getNote(pos) - targetNote) < minDiff) {
//                     Math.abs(provider.getNote(pos) - targetNote) => minDiff;
//                     i => minN;
//                 }
//             }
//         }
//         if (minN >= 0) {
//             1 => allCuts[minN];
//             threadCut.cut(targetNote);
//             // send to server which line to cut
//             sendCutLine(minN, direction);
//         }
//     }
// }


fun void addThread(int direction) { addThread(direction, 0); }

fun void addThread(int direction, int prepopulate) {
    <<< "addthread" >>>;
    threads[threadNum++ % CHANNELS] @=> Thread thread;

    if (thread.isOn()) {
        thread.off();
    }

    float pos; // pos to be stored and thus can be reinterpreted during chord change
    int note;

    // gt axis[2] and [5] are for pitch right now

    if (direction == 0) { // horizontal
        (gt.axis[1] + 1) / 2 => pos;
        thread.init(TriOsc osc);
    } else { // vertical
        (gt.axis[4] + 1) / 2 => pos;
        thread.init(SawOsc osc);
    }

    pos => thread.pos;
    direction => thread.direction;
    if (prepopulate) {
        // grey color
        Math.random2f(0.3, 2) * @(0.1, 0.1, 0.1) => thread.color;
    } else {
        color => thread.color;
    }
    threadNum - 1 => thread.idx;

    allLinePos << pos;
    allLineDir << direction;

    NP.getNote(pos) => note;

    // convert it to freq, starting from C
    // thread.freq(Std.mtof(48 + note));

    thread.on();
    thread.set_target_pitch(0.5, note);

    sendAddLine(thread);

    // updateExistingRhythms();
}


fun void sendAddLine(Thread @thread) {
    // send an OSC message to the server
    // ID, direction, pos, color
    <<< "sendAddline" >>>;
    xmit.start("/client/addline");
    ID => xmit.add;
    thread.direction => xmit.add;
    thread.pos => xmit.add;
    thread.color.x => xmit.add;
    thread.color.y => xmit.add;
    thread.color.z => xmit.add;
    xmit.send();
}


/// ---------- CHORD ---------- /////
// for changing the entire chord/ scale scope

fun void chordChanger(int input[], int pitchBend) {
    NP.notes @=> int oldNotes[]; // save it！
    input @=> NP.notes;

    // sonically
    for (0 => int i; i < CHANNELS; i++) {
        if (threads[i].isOn()) {
            // update the frequency
            NP.getNote(threads[i].pos) => int note;
            // threads[i].freq(Std.mtof(48 + note));

            if (pitchBend) {
                threads[i].set_target_pitch(note);
            } else {
                threads[i].set_target_pitch(0.5, note);
            }
        }
    }

    // visually, shift each line by its chord-tone delta
    for (0 => int i; i < allLinePos.size(); i++) {
        // get old slot position
        Math.round(allLinePos[i] * oldNotes.size()) $ int => int idx;

        // aka index 4 now should be index 3, if old chord has 5 notes, new has 4 notes
        if (idx >= input.size())
            input.size() - 1 => idx;

        if (idx >= oldNotes.size())
            oldNotes.size() - 1 => idx;


        input[idx] - oldNotes[idx] => int semitoneShift;
        // 12 semitones within one octave => compute the pos shift within this full range
        semitoneShift * 1.0 / (NP.octaves * 12) => float posShift;

        allLinePos[i] + posShift => float newPos;

        // clamp
        Math.max(0.0, Math.min(1.0, newPos)) => newPos;

        newPos => allLinePos[i];
    }
    sendLinePos(allLineDir, allLinePos);
}

fun void sendLinePos(int allLineDir[], float allLinePos[]) {
    xmit.start("/client/linepos");
    ID => xmit.add;
    allLinePos.size() => xmit.add;
    for (0 => int i; i < allLinePos.size(); ++i) {
        allLineDir[i] => xmit.add;
        allLinePos[i] => xmit.add;
    }
    xmit.send();
}


// for adding new chord on the context of existing chord(s)
fun void chordAdder(int input[]) { input @=> NP.notes; }

// need to sendAddLine
fun void drawHandler() {

    0.002 => float DEADZONE;

    int hSlot;
    int vSlot;

    int wasMovingH;
    int wasMovingV;


    while (true) {
        1::ms => now;

        // Horizontal thread (axis[2])
        // which includes it being deltaH is positive
        if (gt.vel[2] > DEADZONE && !wasMovingH && !gt.buttonHeldDown) {
            1 => wasMovingH;
            threadNum % CHANNELS => hSlot; // record slot for turning off again
            addThread(0);
        } else if (gt.vel[2] <= 0 && wasMovingH) {
            0 => wasMovingH;
        }

        if (gt.vel[5] > DEADZONE && !wasMovingV && !gt.buttonHeldDown) {
            1 => wasMovingV;
            threadNum % CHANNELS => vSlot;
            addThread(1);
        } else if (gt.vel[5] <= 0 && wasMovingV) {
            0 => wasMovingV;
        }
    }
}


spork ~ drawHandler();


fun void keyboardHandler() {
    while (true) {
        GG.nextFrame() => now;
        if (UI.isKeyPressed(UI_Key.A, false)) {
            // fake a thread pos
            Math.randomf() * 2 - 1 => gt.axis[1];
            addThread(0);
        } else if (UI.isKeyPressed(UI_Key.S, false)) {
            // fake a thread pos
            Math.randomf() * 2 - 1 => gt.axis[4];
            addThread(1);
        } else if (UI.isKeyPressed(UI_Key.Enter, false)) {
            1 => gt.buttonPressed;
            gt.buttonPress.broadcast();
            10::ms => now;
            0 => gt.buttonPressed;
        }
    }
}
spork ~ keyboardHandler();

fun void print() {
    while (true) {
        <<< "axes:", gt.axis[0], gt.axis[1], gt.axis[2], gt.axis[3], gt.axis[4], gt.axis[5] >>>;
        100::ms => now;
    }
}
// spork ~ print();


fun void prePopulate(int numLines) {
    for (0 => int i; i < numLines; i++) {
        Math.randomf() * 2 - 1 => gt.axis[1];
        Math.randomf() * 2 - 1 => gt.axis[4];
        addThread(Math.random2(0, 1), 1);
        10::ms => now;
    }
}

// each prepopulates 5 horizontal for now
// prePopulate(10);


// main loop
while (true) {
    GG.nextFrame() => now;
}
