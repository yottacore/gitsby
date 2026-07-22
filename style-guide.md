<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Style guide

This is the canonical style guide for prose in this project: README, guides, changelog, doc comments, and anything else a human reads. For contribution process, see [contributing.md](contributing.md).

## Prose

- Write for a human in a hurry. Short sentences. One idea per sentence.

	- *Why: run-on sentences that chain several ideas with commas, dashes, and parentheticals are hard to scan, and even harder to translate.*

- Prefer nested bullet points over long paragraphs when there is any structure to convey.

	- *Why: structure that lives in punctuation is invisible; structure that lives in indentation is not.*

- Go easy on **bold**, *italics*, and ALL-CAPS. Use them for genuine emphasis, rarely.

- Skip flowery or dramatic adjectives and adverbs. "Fast" beats "blazingly fast".

- Stick to ASCII. Use `->` not a unicode arrow, `-` not an em/en dash, straight quotes not curly ones. (The one welcome exception: `©`.)

	- *Why: ASCII survives every terminal, diff tool, and grep unmangled.*

## Markdown mechanics

- Never hard-wrap prose. One paragraph or one bullet is one physical line; let the editor soft-wrap it.

	- *Why: hard-wrapped prose makes diffs noisy - a one-word edit reflows and touches many lines.*

- Tabs for indentation.

- Filenames are lower-case, except README.md.

- Files should pass markdownlint, with the per-file disable pragmas at the top of each file (see the top of this one).

## Rationale, in general

Consistency is the point. Any single rule above is debatable; a repo where every document follows the same rules is easier to read, edit, and review than one where each file has its own habits.
