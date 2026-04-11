---
context: fork
agent: ebuild-writer
argument-hint: <repository-url>
---

Create a new Gentoo ebuild for the software at the following repository URL:

$ARGUMENTS

Research the project and determine the correct category by first checking whether the package already exists in the official Gentoo tree (packages.gentoo.org or gitweb.gentoo.org) or the GURU repository (gitweb.gentoo.org/repo/proj/guru.git). Use that category — do not infer from the package's nature. Only fall back to inference if the package has no presence in either repository. Then choose appropriate eclasses and write the ebuild, metadata.xml, and Manifest following EAPI 8 best practices.

After writing the ebuild, run full verification: regenerate the Manifest, run `pkgcheck scan` for QA issues, and build the ebuild through the compile phase using `ebuild <path> clean fetch unpack prepare configure compile` (do not install). Fix any issues found before reporting completion.
