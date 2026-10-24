/* Selected inverse of a sparse Cholesky factor, with queries and local
   contractions, for the analytic gradient of the first-order Laplace objective.

   The gradient of L(theta) = f(u*, theta) + log det H / 2 needs entries of
   H^{-1} on the structural pattern of the factor: the trace of H^{-1} against
   each parameter derivative of H, and for every observation the small block
   W_i H^{-1} W_i'. Forming H^{-1} densely is out of the question at the sizes
   the sparse engine fits (10.77 GiB at 38,028 random dimensions), so these
   entries come from the Takahashi recurrence on the factor's own pattern.

   Input is the permuted lower Cholesky factor L of H, with H[perm, perm] = LL',
   in compressed sparse column storage: for every column the diagonal entry
   first, then strictly increasing row indices. Everything the R side hands
   over is validated here again: types, lengths against the declared caps in a
   wide integer type before any narrowing, pointer monotonicity, the diagonal's
   position and positivity, finiteness. The recurrence visits columns from the
   last to the first; for column i with neighbours j > i in the pattern,

       S[j, i] = - sum_{k > i, k in pattern(i)} L[k, i] S[k, j] / L[i, i],
       S[i, i] = 1 / L[i, i]^2 - sum_{k > i} L[k, i] S[k, i] / L[i, i].

   Every S[k, j] the recurrence reads is itself on the pattern when the pattern
   is a valid Cholesky fill (its neighbours form a clique); if an entry is
   absent the routine refuses rather than treating it as zero, because a
   derivative can be nonzero where the current Hessian entry is zero and a
   silently omitted entry would give a plausible wrong gradient. Sums are
   accumulated in long double in ascending neighbour order; the platform's
   long double width is reported so cross-platform comparisons can account
   for it.

   Nothing here fits a model, forms a mode or decides acceptance. The routines
   are internal, reached through registered .Call entry points only, and the
   R side maps original coordinates to permuted positions. */

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>
#include <float.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

/* Declared caps. They bound allocation and work before anything is allocated,
   and a request that exceeds one is refused by name; they are not estimates
   of what a machine can afford. .gt_selected_caps() reports them to R. */
#define GT_SI_MAX_DIMENSION 60000
#define GT_SI_MAX_FILL 15000000
#define GT_SI_MAX_RECURRENCE 15000000000.0L
#define GT_SI_MAX_QUERIES 8000000
#define GT_SI_MAX_OBSERVATIONS 25000
#define GT_SI_MAX_LOCAL_WIDTH 128
#define GT_SI_MAX_LATENT 8
#define GT_SI_MAX_CONTRACTION_WORK 100000000.0
#define GT_SI_ACCUMULATORS (GT_SI_MAX_LATENT * GT_SI_MAX_LOCAL_WIDTH)

/* Validate a lower Cholesky factor in CSC storage and return its dimension.
   The recurrence work, the sum of squared off-diagonal column degrees, is
   returned through `work` so the caller can report it. */
static int gt_si_csc(SEXP ps, SEXP is, SEXP xs, double *work) {
  if (TYPEOF(ps) != INTSXP || TYPEOF(is) != INTSXP || TYPEOF(xs) != REALSXP)
    Rf_error("Selected inverse: column pointers and row indices must be integer and factor values double.");
  R_xlen_t np = XLENGTH(ps), nz = XLENGTH(is);
  if (np < 2) Rf_error("Selected inverse: the factor needs at least one column.");
  if (np - 1 > GT_SI_MAX_DIMENSION)
    Rf_error("Selected inverse: the factor exceeds the declared dimension cap (%d).", GT_SI_MAX_DIMENSION);
  if (nz > GT_SI_MAX_FILL)
    Rf_error("Selected inverse: the factor exceeds the declared fill cap (%d entries).", GT_SI_MAX_FILL);
  if (nz != XLENGTH(xs))
    Rf_error("Selected inverse: row indices and factor values differ in length.");
  int n = (int) (np - 1), *p = INTEGER(ps), *row = INTEGER(is);
  double *x = REAL(xs);
  if (p[0] != 0 || p[n] != (int) nz) Rf_error("Selected inverse: invalid CSC size.");
  long double operations = 0;
  for (int j = 0; j < n; ++j) {
    if (p[j] == NA_INTEGER || p[j + 1] == NA_INTEGER || p[j] < 0 || p[j] >= p[j + 1] || p[j + 1] > (int) nz)
      Rf_error("Selected inverse: invalid CSC column pointers.");
    if (row[p[j]] != j || !R_FINITE(x[p[j]]) || x[p[j]] <= 0)
      Rf_error("Selected inverse: every column must start with a finite positive diagonal entry.");
    int previous = j - 1;
    for (int z = p[j]; z < p[j + 1]; ++z) {
      if (row[z] == NA_INTEGER || row[z] <= previous || row[z] < j || row[z] >= n || !R_FINITE(x[z]))
        Rf_error("Selected inverse: row indices must be finite, strictly increasing and lower triangular.");
      previous = row[z];
    }
    long double degree = p[j + 1] - p[j] - 1;
    operations += degree * degree;
  }
  if (operations > GT_SI_MAX_RECURRENCE)
    Rf_error("Selected inverse: the recurrence work cap (%.0f products) is exceeded.", (double) GT_SI_MAX_RECURRENCE);
  *work = (double) operations;
  return n;
}

/* Position of the stored entry at (a, b) in either triangle, by binary search
   within the column of the smaller index. Absent support is a refusal. */
static int gt_si_entry(const int *p, const int *row, int a, int b) {
  int col = a < b ? a : b, target = a < b ? b : a;
  int lo = p[col], hi = p[col + 1];
  while (lo < hi) {
    int mid = lo + (hi - lo) / 2;
    if (row[mid] < target) lo = mid + 1; else hi = mid;
  }
  if (lo == p[col + 1] || row[lo] != target)
    Rf_error("Selected inverse: a required entry is outside the factor's structural pattern.");
  return lo;
}

static void gt_si_names(SEXP result, const char **values, int n) {
  SEXP names = PROTECT(Rf_allocVector(STRSXP, n));
  for (int j = 0; j < n; ++j) SET_STRING_ELT(names, j, Rf_mkChar(values[j]));
  Rf_setAttrib(result, R_NamesSymbol, names);
  UNPROTECT(1);
}

/* The selected inverse on the factor's pattern, aligned with the factor's
   values: inverse[z] is S at the position row[z], column of z. */
SEXP gt_selected_inverse(SEXP ps, SEXP is, SEXP xs) {
  double work;
  int n = gt_si_csc(ps, is, xs, &work), *p = INTEGER(ps), *row = INTEGER(is);
  double *lower = REAL(xs);
  SEXP out = PROTECT(Rf_allocVector(REALSXP, XLENGTH(xs)));
  double *inverse = REAL(out);
  memset(inverse, 0, (size_t) XLENGTH(xs) * sizeof(double));
  int max_degree = 0;
  for (int col = 0; col < n; ++col) {
    int degree = p[col + 1] - p[col] - 1;
    if (degree > max_degree) max_degree = degree;
  }
  /* R_alloc does not promise long double alignment: reserve padding and align
     the one reusable scratch array explicitly, once, not per column. */
  size_t alignment = _Alignof(long double);
  size_t scratch_bytes = (size_t) max_degree * sizeof(long double);
  unsigned char *raw = (unsigned char *) R_alloc(scratch_bytes + alignment, 1);
  uintptr_t address = (uintptr_t) raw;
  size_t offset = (alignment - address % alignment) % alignment;
  long double *sums = (long double *) (raw + offset);
  for (int col = n - 1; col >= 0; --col) {
    int diagonal = p[col], first = diagonal + 1, end = p[col + 1];
    int degree = end - first;
    long double pivot = lower[diagonal];
    memset(sums, 0, (size_t) degree * sizeof(long double));
    /* The sorted neighbours form a clique in a valid Cholesky pattern. Visit
       its lower triangle once with monotone scans of each neighbour's column;
       contributions still arrive in ascending neighbour order. */
    for (int a = 0; a < degree; ++a) {
      int neighbour = row[first + a], at = p[neighbour], stop = p[neighbour + 1];
      for (int b = a; b < degree; ++b) {
        int target = row[first + b];
        while (at < stop && row[at] < target) ++at;
        if (at == stop || row[at] != target)
          Rf_error("Selected inverse: a required entry is outside the factor's structural pattern.");
        double value = inverse[at];
        sums[a] += (long double) lower[first + b] * value;
        if (b != a) sums[b] += (long double) lower[first + a] * value;
      }
    }
    for (int j = 0; j < degree; ++j) {
      inverse[first + j] = (double) (-sums[j] / pivot);
      if (!R_FINITE(inverse[first + j])) Rf_error("Selected inverse: a computed entry is not finite.");
    }
    long double sum = 0;
    for (int kp = first; kp < end; ++kp) sum += (long double) lower[kp] * inverse[kp];
    inverse[diagonal] = (double) ((1 / pivot - sum) / pivot);
    if (!R_FINITE(inverse[diagonal]) || inverse[diagonal] <= 0)
      Rf_error("Selected inverse: a computed diagonal entry is not finite and positive.");
    if (col % 64 == 0) R_CheckUserInterrupt();
  }
  SEXP answer = PROTECT(Rf_allocVector(VECSXP, 5));
  SET_VECTOR_ELT(answer, 0, out);
  SET_VECTOR_ELT(answer, 1, Rf_ScalarInteger(n));
  SET_VECTOR_ELT(answer, 2, Rf_ScalarReal((double) XLENGTH(xs)));
  SET_VECTOR_ELT(answer, 3, Rf_ScalarReal(work));
  SET_VECTOR_ELT(answer, 4, Rf_ScalarReal((double) XLENGTH(xs) * sizeof(double)));
  const char *names[] = {"x", "dimension", "factor_entries", "inner_products", "value_bytes"};
  gt_si_names(answer, names, 5);
  UNPROTECT(2);
  return answer;
}

/* Entries of the selected inverse at permuted positions (1-based), in either
   triangle. A position outside the pattern is a refusal, never a zero. */
SEXP gt_selected_queries(SEXP ps, SEXP is, SEXP xs, SEXP rs, SEXP cs) {
  double work;
  int n = gt_si_csc(ps, is, xs, &work);
  if (TYPEOF(rs) != INTSXP || TYPEOF(cs) != INTSXP)
    Rf_error("Selected inverse: query positions must be integer vectors.");
  if (XLENGTH(rs) != XLENGTH(cs))
    Rf_error("Selected inverse: query rows and columns differ in length.");
  if (XLENGTH(rs) > GT_SI_MAX_QUERIES)
    Rf_error("Selected inverse: the query cap (%d positions) is exceeded.", GT_SI_MAX_QUERIES);
  SEXP out = PROTECT(Rf_allocVector(REALSXP, XLENGTH(rs)));
  for (R_xlen_t k = 0; k < XLENGTH(rs); ++k) {
    int r = INTEGER(rs)[k], c = INTEGER(cs)[k];
    if (r == NA_INTEGER || c == NA_INTEGER || r < 1 || c < 1 || r > n || c > n)
      Rf_error("Selected inverse: a query position is outside the matrix.");
    REAL(out)[k] = REAL(xs)[gt_si_entry(INTEGER(ps), INTEGER(is), r - 1, c - 1)];
    if (k % 65536 == 0) R_CheckUserInterrupt();
  }
  UNPROTECT(1);
  return out;
}

/* Local contractions for n observations sharing one q-by-k local design W:
   Q[obs,,] = W S_obs W' and factor_trace = sum_obs C_obs W S_obs, where S_obs is
   the k-by-k block of the selected inverse at the observation's k random
   coordinates. `perms` maps original coordinates to permuted positions
   (1-based) and `ids` holds each observation's k original coordinates. */
SEXP gt_selected_contractions(SEXP ps, SEXP is, SEXP xs, SEXP perms, SEXP ids,
                              SEXP ws, SEXP curvature) {
  double work;
  int m = gt_si_csc(ps, is, xs, &work);
  if (TYPEOF(perms) != INTSXP || TYPEOF(ids) != INTSXP || TYPEOF(ws) != REALSXP ||
      TYPEOF(curvature) != REALSXP)
    Rf_error("Selected inverse: contraction inputs must be an integer permutation, an integer index "
             "matrix, a double design matrix and a double curvature array.");
  if (XLENGTH(perms) != m) Rf_error("Selected inverse: the permutation length differs from the dimension.");
  SEXP iddim = Rf_getAttrib(ids, R_DimSymbol), wdim = Rf_getAttrib(ws, R_DimSymbol);
  if (TYPEOF(iddim) != INTSXP || XLENGTH(iddim) != 2 || TYPEOF(wdim) != INTSXP || XLENGTH(wdim) != 2)
    Rf_error("Selected inverse: the index and design arguments must be matrices.");
  int n = INTEGER(iddim)[0], k = INTEGER(iddim)[1], q = INTEGER(wdim)[0];
  if (n < 1 || n > GT_SI_MAX_OBSERVATIONS)
    Rf_error("Selected inverse: the observation cap (%d) is exceeded or no observation was given.",
             GT_SI_MAX_OBSERVATIONS);
  if (k < 1 || k > GT_SI_MAX_LOCAL_WIDTH)
    Rf_error("Selected inverse: the local width cap (%d coordinates) is exceeded or no coordinate was given.",
             GT_SI_MAX_LOCAL_WIDTH);
  if (q < 1 || q > GT_SI_MAX_LATENT)
    Rf_error("Selected inverse: the latent dimension cap (%d) is exceeded or no dimension was given.",
             GT_SI_MAX_LATENT);
  if (INTEGER(wdim)[1] != k || XLENGTH(ids) != (R_xlen_t) n * k || XLENGTH(ws) != (R_xlen_t) q * k ||
      XLENGTH(curvature) != (R_xlen_t) n * q * q)
    Rf_error("Selected inverse: contraction argument dimensions do not agree.");
  if ((double) n * k * k > GT_SI_MAX_CONTRACTION_WORK)
    Rf_error("Selected inverse: the contraction work cap (%.0f) is exceeded.", GT_SI_MAX_CONTRACTION_WORK);
  int *p = INTEGER(ps), *row = INTEGER(is), *perm = INTEGER(perms), *index = INTEGER(ids);
  double *inverse = REAL(xs), *W = REAL(ws), *C = REAL(curvature);
  int *seen = (int *) R_alloc((size_t) m, sizeof(int));
  memset(seen, 0, (size_t) m * sizeof(int));
  for (int j = 0; j < m; ++j)
    if (perm[j] == NA_INTEGER || perm[j] < 1 || perm[j] > m || seen[perm[j] - 1]++)
      Rf_error("Selected inverse: the permutation is not a permutation of the coordinates.");
  for (R_xlen_t j = 0; j < XLENGTH(ids); ++j)
    if (index[j] == NA_INTEGER || index[j] < 1 || index[j] > m)
      Rf_error("Selected inverse: a random coordinate index is outside the matrix.");
  for (R_xlen_t j = 0; j < XLENGTH(ws); ++j)
    if (!R_FINITE(W[j])) Rf_error("Selected inverse: the local design is not finite.");
  for (R_xlen_t j = 0; j < XLENGTH(curvature); ++j)
    if (!R_FINITE(C[j])) Rf_error("Selected inverse: the curvature is not finite.");
  SEXP outq = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) n * q * q));
  SEXP trace = PROTECT(Rf_allocMatrix(REALSXP, q, k));
  double *Q = REAL(outq), *T = REAL(trace);
  double *S = (double *) R_alloc((size_t) k * k, sizeof(double));
  double *G = (double *) R_alloc((size_t) q * k, sizeof(double));
  int *mapped = (int *) R_alloc((size_t) k, sizeof(int));
  long double accumulated[GT_SI_ACCUMULATORS] = {0}; /* q * k <= GT_SI_ACCUMULATORS, naturally aligned. */
  for (int obs = 0; obs < n; ++obs) {
    for (int j = 0; j < k; ++j) mapped[j] = perm[index[obs + n * j] - 1] - 1;
    for (int b = 0; b < k; ++b) for (int a = 0; a <= b; ++a)
      S[a + k * b] = S[b + k * a] = inverse[gt_si_entry(p, row, mapped[a], mapped[b])];
    for (int b = 0; b < k; ++b) for (int a = 0; a < q; ++a) {
      long double sum = 0;
      for (int c = 0; c < k; ++c) sum += (long double) W[a + q * c] * S[c + k * b];
      G[a + q * b] = (double) sum;
    }
    for (int b = 0; b < q; ++b) for (int a = 0; a < q; ++a) {
      long double sum = 0;
      for (int c = 0; c < k; ++c) sum += (long double) G[a + q * c] * W[b + q * c];
      Q[obs + (R_xlen_t) n * (a + q * b)] = (double) sum;
    }
    for (int b = 0; b < k; ++b) for (int a = 0; a < q; ++a) {
      long double sum = 0;
      for (int c = 0; c < q; ++c)
        sum += (long double) C[obs + (R_xlen_t) n * (a + q * c)] * G[c + q * b];
      accumulated[a + q * b] += sum;
    }
    if (obs % 128 == 0) R_CheckUserInterrupt();
  }
  for (int b = 0; b < k; ++b) for (int a = 0; a < q; ++a) T[a + q * b] = (double) accumulated[a + q * b];
  for (R_xlen_t j = 0; j < XLENGTH(outq); ++j)
    if (!R_FINITE(Q[j])) Rf_error("Selected inverse: a Q contraction is not finite.");
  for (R_xlen_t j = 0; j < XLENGTH(trace); ++j)
    if (!R_FINITE(T[j])) Rf_error("Selected inverse: a derivative contraction is not finite.");
  SEXP answer = PROTECT(Rf_allocVector(VECSXP, 4));
  SET_VECTOR_ELT(answer, 0, outq);
  SET_VECTOR_ELT(answer, 1, trace);
  SET_VECTOR_ELT(answer, 2, Rf_ScalarReal((double) n * k * k));
  SET_VECTOR_ELT(answer, 3, Rf_ScalarReal((double) (k * k + q * k) * sizeof(double) +
    (double) GT_SI_ACCUMULATORS * sizeof(long double) + (double) (m + k) * sizeof(int)));
  const char *names[] = {"Q", "factor_trace", "local_queries_upper_bound", "scratch_bytes"};
  gt_si_names(answer, names, 4);
  UNPROTECT(3);
  return answer;
}

/* The arithmetic widths this build accumulates with. */
SEXP gt_selected_platform(void) {
  SEXP result = PROTECT(Rf_allocVector(INTSXP, 4));
  INTEGER(result)[0] = (int) sizeof(double); INTEGER(result)[1] = (int) sizeof(long double);
  INTEGER(result)[2] = DBL_MANT_DIG; INTEGER(result)[3] = LDBL_MANT_DIG;
  const char *names[] = {"double_bytes", "long_double_bytes", "double_mantissa", "long_double_mantissa"};
  gt_si_names(result, names, 4);
  UNPROTECT(1);
  return result;
}

/* The declared caps, for preflight reports and tests. */
SEXP gt_selected_caps(void) {
  SEXP result = PROTECT(Rf_allocVector(REALSXP, 8));
  REAL(result)[0] = GT_SI_MAX_DIMENSION; REAL(result)[1] = GT_SI_MAX_FILL;
  REAL(result)[2] = (double) GT_SI_MAX_RECURRENCE; REAL(result)[3] = GT_SI_MAX_QUERIES;
  REAL(result)[4] = GT_SI_MAX_OBSERVATIONS; REAL(result)[5] = GT_SI_MAX_LOCAL_WIDTH;
  REAL(result)[6] = GT_SI_MAX_LATENT; REAL(result)[7] = GT_SI_MAX_CONTRACTION_WORK;
  const char *names[] = {"dimension", "fill", "recurrence_products", "queries", "observations",
                         "local_width", "latent", "contraction_work"};
  gt_si_names(result, names, 8);
  UNPROTECT(1);
  return result;
}

static const R_CallMethodDef gt_call_entries[] = {
  {"gt_selected_inverse", (DL_FUNC) &gt_selected_inverse, 3},
  {"gt_selected_queries", (DL_FUNC) &gt_selected_queries, 5},
  {"gt_selected_contractions", (DL_FUNC) &gt_selected_contractions, 7},
  {"gt_selected_platform", (DL_FUNC) &gt_selected_platform, 0},
  {"gt_selected_caps", (DL_FUNC) &gt_selected_caps, 0},
  {NULL, NULL, 0}
};

void attribute_visible R_init_Gtheory4LLM(DllInfo *dll) {
  R_registerRoutines(dll, NULL, gt_call_entries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
