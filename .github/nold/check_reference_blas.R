# CI regression probe for the two public issue #66 systems; no package fit is run.
# Rscript --vanilla check.R snapshot OUTPUT_DIR [PACKAGE ...]
# Rscript --vanilla check.R reference OUTPUT_DIR [PACKAGE ...]
# snapshot: numerical failures are retained diagnostic data, exit 0.
# reference: require actual Linux/noLD/reference backend and accurate solves, exit 1 otherwise.
# Invalid fixtures, dependency load failures and other operational failures always exit 1.

scalar_error <- function(A, b, x) {
  if (is.null(x) || length(x) != ncol(A) || any(!is.finite(x))) return(Inf)
  residual <- 0; a_norm <- 0; x_norm <- 0; b_norm <- 0
  for (i in seq_len(nrow(A))) {
    total <- 0; row_norm <- 0
    for (j in seq_len(ncol(A))) {
      total <- total + A[i, j] * x[j]
      row_norm <- row_norm + abs(A[i, j])
    }
    residual <- max(residual, abs(total - b[i]))
    a_norm <- max(a_norm, row_norm); b_norm <- max(b_norm, abs(b[i]))
  }
  for (j in seq_along(x)) x_norm <- max(x_norm, abs(x[j]))
  denominator <- a_norm * x_norm + b_norm
  if (!is.finite(residual) || !is.finite(denominator)) return(Inf)
  if (residual == 0) return(0)
  if (denominator == 0) return(Inf)
  residual / denominator
}

capture_operation <- function(expr) {
  error <- NULL; warnings <- character()
  value <- tryCatch(withCallingHandlers(force(expr), warning=function(w) {
    warnings <<- c(warnings, conditionMessage(w))
  }), error=function(e) { error <<- conditionMessage(e); NULL })
  list(value=value, error=error, warnings=warnings)
}

normalized_path <- function(x) {
  if (length(x) != 1L || is.na(x) || !nzchar(x) || !file.exists(x)) return(NA_character_)
  normalizePath(x, mustWork=TRUE)
}

environment_record <- function() {
  # Calling La_library() also loads LAPACK before checking process maps.
  blas <- normalized_path(extSoftVersion()[['BLAS']])
  lapack <- normalized_path(La_library())
  maps <- if (file.exists('/proc/self/maps')) readLines('/proc/self/maps',warn=FALSE) else character()
  paths <- unique(sub('^.*[[:space:]](/.*)$','\\1',maps[grepl('[[:space:]]/',maps)]))
  mapped <- vapply(paths, normalized_path, character(1))
  native_files <- c(BLAS=blas,LAPACK=lapack,
    R_executable=normalized_path(file.path(R.home('bin'),'exec','R')),
    libR=normalized_path(file.path(R.home('lib'),'libR.so')))
  present <- !is.na(native_files)
  hashes <- data.frame(role=names(native_files)[present],path=unname(native_files[present]),
    bytes=unname(file.info(native_files[present])$size),
    md5=unname(tools::md5sum(native_files[present])),stringsAsFactors=FALSE)
  list(native_file_hashes=hashes,R=R.version, system=Sys.info(), long_double=unname(capabilities('long.double')),
    sizeof_longdouble=.Machine$sizeof.longdouble, BLAS=blas, LAPACK=lapack,
    reference_BLAS=normalized_path('/usr/lib/x86_64-linux-gnu/blas/libblas.so.3'),
    reference_LAPACK=normalized_path('/usr/lib/x86_64-linux-gnu/lapack/liblapack.so.3'),
    mapped_paths=unname(mapped[!is.na(mapped)]), process_maps=maps,
    cpu=if (file.exists('/proc/cpuinfo')) readLines('/proc/cpuinfo',warn=FALSE) else character(),
    threads=Sys.getenv(c('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS'),unset=NA_character_),
    package_versions=vapply(loadedNamespaces(),function(x)as.character(utils::packageVersion(x)),character(1)),
    DLLs=vapply(getLoadedDLLs(),function(x)x[['path']],character(1)))
}

reference_failures <- function(info) {
  reasons <- character()
  if (!identical(unname(info$system[['sysname']]),'Linux')) reasons <- c(reasons,'Linux runtime required')
  if (!identical(info$long_double,FALSE) || !identical(info$sizeof_longdouble,0L))
    reasons <- c(reasons,'no-long-double capability and size proof required')
  if (is.na(info$reference_BLAS) || is.na(info$reference_LAPACK))
    reasons <- c(reasons,'reference BLAS/LAPACK library files missing')
  if (is.na(info$BLAS) || !identical(info$BLAS,info$reference_BLAS))
    reasons <- c(reasons,'actual BLAS is not the reference library')
  if (is.na(info$LAPACK) || !identical(info$LAPACK,info$reference_LAPACK))
    reasons <- c(reasons,'actual LAPACK is not the reference library')
  if (!length(info$process_maps) || !all(c(info$reference_BLAS,info$reference_LAPACK) %in% info$mapped_paths))
    reasons <- c(reasons,'reference BLAS/LAPACK mapping proof missing')
  if (any(grepl('openblas',info$process_maps,ignore.case=TRUE)))
    reasons <- c(reasons,'OpenBLAS is mapped into the reference process')
  hashes <- info$native_file_hashes
  required <- c('BLAS','LAPACK','R_executable','libR')
  if (!is.data.frame(hashes) || !all(c('role','path','bytes','md5') %in% names(hashes)) ||
      !identical(sort(hashes$role),sort(required)) ||
      anyNA(hashes) || any(!is.finite(hashes$bytes)) || any(hashes$bytes<=0) ||
      any(!grepl('^[0-9a-f]{32}$',hashes$md5)) ||
      !all(hashes$path %in% info$mapped_paths))
    reasons <- c(reasons,'required native runtime file identity or mapping proof missing')
  reasons
}

baseline_failures <- function(info, baseline) {
  invalid <- reference_failures(baseline)
  if (length(invalid)) return(paste('invalid reference baseline:',paste(invalid,collapse='; ')))
  canonical <- function(x) {
    h <- x$native_file_hashes
    h <- h[match(c('BLAS','LAPACK','R_executable','libR'),h$role),c('role','path','bytes','md5')]
    rownames(h)<-NULL;h
  }
  if (!identical(canonical(info),canonical(baseline))) 'native runtime file identities differ from reference baseline' else character()
}

probe_main <- function(args=commandArgs(TRUE), fixture_file=NULL) {
  if (length(args)<2L || !args[1L] %in% c('snapshot','reference'))
    stop('Usage: Rscript --vanilla check.R {snapshot|reference} OUTPUT_DIR [PACKAGE ...]')
  mode <- args[1L]; out <- args[2L]; packages <- args[-c(1L,2L)]
  if (dir.exists(out) && length(list.files(out,all.files=TRUE,no..=TRUE))) stop('Output directory must be empty')
  dir.create(out,recursive=TRUE,showWarnings=FALSE);out<-normalizePath(out,mustWork=TRUE)
  evidence <- list(mode=mode, diagnostic_only=identical(mode,'snapshot'), package_qualification=FALSE,
    repetitions=20L, bound_formula='32 * nrow(H) * .Machine$double.eps',packages_requested=packages,
    environments=list(),stored_steps=list(),operations=list(),failure=NULL)
  rows <- list(); exit_status <- 1L
  tryCatch({
    if (is.null(fixture_file)) {
      script <- sub('^--file=','',commandArgs()[grepl('^--file=',commandArgs())])
      if (length(script)!=1L) stop('Cannot locate adjacent solve_probe_inputs.R')
      fixture_file <- file.path(dirname(normalizePath(script,mustWork=TRUE)),'solve_probe_inputs.R')
    }
    fixture_env <- new.env(parent=baseenv());sys.source(fixture_file,fixture_env)
    inputs <- fixture_env$inputs
    if (!identical(names(inputs),c('binary','ordinal'))) stop('Both issue #66 fixtures are required')
    evidence$fixture_file_md5 <- unname(tools::md5sum(fixture_file))
    evidence$provenance <- lapply(inputs,`[[`,'provenance')
    baseline_path <- Sys.getenv('GTHEORY_REFERENCE_BASELINE')
    baseline <- if(mode=='reference' && nzchar(baseline_path)) readRDS(normalizePath(baseline_path,mustWork=TRUE)) else NULL
    evidence$reference_baseline <- if(is.null(baseline)) NULL else normalizePath(baseline_path,mustWork=TRUE)
    snapshot <- function(label) {
      info <- environment_record();evidence$environments[[label]] <<- info
      if(label=='after_dependencies') saveRDS(info,file.path(out,'runtime.rds'))
      if (mode=='reference') {
        bad <- reference_failures(info)
        if(!length(bad) && !is.null(baseline)) bad <- baseline_failures(info,baseline)
        if (length(bad)) stop(paste(label,paste(bad,collapse='; '),sep=': '))
      }
    }
    snapshot('before_dependencies')
    for (package in packages) loadNamespace(package)
    snapshot('after_dependencies')
    for (name in names(inputs)) {
      z <- inputs[[name]];d<-nrow(z$H);bound<-32*d*.Machine$double.eps
      if (!identical(dim(z$H),c(28L,28L)) || !identical(dim(z$factor),dim(z$H)) ||
          length(z$b)!=d || length(z$stored_step)!=d ||
          any(!is.finite(c(z$H,z$b,z$factor,z$stored_step))) ||
          any(z$factor[lower.tri(z$factor)]!=0) || any(diag(z$factor)<=0)) stop('Malformed fixture: ',name)
      original_error<-scalar_error(z$H,z$b,z$stored_step)
      evidence$stored_steps[[name]]<-list(error=original_error,bound=bound,invalid=is.finite(original_error)&&original_error>bound)
      if (!is.finite(original_error) || original_error<=bound) stop('Known-invalid stored step no longer fails: ',name)
      for (factor_source in c('stored','fresh_chol')) for (rep in seq_len(20L)) {
        factor<-capture_operation(if(factor_source=='stored') z$factor else chol(z$H))
        forward<-capture_operation(if(is.null(factor$value)) stop('factor unavailable') else forwardsolve(t(factor$value),z$b))
        step<-capture_operation(if(is.null(forward$value)) stop('forward solve unavailable') else backsolve(factor$value,forward$value))
        errors<-c(factor$error,forward$error,step$error);warnings<-c(factor$warnings,forward$warnings,step$warnings)
        forward_error<-if(is.null(factor$value)) Inf else scalar_error(t(factor$value),z$b,forward$value)
        backward_error<-if(is.null(factor$value)||is.null(forward$value)) Inf else scalar_error(factor$value,forward$value,step$value)
        solve_error<-scalar_error(z$H,z$b,step$value)
        valid<-!length(errors)&&!length(warnings)&&all(is.finite(c(forward_error,backward_error,solve_error)))&&
          all(c(forward_error,backward_error,solve_error)<=bound)
        row<-data.frame(problem=name,factor_source=factor_source,repetition=rep,bound=bound,
          forward_error=forward_error,backward_error=backward_error,solve_error=solve_error,valid=valid,
          original_difference=if(is.null(step$value)) NA_real_ else max(abs(as.numeric(step$value)-as.numeric(z$stored_step))),
          errors=paste(errors,collapse='; '),warnings=paste(warnings,collapse='; '),stringsAsFactors=FALSE)
        rows[[length(rows)+1L]]<-row
        evidence$operations[[length(evidence$operations)+1L]]<-list(row=row,factor=factor,forward=forward,step=step)
      }
      snapshot(paste0('after_',name))
    }
    snapshot('after_all_operations')
    tab<-do.call(rbind,rows)
    evidence$native_invalid<-sum(!tab$valid);evidence$native_total<-nrow(tab)
    if (mode=='reference' && any(!tab$valid)) stop('Native solve regression under qualified reference backend')
    exit_status<-0L
  },error=function(e) {evidence$failure<<-conditionMessage(e)})
  evidence$exit_status<-exit_status
  evidence$reference_probe_pass<-identical(mode,'reference')&&exit_status==0L
  saveRDS(evidence,file.path(out,'evidence.rds'))
  if(length(rows))write.table(do.call(rbind,rows),file.path(out,'results.tsv'),sep='\t',quote=TRUE,row.names=FALSE)
  summary<-evidence[c('mode','diagnostic_only','package_qualification','repetitions','bound_formula','packages_requested','fixture_file_md5','reference_baseline','provenance','stored_steps','native_total','native_invalid','failure','exit_status','reference_probe_pass')]
  writeLines(capture.output(dput(summary)),file.path(out,'summary.txt'))
  cat('Mode:',mode,'; native invalid:',if(is.null(evidence$native_invalid))'not completed' else evidence$native_invalid,
      '; reference probe pass:',evidence$reference_probe_pass,'; evidence:',out,'\n')
  if(!is.null(evidence$failure))message(evidence$failure)
  exit_status
}
if(sys.nframe()==0L)quit(status=probe_main())
