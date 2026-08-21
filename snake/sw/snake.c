// ============================================================================
// snake.c -- Snake for the SCR1 SoC (VGA tile grid + PS/2 WASD).  Phase 4.
//
// Field: 40x30 tile grid.  Row 0 = white score bar. Rows 1..29 framed by walls,
// interior play area is x in [1,38], y in [2,28].  Controls: WASD.  On death:
// flash + UART "GAME OVER", press any key to restart.
//
// Build: snake/sw/Makefile  (MEM=tcm, rv32im, picolibc). Load via XMODEM.
// ============================================================================
#include "snake_hw.h"
#include "sc_print.h"

// ---- play area bounds ----
#define X_MIN 1
#define X_MAX (GRID_W - 2)   // 38
#define Y_MIN 2
#define Y_MAX (GRID_H - 2)   // 28
#define SCORE_ROW 0

#define MAX_LEN 512
#define STEP_CYCLES 4500000u  // ~150 ms @30 MHz between moves

// ---- simple LCG rng ----
static uint32_t rng_state;
static inline uint32_t rng_next(void) {
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state;
}

// ---- snake state ----
static uint8_t occ[GRID_W][GRID_H];       // occupancy (1 = body)
static int16_t sx[MAX_LEN], sy[MAX_LEN];  // ring buffer of body cells
static int head, tail, length;            // ring indices / count
static int dir_x, dir_y;                  // current direction
static int ax, ay;                        // apple
static int score;

static void busy_wait(uint32_t cycles) {
    uint32_t t0 = rdcycle();
    while ((rdcycle() - t0) < cycles) { /* spin */ }
}

static void draw_frame(void) {
    // clear whole grid to background
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            vga_cell(x, y, C_BG);
    // walls: rectangle around the play field (rows 1 and Y_MAX+1, cols 0/39)
    for (int x = 0; x < GRID_W; x++) {
        vga_cell(x, 1,          C_WALL);
        vga_cell(x, GRID_H - 1, C_WALL);
    }
    for (int y = 1; y < GRID_H; y++) {
        vga_cell(0,          y, C_WALL);
        vga_cell(GRID_W - 1, y, C_WALL);
    }
}

static void draw_score(void) {
    for (int x = 0; x < GRID_W; x++)
        vga_cell(x, SCORE_ROW, (x < score) ? C_TEXT : C_BG);
}

static void spawn_apple(void) {
    for (;;) {
        int x = X_MIN + (int)(rng_next() % (uint32_t)(X_MAX - X_MIN + 1));
        int y = Y_MIN + (int)(rng_next() % (uint32_t)(Y_MAX - Y_MIN + 1));
        if (!occ[x][y]) { ax = x; ay = y; break; }
    }
    vga_cell(ax, ay, C_APPLE);
}

static void snake_reset(void) {
    for (int x = 0; x < GRID_W; x++)
        for (int y = 0; y < GRID_H; y++)
            occ[x][y] = 0;
    head = tail = 0;
    length = 0;
    dir_x = 1; dir_y = 0;
    score = 0;

    draw_frame();
    draw_score();

    // start length 3 at centre, moving right
    int cx = GRID_W / 2, cy = GRID_H / 2;
    for (int i = 0; i < 3; i++) {
        int x = cx - 2 + i, y = cy;
        sx[head] = x; sy[head] = y;
        occ[x][y] = 1;
        vga_cell(x, y, (i == 2) ? C_HEAD : C_BODY);
        head = (head + 1) % MAX_LEN;
        length++;
    }
    head = (head - 1 + MAX_LEN) % MAX_LEN;  // head = index of last written cell

    spawn_apple();
}

// read all pending scancodes, update the pending direction (WASD, make codes)
static void poll_input(int *pdx, int *pdy) {
    static int skip_next = 0;   // set after 0xF0/0xE0 to drop the following code
    while (kbd_has_data()) {
        int c = kbd_pop();
        if (c == SC_BREAK || c == SC_EXT) { skip_next = 1; continue; }
        if (skip_next) { skip_next = 0; continue; }   // ignore released key code
        switch (c) {
            case SC_W: if (dir_y == 0) { *pdx = 0;  *pdy = -1; } break;
            case SC_S: if (dir_y == 0) { *pdx = 0;  *pdy =  1; } break;
            case SC_A: if (dir_x == 0) { *pdx = -1; *pdy =  0; } break;
            case SC_D: if (dir_x == 0) { *pdx =  1; *pdy =  0; } break;
            default: break;
        }
    }
}

static void wait_any_key(void) {
    // drain, then wait for a fresh make code
    while (kbd_has_data()) (void)kbd_pop();
    for (;;) {
        if (kbd_has_data()) {
            int c = kbd_pop();
            if (c != SC_BREAK && c != SC_EXT) break;
            if (kbd_has_data()) (void)kbd_pop();  // consume the code after prefix
        }
    }
}

static void game_over(void) {
    sc_printf("GAME OVER  score=%d\n", score);
    for (int f = 0; f < 4; f++) {                 // flash the field red/black
        uint32_t col = (f & 1) ? C_BG : C_APPLE;
        for (int y = Y_MIN - 1; y <= Y_MAX + 1; y++)
            for (int x = X_MIN - 1; x <= X_MAX + 1; x++)
                vga_cell(x, y, col);
        busy_wait(STEP_CYCLES);
    }
    wait_any_key();
}

int main(void) {
    sc_printf("SCR1 Snake: WASD to move\n");
    rng_state = rdcycle() | 1u;

    for (;;) {                       // one iteration = one full game
        snake_reset();

        for (;;) {                   // per-move loop
            busy_wait(STEP_CYCLES);
            poll_input(&dir_x, &dir_y);

            int hx = sx[head], hy = sy[head];
            int nx = hx + dir_x, ny = hy + dir_y;

            // wall collision (play field is X_MIN..X_MAX, Y_MIN..Y_MAX)
            if (nx < X_MIN || nx > X_MAX || ny < Y_MIN || ny > Y_MAX) break;

            int grow = (nx == ax && ny == ay);

            // self collision -- allowed to enter the tail cell if it will move
            if (occ[nx][ny]) {
                int tx = sx[tail], ty = sy[tail];
                if (!(!grow && nx == tx && ny == ty)) break;
            }

            // turn old head into body
            vga_cell(hx, hy, C_BODY);

            // advance head
            head = (head + 1) % MAX_LEN;
            sx[head] = nx; sy[head] = ny;
            occ[nx][ny] = 1;
            vga_cell(nx, ny, C_HEAD);

            if (grow) {
                length++;
                score++;
                draw_score();
                spawn_apple();
            } else {
                // erase tail
                int tx = sx[tail], ty = sy[tail];
                occ[tx][ty] = 0;
                vga_cell(tx, ty, C_BG);
                tail = (tail + 1) % MAX_LEN;
            }

            if (length >= MAX_LEN - 2) break;   // win / safety
        }

        game_over();
    }
    return 0;
}
