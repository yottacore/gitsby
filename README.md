<!-- omit in toc -->
# x9git

<!-- omit in toc -->
## Table of contents

- [Summary](#summary)
- [More detail](#more-detail)
- [General attributes](#general-attributes)
- ["Opinionated workflow": What are the opinions?](#opinionated-workflow-what-are-the-opinions)
- [Installation](#installation)

## Summary

An "extreme" Git wrapper.

This one *vastly* simplifies Git - by encouraging an opinionated workflow, and ignoring ≈50% of Git's myriad functionality in order to remove ≈95% of its complexity.

x9git and git are 100% compatible and interchangeable.

## More detail

One reason Git is so complex, is because it's so flexible. It's so flexible because it supports a wide variety of workflows, team sizes, and very narrow/hard edge-cases.

Arguably, about 90% of Git's complexity is due to covering a fringe about 10% of use-cases. If you buy that argument, then axiomatically, if you lop off that 10% of fringe use-cases, then Git becomes 90% easier to work with. This goes further, lopping off (very approximately) half of the functionality, and is about 95% easier to work with.

## General attributes

- x9git encourages an opinionated workflow.
- It doesn't cover fringe use-cases, which Git itself can cover while still using this for the more common stuff.
- It's goal-oriented, rather than task-driven. (Which sounds like hand-wavy doublespeak, but is true. The subcommands themselves illustrate how.)

To be clear, x9git is just a bash shell script. There's every very little "logic", it's more about exposing a set of goal-oriented commands, sanity-checking arguments and underlying filesystem, and then chaining together the appropriate git commands to accomplish that goal.

x9git and regular git are fully compatible. x9git does nothing that git can't do directly (usually with about 4x as many commands). Axiomatically, nothing git can do, will cause x9git problems - at least, conceptually. It's nigh impossible to test every possible permutation, but a main driver of x9git is 1) to make few assumptions about underlying state, and 2) do things in a safe way [if occasionally redundant and/or unnecessary], that is tolerant of unexpected or inconsistent states.

## "Opinionated workflow": What are the opinions?

There are many implicit opinions baked in, but here are the main explicit ones:

- `git pull --ff-only` is safer than and preferrable to `git pull --rebase`.
- `git push` only to a feature branch you created.
- Don't `push` to `develop`, `main`, or `master`; instead, create a pull request. Even if you otherwise have the rights to, and even for small personal projects. While pull requests are overkill for small personal projects, it is nevertheless good hygene, and fosters good working habits and experience.

## Installation

- Installing from the web
  ~~~
  cd /tmp
  wget https://raw.githubusercontent.com/jim-collier/x9git/main/x9git
  chmod +x x9git
  cp x9git "/wherever/you/need/it/to/go/"
  ~~~
- Updating existing version from local git copy
  ~~~
  tmpExisting="$(which x9git)" && cp x9git "${tmpExisting}" && chmod +x "${tmpExisting}"
  ~~~
