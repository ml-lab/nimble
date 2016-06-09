#include <nimble/RcppUtils.h>
#include <nimble/ModelClassUtils.h>
#include <nimble/accessorClasses.h>
#include <nimble/dists.h>

#include <R_ext/Rdynload.h>

#define FUN(name, numArgs) \
  {#name, (DL_FUNC) &name, numArgs}

#define CFUN(name, numArgs) \
  {"R_"#name, (DL_FUNC) &name, numArgs}

#include <unordered_map>
std::unordered_map<SEXP, R_CFinalizer_t> RnimblePtrs_Pkg; // Here the finalizer will be the RNimble_PtrFinalizer in a nimble-generated dll
SEXP get_RnimblePtrs_Pkg() {
  return(R_MakeExternalPtr(&RnimblePtrs_Pkg, R_NilValue, R_NilValue));
}

// can't make an external function ptr, but we can pass the address from getNativeSymbolInfo 
void
RNimble_PtrFinalizer_Pkg(SEXP obj)
{
    R_CFinalizer_t cfun;
    cfun = RnimblePtrs_Pkg[obj];
    printf("In RNimble_PtrFinalizer_Pkg with finalizer %p for object %p\n", cfun, obj);
    if(cfun) {
      printf("Invoking DLL finalizer\n");
      cfun(obj); // invoke the finalizer
    } else {
      printf("Not invoking DLL finalizer because the pointer was already cleared\n");
    }
    R_ClearExternalPtr(obj);
    RnimblePtrs_Pkg.erase(obj);
    printf("number of remaining RnimblePtrs_Pkg pointers = %d\n", (int) RnimblePtrs_Pkg.size());
    // Below concepts go in DLL RNimble_PtrFinalizer
    // if(RnimblePtrs.empty() && DllPtr) {
    //     // arrange to dyn.unload()
    //     printf("no more nimble pointers in the DLL %p\n", DllPtr);
    //     Rf_PrintValue(DllPtr);
    //     // Interesting to see if we dyn.unload() from a routine in that DLL what happens.
    //     UnloadNimbleDLL(DllPtr);
    // }
}


R_CallMethodDef CallEntries[] = {
 {"getModelValuesPtrFromModel", (DL_FUNC) &getModelValuesPtrFromModel, 1},
// FUN(setNodeModelPtr, 3),
 FUN(getAvailableNames, 1),
 FUN(getMVElement, 2),
 FUN(setMVElement, 3),
 FUN(resizeManyModelVarAccessor, 2),
 FUN(resizeManyModelValuesAccessor, 2),
 FUN(getModelObjectPtr, 2),
 // FUN(getModelValuesMemberElement, 2),
 FUN(getNRow, 1),
 FUN(addBlankModelValueRows, 2),
 FUN(copyModelValuesElements, 4),
 FUN(C_dwish_chol, 5),
 FUN(C_rwish_chol, 3),
 FUN(C_ddirch, 3),
 FUN(C_rdirch, 1),
 FUN(C_dmulti, 4),
 FUN(C_rmulti, 2),
 FUN(C_dcat, 3),
 FUN(C_rcat, 2),
 FUN(C_dt_nonstandard, 5),
 FUN(C_rt_nonstandard, 4),
 FUN(C_dmnorm_chol, 5),
 FUN(C_rmnorm_chol, 3),
 FUN(C_dinterval, 4),
 FUN(C_rinterval, 3),
 FUN(makeNumericList, 3),
//   The following 4 conflict with names of R functions. So we prefix them with a R_
 CFUN(setPtrVectorOfPtrs, 3),
 CFUN(setOnePtrVectorOfPtrs, 3),
 CFUN(setDoublePtrFromSinglePtr, 2),
// CFUN(setSinglePtrFromSinglePtr, 2),
// FUN(newModelValues, 1),
 {NULL, NULL, 0}
};

/* Arrange to register the routines so that they can be checked and also accessed by 
   their equivalent name as an R symbol, e.g. .Call(setNodeModelPtr, ....)
 */
extern "C"
void
R_init_nimble(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
}


