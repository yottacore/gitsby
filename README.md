# x9git
YAGW: Yet Another Git Wrapper. One reason Git is so complex, is because it's so flexible. It's so flexible because it supports a wide variety of workflows and team sizes.

Arguably, 90% of Git's complexity is due to covering a fringe 10% of use-cases.

If you buy that argument, then axiomatically, if you lop off that 10% of fringe use-cases, then Git becomes 90% easier to work with.

This project aims to get most of the way there:

- x9git encourages (but doesn't necessarily enforce) an opinionated workflow
- It doesn't cover fringe use-cases, which Git itself can cover while still using this for the more common stuff.
- It's goal-oriented, rather than task-driven. (Which sounds like hand-wavy doublespeak, but is true. The subcommands themselves illustrate how.)

To be super clear, x9git is not magic. It's just a bash shell script. There's every very little "logic", it's more about exposing a set of goal-oriented commands, sanity-checking arguments and underlying filesystem, and then chaining together the appropriate git commands to accomplish that goal.

x9git and regular git are fully compatible. x9git does nothing that git can't do directly (usually with about 4x as many commands). Axiomatically, nothing git can do, will cause x9git problems - at least, conceptually. It's nigh impossible to test every possible permutation, but a main driver of x9git is 1) to make few assumptions about underlying state, and 2) do things in a safe way [if occasionally redundant and/or unnecessary], that is tolerant of unexpected or inconsistent states.

x9git can optionally be invoked by one or more simple custom wrapper scripts that optionally implements various pre- and/or post- hooks. This is as simple as writing a simple script (that maybe just copies a file somewhere, or invokes a build process), that starts off with `source x9git`.

x9git was written and is actively used for personal use, and a small corporate production team project. It has not been tested in a large team environment, but no design choices have been made that conceptually limit team size.

Note: This repo has no `develop` branch; feature branches are merged directly into `main`.
