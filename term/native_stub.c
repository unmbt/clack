/*
 * Minimal cross-platform UTF-8 TTY native stub for unmbt/clack.
 *
 * Adapted from battle-tested unmbt/moonset/cli/tty_native.c with:
 * - Windows WriteConsoleW UTF-8 output (no SetConsoleOutputCP pollution)
 * - Preservation of ENABLE_QUICK_EDIT_MODE / ENABLE_INSERT_MODE / ENABLE_EXTENDED_FLAGS
 * - ENABLE_VIRTUAL_TERMINAL_INPUT for cancellable async ReadConsoleW VT streams
 * - POSIX termios preserving OPOST
 * - Crash-safe atexit + Windows SetConsoleCtrlHandler cleanup closing
 *   Bracketed Paste (?2004l), DEC 2026 (?2026l), SGR reset, and cursor show (?25h)
 */

#include <stdint.h>
#include <stdlib.h>

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#include <stdio.h>

#ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
#define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
#endif
#ifndef ENABLE_INSERT_MODE
#define ENABLE_INSERT_MODE 0x0020
#endif
#ifndef ENABLE_QUICK_EDIT_MODE
#define ENABLE_QUICK_EDIT_MODE 0x0040
#endif
#ifndef ENABLE_EXTENDED_FLAGS
#define ENABLE_EXTENDED_FLAGS 0x0080
#endif
#ifndef ENABLE_VIRTUAL_TERMINAL_INPUT
#define ENABLE_VIRTUAL_TERMINAL_INPUT 0x0200
#endif

static int g_clack_raw_active = 0;
static int g_clack_atexit_registered = 0;
static int g_clack_ctrl_handler_registered = 0;
static DWORD g_clack_orig_in_mode = 0;
static DWORD g_clack_orig_out_mode = 0;

static void clack_tty_restore_atexit(void) {
  if (!g_clack_raw_active) return;
  HANDLE hIn = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hOut != INVALID_HANDLE_VALUE && hOut != NULL) {
    DWORD written = 0;
    const WCHAR reset_seq[] = L"\x1b[0m\x1b[?2004l\x1b[?25h\x1b[?2026l";
    WriteConsoleW(hOut, reset_seq,
                  (DWORD)(sizeof(reset_seq) / sizeof(WCHAR) - 1),
                  &written, NULL);
    SetConsoleMode(hOut, g_clack_orig_out_mode);
  }
  if (hIn != INVALID_HANDLE_VALUE && hIn != NULL) {
    DWORD restore_in = g_clack_orig_in_mode;
    if (restore_in & (ENABLE_QUICK_EDIT_MODE | ENABLE_INSERT_MODE)) {
      restore_in |= ENABLE_EXTENDED_FLAGS;
    }
    SetConsoleMode(hIn, restore_in);
  }
  g_clack_raw_active = 0;
}

static BOOL WINAPI clack_tty_ctrl_handler(DWORD ctrl_type) {
  (void)ctrl_type;
  clack_tty_restore_atexit();
  return FALSE;
}

int clack_tty_is_tty(void) {
  if (!_isatty(_fileno(stdin)) || !_isatty(_fileno(stdout))) {
    return 0;
  }
  HANDLE hIn = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hIn == INVALID_HANDLE_VALUE || hIn == NULL ||
      hOut == INVALID_HANDLE_VALUE || hOut == NULL) {
    return 0;
  }
  DWORD in_mode = 0, out_mode = 0;
  if (!GetConsoleMode(hIn, &in_mode) || !GetConsoleMode(hOut, &out_mode)) {
    return 0;
  }
  return 1;
}

int clack_tty_enter_raw(void) {
  if (g_clack_raw_active) return 0;
  HANDLE hIn = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hIn == INVALID_HANDLE_VALUE || hOut == INVALID_HANDLE_VALUE) return -1;
  if (!GetConsoleMode(hIn, &g_clack_orig_in_mode)) return -1;
  if (!GetConsoleMode(hOut, &g_clack_orig_out_mode)) return -1;

  DWORD new_out = g_clack_orig_out_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING |
                  ENABLE_PROCESSED_OUTPUT;
  SetConsoleMode(hOut, new_out);

  /*
   * Preserve QuickEdit/Insert/Extended flags so terminal mouse selection and
   * scrollback remain functional. Enable VT input so arrow keys, Shift+Tab,
   * and Bracketed Paste arrive as standard ANSI sequences via ReadConsoleW.
   */
  DWORD new_in = (g_clack_orig_in_mode &
                  ~(DWORD)(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT |
                           ENABLE_PROCESSED_INPUT | ENABLE_WINDOW_INPUT |
                           ENABLE_MOUSE_INPUT)) |
                 ENABLE_VIRTUAL_TERMINAL_INPUT;
  if (new_in & (ENABLE_QUICK_EDIT_MODE | ENABLE_INSERT_MODE)) {
    new_in |= ENABLE_EXTENDED_FLAGS;
  }
  if (!SetConsoleMode(hIn, new_in)) {
    /* Fallback for legacy consoles without ENABLE_VIRTUAL_TERMINAL_INPUT */
    new_in &= ~(DWORD)ENABLE_VIRTUAL_TERMINAL_INPUT;
    SetConsoleMode(hIn, new_in);
  }

  g_clack_raw_active = 1;
  if (!g_clack_atexit_registered) {
    atexit(clack_tty_restore_atexit);
    g_clack_atexit_registered = 1;
  }
  if (!g_clack_ctrl_handler_registered) {
    if (SetConsoleCtrlHandler(clack_tty_ctrl_handler, TRUE)) {
      g_clack_ctrl_handler_registered = 1;
    }
  }
  return 0;
}

int clack_tty_leave_raw(void) {
  clack_tty_restore_atexit();
  return 0;
}

int clack_tty_cols(void) {
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (hOut != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(hOut, &info)) {
    int cols = (int)(info.srWindow.Right - info.srWindow.Left + 1);
    if (cols > 0) return cols;
  }
  return 80;
}

int clack_tty_rows(void) {
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (hOut != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(hOut, &info)) {
    int rows = (int)(info.srWindow.Bottom - info.srWindow.Top + 1);
    if (rows > 0) return rows;
  }
  return 24;
}

void clack_tty_write_utf8(const uint8_t *buf, int len) {
  if (buf == NULL || len <= 0) return;
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hOut == INVALID_HANDLE_VALUE || hOut == NULL) return;
  DWORD mode = 0;
  if (GetConsoleMode(hOut, &mode)) {
    int wlen = MultiByteToWideChar(CP_UTF8, 0, (const char *)buf, len, NULL, 0);
    if (wlen > 0) {
      WCHAR stack_buf[512];
      WCHAR *wbuf = (wlen <= 512)
                        ? stack_buf
                        : (WCHAR *)malloc((size_t)wlen * sizeof(WCHAR));
      if (wbuf != NULL) {
        int converted =
            MultiByteToWideChar(CP_UTF8, 0, (const char *)buf, len, wbuf, wlen);
        if (converted > 0) {
          DWORD written = 0;
          WriteConsoleW(hOut, wbuf, (DWORD)converted, &written, NULL);
        }
        if (wbuf != stack_buf) free(wbuf);
        return;
      }
    }
  }
  DWORD written = 0;
  WriteFile(hOut, buf, (DWORD)len, &written, NULL);
}

#else /* POSIX */

#include <errno.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

static int g_clack_raw_active = 0;
static int g_clack_atexit_registered = 0;
static struct termios g_clack_orig_termios;

static void clack_tty_restore_atexit(void) {
  if (!g_clack_raw_active) return;
  const char reset_seq[] = "\x1b[0m\x1b[?2004l\x1b[?25h\x1b[?2026l";
  ssize_t ignored = write(STDOUT_FILENO, reset_seq, sizeof(reset_seq) - 1);
  (void)ignored;
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_clack_orig_termios);
  g_clack_raw_active = 0;
}

int clack_tty_is_tty(void) {
  return (isatty(STDIN_FILENO) && isatty(STDOUT_FILENO)) ? 1 : 0;
}

int clack_tty_enter_raw(void) {
  if (g_clack_raw_active) return 0;
  if (tcgetattr(STDIN_FILENO, &g_clack_orig_termios) != 0) return -1;
  struct termios raw = g_clack_orig_termios;
  raw.c_iflag &= ~(unsigned long)(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
  /* Preserve OPOST so '\n' translates cleanly when needed */
  raw.c_cflag |= (unsigned long)(CS8);
  raw.c_lflag &= ~(unsigned long)(ECHO | ICANON | IEXTEN | ISIG);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;
  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0) return -1;
  g_clack_raw_active = 1;
  if (!g_clack_atexit_registered) {
    atexit(clack_tty_restore_atexit);
    g_clack_atexit_registered = 1;
  }
  return 0;
}

int clack_tty_leave_raw(void) {
  clack_tty_restore_atexit();
  return 0;
}

int clack_tty_cols(void) {
  struct winsize ws;
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
    return (int)ws.ws_col;
  }
  return 80;
}

int clack_tty_rows(void) {
  struct winsize ws;
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0) {
    return (int)ws.ws_row;
  }
  return 24;
}

void clack_tty_write_utf8(const uint8_t *buf, int len) {
  if (buf == NULL || len <= 0) return;
  int offset = 0;
  while (offset < len) {
    ssize_t n = write(STDOUT_FILENO, buf + offset, (size_t)(len - offset));
    if (n < 0) {
      if (errno == EINTR) continue;
      break;
    }
    if (n == 0) break;
    offset += (int)n;
  }
}

#endif
