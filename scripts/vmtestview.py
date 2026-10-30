#!/usr/bin/env python3
"""Follows the test log with the progress bars pinned to the bottom of the terminal.

    scripts/vmtestview.py [LOG]        LOG defaults to $TEST_LOG, else ~/vms/test.log
    scripts/vmtestview.py --once [LOG] one frame as plain text (for a pipe or a test), no terminal tricks

The test scripts (vmsuite.sh) append "[suite] ..." lines to the log. The lines that start with "~~" are progress
("~~ <bar> 45%  block 5/11  120 passed, 0 failed"); they are not scrolled but drawn as one bar per suite plus a
total in the last lines of the terminal, which stay put while the other lines scroll above them (a terminal scroll
region, like apt's progress bar). Ctrl-C leaves the terminal as it was.
"""
import os
import re
import shutil
import signal
import sys
import time

HEAD = 3000       # lines of the log read at the start, to know the state of a run that is already going
SHOW = 60         # of those, the last ones shown above the bars
CELLS = 20

PROGRESS = re.compile(r'^\[(\S+)\] ~~ \S+\s+(\d+)%\s+block (\d+)/(\d+)\s+(\d+) passed, (\d+) failed')
STARTED = re.compile(r'^\[(\S+)\] ===== vmsuite\.sh (\S+)')
SGR = {'pass': '\x1b[32m', 'fail': '\x1b[1;31m', 'skip': '\x1b[33m', 'step': '\x1b[2m'}


class Suites:
    """The latest progress line of every suite in the log."""

    def __init__(self):
        self.s = {}

    def feed(self, line):
        """True when the line was progress (not to be scrolled)."""
        m = STARTED.match(line)
        if m:
            self.s[m.group(1)] = dict(done=0, total=0, passed=0, failed=0)
            return False
        m = PROGRESS.match(line)
        if not m:
            return False
        name, _pct, done, total, passed, failed = m.groups()
        self.s[name] = dict(done=int(done), total=int(total), passed=int(passed), failed=int(failed))
        return True

    @staticmethod
    def bar(done, total, failed, color):
        share = done / total if total else 0
        cells = int(share * CELLS)
        on, off = ('█' * cells), ('░' * (CELLS - cells))
        if color:
            return ('\x1b[31m' if failed else '\x1b[32m') + on + '\x1b[2;37m' + off + '\x1b[0m'
        return on + off

    def rows(self, color):
        """The lines for the bottom: one per suite, and a total when there are several."""
        out = []
        names = sorted(self.s)
        width = max([len(n) for n in names] + [5])
        td = tt = tp = tf = 0
        for n in names:
            v = self.s[n]
            td += v['done']; tt += v['total']; tp += v['passed']; tf += v['failed']
            out.append(self._row(n.ljust(width), v['done'], v['total'], v['passed'], v['failed'], color))
        if len(names) > 1:
            out.append(self._row('total'.ljust(width), td, tt, tp, tf, color, bold=True))
        return out

    def _row(self, label, done, total, passed, failed, color, bold=False):
        pct = 100 * done // total if total else 0
        finished = total > 0 and done >= total
        mark = ('✓' if not failed else '✗') if finished else ' '
        text = '%s %s %3d%% %s block %d/%d  %d passed, %d failed' % (
            label, self.bar(done, total, failed, color), pct, mark, done, total, passed, failed)
        if color and bold:
            text = '\x1b[1m' + text + '\x1b[0m'
        return text


def decorate(line, color):
    if not color:
        return line
    body = line.split('] ', 1)[-1] if line.startswith('[') else line
    for key, test in (('fail', body.startswith('FAIL')), ('pass', body.startswith('PASS')),
                      ('skip', body.startswith('SKIP')), ('step', body.startswith('#####'))):
        if test:
            return SGR[key] + line + '\x1b[0m'
    return line


def visible_cut(text, cols):
    """Cuts plain text to the width (colour codes are added after cutting, never inside)."""
    return text if len(text) < cols else text[:cols - 2] + '…'


def tail_lines(path, count):
    try:
        with open(path, 'rb') as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - count * 400))
            data = f.read().decode('utf-8', 'replace')
        return data.splitlines()[-count:]
    except OSError:
        return []


def once(path):
    suites, shown = Suites(), []
    for line in tail_lines(path, HEAD):
        if not suites.feed(line):
            shown.append(line)
    print('\n'.join(shown[-SHOW:]))
    print()
    print('\n'.join(suites.rows(False)))


class Screen:
    def __init__(self, path):
        self.path = path
        self.suites = Suites()
        self.rows = shutil.get_terminal_size((80, 24))
        self.k = 0
        self.resized = False
        self.pos = 0
        self.partial = ''
        signal.signal(signal.SIGWINCH, lambda *_: setattr(self, 'resized', True))

    def write(self, text):
        sys.stdout.write(text)
        sys.stdout.flush()

    def layout(self):
        """Sets the scroll region to everything above the bars and draws the bars."""
        cols, rows = self.rows.columns, self.rows.lines
        bars = self.suites.rows(True)
        k = len(bars) + 1                    # one empty line between the log and the bars
        k = min(k, max(1, rows // 2))
        out = ''
        if self.k and k > self.k:
            # The bars need more lines: first scroll the log up inside the old region, or the new bar lines would
            # cover the last lines of the log (a FAIL among them).
            out += '\x1b[%d;1H' % (rows - self.k) + '\n' * (k - self.k)
        out += '\x1b[r\x1b[1;%dr' % (rows - k)   # reset, then the scroll region 1..rows-k
        for i in range(k):
            out += '\x1b[%d;1H\x1b[2K' % (rows - k + 1 + i)
        for i, text in enumerate(bars[-(k - 1):] if k > 1 else []):
            plain = re.sub(r'\x1b\[[0-9;]*m', '', text)
            if len(plain) >= cols:           # too narrow: drop the counts
                text = text[:text.rfind('block')] if 'block' in text else text
            out += '\x1b[%d;1H%s' % (rows - k + 2 + i, text)
        out += '\x1b[%d;1H' % (rows - k)
        self.k = k
        self.write(out)

    def scroll_line(self, line):
        cols, rows = self.rows.columns, self.rows.lines
        line = decorate(visible_cut(line, cols), True)
        self.write('\x1b7\x1b[%d;1H\n%s\x1b[0m\x1b[K\x1b8' % (rows - self.k, line))

    def run(self):
        os.system('')                         # enable ANSI on terminals that need it
        self.write('\x1b[2J\x1b[H')
        shown = []
        for line in tail_lines(self.path, HEAD):
            if not self.suites.feed(line):
                shown.append(line)
        self.layout()
        for line in shown[-SHOW:]:
            self.scroll_line(line)
        try:
            self.pos = os.path.getsize(self.path)
        except OSError:
            self.pos = 0
        try:
            while True:
                self.follow()
                time.sleep(0.3)
        except KeyboardInterrupt:
            pass
        finally:
            self.write('\x1b[r\x1b[%d;1H\n' % self.rows.lines)

    def follow(self):
        if self.resized:
            self.resized = False
            self.rows = shutil.get_terminal_size((80, 24))
            self.layout()
        try:
            size = os.path.getsize(self.path)
        except OSError:
            return
        if size < self.pos:                   # truncated: start again
            self.pos, self.partial = 0, ''
        if size == self.pos:
            return
        with open(self.path, 'rb') as f:
            f.seek(self.pos)
            data = f.read().decode('utf-8', 'replace')
            self.pos = f.tell()
        lines = (self.partial + data).split('\n')
        self.partial = lines.pop()
        changed = False
        for line in lines:
            if self.suites.feed(line):
                changed = True
            else:
                if STARTED.match(line):
                    changed = True
                self.scroll_line(line)
        if changed:
            self.layout()


def main():
    args = [a for a in sys.argv[1:] if a != '--once']
    path = os.path.expanduser(args[0] if args else os.environ.get('TEST_LOG', '~/vms/test.log'))
    if '--once' in sys.argv[1:] or not sys.stdout.isatty():
        once(path)
        return
    Screen(path).run()


if __name__ == '__main__':
    main()
