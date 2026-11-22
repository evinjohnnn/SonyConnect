/*
 * Anchor translation unit.
 *
 * SwiftPM requires a C target to contain at least one compilable source file
 * even when the target is headers-only. The actual implementation lives in the
 * Rust core (libmdr_ffi.a); this file exists solely to satisfy the package
 * manifest and to trip a clear link error if the core was never built.
 */

#include "sony_mdr.h"

/* Referenced by the Swift layer's --version path through mdr_version(); taking
 * its address here guarantees the symbol is pulled from the archive. */
const char *sony_mdr_link_check(void)
{
    return mdr_version();
}
