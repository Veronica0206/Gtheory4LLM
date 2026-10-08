#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <R.h>
#include <Rinternals.h>
#include <dlfcn.h>

/* Read-only diagnostics: inspect an already-loaded provider, never load one. */
SEXP gtheory_openblas_meta(SEXP path) {
    const char *keys[] = {"available", "status", "requested_path",
        "provider_path", "config", "corename", "num_threads", "parallel"};
    SEXP out, names;
    void *handle = NULL;
    void *config_symbol = NULL;
    char *(*config_fn)(void) = NULL;
    char *(*core_fn)(void) = NULL;
    int (*threads_fn)(void) = NULL;
    int (*parallel_fn)(void) = NULL;
    int i;
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 ||
        STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("Expected one nonmissing loaded-library path");
    }
    PROTECT(out = Rf_allocVector(VECSXP, 8));
    PROTECT(names = Rf_allocVector(STRSXP, 8));
    for (i = 0; i < 8; ++i) SET_STRING_ELT(names, i, Rf_mkChar(keys[i]));
    Rf_setAttrib(out, R_NamesSymbol, names);
    SET_VECTOR_ELT(out, 0, Rf_ScalarLogical(0));
    SET_VECTOR_ELT(out, 1, Rf_mkString("rtld_noload_unavailable"));
    SET_VECTOR_ELT(out, 2, Rf_mkString(CHAR(STRING_ELT(path, 0))));
    for (i = 3; i < 6; ++i) SET_VECTOR_ELT(out, i, Rf_ScalarString(NA_STRING));
    SET_VECTOR_ELT(out, 6, Rf_ScalarInteger(NA_INTEGER));
    SET_VECTOR_ELT(out, 7, Rf_ScalarInteger(NA_INTEGER));
#ifdef RTLD_NOLOAD
    handle = dlopen(CHAR(STRING_ELT(path, 0)), RTLD_LAZY | RTLD_NOLOAD);
    if (!handle) {
        SET_VECTOR_ELT(out, 1, Rf_mkString("provider_not_loaded"));
        UNPROTECT(2);
        return out;
    }
    config_symbol = dlsym(handle, "openblas_get_config");
    config_fn = (char *(*)(void)) config_symbol;
    core_fn = (char *(*)(void)) dlsym(handle, "openblas_get_corename");
    threads_fn = (int (*)(void)) dlsym(handle, "openblas_get_num_threads");
    parallel_fn = (int (*)(void)) dlsym(handle, "openblas_get_parallel");
    if (config_fn && core_fn && threads_fn && parallel_fn) {
        Dl_info info;
        const char *config = config_fn();
        const char *core = core_fn();
        SET_VECTOR_ELT(out, 0, Rf_ScalarLogical(1));
        SET_VECTOR_ELT(out, 1, Rf_mkString("ok"));
        if (dladdr(config_symbol, &info) && info.dli_fname) {
            SET_VECTOR_ELT(out, 3, Rf_mkString(info.dli_fname));
        }
        if (config) SET_VECTOR_ELT(out, 4, Rf_mkString(config));
        if (core) SET_VECTOR_ELT(out, 5, Rf_mkString(core));
        SET_VECTOR_ELT(out, 6, Rf_ScalarInteger(threads_fn()));
        SET_VECTOR_ELT(out, 7, Rf_ScalarInteger(parallel_fn()));
    } else {
        SET_VECTOR_ELT(out, 1, Rf_mkString("missing_openblas_symbols"));
    }
    dlclose(handle);
#endif
    UNPROTECT(2);
    return out;
}
