#include <unordered_map>
#include "nimble/dll_shared.h"

/*
 The idea is to maintain a table of Nimble objects created by routines in this model-specific DLL.
 Whenever we create an object, we call RegisterNimblePointer(). This caches the SEXP in the table
 and sets a finalizer to be called when R determines the SEXP is no longer referenced.
 This finalizer invokes the actual finalizer to release the 


  Some calls from the R code in the nimble package (i.e not the machine generated code for a model)
  calls some routines (in the nimble package's own dll/dso) and these are then in a different "space".
  This is a call to newNumberedObjects()
*/


/*
Update to this idea:
dll.cpp will be compiled into each on-the-fly dll
dll_shared.cpp will be compiled once for each R/nimble session, upon first use of compileNimble.

dll_shared.cpp will contain "global" finalizer registry system for objects *all* dlls throughout a session.
dll.cpp will contain a registry system just for objects from itself

The two registries are called hierarchically.  The purpose of the dll_shared registry is so that even if a particular cppProject dll is dyn.unloaded(), there is a still a valid finalizer function.

There is apparently *no* way to clear a registered finalizer except via R's garbage collection mechanism, and that is not proving to be reliable for our needs.
*/

void hw() {
  // this exists to allow a test of what is loaded
  printf("Hello world from dll.cpp\n");
}

void RNimble_PtrFinalizer_shared(SEXP obj);

std::unordered_map<SEXP, R_CFinalizer_t> RnimblePtrs_shared;

//static SEXP DllPtr = NULL;
//static const char *dllPath = NULL;
//R_CFinalizer_t UnloadNimbleDll_Finalizer_ref = NULL;

//R_CFinalizer_t RNimble_PtrFinalizer_Pkg;
// // whoops, this cast isn't allowed.  
// void set_RNimble_PtrFinalizer_Pkg(SEXP ptr) {
//   RNimble_PtrFinalizer_Pkg = static_cast<R_CFinalizer_t>(R_ExternalPtrAddr(ptr) );
// }


/* This is called after we compile the model-specific DLL and we then set the DLLInfo object
   so it knows "who it is".
*/
// Not using this yet.
// extern "C"
// SEXP 
// R_setDllObject(SEXP ptr, SEXP finalizerRef)
// {
//     // should ensure it is not unloaded by the R code. Should we R_PreserveObject() this?
//     DllPtr = ptr;
//     dllPath = strdup(CHAR(STRING_ELT(VECTOR_ELT(DllPtr, 1), 0)));  // the path argument

//     UnloadNimbleDll_Finalizer_ref = (R_CFinalizer_t) R_ExternalPtrAddr(finalizerRef);

//     return(R_NilValue);
// }


/* 
  This is  the routine that is called whenever we create an R external ptr within this DLL
  and need to ensure it is garbage collected.
 */
void
RegisterNimblePointer_shared(SEXP ptr, R_CFinalizer_t finalizer)
{
  printf("RegisterNimblePointer_shared:  %p, finalizer = %p.  Total number of nimble objects = %d.\n", ptr, finalizer, (int) (RnimblePtrs_shared.size() + 1));
#if 1   // for debugging
    size_t n = RnimblePtrs_shared.size();
    if(n == 0)
        printf("first object\n");
#endif
    RnimblePtrs_shared[ptr] = finalizer;
    R_RegisterCFinalizerEx(ptr, RNimble_PtrFinalizer_shared, TRUE);
}

/* Arrange to call dyn.unload(path.to.so) */
// extern "C" 
// void
// UnloadNimbleDll_Finalizer(SEXP dummy)
// {
//         SEXP e;
//  printf("UnloadNimbleDll_Finalizer\n");
//         PROTECT(e = allocVector(LANGSXP, 2));
//         SETCAR(e, Rf_install("dyn.unload"));
//         SETCAR(CDR(e), R_ExternalPtrTag(dummy));
//         Rf_PrintValue(e);
//         DllPtr = NULL;
//         Rf_eval(e, R_GlobalEnv);
//         UNPROTECT(1);

// }

/* A finalizer that creates another finalizer.
  This doesn't make sense!  We need to call back to the nimble package to ensure that this DLL does not contain the routine that is the finalizer itself.
  We can set a pointer to a routine in the nimble.so and use that as the finalizer. 
*/
// void
// UnloadNimbleDLL(SEXP dllInfo)
// {
//     if(UnloadNimbleDll_Finalizer_ref) {
//         SEXP ref = R_MakeExternalPtr(dllInfo, Rf_install(dllPath), R_NilValue);
//         PROTECT(ref);
//         R_RegisterCFinalizerEx(ref, UnloadNimbleDll_Finalizer_ref, TRUE);
//         UNPROTECT(1);
//     }
// }

void showExtPtrAddress(SEXP obj) {
  printf("pointer %p pointer to address %p\n", obj, R_ExternalPtrAddr(obj));
}

void Clear_PtrFinalizer_shared(SEXP obj) {
  RnimblePtrs_shared.erase(obj);
}

void
RNimble_PtrFinalizer_shared(SEXP obj)
{
    R_CFinalizer_t cfun;
    cfun = RnimblePtrs_shared[obj];
    printf("From shared finalizer, checking for single dll finalizer %p for object %p\n", cfun, obj);
    if(cfun) {
      printf("Invoking single dll finalizer\n");
      cfun(obj); // invoke the finalizer
    } else {
      printf("Not invoking single dll finalizer because the pointer was already cleared\n");
    }
    R_ClearExternalPtr(obj);
    RnimblePtrs_shared.erase(obj);
    printf("number of remaining global nimble pointers = %d\n", (int) RnimblePtrs_shared.size());
    if(RnimblePtrs_shared.empty()) {
        // arrange to dyn.unload()
        printf("no more global nimble pointers.\n");
	//        Rf_PrintValue(DllPtr);
        // Interesting to see if we dyn.unload() from a routine in that DLL what happens.
        //UnloadNimbleDLL(DllPtr);
    }
}

#ifndef IN_NIMBLE_PKG
#endif

// extern "C"
// SEXP
// R_getNumNimbleObjects()
// {
//     return(ScalarReal(  RnimblePtrs.size() ) );
// }


// #if 0
// //extern "C"
// void 
// R_dll_finalizer(SEXP obj)
// {
//     void *ptr = R_ExternalPtrAddr(obj);
//     if(ptr)
//        numExternalObjects--;

//     R_ClearExternalPtr(obj);
// }

// void 
// addExternalObject(SEXP obj)
// {
//     numExternalObjects++;
// }
// #endif
