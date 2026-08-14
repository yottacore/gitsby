<!-- omit in toc -->
# Contributing

*This file was generated via [https://contributing.md/generator/](https://contributing.md/generator/)*

First off, thanks for taking the time to contribute!

All types of contributions are encouraged and valued. See the [Table of Contents](#table-of-contents) for different ways to help and details about how this project handles them. Please make sure to read the relevant section before making your contribution. It will make it a lot easier for us maintainers and smooth out the experience for all involved. The community looks forward to your contributions.

> And if you like the project, but just don't have time to contribute, that's fine. There are other easy ways to support the project and show your appreciation, which we would also be very happy about:
>
> - Star the project
> - Tweet/skeet/post about it
> - Refer this project in your project's readme
> - Mention the project to your friends/colleagues

<!-- omit in toc -->
## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [I Have a Question](#i-have-a-question)
- [I Want To Contribute](#i-want-to-contribute)
	- [Reporting Bugs](#reporting-bugs)
	- [Suggesting Enhancements](#suggesting-enhancements)
	- [Your First Code Contribution](#your-first-code-contribution)
- [Styleguides](#styleguides)
	- [Commit Messages](#commit-messages)

## Code of Conduct

This project and everyone participating in it is governed by the
[gitsby Code of Conduct](https://github.com/jim-collier/gitsby/blob/main/code_of_conduct.md).
By participating, you are expected to uphold this code. Please report unacceptable behavior to <gitsby@ubx9.com>.

## I Have a Question

Before you ask a question, it is best to search for existing [Issues](https://github.com/jim-collier/gitsby/issues) that might help you. In case you have found a suitable issue and still need clarification, you can write your question in this issue. It is also advisable to search the internet for answers first.

If you then still feel the need to ask a question and need clarification, we recommend the following:

- Open an [Issue](https://github.com/jim-collier/gitsby/issues/new).
- Provide as much context as you can about what you're running into.
- Provide project and platform versions, depending on what seems relevant.

We will then take care of the issue as soon as possible.

<!--
You might want to create a separate issue tag for questions and include it in this description. People should then tag their issues accordingly.

Depending on how large the project is, you may want to outsource the questioning, e.g. to Stack Overflow or Gitter. You may add additional contact and information possibilities:
- IRC
- Slack
- Gitter
- Stack Overflow tag
- Blog
- FAQ
- Roadmap
- E-Mail List
- Forum
-->

## I Want To Contribute

> ### Legal Notice <!-- omit in toc -->
>
> When contributing to this project, you must agree that you have authored 100% of the content, that you have the necessary rights to the content and that the content you contribute may be provided under the project licence.

### Reporting Bugs

<!-- omit in toc -->
#### Before Submitting a Bug Report

A good bug report shouldn't leave others needing to chase you up for more information. Therefore, we ask you to investigate carefully, collect information and describe the issue in detail in your report. Please complete the following steps in advance to help us fix any potential bug as fast as possible.

- Make sure that you are using the latest version.
- Determine if your bug is really a bug and not an error on your side e.g. using incompatible environment components/versions (Make sure that you have read the [documentation](https://github.com/jim-collier/gitsby/blob/main/README.md). If you are looking for support, you might want to check [this section](#i-have-a-question)).
- To see if other users have experienced (and potentially already solved) the same issue you are having, check if there is not already a bug report existing for your bug or error in the [bug tracker](https://github.com/jim-collier/gitsby/issues?q=label%3Abug).
- Also search the internet, including Stack Overflow, to see if users outside the GitHub community have discussed the issue.
- Collect information about the bug:
	- OS, platform, and version (Windows, Linux, macOS, x86_64, ARM64).
	- Which implementation, Bash or PowerShell, and its version.
	- Your `git` version, and `gitsby -v`.
	- Your input and the output.
	- Can you reliably reproduce it? Can you reproduce it with older versions?
	- Steps to cleanly reproduce from scratch.

<!-- omit in toc -->
#### How Do I Submit a Good Bug Report?

> You must never report security related issues, vulnerabilities or bugs including sensitive information to the issue tracker, or elsewhere in public. Instead sensitive bugs must be sent by email to <gitsby@ubx9.com>.
<!-- You may add a PGP key to allow the messages to be sent encrypted as well. -->

We use GitHub issues to track bugs and errors. If you run into an issue with the project:

- Open an [Issue](https://github.com/jim-collier/gitsby/issues/new). (Since we can't be sure at this point whether it is a bug or not, we ask you not to talk about a bug yet and not to label the issue.)
- Explain the behavior you would expect and the actual behavior.
- Please provide as much context as possible and describe the *reproduction steps* that someone else can follow to recreate the issue on their own. This usually includes your code. For good bug reports you should isolate the problem and create a reduced test case.
- Provide the information you collected in the previous section.

Once it's filed:

- The project team will label the issue accordingly.
- A team member will try to reproduce the issue with your provided steps. If there are no reproduction steps or no obvious way to reproduce the issue, the team will ask you for those steps and mark the issue as `needs-repro`. Bugs with the `needs-repro` tag will not be addressed until they are reproduced.
- If the team is able to reproduce the issue, it will be marked `needs-fix`, as well as possibly other tags (such as `critical`), and the issue will be left to be implemented by someone.

<!-- You might want to create an issue template for bugs and errors that can be used as a guide and that defines the structure of the information to be included. If you do so, reference it here in the description. -->

### Suggesting Enhancements

This covers both new features and small improvements to what's already there. Following these guidelines helps everyone understand your suggestion and find related ones.

<!-- omit in toc -->
#### Before Submitting an Enhancement

- Make sure that you are using the latest version.
- Read the [documentation](https://github.com/jim-collier/gitsby/blob/main/README.md) carefully and find out if the functionality is already covered, maybe by an individual configuration.
- Perform a [search](https://github.com/jim-collier/gitsby/issues) to see if the enhancement has already been suggested. If it has, add a comment to the existing issue instead of opening a new one.
- Find out whether your idea fits with the scope and aims of the project. It's up to you to make a strong case to convince the project's developers of the merits of this feature. Keep in mind that we want features that will be useful to the majority of our users and not just a small subset. If you're just targeting a minority of users, consider writing an add-on/plugin library.

<!-- omit in toc -->
#### How Do I Submit a Good Enhancement Suggestion?

Enhancement suggestions are tracked as [GitHub issues](https://github.com/jim-collier/gitsby/issues).

- Use a clear and descriptive title.
- Describe the suggestion step by step, in as much detail as you can.
- Say what the current behavior is, what you expected instead, and why. Mention any alternatives that don't work for you.
- Explain why it would be useful to most gitsby users. Pointing at another project that solved it well helps.

<!-- You might want to create an issue template for enhancement suggestions that can be used as a guide and that defines the structure of the information to be included. If you do so, reference it here in the description. -->

### Your First Code Contribution

<!-- omit in toc -->
#### Set up

One-liner setup. It clones the repo, checks out the `dev` branch, and checks the tooling, offering to install what's missing. It shows the plan and asks before doing anything.

- Linux / macOS:

	~~~bash
	curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.bash | bash
	~~~

- Windows (PowerShell 7+):

	~~~pwsh
	irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.ps1 | iex
	~~~

Or clone it yourself and install the tooling by hand.

<!-- omit in toc -->
#### What you need

- `git`, and `bash` 4.4 or newer. (The two installers themselves also run on macOS stock bash 3.2.)
- `shellcheck`, to lint the Bash side.
- `pwsh` 7+ and its `PSScriptAnalyzer` module, if you touch the PowerShell side. Without them, those stages report themselves absent and skip.
- `markdownlint` (`npm install -g markdownlint-cli`), to lint the docs.
- `python3` with Pillow, and optionally `gifsicle`, to regenerate the demo. Only needed for a full pipeline run.
- `gh`, if you want to exercise the `pr` command.

<!-- omit in toc -->
#### Where things are

- `bin/gitsby` and `bin/gitsby.ps1` - the two implementations. They are ports of each other, so a change to one nearly always belongs in the other.
- `cicd/` - the local pipeline and its config.
- `cicd/utility/demo/` - everything the demo gif is built from. Start at `script.txt`, which describes scene by scene what the demo shows; the scenario file beside it is the same thing in the form the renderer reads.
- `project/` - design notes and the backlog.

<!-- omit in toc -->
#### Run the checks

- `cicd/cicd.bash --quick` - the whole pipeline, minus the slow stages. Run this before you push.
- `cicd/cicd.bash` - everything, including the fuzz suite and the demo.

- `cicd/parity.bash` - just the parity suite: whether the two builds *answer the same* for one input, rather than whether each behaves correctly. Runs inside the test stage too.
- `cicd/release.bash --dry-run` - what cutting a release would do, changing nothing.
- `cicd/test.bash` - just the regression suite. It builds throwaway repos under a temp directory and never touches the network or your real repos.
- `cicd/fuzz.bash` - just the fuzz suite.

The pipeline fast-forwards from `origin` before it builds anything, so the checks run against the tree that will actually be pushed. It stops if your branch has diverged, warns and carries on if you're offline or the branch has no upstream, and `--no-sync` (`-NoSync`) skips it.

Both suites run once per implementation, so a Bash-only change still has to keep the PowerShell side green.

<!-- omit in toc -->
#### Then

Work on a short-named feature branch off `dev`, and open a PR back to `dev`. `main` is release-only. Coding style is in [style-guide.md](style-guide.md).

<!-- TODO
### Improving The Documentation
Updating, improving and correcting the documentation

-->

## Styleguides

Code (Bash and PowerShell) follows the project [style guide](style-guide.md).

### Commit Messages

Short and plain. A few words about what changed is enough, and that is what the history here looks like. Put the detail in the pull request, not the subject line.

<!-- TODO
## Join The Project Team
-->

<!-- omit in toc -->
## Attribution

This guide is based on the [contributing.md generator](https://contributing.md/generator)!
