---
context: fork
agent: ebuild-writer
argument-hint: <repository-url>
---

Create a new Gentoo ebuild for the software at the following repository URL:

$ARGUMENTS

Research the project, determine the correct category, choose appropriate eclasses, and write the ebuild, metadata.xml, and Manifest following EAPI 8 best practices.

After writing the ebuild, run full verification: regenerate the Manifest, run `pkgcheck scan` for QA issues, and build the ebuild through the compile phase using `ebuild <path> clean fetch unpack prepare configure compile` (do not install). Fix any issues found before reporting completion.
