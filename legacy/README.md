<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->

# Legacy builds

The Bash and PowerShell implementations of gitsby, frozen at **v2.1.0** (2026-08-14). Kept here for reference, not for use.

- `bin/gitsby` - the Bash build.
- `bin/gitsby.ps1` - the PowerShell build.
- `install.bash`, `install.ps1` - the v2.1.0 installers. They look for a `gitsby` / `gitsby.ps1` release asset, which only releases up to v2.1.0 publish, so `--ref v2.1.0` is the way to reach the frozen build once a later release exists.
- `install-dev.bash`, `install-dev.ps1` - contributor setup for the script era. Superseded; a Go checkout needs only Go.

## Why these are still here

The Go build in `src-go/` is compared against them. Every command the two share has to answer the same way, and `cicd/parity.bash` is what proves it. Once that comparison retires, so do these files - the v2.1.0 tag keeps them either way.

## Hotfixes do not start here

Start at the tag, where the whole tree is exactly what shipped - the scripts, the CI/CD pipeline that built them, and the installers, all in their original places and wired to each other:

```bash
git switch -c hotfix/2.1.1 v2.1.0
```

This folder is deliberately not that. It holds the deliverables alone: no pipeline, no test suite, nothing to run them with. Trying to hotfix from here means rebuilding what the tag already has.

A hotfix ships from its own branch and gets its own tag. It is never merged back to `main` - these paths do not exist there.

## Do not edit

Read them, compare against them, copy from them. Editing them creates a divergence with nothing left to reconcile it back.
