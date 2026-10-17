STORY UPDATE (overrides the arc in PROJECT_CONTEXT.md section 4 and the "final act" notes).
Game rules in section 3 do NOT change. This is story and presentation only.

PREMISE
The player is the Clockkeeper, climbing a burnt-out clock tower called the Pyre toward
the center of the dial. A playful fire spirit helps them by carrying ash between hours.

THE PROBLEM WE ARE FIXING
If the player is the loyal keeper and she is just an arsonist, the final choice is
obvious. So saving the clock must cost something, and her case must be believable.

THE SECRET (revealed in layers)
1. The Pyre runs on her. She is the clock's fuel. She has burned inside it for ages,
   bound there by the Keepers, the player's own order. The player was the jailer without
   knowing it.
2. The shadows are burnt-out hours. Every burn the player made, with her help, left one
   behind. The clock is dying partly because of the player's own puzzle-solving.
3. Her wish to burn the clock is a wish to be free. It is not malice.

ARC
- Act 1 (hours 12 and 2): she is charming, funny, helpful. The player thinks she is a
  guide. Tutorial: burn, ash transfer, wait.
- Act 2: shadows multiply. The player realizes they come from the hours that were burned.
  Her laugh starts to sound different (more strained, lonelier). The player starts to
  wonder what they have been doing.
- Act 3: the reveal that she is the fuel and the Keepers bound her. She is not escaping
  the clock, she is finishing it. She never begs. She teases right up to the end.

THE ENDING CHOICE (after the final level is won, NOT a core rule)
At the center the player chooses:
- WIND the clock: the clock is saved and the day goes on, but she is bound again and
  put out. The shadows fade.
- LET IT BURN: she is free, but the clock, the day, and the hours inside it are gone.
Neither ending is clean and neither is labelled "good" or "bad". The choice is between
duty and her freedom. It is implemented in presentation and dialogue after `level_won`
of the final level, so core logic stays deterministic.

TONE
Dark but not cruel. She is a trickster villain in presentation and a tragic figure in
truth. Her lines in act 1 should read as flirty-teasing and fun, and on a second
playthrough they should read as heartbreaking.

RULES FOR YOU (the AI)
- Do not add new core rules or object types because of this story.
- If something here conflicts with PROJECT_CONTEXT.md section 3, tell me instead of
  choosing silently.
- Keep the spirit original. Do not copy any existing character.
