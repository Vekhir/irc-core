[![Build Status](https://travis-ci.org/jtdaugherty/vty.png)](https://travis-ci.org/jtdaugherty/vty)

`vty` is a terminal interface library. It provides a high-level
interface for doing terminal I/O.

Install via `git` with:

```
git clone git://github.com/coreyoconnor/vty.git
```

Install via `cabal` with:

```
cabal install vty
```

# Features

* Supports a large number of terminals. vt100, ansi, hurd, linux,
  screen, etc., or anything with a sufficient terminfo entry.

* Automatic handling of window resizes.

* Unicode output on terminals with UTF-8 support.

* Handles multi-column glyphs. (Requires user to properly configure
  terminal.)

* Efficient output. Output buffering and terminal state changes are
  minimized.

* Minimizes repaint area, which virtually eliminates the flicker
  problems that plague ncurses programs.

* A pure, compositional interface for efficiently constructing display
  images.

* Automatically decodes keyboard keys into (key,[modifier]) tuples.

* Automatically supports refresh on Ctrl-L.

* Supports a keypress timeout after for lone ESC. The timeout is
  customizable.

* The interface is designed for easy extension.

* Supports ANSI graphics modes (SGR as defined in `console_codes(4)`)
  with a type-safe interface and graceful fallback for terminals
  with limited or nonexistent support for such modes.

* Properly handles cleanup (but not due to signals).

* Provides a comprehensive test suite.

# Known Issues

* Terminals have numerous quirks and bugs. Vty picks what works best for
  the author in ambiguous or buggy situations.

* Signal handling of STOP, TERM and INT are nonexistent.

* The character encoding of the terminal is assumed to be UTF-8 if
  unicode is used.

* Terminfo is assumed to be correct unless there is an override
  configured. Some terminals will not have correct special key support
  (shifted F10 etc). See `Config` for customizing vty's behavior for a
  particular terminal.

* Uses the `TIOCGWINSZ` ioctl to find the current window size, which
  appears to be limited to Linux and BSD.

* Supports "normal" and "extended" (SGR) mouse modes as described at
  http://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Mouse-Tracking

* Supports bracketed paste mode as described at
  http://cirw.in/blog/bracketed-paste

# Platform Support

## Posix Terminals

Uses terminfo to determine terminal protocol. With some special rules to
handle some omissions from terminfo.

## Windows

Unsupported (but contributions and testing here are very welcome!)

# Development Notes

## Under NixOS

### Using cabal

After installing `ncurses` to the user environment:

~~~
LIBRARY_PATH=$HOME/.nix-profile/lib/ cabal configure --enable-tests --extra-lib-dirs=$HOME/.nix-profile/lib
LIBRARY_PATH=$HOME/.nix-profile/lib/ cabal build
LIBRARY_PATH=$HOME/.nix-profile/lib/ cabal test
~~~

## Code Coverage

As of last testing, profiling causes issues with coverage when enabled.
To evaluate coverage, configure as follows:

~~~
rm -rf dist ; cabal configure --enable-tests --enable-library-coverage \
  --disable-library-profiling \
  --disable-executable-profiling
~~~

## Profiling

~~~
rm -rf dist ; cabal configure --enable-tests --disable-library-coverage \
  --enable-library-profiling \
  --enable-executable-profiling
~~~
