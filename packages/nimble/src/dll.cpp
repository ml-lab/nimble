#include <unordered_map>
#include "nimble/dll.h"

/*
 The idea is to maintain a table of Nimble objects created by routines in this model-specific DLL.
 Whenever we create an object, we call RegisterNimblePointer(). This caches the SEXP in the table
 and sets a finalizer to be called when R determines the SEXP is no longer referenced.
 This finalizer invokes the actual finalizer to release the 


  Some calls from the R code in the nimble package (i.e not the machine generated code for a model)
  calls some routines (in the nimble package's own dll/dso) and these are then in a different "space".
  This is a call to newNumberedObjects()
*/

void RNimble_PtrFinalizer(SEXP obj);

std::unordered_map<SEXP, R_CFinalizer_t> RnimblePtrs;

static SEXP DllPtr = NULL;
static const char *dllPath = NULL;

R_CFinalizer_t UnloadNimbleDll_Finalizer_ref = NULL;

/* This is called after we compile the model-specific DLL and we then set the DLLInfo object
   so it knows "who it is".
*/
extern "C"
SEXP 
R_setDllObject(SEXP ptr, SEXP finalizerRef)
{
    // should ensure it is not unloaded by the R code. Should we R_PreserveObject() this?
    DllPtr = ptr;
    dllPath = strdup(CHAR(STRING_ELT(VECTOR_ELT(DllPtr, 1), 0)));  // the path argument

    UnloadNimbleDll_Finalizer_ref = (R_CFinalizer_t) R_ExternalPtrAddr(finalizerRef);

    return(R_NilValue);
}


/* 
  This is  the routine that is called whenever we create an R external ptr within this DLL
  and need to ensure it is garbage collected.
 */
void
RegisterNimblePointer(SEXP ptr, R_CFinalizer_t finalizer)
{
    printf("RegisterNimblePointer:  %p, finalizer = %p.  Total number of nimble objects = %d in DLL %p\n", ptr, finalizer, (int) (RnimblePtrs.size() + 1), DllPtr);
#if 1   // for debugging
    size_t n = RnimblePtrs.size();
    if(n == 0)
        printf("first object\n");
#endif
    RnimblePtrs[ptr] = finalizer;
    R_RegisterCFinalizerEx(ptr, RNimble_PtrFinalizer, TRUE);
}

extern "C" 
void
ClearAllPointers()
{
  printf("ClearAllPointers\n");
  std::unordered_map<SEXP, R_CFinalizer_t>::iterator iPointers;
  R_CFinalizer_t cfun;
  SEXP obj;
  for(iPointers = RnimblePtrs.begin(); iPointers != RnimblePtrs.end(); iPointers++) {
    obj = iPointers->first;
    cfun = iPointers->second;
    printf("Calling finalizer %p for object %p\n", cfun, obj);
    if(cfun)
      cfun(obj); // invoke the finalizer
    R_ClearExternalPtr(obj);    
  }
  RnimblePtrs.clear();
}


/* Arrange to call dyn.unload(path.to.so) */
extern "C" 
void
UnloadNimbleDll_Finalizer(SEXP dummy)
{
        SEXP e;
 printf("UnloadNimbleDll_Finalizer\n");
        PROTECT(e = allocVector(LANGSXP, 2));
        SETCAR(e, Rf_install("dyn.unload"));
        SETCAR(CDR(e), R_ExternalPtrTag(dummy));
        Rf_PrintValue(e);
        DllPtr = NULL;
        Rf_eval(e, R_GlobalEnv);
        UNPROTECT(1);

}

/* A finalizer that creates another finalizer.
  This doesn't make sense!  We need to call back to the nimble package to ensure that this DLL does not contain the routine that is the finalizer itself.
  We can set a pointer to a routine in the nimble.so and use that as the finalizer. 
*/
void
UnloadNimbleDLL(SEXP dllInfo)
{
    if(UnloadNimbleDll_Finalizer_ref) {
        SEXP ref = R_MakeExternalPtr(dllInfo, Rf_install(dllPath), R_NilValue);
        PROTECT(ref);
        R_RegisterCFinalizerEx(ref, UnloadNimbleDll_Finalizer_ref, TRUE);
        UNPROTECT(1);
    }
}


void
RNimble_PtrFinalizer(SEXP obj)
{
    R_CFinalizer_t cfun;
    cfun = RnimblePtrs[obj];
    printf("Calling finalizer %p for object %p\n", cfun, obj);
    if(cfun)
      cfun(obj); // invoke the finalizer
    R_ClearExternalPtr(obj);
    RnimblePtrs.erase(obj);
    printf("number of remaining nimble pointers = %d\n", (int) RnimblePtrs.size());
    if(RnimblePtrs.empty() && DllPtr) {
        // arrange to dyn.unload()
        printf("no more nimble pointers in the DLL %p\n", DllPtr);
        Rf_PrintValue(DllPtr);
        // Interesting to see if we dyn.unload() from a routine in that DLL what happens.
        UnloadNimbleDLL(DllPtr);
    }
}


#ifndef IN_NIMBLE_PKG
#endif

extern "C"
SEXP
R_getNumNimbleObjects()
{
    return(ScalarReal(  RnimblePtrs.size() ) );
}


#if 0
//extern "C"
void 
R_dll_finalizer(SEXP obj)
{
    void *ptr = R_ExternalPtrAddr(obj);
    if(ptr)
       numExternalObjects--;

    R_ClearExternalPtr(obj);
}

void 
addExternalObject(SEXP obj)
{
    numExternalObjects++;
}
#endif
