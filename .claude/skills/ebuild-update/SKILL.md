---
context: fork
agent: ebuild-updater
argument-hint: <category/name>
---

Check upstream for new releases and bump the ebuild version for the following package:

$ARGUMENTS

Find the existing ebuild(s), determine the upstream source from metadata.xml, compare versions, and create a new ebuild for the latest upstream release if one is available.

After creating the new ebuild, run full verification: regenerate the Manifest, run `pkgcheck scan` for QA issues, and build the new ebuild through the compile phase using `ebuild <path> clean fetch unpack prepare configure compile` (do not install). Fix any issues found before reporting completion.
