---
context: fork
agent: ebuild-verifier
argument-hint: <category/name> or <category/name-version>
---

Run full verification for the following Gentoo package:

$ARGUMENTS

Run all verification steps: regenerate the Manifest if needed, run pkgcheck QA scan, and build the ebuild through the compile phase (without installing). Report the results of each step.
