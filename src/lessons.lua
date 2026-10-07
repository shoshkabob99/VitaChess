-- lessons.lua - the Learn courses (content only; learn.lua runs them)
--
-- Each lesson is a list of steps:
--   explain  { kind = "explain", fen, text, marks }      read, then Next
--   targets  { kind = "targets", fen, text, stars }      move the piece onto every star
--   find     { kind = "find", fen, text, ... }           make the right move(s)
--
-- "find" steps use one of:
--   line  = "e2e4 e7e5 g1f3"  exact moves: yours, the reply, yours... (any checkmate also counts)
--   rule  = "mate" | "check" | "capture" | "king" | "block" | "castle" | "stopmate"
--   accept = "e2e4 d2d4"      any one of these moves
-- plus optional intro = "d7d5" (moves played first, before your turn),
-- hint = "...", done = "..." (shown when you get it right).
-- marks = "e4:g d5:r" highlights squares (g green, r red, b blue, y yellow).
--
--   guide    { kind = "guide", side = "w"/"b", moves = { { "e2e4", "why" }, ... } }
--            a walkthrough: you play your side's moves (highlighted), the computer
--            plays the other side's; every move comes with its explanation
--   play     { kind = "play", fen, goal = "mate" | "promote", limit = moves }
--            a real game against the computer: reach the goal within the move limit
-- verify = "best" asks the tests to confirm the engine agrees it's the best move.
-- Moves are written in UCI form (from square, to square, promotion letter).
--
-- tests/test_rules.lua plays through every step to check the positions and answers.

local START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

return {
  ---------------------------------------------------------------------------
  { id = "basics", title = "The Basics",
    desc = "How the pieces move, check, checkmate, and the special rules.",
    lessons = {
      { id = "board", title = "The Board and the Goal", steps = {
        { kind = "explain", fen = START,
          text = "Chess is played on an 8x8 board by two players, White and Black. White always moves first, then the players take turns.\nThe goal is to checkmate the enemy king: attack it so that it has no way to escape." },
        { kind = "explain", fen = START, marks = "e4:y a1:b h8:b",
          text = "The columns are called files, lettered a to h. The rows are ranks, numbered 1 to 8.\nEvery square is named by its file and rank. The yellow square is e4. The blue corners are a1 and h8." },
        { kind = "explain", fen = START, marks = "d1:y d8:y",
          text = "Each side starts with 8 pawns, 2 rooks, 2 knights, 2 bishops, a queen and a king.\nThe queen starts on her own colour: the white queen on a light square, the black queen on a dark one." },
      } },

      { id = "rook", title = "The Rook", steps = {
        { kind = "explain", fen = "k7/8/8/8/3R4/8/8/7K w - - 0 1", marks = "d8:g d1:g a4:g h4:g d6:g b4:g",
          text = "The rook moves any number of squares in a straight line: up, down, left or right.\nIt can't jump over other pieces." },
        { kind = "targets", fen = "7k/8/8/8/8/8/3R4/7K w - - 0 1", stars = "d7 a7 a2 g2",
          text = "Move the rook onto every star. You can take them in any order.",
          done = "Rooks love open lines. Later in the game they are among your strongest pieces." },
      } },

      { id = "bishop", title = "The Bishop", steps = {
        { kind = "explain", fen = "k7/8/8/8/3B4/8/8/7K w - - 0 1", marks = "b6:g f6:g b2:g f2:g a7:g g1:g",
          text = "The bishop moves diagonally, any number of squares.\nA bishop always stays on the colour it started on, so each side has one light-squared and one dark-squared bishop." },
        { kind = "targets", fen = "k7/8/8/8/8/8/8/2B4K w - - 0 1", stars = "e3 h6 f8 a3",
          text = "Collect every star with the bishop.",
          done = "Notice every star was on a dark square. This bishop can never reach a light one." },
      } },

      { id = "queen", title = "The Queen", steps = {
        { kind = "explain", fen = "k7/8/8/8/3Q4/8/8/7K w - - 0 1", marks = "d8:g h8:g a4:g a7:g g1:g d1:g h4:g",
          text = "The queen is the most powerful piece. She moves like a rook and a bishop combined: any number of squares in a straight line or along a diagonal." },
        { kind = "targets", fen = "7k/8/8/8/8/8/8/3Q3K w - - 0 1", stars = "h5 e8 a4 c2",
          text = "Collect every star with the queen.",
          done = "Because she is so valuable, be careful not to bring the queen out too early where she can be chased around." },
      } },

      { id = "knight", title = "The Knight", steps = {
        { kind = "explain", fen = "k7/8/8/8/3N4/8/8/7K w - - 0 1", marks = "c6:g e6:g f5:g f3:g e2:g c2:g b3:g b5:g",
          text = "The knight moves in an L shape: two squares in one direction, then one square to the side.\nIt always lands on a square of the opposite colour." },
        { kind = "explain", fen = START, marks = "b1:y a3:g c3:g g1:y f3:g h3:g",
          text = "The knight is the only piece that can jump over others. That's why knights can come out at the very start, hopping over the pawns." },
        { kind = "targets", fen = "k7/8/8/8/8/8/8/1N5K w - - 0 1", stars = "c3 e4 g5 f7",
          text = "Collect the stars with the knight. Plan your hops!",
          done = "Knights are tricky. They are especially strong close to the centre, where they reach the most squares." },
      } },

      { id = "king", title = "The King", steps = {
        { kind = "explain", fen = "k7/8/8/8/4K3/8/8/8 w - - 0 1", marks = "d5:g e5:g f5:g d4:g f4:g d3:g e3:g f3:g",
          text = "The king moves one square in any direction.\nHe is the most important piece: if your king is checkmated, you lose. Your king may never move onto a square where it would be attacked." },
        { kind = "targets", fen = "k7/8/8/8/8/8/8/4K3 w - - 0 1", stars = "e3 g4 f6",
          text = "Walk the king to every star, one square at a time." },
        { kind = "explain", fen = "8/8/8/3k4/8/3K4/8/8 w - - 0 1", marks = "c4:r d4:r e4:r",
          text = "Two kings can never stand next to each other, since each would be attacking the other. The red squares are off limits to both kings." },
      } },

      { id = "pawn", title = "The Pawn", steps = {
        { kind = "explain", fen = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", marks = "e3:g e4:g",
          text = "Pawns move straight forward one square. On its very first move, a pawn may move two squares instead.\nPawns never move backwards." },
        { kind = "explain", fen = "4k3/8/8/3pnp2/4P3/8/8/4K3 w - - 0 1", marks = "d5:r f5:r e5:b",
          text = "Pawns capture differently from how they move: one square diagonally forward.\nThis pawn can capture on d5 or f5, but it can't move forward, because the knight on e5 blocks it." },
        { kind = "find", fen = "4k3/8/8/3n4/4P3/8/8/4K3 w - - 0 1", line = "e4d5",
          text = "Capture the black knight with your pawn.",
          hint = "Pawns capture diagonally forward.",
          done = "A pawn is worth the least, so trading it for a knight is a great deal." },
      } },

      { id = "values", title = "Capturing and Piece Values", steps = {
        { kind = "explain", fen = START,
          text = "To capture, move your piece onto a square with an enemy piece. The enemy piece is removed from the board.\nRough values: pawn 1, knight 3, bishop 3, rook 5, queen 9. The king is priceless." },
        { kind = "find", fen = "3r2k1/3r1ppp/8/n7/8/7P/3Q1PP1/6K1 w - - 0 1", line = "d2a5", verify = "best",
          text = "Your queen can capture the rook on d7 or the knight on a5. Only one of them is safe to take. Which?",
          hint = "Is the rook on d7 protected?",
          done = "Free material! The rook was protected by the other rook, so taking it would lose your queen." },
      } },

      { id = "check", title = "Check", steps = {
        { kind = "explain", fen = "4k3/8/8/8/8/8/8/4R1K1 b - - 0 1", marks = "e8:r e1:y",
          text = "When a king is attacked, it is in check. The player in check must get out of it right away.\nThere are three ways: move the king, block the attack, or capture the attacker." },
        { kind = "find", fen = "4r1k1/8/8/8/8/8/5PPP/4K3 w - - 0 1", rule = "king",
          text = "The black rook is checking your king. Get out of check by moving the king.",
          hint = "Step off the e-file.",
          done = "The king is out of the rook's line." },
        { kind = "find", fen = "6k1/5ppp/1b6/8/8/3R4/6PP/6K1 w - - 0 1", rule = "block",
          text = "Check from the bishop! This time, block the check by putting your rook in the way.",
          hint = "The bishop attacks along the diagonal b6, c5, d4, e3, f2.",
          done = "A blocked check is no longer a check." },
        { kind = "find", fen = "4r1k1/8/8/8/8/2N5/4q3/4K3 w - - 0 1", rule = "capture",
          text = "The black queen is giving check. Capture her!",
          hint = "Your king can't take her because the rook protects her. Which piece can?",
          done = "Capturing the attacker is often the best way out of check." },
      } },

      { id = "mate", title = "Checkmate and Stalemate", steps = {
        { kind = "explain", fen = "3R2k1/5ppp/8/8/8/8/8/6K1 b - - 0 1", marks = "d8:y g8:r",
          text = "Checkmate: the king is in check and there's no way out. The game is over.\nHere the black king is trapped by its own pawns." },
        { kind = "find", fen = "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", rule = "mate",
          text = "Checkmate the black king in one move.",
          hint = "Use the rook on the back rank.",
          done = "Checkmate!" },
        { kind = "explain", fen = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", marks = "h8:y g8:r g7:r h7:r",
          text = "Stalemate: it's your turn, your king is NOT in check, but you have no legal move. That's a draw!\nHere Black has no safe square and nothing else to move." },
        { kind = "find", fen = "7k/8/6K1/8/8/8/8/5Q2 w - - 0 1", rule = "mate",
          text = "Checkmate in one. Careful: some queen moves only give stalemate!",
          hint = "Check along the back rank.",
          done = "Checkmate! Queen f7 would have been stalemate." },
      } },

      { id = "castling", title = "Castling", steps = {
        { kind = "explain", fen = "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1", marks = "g1:g c1:g e1:y",
          text = "Castling moves the king and a rook at once. The king steps two squares toward a rook, and the rook jumps to the square on the king's other side.\nIt tucks the king away safely and brings the rook into play." },
        { kind = "explain", fen = "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1",
          text = "You may castle only if: the king and that rook have never moved, the squares between them are empty, the king is not in check, and the king doesn't pass through or land on an attacked square." },
        { kind = "find", fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", rule = "castle",
          text = "Castle kingside: move your king two squares toward the rook on h1.",
          hint = "Select the king and move it to g1.",
          done = "Your king is safe and your rook is ready to join the game." },
        { kind = "explain", fen = "r3k2r/8/8/8/2b5/8/8/R3K2R w KQkq - 0 1", marks = "f1:r c4:r",
          text = "Here White can't castle kingside: the black bishop attacks f1, a square the king would cross. Castling queenside is still allowed." },
      } },

      { id = "enpassant", title = "En Passant", steps = {
        { kind = "explain", fen = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", marks = "d5:r d6:g e5:y",
          text = "If a pawn moves two squares and lands right beside an enemy pawn, that enemy pawn may capture it as if it had moved only one square.\nThis is called en passant (\"in passing\"). It's only allowed on the very next move." },
        { kind = "find", fen = "4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1", intro = "d7d5", line = "e5d6",
          text = "Black's pawn just jumped two squares past yours. Capture it en passant!",
          hint = "Move your pawn diagonally to d6, behind the black pawn.",
          done = "The black pawn is gone, even though you landed on an empty square." },
      } },

      { id = "promotion", title = "Promotion", steps = {
        { kind = "explain", fen = "4k3/1P6/8/8/8/8/8/4K3 w - - 0 1", marks = "b8:g",
          text = "When a pawn reaches the far end of the board, it promotes: it becomes a queen, rook, bishop or knight of your choice.\nAlmost always you choose a queen." },
        { kind = "find", fen = "8/1P5k/8/8/8/8/8/4K3 w - - 0 1", line = "b7b8q",
          text = "Promote your pawn to a queen.",
          hint = "Move the pawn to b8 and pick the queen.",
          done = "From a humble pawn to the strongest piece on the board." },
        { kind = "find", fen = "8/4P1k1/3q4/8/8/8/P7/7K w - - 0 1", line = "e7e8n g7f7 e8d6",
          text = "Sometimes a knight is better! Promote to a knight with check, then win the queen.",
          hint = "A knight on e8 would attack g7 and d6.",
          done = "An underpromotion fork! A queen on e8 wouldn't give check, but the knight does, and wins the black queen." },
      } },

      { id = "draws", title = "Draws", steps = {
        { kind = "explain", fen = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1",
          text = "Not every game has a winner. Stalemate is one kind of draw: the player to move has no legal move but isn't in check." },
        { kind = "explain", fen = "8/8/3k4/8/8/4KB2/8/8 w - - 0 1",
          text = "Insufficient material: if neither side has enough pieces to ever checkmate, the game is drawn. For example: king against king, or king and one bishop or knight against a king." },
        { kind = "explain", fen = START,
          text = "Threefold repetition: the same position happens three times. 50-move rule: 50 moves each with no capture and no pawn move.\nAnd the players can simply agree to a draw. Vita Chess handles all of these for you." },
      } },
    } },

  ---------------------------------------------------------------------------
  { id = "mates", title = "Checks and Checkmates",
    desc = "Special kinds of check and the classic checkmating patterns.",
    lessons = {
      { id = "discovered", title = "Discovered Check", steps = {
        { kind = "explain", fen = "4k3/8/8/8/4B3/8/8/4R1K1 w - - 0 1", marks = "e1:y e4:b e8:r",
          text = "A discovered check: you move one piece out of the way and reveal a check from the piece behind it.\nThe piece that moves is free to cause trouble anywhere, because the opponent must deal with the check first." },
        { kind = "find", fen = "4k3/1q6/8/8/4B3/8/5PPP/4R1K1 w - - 0 1", line = "e4b7", verify = "best",
          text = "Move the bishop to reveal check from your rook, and win something big at the same time.",
          hint = "Where can the bishop go along its diagonal?",
          done = "The bishop takes the queen, and the rook gives check. Black can't recapture in time." },
      } },

      { id = "double", title = "Double Check", steps = {
        { kind = "explain", fen = "3qkb2/3p1p2/3N4/8/8/8/8/4R1K1 b - - 0 1", marks = "e8:r d6:y e1:y",
          text = "In a double check, two pieces give check at once. You can't block or capture both, so the king MUST move. If it can't, it's checkmate." },
        { kind = "find", fen = "3qkb2/3p1p2/8/8/4N3/8/8/4R1K1 w - - 0 1", rule = "mate",
          text = "Deliver checkmate with a double check.",
          hint = "Move the knight to a square where it also checks the king.",
          done = "Double check and mate! The king's own pieces box it in." },
      } },

      { id = "perpetual", title = "Perpetual Check", steps = {
        { kind = "explain", fen = "7k/6p1/8/3Q4/8/8/1rr3PP/7K w - - 0 1",
          text = "If you can keep giving check forever and the king can't escape, the game ends in a draw by repetition.\nThis is perpetual check, and it can save a lost game. Here Black has two extra rooks..." },
        { kind = "find", fen = "7k/6p1/8/3Q4/8/8/1rr3PP/7K w - - 0 1",
          line = "d5h5 h8g8 h5e8 g8h7 e8h5 h7g8 h5e8 g8h7 e8h5 h7g8 h5e8", expect = "repetition",
          text = "...but White to move can force a draw. Keep checking with the queen on h5 and e8!",
          hint = "Check from h5, then from e8, and repeat.",
          done = "Draw by repetition. Black can never escape the checks." },
      } },

      { id = "backrank", title = "Back-Rank Mate", steps = {
        { kind = "explain", fen = "3R2k1/5ppp/8/8/8/8/8/6K1 b - - 0 1", marks = "d8:y g8:r f7:b g7:b h7:b",
          text = "A king hiding behind its own pawns can get trapped on the back rank. A rook or queen checking along that rank is checkmate.\nTip: give your own king an escape square by moving a pawn, like h3." },
        { kind = "find", fen = "6k1/5ppp/8/8/8/8/1r3PPP/2R3K1 w - - 0 1", rule = "mate",
          text = "Deliver a back-rank mate.",
          done = "Checkmate on the back rank." },
        { kind = "find", fen = "2r3k1/5ppp/8/8/8/8/4QPPP/4R1K1 w - - 0 1", line = "e2e8 c8e8 e1e8",
          text = "Mate in two: the black rook guards the back rank. Sacrifice your queen to drag it away!",
          hint = "Check on e8 with the queen.",
          done = "The rook had to take the queen, and then the back rank had no defender." },
      } },

      { id = "scholar", title = "Scholar's Mate", steps = {
        { kind = "explain", fen = "r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4", marks = "f7:r c4:y",
          text = "Scholar's Mate is a famous trap aimed at f7, Black's weakest square at the start: only the king protects it.\nThe queen and bishop team up to strike there." },
        { kind = "find", fen = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", rule = "mate",
          text = "Black has missed the threat. Checkmate!",
          hint = "Attack f7.",
          done = "Scholar's Mate!" },
        { kind = "find", fen = "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3", rule = "stopmate",
          text = "Now you are Black. White threatens queen takes f7, checkmate. Stop it!",
          hint = "Protect f7, or block the queen's path to it.",
          done = "Threat stopped. Against this trap, g6 (hitting the queen) or queen to e7 are the usual replies." },
      } },

      { id = "smothered", title = "Smothered Mate", steps = {
        { kind = "explain", fen = "6rk/5Npp/8/8/8/8/8/6K1 b - - 0 1", marks = "f7:y h8:r g8:b g7:b h7:b",
          text = "When a king is surrounded by its own pieces, a single knight check can be checkmate. This is a smothered mate." },
        { kind = "find", fen = "5r1k/6pp/7N/8/8/1Q6/8/6K1 w - - 0 1", line = "b3g8 f8g8 h6f7",
          text = "Mate in two, the famous way: give up your queen to smother the king!",
          hint = "Put the queen on g8. The knight protects it.",
          done = "Philidor's Legacy: the rook blocks its own king in, and the knight delivers mate." },
      } },

      { id = "ladder", title = "The Ladder Mate", steps = {
        { kind = "explain", fen = "1k4R1/7R/8/8/8/8/8/7K b - - 0 1", marks = "b8:r g8:y h7:y",
          text = "Two rooks can drive a king to the edge like climbing a ladder: one rook cuts off a rank, and the other checks on the next rank up." },
        { kind = "find", fen = "8/8/8/2k5/6R1/7R/8/7K w - - 0 1", line = "h3h5 c5d6 g4g6 d6c7 h5h7 c7b8 g6g8",
          text = "Climb the ladder! Check with one rook, then the other, pushing the king up to the 8th rank.",
          hint = "Start with the rook from h3 to h5.",
          done = "Checkmate with the rook ladder." },
      } },

      { id = "queenmate", title = "Queen and King Mates", steps = {
        { kind = "explain", fen = "3k4/3Q4/3K4/8/8/8/8/8 b - - 0 1", marks = "d7:y d8:r d6:b",
          text = "A queen can't checkmate alone, but with your king's help it's easy. A common pattern: the queen right in front of the enemy king, protected by your king." },
        { kind = "find", fen = "3k4/8/3K4/8/8/8/8/7Q w - - 0 1", rule = "mate",
          text = "Checkmate in one.",
          hint = "Your king covers the squares in front of Black's king. Check along the back rank.",
          done = "Checkmate." },
      } },

      { id = "arabian", title = "Rook and Knight Mate", steps = {
        { kind = "explain", fen = "7k/7R/5N2/8/8/8/8/6K1 b - - 0 1", marks = "h8:r h7:y f6:y g8:b",
          text = "The Arabian Mate, one of the oldest known patterns: the rook checks right next to the cornered king, and the knight protects the rook and covers the last escape square." },
        { kind = "find", fen = "7k/R7/5N2/8/8/8/8/6K1 w - - 0 1", rule = "mate",
          text = "Deliver the Arabian Mate.",
          hint = "The knight protects h7.",
          done = "Checkmate!" },
      } },
    } },

  ---------------------------------------------------------------------------
  { id = "tactics", title = "Tactics",
    desc = "Forks, pins, skewers and other tricks that win material.",
    lessons = {
      { id = "forks", title = "Forks", steps = {
        { kind = "explain", fen = "r3k3/2N4p/8/8/8/8/7P/4K3 b - - 0 1", marks = "c7:y e8:r a8:r",
          text = "A fork is one piece attacking two or more targets at once. Your opponent can only save one.\nKnights are famous forkers, but every piece can fork, even a pawn." },
        { kind = "find", fen = "r3k3/7p/8/1N6/8/8/7P/4K3 w - - 0 1", line = "b5c7", verify = "best",
          text = "Fork the king and the rook with your knight.",
          hint = "Which square does the knight attack both from?",
          done = "The king must move, and the rook falls." },
        { kind = "find", fen = "4k3/8/3b1n2/8/3PP3/8/8/4K3 w - - 0 1", line = "e4e5", verify = "best",
          text = "Now fork two pieces with a pawn.",
          hint = "A pawn attacks the two squares diagonally in front of it.",
          done = "The pawn attacks both the bishop and the knight, and the d4 pawn protects it." },
        { kind = "find", fen = "r5k1/6pp/8/8/8/8/6PP/3Q2K1 w - - 0 1", line = "d1d5", verify = "best",
          text = "Find a queen move that checks the king and attacks the rook.",
          hint = "Look for a central square on both diagonals.",
          done = "A queen fork. After the king moves, the rook is yours." },
      } },

      { id = "pins", title = "Pins", steps = {
        { kind = "explain", fen = "4k3/8/2n5/1B6/8/8/8/4K3 w - - 0 1", marks = "b5:y c6:r e8:r",
          text = "A pin attacks a piece that can't move away without exposing something more valuable behind it.\nWhen the piece behind is the king, the pin is absolute: the pinned piece isn't allowed to move at all." },
        { kind = "find", fen = "4k3/1p5p/2n5/8/8/8/7P/4KB2 w - - 0 1", line = "f1b5",
          text = "Pin the black knight to its king.",
          hint = "Put the bishop on the diagonal that runs through c6 and e8.",
          done = "The knight is pinned. It can't move without exposing the king." },
        { kind = "find", fen = "4k3/1p5p/2n5/1B6/3P4/8/7P/4K3 w - - 0 1", line = "d4d5", verify = "best",
          text = "The knight is pinned, and the b7 pawn protects it. Attack it with something cheaper and win it!",
          hint = "A pinned piece can't run away from a pawn.",
          done = "The pinned knight is lost." },
      } },

      { id = "skewers", title = "Skewers", steps = {
        { kind = "explain", fen = "3q4/8/8/8/3k4/8/7P/3R3K b - - 0 1", marks = "d1:y d4:r d8:r",
          text = "A skewer is a pin in reverse: you attack a valuable piece, it has to move away, and you capture the piece behind it." },
        { kind = "find", fen = "3q4/7p/8/8/3k4/8/7P/R6K w - - 0 1", line = "a1d1", verify = "best",
          text = "Skewer the king and the queen.",
          hint = "Check the king along the d-file.",
          done = "The king steps aside, and you take the queen." },
        { kind = "find", fen = "q7/7p/8/3k4/8/8/4B2P/7K w - - 0 1", line = "e2f3", verify = "best",
          text = "Now skewer with the bishop.",
          hint = "The king and queen share a diagonal.",
          done = "Check, then the queen falls." },
      } },

      { id = "discovered-attack", title = "Discovered Attacks", steps = {
        { kind = "explain", fen = "3q2k1/5ppp/8/8/8/3B4/5PPP/3R2K1 w - - 0 1", marks = "d1:y d3:b d8:r",
          text = "Move one piece to unleash an attack from the piece behind it. Now two attacks happen at once: from the piece that moved, and from the one that was revealed." },
        { kind = "find", fen = "6k1/3q1ppp/8/8/8/3B4/5PPP/3R2K1 w - - 0 1", line = "d3h7", verify = "best",
          text = "Move the bishop with check and reveal an attack on the queen.",
          hint = "Grab a pawn next to the black king.",
          done = "Black must answer the check, and your rook takes the queen." },
      } },

      { id = "defender", title = "Removing the Defender", steps = {
        { kind = "explain", fen = "6k1/5ppp/5n2/3b2B1/8/8/5PPP/3R2K1 w - - 0 1", marks = "f6:r d5:y g5:b",
          text = "If a piece is protected only once, capture or chase away its defender. Then the piece it was guarding falls.\nHere the knight on f6 is the only defender of the bishop on d5." },
        { kind = "find", fen = "6k1/5ppp/5n2/3b2B1/8/8/5PPP/3R2K1 w - - 0 1", line = "g5f6 g7f6 d1d5",
          text = "Remove the defender, then win the bishop.",
          hint = "Capture the knight first.",
          done = "With the knight gone, the bishop had no protection." },
      } },

      { id = "deflection", title = "Deflection", steps = {
        { kind = "explain", fen = "1r4k1/1P3ppp/8/8/8/8/5PPP/2R3K1 w - - 0 1", marks = "b8:r b7:y",
          text = "A defender can't do two jobs at once. Lure it away from its post, and whatever it was guarding collapses.\nHere the black rook is the only thing stopping your pawn from promoting." },
        { kind = "find", fen = "1r4k1/1P3ppp/8/8/8/8/5PPP/2R3K1 w - - 0 1", line = "c1c8 b8c8 b7c8q",
          text = "Deflect the rook and promote your pawn.",
          hint = "Check on c8, right next to the rook.",
          done = "The rook was lured away, and your new queen arrives with check." },
      } },

      { id = "review", title = "Tactics Review", steps = {
        { kind = "find", fen = "6k1/3q1p1p/8/8/4N3/8/5PPP/6K1 w - - 0 1", line = "e4f6", verify = "best",
          text = "Win the queen.",
          hint = "A knight check can attack two things.",
          done = "A royal fork: king and queen." },
        { kind = "find", fen = "6k1/5ppp/8/8/8/8/5PPP/1Q4K1 w - - 0 1", rule = "mate",
          text = "Checkmate in one.",
          done = "Back-rank mate." },
        { kind = "find", fen = "6k1/1q3ppp/8/8/4B3/8/5PPP/4R1K1 w - - 0 1", line = "e4b7", verify = "best",
          text = "Win the queen with one move.",
          hint = "Look at the bishop's diagonal.",
          done = "The queen was simply hanging. Always look for free pieces first!" },
      } },
    } },

  ---------------------------------------------------------------------------
  { id = "openings", title = "Openings",
    desc = "Opening principles, then famous openings for White and Black, move by move.",
    lessons = {
      { id = "principles", title = "Opening Principles", steps = {
        { kind = "explain", fen = START, marks = "d4:g e4:g d5:g e5:g",
          text = "The opening is about getting ready for battle. Three goals:\n1. Control the centre (the green squares) with pawns.\n2. Develop: bring out your knights and bishops.\n3. Castle, to keep your king safe." },
        { kind = "find", fen = START, accept = "e2e4 d2d4",
          text = "Make a first move that grabs the centre with a pawn.",
          hint = "Push a centre pawn two squares.",
          done = "Both e4 and d4 claim the centre and open lines for your queen and a bishop." },
        { kind = "find", fen = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
          accept = "g1f3 b1c3 f1c4 f1b5",
          text = "Now develop a piece toward the centre. Knights usually come out before bishops.",
          hint = "Try a knight move toward the middle of the board.",
          done = "Nice. Every developed piece is a soldier ready for the fight." },
        { kind = "explain", fen = START,
          text = "Things to avoid in the opening: moving the same piece twice, bringing the queen out early (she gets chased around), and making lots of pawn moves.\nEvery move should help a piece join the game." },
        { kind = "find", fen = "rnb1kbnr/ppp1pppp/8/3q4/8/8/PPPP1PPP/RNBQKBNR w KQkq - 0 3", line = "b1c3", verify = "best",
          text = "Black's queen came out early. Develop a piece AND attack her at the same time.",
          hint = "Which knight move hits d5?",
          done = "The queen has to move again while you keep developing. That's a free tempo." },
      } },

      { id = "italian", title = "Italian Game", steps = {
        { kind = "guide", side = "w", fen = START,
          text = "The Italian Game: quick development and pressure on f7. Play the highlighted moves.",
          moves = {
            { "e2e4", "Claim the centre and free your bishop and queen." },
            { "e7e5", "Black claims the centre too." },
            { "g1f3", "Develop a knight and attack the e5 pawn." },
            { "b8c6", "Black defends e5 with a knight." },
            { "f1c4", "The Italian bishop aims straight at f7, Black's weak spot." },
            { "f8c5", "Black answers with an Italian bishop of its own." },
            { "c2c3", "Prepare d4 to build a strong pawn centre." },
            { "g8f6", "Black develops and attacks e4." },
            { "d2d3", "A calm, solid way to protect e4. (d4 is the sharper choice.)" },
            { "d7d6", "Black supports e5." },
            { "e1g1", "Castle: your king is safe and your rook is ready." },
          },
          done = "That's the Italian Game. Both sides are developed, and White is ready to play d4 later." },
      } },

      { id = "ruylopez", title = "Ruy Lopez", steps = {
        { kind = "guide", side = "w", fen = START,
          text = "The Ruy Lopez (Spanish Game), one of the oldest and most respected openings.",
          moves = {
            { "e2e4", "Take the centre." },
            { "e7e5", "Black mirrors." },
            { "g1f3", "Attack e5." },
            { "b8c6", "Black defends it." },
            { "f1b5", "The Spanish bishop pressures the knight that defends e5." },
            { "a7a6", "Black asks the bishop where it wants to go." },
            { "b5a4", "Keep the pressure on the knight." },
            { "g8f6", "Black develops and attacks e4." },
            { "e1g1", "Castle early. e4 is safe for now, because Black's e5 pawn would fall in return." },
            { "f8e7", "Black prepares to castle." },
            { "f1e1", "The rook protects e4." },
            { "b7b5", "Black gains space and pushes the bishop back." },
            { "a4b3", "The bishop still aims at f7 from b3." },
            { "d7d6", "Black supports e5." },
            { "c2c3", "Prepare d4." },
            { "e8g8", "Black castles. Both sides have a rich position ahead." },
          },
          done = "The Closed Ruy Lopez. Its slow pressure has been played by world champions for 150 years." },
      } },

      { id = "queensgambit", title = "Queen's Gambit", steps = {
        { kind = "guide", side = "w", fen = START,
          text = "The Queen's Gambit: White offers a wing pawn to win control of the centre.",
          moves = {
            { "d2d4", "Take the centre with the queen's pawn." },
            { "d7d5", "Black does the same." },
            { "c2c4", "The gambit: offer the c-pawn to pull Black's d5 pawn away from the centre." },
            { "e7e6", "The Queen's Gambit Declined: Black keeps a solid pawn on d5." },
            { "b1c3", "Develop and add pressure on d5." },
            { "g8f6", "Black defends d5 again." },
            { "c1g5", "Pin the knight to the queen." },
            { "f8e7", "Black breaks the pin." },
            { "e2e3", "Open a path for the light-squared bishop." },
            { "e8g8", "Black castles." },
            { "g1f3", "Develop the last knight. White is ready to castle too." },
          },
          done = "The Queen's Gambit Declined, a favourite at every level from club players to world champions." },
      } },

      { id = "london", title = "London System", steps = {
        { kind = "guide", side = "w", fen = START,
          text = "The London System: a simple, solid setup you can play against almost anything.",
          moves = {
            { "d2d4", "Take the centre." },
            { "d7d5", "Black matches it." },
            { "c1f4", "Get the bishop out BEFORE playing e3, which would lock it in." },
            { "g8f6", "Black develops." },
            { "e2e3", "Now e3 supports d4 and opens the other bishop." },
            { "c7c5", "Black challenges your centre." },
            { "c2c3", "Build a solid pawn triangle that holds d4." },
            { "b8c6", "Black adds pressure on d4." },
            { "b1d2", "The knight goes to d2 so the c3 pawn stays." },
            { "e7e6", "Black prepares to develop." },
            { "g1f3", "Defend d4 again. Next come Bd3 and castling." },
          },
          done = "That's the London setup: the same plan works against most of Black's replies." },
      } },

      { id = "sicilian", title = "Sicilian Defence", steps = {
        { kind = "guide", side = "b", fen = START,
          text = "Now you play Black. The Sicilian is the most popular answer to 1.e4.",
          moves = {
            { "e2e4", "White takes the centre." },
            { "c7c5", "The Sicilian: fight for d4 from the side and create an unbalanced game." },
            { "g1f3", "White develops." },
            { "d7d6", "Prepare to bring out your knight to f6." },
            { "d2d4", "White strikes in the centre." },
            { "c5d4", "Trade your wing pawn for White's centre pawn." },
            { "f3d4", "White recaptures." },
            { "g8f6", "Develop and attack e4." },
            { "b1c3", "White defends e4." },
            { "a7a6", "The Najdorf: a flexible move that keeps White's pieces off b5." },
          },
          done = "The Najdorf Sicilian, a favourite of Fischer and Kasparov. Black has an extra centre pawn for the long fight." },
      } },

      { id = "french", title = "French Defence", steps = {
        { kind = "guide", side = "b", fen = START,
          text = "You play Black again. The French Defence is solid and full of counterattack.",
          moves = {
            { "e2e4", "White takes the centre." },
            { "e7e6", "Prepare d5 with support." },
            { "d2d4", "White builds a big centre." },
            { "d7d5", "Challenge the e4 pawn right away." },
            { "b1c3", "White defends e4." },
            { "g8f6", "Attack e4 again." },
            { "c1g5", "White pins your knight." },
            { "f8e7", "Break the pin." },
            { "e4e5", "White gains space and kicks the knight." },
            { "f6d7", "The knight steps back, ready to attack e5 later." },
            { "g5e7", "White trades bishops." },
            { "d8e7", "Recapture with the queen." },
          },
          done = "The French. Black's plan is to strike White's pawn chain with ...c5 and ...f6." },
      } },

      { id = "carokann", title = "Caro-Kann Defence", steps = {
        { kind = "guide", side = "b", fen = START,
          text = "The Caro-Kann: a rock-solid defence for Black.",
          moves = {
            { "e2e4", "White takes the centre." },
            { "c7c6", "Prepare d5 while keeping your bishop's diagonal open." },
            { "d2d4", "White builds the centre." },
            { "d7d5", "Strike at e4." },
            { "b1c3", "White defends." },
            { "d5e4", "Trade in the centre." },
            { "c3e4", "White recaptures." },
            { "c8f5", "Develop the bishop OUTSIDE your pawn chain before playing ...e6." },
            { "e4g3", "White attacks the bishop." },
            { "f5g6", "Retreat to a safe, active square." },
            { "h2h4", "White threatens to trap the bishop with h5." },
            { "h7h6", "Make an escape square for the bishop." },
          },
          done = "The Classical Caro-Kann. Black's position is very hard to break." },
      } },

      { id = "traps", title = "Opening Traps", steps = {
        { kind = "explain", fen = "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", marks = "h4:r e1:r f2:y g3:y",
          text = "Fool's Mate, the fastest checkmate possible. White weakened the diagonal to the king with two careless pawn moves, and Black's queen strikes on move 2." },
        { kind = "find", fen = START, intro = "f2f3 e7e5 g2g4", rule = "mate",
          text = "You are Black. White has just made the same two mistakes. Checkmate!",
          hint = "The queen can reach h4.",
          done = "Fool's Mate. Lesson: don't weaken your king's position early." },
      } },
    } },

  ---------------------------------------------------------------------------
  { id = "strategy", title = "Strategy",
    desc = "Active pieces, open files, pawn structure, passed pawns and trading.",
    lessons = {
      { id = "activity", title = "Active Pieces", steps = {
        { kind = "explain", fen = "6k1/5ppp/8/4n3/8/N7/5PPP/6K1 w - - 0 1", marks = "a3:r e5:g",
          text = "\"A knight on the rim is dim.\" A centralised knight controls up to 8 squares. On the edge it only reaches 4 or fewer.\nGood pieces are active pieces: centralise them and give them open lines." },
        { kind = "find", fen = "6k1/5ppp/8/8/8/N7/5PPP/6K1 w - - 0 1", accept = "a3c4 a3b5 a3c2",
          text = "Improve your knight: bring it off the edge toward the centre.",
          hint = "Head for c4 or b5.",
          done = "Much better. From there it can keep heading for the centre." },
      } },

      { id = "openfiles", title = "Rooks on Open Files", steps = {
        { kind = "explain", fen = "r4rk1/pp3ppp/8/8/8/8/PP3PPP/R4RK1 w - - 0 1", marks = "c1:g d1:g e1:g c8:g d8:g e8:g",
          text = "An open file has no pawns on it. Rooks love open files: they can travel all the way into the enemy camp.\nHere the c, d and e files are all open." },
        { kind = "find", fen = "r4rk1/pp3ppp/8/8/8/8/PP3PPP/R4RK1 w - - 0 1",
          accept = "a1c1 a1d1 a1e1 f1c1 f1d1 f1e1",
          text = "Put one of your rooks on an open file.",
          hint = "Slide a rook to c1, d1 or e1.",
          done = "Your rook controls the file. Next it could invade on the 7th rank." },
      } },

      { id = "structure", title = "Pawn Structure", steps = {
        { kind = "explain", fen = "6k1/p4p1p/1p3p2/8/8/2P5/P1P2PPP/6K1 w - - 0 1", marks = "c2:r c3:r f6:r f7:r",
          text = "Doubled pawns (two pawns on one file, like c2 and c3) can't protect each other and are easy to block." },
        { kind = "explain", fen = "6k1/pp3ppp/8/3p4/8/8/PP3PPP/6K1 w - - 0 1", marks = "d5:r",
          text = "An isolated pawn has no friendly pawns on the files beside it, so no pawn can ever protect it. Pieces have to babysit it instead." },
        { kind = "explain", fen = "6k1/p4ppp/8/1P6/8/8/5PPP/6K1 w - - 0 1", marks = "b5:g b6:g b7:g b8:g",
          text = "A passed pawn has no enemy pawns in front of it or on the files beside it. Nothing but pieces can stop it from promoting. Passed pawns win endgames." },
      } },

      { id = "passed", title = "Passed Pawns", steps = {
        { kind = "explain", fen = "6k1/6pp/3P4/8/8/8/6PP/6K1 w - - 0 1", marks = "d6:g d8:y",
          text = "\"Passed pawns must be pushed!\" The closer a passed pawn gets to promoting, the more of the opponent's attention it demands." },
        { kind = "find", fen = "6k1/6pp/3P4/8/8/8/6PP/6K1 w - - 0 1", line = "d6d7", verify = "best",
          text = "Push your passed pawn. Can the black king catch it?",
          hint = "Count: two moves to promote. How many does the black king need to reach d8?",
          done = "The king is too far away. Next move the pawn becomes a queen." },
      } },

      { id = "trading", title = "Trade When Ahead", steps = {
        { kind = "explain", fen = "3q1rk1/5ppp/8/8/8/8/5PPP/R2QR1K1 w - - 0 1",
          text = "When you are ahead in material, trade pieces (but not pawns). Fewer pieces means fewer chances for your opponent to fight back, and your extra material counts for more.\nHere White has an extra rook." },
        { kind = "find", fen = "3q1rk1/5ppp/8/8/8/8/5PPP/R2QR1K1 w - - 0 1", line = "d1d8",
          text = "Offer a queen trade.",
          hint = "Take the black queen. Black can recapture, but the trade helps you.",
          done = "With queens off, your extra rook decides the game." },
      } },
    } },

  ---------------------------------------------------------------------------
  { id = "endgames", title = "Endgame Practice",
    desc = "King activity, opposition, and checkmate drills against the computer.",
    lessons = {
      { id = "kingactive", title = "King Activity", steps = {
        { kind = "explain", fen = "8/5pkp/6p1/8/8/6P1/5PKP/8 w - - 0 1", marks = "d4:g e4:g d5:g e5:g",
          text = "In the middlegame the king hides. In the endgame, with fewer pieces around, the king becomes a strong fighter. March it toward the centre!" },
        { kind = "find", fen = "8/5pkp/6p1/8/8/6P1/5PKP/8 w - - 0 1", accept = "g2f3",
          text = "Start your king's march to the centre.",
          hint = "Step diagonally toward e4.",
          done = "Next stop e4. The more active king usually wins pawn endgames." },
      } },

      { id = "opposition", title = "The Opposition", steps = {
        { kind = "explain", fen = "8/8/8/3k4/8/3K4/8/8 b - - 0 1", marks = "d3:y d5:y d4:r",
          text = "When two kings face each other with one square between them, the player who must move has to give way. The other side \"has the opposition\".\nHere Black is to move, so White has the opposition." },
        { kind = "find", fen = "8/8/8/3k4/8/8/3K4/8 w - - 0 1", accept = "d2d3",
          text = "Take the opposition: move your king so the kings face each other with one square between, and Black has to move.",
          hint = "Step straight up the d-file.",
          done = "You have the opposition. In pawn endgames this decides who gets through." },
      } },

      { id = "square", title = "Rule of the Square", steps = {
        { kind = "explain", fen = "8/8/8/p7/8/8/8/4K2k w - - 0 1", marks = "a1:b a4:b d1:b d4:b a5:y",
          text = "Can your king catch a runaway pawn? Picture a square from the pawn to its promotion square (blue corners). If your king can step inside the square, it catches the pawn." },
        { kind = "find", fen = "8/8/8/p7/8/8/8/4K2k w - - 0 1", accept = "e1d2 e1d1",
          text = "Step into the square to catch the pawn.",
          hint = "The square runs from a1 to d4.",
          done = "You're inside the square, so the pawn can't escape your king." },
      } },

      { id = "queendrill", title = "Drill: Queen Checkmate", steps = {
        { kind = "explain", fen = "8/8/8/4k3/8/8/8/4K2Q w - - 0 1",
          text = "King and queen against a lone king is always a win. The method: use the queen to shrink the king's box, staying a knight's move away from it. Then bring your king close and deliver mate.\nWatch out for stalemate!" },
        { kind = "play", fen = "8/8/8/4k3/8/8/8/4K2Q w - - 0 1", goal = "mate", limit = 25,
          text = "Checkmate the computer's king within 25 moves.",
          hint = "Keep the queen a knight's move from the king to box it in. Never leave it without a move unless it's checkmate.",
          done = "Checkmate! You've mastered the most important basic mate." },
      } },

      { id = "rookdrill", title = "Drill: Rook Checkmate", steps = {
        { kind = "explain", fen = "8/8/8/4k3/8/8/8/R3K3 w - - 0 1",
          text = "King and rook can also force mate. The rook cuts the king off along a rank or file. Bring your king up, and whenever the kings face each other, check with the rook to push the king back a line." },
        { kind = "play", fen = "8/8/8/4k3/8/8/8/R3K3 w - - 0 1", goal = "mate", limit = 32,
          text = "Checkmate the computer's king within 32 moves.",
          hint = "Use the rook to cut off a rank. Approach with your king, and check when the kings are facing each other.",
          done = "Checkmate with the rook. Excellent technique!" },
      } },

      { id = "tworooks", title = "Drill: Two Rook Ladder", steps = {
        { kind = "play", fen = "8/8/8/3k4/8/8/8/R3K2R w - - 0 1", goal = "mate", limit = 12,
          text = "Use the ladder: checkmate with your two rooks within 12 moves.",
          hint = "One rook cuts off a rank, the other checks on the next rank. If the king attacks a rook, move it to the far side.",
          done = "Up the ladder and checkmate!" },
      } },

      { id = "pawndrill", title = "Drill: Promote the Pawn", steps = {
        { kind = "explain", fen = "4k3/8/4K3/4P3/8/8/8/8 w - - 0 1", marks = "e6:g",
          text = "With your king on the 6th rank in front of your pawn, the win is guaranteed. Use your king to clear the way, and keep the opposition in mind." },
        { kind = "play", fen = "4k3/8/4K3/4P3/8/8/8/8 w - - 0 1", goal = "promote", limit = 12,
          text = "Promote your pawn to a queen within 12 moves, without allowing stalemate or losing the pawn.",
          hint = "Your king steps aside to a square like d6 or f6 and escorts the pawn.",
          done = "The pawn has promoted. You've won the endgame!" },
      } },
    } },
}
