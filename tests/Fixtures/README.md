# Fixtures

The test-suite does not store binary media. `Run-Tests.ps1` generates tiny fixtures at run time with FFmpeg's `lavfi` sources
(`testsrc`, `sine`, `color`) into a temporary folder (`fftui-tests-*` under the system temp path) and deletes that folder afterwards.
Helpers: `New-Fixture` in `tests/TestHelpers.ps1`. File names deliberately include spaces, parentheses, ampersands, apostrophes,
Arabic and Cyrillic characters.
