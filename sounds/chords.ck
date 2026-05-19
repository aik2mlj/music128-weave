public class Chords {
    // you will realize that counting keyboard from 0 (root) to 3 results in the minor 3rd

    // all chords within c_minorScale
    [0, 3, 7] @=> static int c_minor[];
    [2, 5, 8]  @=> static int d_dim[];
    [3, 7, 10] @=> static int eb_major[];
    [5, 8, 12] @=> static int f_minor[];
    [7, 10, 14] @=> static int g_minor[];
    [8, 12, 15] @=> static int ab_major[];
    [10, 14, 17] @=> static int bb_major[];
 
    // all chords within c_majorScale
    [0, 4, 7] @=> static int c_major[];
    [2, 5, 9]  @=> static int d_minor[]; 
    [4, 7, 11] @=> static int e_minor[];
    [5, 9, 12] @=> static int f_major[];
    [7, 11, 14] @=> static int g_major[];
    [9, 12, 16] @=> static int a_minor[];
    [11, 14, 17] @=> static int b_dim[];

    // additional sdm chords
    [1, 5, 8] @=> static int db_major[];


    [0, 5, 7] @=> static int c_sus4[];
    [0, 2, 7] @=> static int c_sus2[];
    [0, 4, 7, 10] @=> static int c_dom7[];
    [0, 4, 7, 11] @=> static int c_maj7[];
    [0, 3, 7, 10] @=> static int c_min7[];
    [0, 5, 7, 10] @=> static int c_sus47[];
    [0, 3, 7, 13] @=> static int c_min79[];

}
