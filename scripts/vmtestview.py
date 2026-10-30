#!/usr/bin/env python3
"""Follows the test log with the progress bars pinned to the bottom of the terminal.

    scripts/vmtestview.py [LOG]        LOG defaults to $TEST_LOG, else ~/vms/test.log
    scripts/vmtestview.py --once [LOG] one frame as plain text (for a pipe or a test), no terminal tricks

The test scripts append "[suite] ..." lines to the log. The lines that start with "~~" are progress
("~~ <bar> 45%  block 5/11  120 passed, 0 failed", and "[plan] ~~ plan cli menu hw ..." from vmtest.sh, which names
the whole package of suites of a run); they are not scrolled but drawn as one bar per suite plus a total in the last
lines of the terminal, which stay put while the other lines scroll above them (a terminal scroll region, like apt's
progress bar). The total is the share of the WHOLE package: every planned suite counts, also the ones that have not
started, each weighted by its expected number of checks (the count of its last complete run, kept by vmsuite.sh in
<log dir>/expected/<suite>; the numbers below are the fallback). Ctrl-C leaves the terminal as it was.
"""
import os
import re
import shutil
import signal
import sys
import time

HEAD = 30000      # lines of the log read at the start, to know the state of a run that is already going
SHOW = 60         # of those, the last ones shown above the bars
CELLS = 20

PROGRESS = re.compile(r'^\[(\S+)\] ~~ \S+\s+(\d+)%\s+block (\d+)/(\d+)\s+(\d+) passed, (\d+) failed')
STARTED = re.compile(r'^\[(\S+)\] ===== vmsuite\.sh (\S+)')
PLAN = re.compile(r'^\[plan\] ~~ plan (.*)$')
CHECK = re.compile(r'^\[(\S+)\] (PASS|FAIL|SKIP) ')
# Checks of a complete run of each suite (PASS + FAIL + SKIP), until vmsuite.sh has kept its own count.
EXPECTED = dict(cli=255, menu=37, hw=98, installer=4, toggles=43, nvidia=102, gnome=60)
SGR = {'pass': '\x1b[32m', 'fail': '\x1b[1;31m', 'skip': '\x1b[33m', 'step': '\x1b[2m'}


class Suites:
    """The state of every suite in the log, and of the package of suites the run was planned as."""

    def __init__(self, expected_dir=None):
        self.s = {}
        self.plan = []
        self.expected_dir = expected_dir

    def _suite(self, name):
        return self.s.setdefault(name, dict(done=0, total=0, passed=0, failed=0, count=0, started=False))

    def expected(self, name):
        try:
            with open(os.path.join(self.expected_dir, name)) as f:
                n = int(f.read().split()[0])
                if n > 0:
                    return n
        except (OSError, ValueError, IndexError, TypeError):
            pass
        return EXPECTED.get(name, 50)

    def feed(self, line):
        """True when the line was progress (not to be scrolled)."""
        m = PLAN.match(line)
        if m:
            self.plan = m.group(1).split()
            self.s = {}                       # a new package of suites: nothing of the last one counts
            return True
        m = STARTED.match(line)
        if m:
            self.s[m.group(1)] = dict(done=0, total=0, passed=0, failed=0, count=0, started=True)
            return False
        m = PROGRESS.match(line)
        if m:
            name, _pct, done, total, passed, failed = m.groups()
            v = self._suite(name)
            v.update(done=int(done), total=int(total), passed=int(passed), failed=int(failed), started=True)
            return True
        m = CHECK.match(line)
        if m:
            self._suite(m.group(1))['count'] += 1
        return False

    @staticmethod
    def bar(share, failed, color):
        cells = int(max(0.0, min(1.0, share)) * CELLS)
        on, off = ('█' * cells), ('░' * (CELLS - cells))
        if color:
            return ('\x1b[31m' if failed else '\x1b[32m') + on + '\x1b[2;37m' + off + '\x1b[0m'
        return on + off

    def parts(self):
        """(name, share 0..1, finished, expected checks, checks so far, entry) for every suite of the package."""
        names = list(self.plan) + [n for n in sorted(self.s) if n not in self.plan]
        out = []
        for n in names:
            v = self.s.get(n)
            exp = self.expected(n)
            if v is None:
                out.append((n, 0.0, False, exp, 0, None))
                continue
            finished = v['total'] > 0 and v['done'] >= v['total']
            share = 1.0 if finished else min(v['count'], exp - 1) / exp if exp > 1 else 0.0
            out.append((n, share, finished, exp, v['count'], v))
        return out

    def rows(self, color):
        """The lines for the bottom: one per suite of the package, and the total of the whole package."""
        parts = self.parts()
        width = max([len(p[0]) for p in parts] + [5])
        lines = []
        wsum = psum = 0.0
        tpass = tfail = 0
        for name, share, finished, exp, count, v in parts:
            weight = float(max(exp, count)) if v is not None and not finished else float(exp)
            wsum += weight
            psum += weight * share
            failed = v['failed'] if v else 0
            tpass += v['passed'] if v else 0
            tfail += failed
            lines.append(self._row(name.ljust(width), share, finished, exp, count, v, color))
        if len(parts) > 1 or not parts:
            total = psum / wsum if wsum else 0.0
            lines.append(self._total(('total'.ljust(width)), total, len(parts), tpass, tfail, color))
        return lines

    def _row(self, label, share, finished, exp, count, v, color):
        pct = int(100 * share)
        failed = v['failed'] if v else 0
        if v is None:
            detail = 'waiting  (about %d checks)' % exp
            mark = ' '
        else:
            mark = ('✓' if not failed else '✗') if finished else ' '
            detail = '%d/%d checks  block %d/%d  %d failed' % (min(count, exp) if not finished else count, exp if not finished else count,
                                                             v['done'], v['total'], failed)
        text = '%s %s %3d%% %s %s' % (label, self.bar(share, failed, color), pct, mark, detail)
        if color and v is None:
            text = '\x1b[2m' + text + '\x1b[0m'
        return text

    def _total(self, label, share, n, passed, failed, color):
        text = '%s %s %3d%%   all %d suites  %d passed, %d failed' % (label, self.bar(share, failed, color), int(100 * share), n, passed, failed)
        return '\x1b[1m' + text + '\x1b[0m' if color else text


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
    suites, shown = Suites(os.path.join(os.path.dirname(path), 'expected')), []
    for line in tail_lines(path, HEAD):
        if not suites.feed(line):
            shown.append(line)
    print('\n'.join(shown[-SHOW:]))
    print()
    print('\n'.join(suites.rows(False)))


class Screen:
    def __init__(self, path):
        self.path = path
        self.suites = Suites(os.path.join(os.path.dirname(path), 'expected'))
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
