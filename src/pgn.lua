-- pgn.lua - write a game in PGN, the standard chess file format that
-- Lichess, chess.com and chess software can open.

local PGN = {}

-- info: { white = "...", black = "...", date = "2026.10.07",
--         result = "1-0" | "0-1" | "1/2-1/2" | "*", timeControl = "300+0" or nil,
--         termination = "..." }
function PGN.build(g, info)
  local out = {
    '[Event "Vita Chess"]',
    '[Site "PlayStation Vita"]',
    '[Date "' .. (info.date or "????.??.??") .. '"]',
    '[Round "-"]',
    '[White "' .. info.white .. '"]',
    '[Black "' .. info.black .. '"]',
    '[Result "' .. info.result .. '"]',
  }
  if info.timeControl then out[#out + 1] = '[TimeControl "' .. info.timeControl .. '"]' end
  if info.termination then out[#out + 1] = '[Termination "' .. info.termination .. '"]' end
  out[#out + 1] = ""

  -- movetext, wrapped at 80 characters
  local tokens = {}
  for i, rec in ipairs(g.played) do
    if i % 2 == 1 then tokens[#tokens + 1] = math.floor((i + 1) / 2) .. "." end
    tokens[#tokens + 1] = rec.san
  end
  tokens[#tokens + 1] = info.result
  local line = ""
  for _, t in ipairs(tokens) do
    if #line + #t + 1 > 80 then out[#out + 1] = line; line = t
    else line = (line == "") and t or (line .. " " .. t) end
  end
  out[#out + 1] = line
  return table.concat(out, "\n") .. "\n"
end

return PGN
