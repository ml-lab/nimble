#ifndef _NIMBLE_DLL
#define _NIMBLE_DLL
#include <Rinternals.h>

extern "C" {
  void callhw();
}


void RegisterNimblePointer(SEXP ptr, R_CFinalizer_t finalizer);

//#define RegisterNimbleFinalizer RegisterNimblePointer

#endif
