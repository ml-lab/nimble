#include <Rinternals.h>

void RegisterNimblePointer(SEXP ptr, R_CFinalizer_t finalizer);

#define RegisterNimbleFinalizer RegisterNimblePointer

