public class BPM {
    static dur myDuration[3];
    static dur quarterNote, eighthNote, sixteenthNote, sextupletNote, bar;

    // Derives standard musical durations from the supplied BPM value.
    fun void tempo(float beat) {
        // and it sets up the length in seconds for quarter, eighth, and sixteenth tuplets
        // accordingly SPB = second per beat
        60.0 / beat => float SPB;
        SPB::second => quarterNote;
        quarterNote / 2 => eighthNote;
        eighthNote / 2 => sixteenthNote;
        eighthNote / 3 => sextupletNote;
        quarterNote * 4 => bar;

        [quarterNote, eighthNote, sixteenthNote, sextupletNote] @=> myDuration;
    }
}
