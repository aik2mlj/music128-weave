public class Chords {
    // you will realize that counting keyboard from 0 (root) to 3 results in the minor 3rd

    // all chords within c_minorScale
    [0, 3, 7] @=> static int c_minor[];
    [2, 5, 8] @=> static int d_dim[];
    [3, 7, 10] @=> static int eb_major[];
    [5, 8, 12] @=> static int f_minor[];
    [7, 10, 14] @=> static int g_minor[];
    [8, 12, 15] @=> static int ab_major[];
    [10, 14, 17] @=> static int bb_major[];

    // all chords within c_majorScale
    [0, 4, 7] @=> static int c_major[];
    [2, 5, 9] @=> static int d_minor[];
    [4, 7, 11] @=> static int e_minor[];
    [5, 9, 12] @=> static int f_major[];
    [7, 11, 14] @=> static int g_major[];
    [9, 12, 16] @=> static int a_minor[];
    [11, 14, 17] @=> static int b_dim[];


    // addiitonal fancier chords
    [-1, 6, 10, 13, 15] @=> static int b_maj9[];
    [-6, 1, 8, 10, 5] @=> static int fsharp_maj9[];
    [1, 4, 8, 11] @=> static int csharp_maj7[];
    [-4, 3, 7, 10] @=> static int aflat_sus2[]; // Ab Eb G
    [-3, 2, 4, 10] @=> static int a_add4[];     // A D E G
    [-2, 3, 5, 8] @=> static int bflat_9sus4[];

    // additional sdm chords


    [1, 5, 8] @=> static int db_major[];


    [0, 5, 7] @=> static int c_sus4[];
    [0, 2, 7] @=> static int c_sus2[];
    [0, 4, 7, 10] @=> static int c_dom7[];
    [0, 4, 7, 11] @=> static int c_maj7[];
    [0, 3, 7, 10] @=> static int c_min7[];
    [0, 5, 7, 10] @=> static int c_sus47[];
    [0, 3, 7, 13] @=> static int c_min79[];


    fun int[] chordInverter(int input[], int inversion, int dir) {
        input.size() => int n;
        int result[n];

        for (0 => int i; i < n; i++)
            input[i] => result[i];

        if (inversion == 0)
            return result;

        // if invertion downward
        if (dir == 0) {
            // if triad, if inversion ==1, drop indice 1 & 2
            for (inversion => int i; i < n; i++)
                result[i] - 12 => result[i];
        } else if (dir == 1) { // upward
            for (0 => int i; i < inversion; i++)
                result[i] + 12 => result[i];
        }

        // insertion sort
        for (1 => int i; i < n; i++) {
            result[i] => int key;
            i - 1 => int j;
            while (j >= 0 && result[j] > key) {
                result[j] => result[j + 1];
                j--;
            }
            key => result[j + 1];
        }

        return result;
    }
}
