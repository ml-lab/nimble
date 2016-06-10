#ifndef _NIMBLE_DLL
#define _NIMBLE_DLL
#include <Rinternals.h>

extern "C" {
  void hw();
  void showExtPtrAddress(SEXP obj);
}

void RegisterNimblePointer_shared(SEXP ptr, R_CFinalizer_t finalizer);
void Clear_PtrFinalizer_shared(SEXP obj);

//#define RegisterNimbleFinalizer RegisterNimblePointer

#endif
