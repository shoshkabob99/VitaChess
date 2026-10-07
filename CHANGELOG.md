# Changelog

## v1.0
- First public release.
- Stats: records from older versions are reconciled, so "Games finished" always matches your record.

## v0.10
- Move list: drag to scroll through the whole game, and tap any move to see that position
  (or step with L and R). The board gets a gold frame while you look back; Circle or the
  Live button returns to the game.
- Stats & Trophies screen: games, record against the computer, win streaks, fastest win,
  longest game, favourite opening moves, puzzle and lesson progress, and 25 trophies.
  A banner with a chime appears when you unlock one.
- Hints draw an arrow on the board.
- The king gives a quick shake when put in check.
- Captured pieces fly from the board to the captor's card.
- Sound volume setting (Off, 25%, 50%, 75%, 100%) replaces the on/off switch.
- Status text capitalised: "Your Move", "White to Move", and so on.

## v0.9
- New logo (glossy pieces on a board), in white: on the main menu, the LiveArea, the Start
  gate, and a new bubble icon (white logo on the blue background).
- LiveArea background now matches the Floating pieces blue.

## v0.8.1
- New defaults: Staunton pieces on the Tournament (green) board. Players who already saved
  their settings keep their choices.

## v0.8
- Animated menu backgrounds: Floating pieces (default; soft chess pieces drifting upward at
  three depths with specks of light) and Waves (glowing ribbons, XMB style). Classic (the
  old checkered background) is still available. Choose in Settings > Menu background.
- Menu buttons are semi-transparent over the backgrounds; the highlighted one glows gently
  and has a gold edge.
- Menu sounds: a tick when moving, a click when selecting, a lower tick for going back
  (follows the Sound effects setting).
- Screens fade in when you switch between them.

## v0.7.1
- Controller hints use PlayStation button icons (cross, circle, triangle, square, D-pad,
  START, SELECT) instead of text, in the puzzle and lesson panels and every menu footer.

## v0.7
- Crisp text: the Inter font is pre-rendered into bitmap atlases (`tools/make_fonts.py`) and
  drawn pixel-for-pixel. Fixes letters drawn wrongly by the Vita's font renderer (faint "c"
  and "k", "t" without a crossbar) and soft small text. Minimum text size raised to 14px.
- New LiveArea background and Start gate, laid out around the system's gate and icons.
- Sharp title-screen emblem (rendered at full size instead of an enlarged sprite).
- "Made by shoshkabob" on the main menu; removed the controls hint there.
- Learn menu: course details moved to a side panel (fixes the box covering the list).
- Brighter secondary text for readability.

## v0.6
- Learn part 2, three more courses (21 lessons):
  - Openings: opening principles, then guided walkthroughs of the Italian Game, Ruy Lopez,
    Queen's Gambit, London System, Sicilian, French and Caro-Kann, plus opening traps.
  - Strategy: active pieces, rooks on open files, pawn structure, passed pawns, trading when ahead.
  - Endgame Practice: king activity, the opposition, rule of the square, and drills against the
    computer: queen mate, rook mate, two-rook ladder, and promoting a pawn.
- New lesson types: guided walkthroughs (play the highlighted move, read why) and drills
  (real play against the computer with a move limit; stalemate or running out of moves = retry).
- Desktop preview: `python tools/build.py --desktop` builds a .love file that runs the Vita
  game on Windows, Mac or Linux with LOVE 11 (mouse = touchscreen, keyboard or gamepad = buttons).
- Wireless updates: `python tools/build.py --deploy <Vita IP>` uploads index.lua over FTP.

## v0.5
- Learn section with three courses (30 lessons, 79 steps):
  - The Basics: the board, every piece, pawns, capturing and values, check, checkmate and
    stalemate, castling, en passant, promotion (including underpromotion), draws.
  - Checks and Checkmates: discovered check, double check, perpetual check, back-rank mate,
    Scholar's Mate (and how to stop it), smothered mate, the rook ladder, queen mates,
    the Arabian mate.
  - Tactics: forks, pins, skewers, discovered attacks, removing the defender, deflection, review.
- Lessons mix explanations (with highlighted squares), "collect the stars" piece practice,
  and positions where you find the right move. The computer plays the replies.
- Hints, gentle feedback on wrong moves, and progress saved to ux0:data/VitaChess/learn.txt.
- Every lesson position and answer is checked by the tests.
- The PSP test build includes everything above.

## PSP test build (from v0.4)
- `python tools/build.py --psp` builds a PSP version for the LuaDEV R0 interpreter.
- `src/platform_psp.lua` draws the same layout at half size for the 480x272 screen; buttons only.
- Uses the PSP's built-in font, 32px piece sprites, and 44.1 kHz sounds (`assets/psp/`).
- Saves go to a `data` folder next to the EBOOT.PBP.
- The build modules now use a small built-in loader instead of Lua's package library.

## v0.4
- Puzzle mode: 1,000 tactics puzzles from the Lichess puzzle database, rated 400 to 2900.
- Your own puzzle rating (starts at 1000), plus solved count, current streak, and best streak.
- Difficulty: Adaptive (near your rating), Easy, Medium, Hard, Expert. Unseen puzzles come first.
- Two-step hints (the piece, then the move), step-by-step solutions, Try Again, Next.
- Any checkmating move counts as correct, as on Lichess.
- Puzzle progress is saved to ux0:data/VitaChess/puzzles.txt and never touches your saved game.

## v0.3
- Chess clocks: 3+2, 5, 10, 15+10, 30 minutes (vs computer and two players). Running out of
  time loses, or draws if the opponent can't checkmate. The computer manages its own clock.
- Player cards showing names, clocks, captured pieces, and material lead.
- Pieces slide to their squares (can be turned off in Settings).
- Sharper TrueType text (DejaVu Sans).
- Resign and offer a draw from the pause menu, with confirmation. The computer accepts draws
  only when it isn't better.
- Your win/loss/draw record at each difficulty level.
- Finished games are saved as PGN files in ux0:data/VitaChess/games/.
- Opening book: the computer plays varied, natural openings (41 lines).
- Two Players now has its own setup screen (clock, auto-flip).
- Save format v3 (adds clock and how the game ended); older saves still load.

## v0.2.1
- Code split into modules (`src/`), with all Vita-specific calls isolated in `platform.lua`.
- Build script (`tools/build.py`) bundles the modules and assembles the VPK.
- Automated tests for the rules, the computer player, and the menus.
- No gameplay changes.

## v0.2
- Main menu, settings screen, pause and game-over menus.
- Computer opponent with 8 difficulty levels (play as White, Black, or Random).
- 7 board themes, 5 piece sets, sound effects, hints, auto-flip for two players.
- Save format v2 (remembers mode, level, and colours).

## v0.1
- Two-player chess with full rules, touch and button controls, auto-save.
