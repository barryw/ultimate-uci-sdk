# The Ultimate SDK Programmer's Reference Guide

A book, in the style of the 1982 Commodore 64 User's Guide — because Commodore
knew how to write a manual that a person could actually sit down with.

```
make            # -> guide.pdf
```

Needs a TeX installation with `tcolorbox`, `titlesec`, `avant` and
`inconsolata`. TeX Live and MacTeX both have all four.

## What is here

| | |
|---|---|
| `guide.tex` | the book: front matter, and the order of the chapters |
| `ultimatesdk.sty` | the look — blue divider pages, C64 screens, keycaps |
| `chapters/` | one file per chapter |

## The style, and why

The original guide does a handful of things that make it recognisable, and each
one is a decision in `ultimatesdk.sty`:

- **A blue divider leaf in front of every chapter**, with a large numeral and
  the chapter's contents bulleted underneath. It doubles as a per-chapter table
  of contents, which is why the original is so easy to leaf through.
- **Section headings in bold blue**, set in a geometric sans. URW Gothic is as
  close to the original's Kabel as anything that ships with TeX.
- **Listings drawn as a C64 screen**, in the machine's own palette — so a
  listing in the book is the colour it will be on the screen in front of you.
  The text blue is lifted slightly for print; that is the one place legibility
  beats authenticity, and the style file says so.
- **Keys drawn as keycaps**, so RETURN reads as a key rather than as a word.
- **Warm second-person prose on a narrow measure.** The original says "you",
  and it explains before it specifies.

## Writing a chapter

```latex
\guidechapter{TITLE IN CAPS}{%
  \item what this chapter covers
  \item one bullet per section
}

\section{A Section}
Body text.

\begin{screen}
PRINT UREU
\end{screen}
```

`screen` is for what you type at the machine; `listingbox` is for source you
keep in a file. Both take raw underscores, so `ultimate_reu_size` needs no
escaping. `\key{return}` draws a keycap, and `note` and `warning` are the two
callout environments.

## Keeping it true

The guide repeats figures that live in the SDK's own documentation — timings,
sizes, keyword tokens, result codes. When those change, `docs/generated/` and
`docs/uci.md` are the source; this book follows them.
