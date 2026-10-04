# Analysis specified in PROTOCOL.md; no fitting occurs here.
out <- commandArgs(trailingOnly = TRUE)[[1L]]
d <- read.csv(file.path(out, "attempts.csv"), stringsAsFactors = FALSE)
scenarios <- unique(d$scenario)
labels <- c("Binary: balanced / 24 items", "Binary: rare / 12 items",
            "Ordinal: balanced / 24 items", "Ordinal: rare / 12 items")
wilson <- function(k, n) {
  if (!n) return(c(NA_real_, NA_real_))
  z <- qnorm(.975); p <- k/n
  center <- (p + z^2/(2*n)) / (1 + z^2/n)
  half <- z * sqrt(p*(1-p)/n + z^2/(4*n^2)) / (1 + z^2/n)
  c(max(0, center-half), min(1, center+half))
}
acceptance <- do.call(rbind, lapply(scenarios, function(s) {
  x <- d[d$scenario == s, ]
  n <- sum(x$status != "budget_not_started"); k <- sum(x$status == "accepted")
  interval <- wilson(k, n)
  data.frame(scenario=s, planned=nrow(x), attempted=n, accepted=k,
             rejected=sum(x$status == "rejected"), errors=sum(x$status == "error"),
             timeouts=sum(x$status == "timeout"), unstarted=sum(x$status == "budget_not_started"),
             acceptance=if (n) k/n else NA_real_, wilson95_lower=interval[1], wilson95_upper=interval[2],
             accepted_boundaries=sum(x$status == "accepted" & x$boundary, na.rm=TRUE),
             seconds=sum(x$process_seconds, na.rm=TRUE))
}))
recovery <- do.call(rbind, lapply(scenarios, function(s) {
  x <- d[d$scenario == s, ]
  do.call(rbind, lapply(c("variance", "reliability"), function(metric) {
    keep <- x$status == "accepted" & is.finite(x[[paste0(metric, "_estimate")]])
    error <- x[[paste0(metric, "_estimate")]][keep] - x[[paste0(metric, "_true")]][keep]
    n <- length(error); rmse <- if (n) sqrt(mean(error^2)) else NA_real_
    data.frame(scenario=s, estimand=metric, accepted=sum(x$status == "accepted"), usable=n,
      truth=x[[paste0(metric,"_true")]][1],
      mean=if (n) mean(x[[paste0(metric,"_estimate")]][keep]) else NA_real_,
      bias=if (n) mean(error) else NA_real_, bias_mcse=if (n>1) sd(error)/sqrt(n) else NA_real_,
      rmse=rmse, rmse_mcse=if (n>1) {if (rmse==0) 0 else sd(error^2)/(2*rmse*sqrt(n))} else NA_real_)
  }))
}))
write.csv(acceptance, file.path(out,"acceptance.csv"), row.names=FALSE, na="NA")
write.csv(recovery, file.path(out,"recovery.csv"), row.names=FALSE, na="NA")
fmt <- function(x, digits=3) ifelse(is.na(x), "NA", formatC(x,format="f",digits=digits))
text <- c("# Executed pilot results", "", "Acceptance and disposition counts are primary. Every planned row is retained.", "",
          "| Setting | Accepted / attempted | Rejected | Errors | Timeouts | Unstarted | 95% Wilson Monte Carlo interval |",
          "|---|---:|---:|---:|---:|---:|---|")
for (i in seq_len(nrow(acceptance))) {
  a <- acceptance[i, ]
  text <- c(text,sprintf("| %s | %d / %d | %d | %d | %d | %d | %.1f%%–%.1f%% |", labels[i],a$accepted,a$attempted,
       a$rejected,a$errors,a$timeouts,a$unstarted,100*a$wilson95_lower,100*a$wilson95_upper))
}
text <- c(text,"", "Recovery below is **conditional on numerical acceptance and a finite estimate**. MCSEs use the usable n in each row; ten or fewer repetitions give poor precision.", "",
          "| Setting | Estimand | Usable n | Truth | Mean | Bias (MCSE) | RMSE (MCSE) |",
          "|---|---|---:|---:|---:|---:|---:|")
for (i in seq_len(nrow(recovery))) {
  a <- recovery[i, ]
  text <- c(text,sprintf("| %s | %s | %d | %s | %s | %s (%s) | %s (%s) |", labels[match(a$scenario,scenarios)],a$estimand,
       a$usable,fmt(a$truth),fmt(a$mean),fmt(a$bias),fmt(a$bias_mcse),fmt(a$rmse),fmt(a$rmse_mcse)))
}
text <- c(text,"", "Bias MCSE = sd(error)/sqrt(n). RMSE MCSE is a delta-method approximation using squared errors. These describe simulation noise, not uncertainty intervals for individual fitted parameters.", "",
          "Inspect `attempts.csv` for every error, rejection, warning, category count and runtime; `details/` keeps returned numerical diagnostics. No failed panel was replaced or rerun. The displayed estimates are not selected by closeness to truth.", "",
          "This small pilot neither identifies a reliable operating range nor separates finite-sample and first-order Laplace approximation bias. The few-group setting also changes replication and rarity. No interval-coverage, observed-score reliability, sparse-backend, or production-readiness conclusion follows.", "",
          "![Acceptance and conditional recovery](pilot.png)", "",
          "The left panel uses attempted-fit denominators and Wilson 95% Monte Carlo intervals. Filled points are accepted fits; open crosses in the variance panel are rejected diagnostic estimates. Dashed marks show generating truths. Latent reliability is extracted only for accepted fits.")
writeLines(text,file.path(out,"RESULTS.md"))
plot_pilot <- function() {
  par(mfrow=c(1,3), mar=c(4.5,1,3.5,1), oma=c(3,0,3,0), family="sans", xpd=FALSE)
  colors <- c("#2563A5","#DD8844","#2563A5","#DD8844")
  y <- 4:1
  plot(NA,xlim=c(-.03,1.03),ylim=c(.5,4.9),yaxt="n",xlab="Acceptance proportion",ylab="",main="1. Acceptance first",bty="n")
  abline(v=seq(0,1,.25),col="#E4E8EC",lty=1)
  for (i in 1:4) {
    a <- acceptance[i, ]
    segments(a$wilson95_lower,y[i],a$wilson95_upper,y[i],col=colors[i],lwd=2)
    points(a$acceptance,y[i],pch=19,cex=1.1,col=colors[i])
    text(0,y[i]+.32,paste0(labels[i],"  [",a$accepted,"/",a$attempted,"]"),adj=0,cex=.72)
  }
  for (metric in c("variance","reliability")) {
    values <- d[[paste0(metric,"_estimate")]]
    limits <- if (metric=="variance") c(0,max(1,values[is.finite(values)])*1.05) else c(0,1)
    plot(NA,xlim=limits,ylim=c(.5,4.9),yaxt="n",xlab=if(metric=="variance") "Item variance estimate" else "Latent mean-score G = Phi",
         ylab="",main=if(metric=="variance") "2. Variance recovery" else "3. Latent reliability",bty="n")
    abline(v=pretty(limits),col="#E4E8EC")
    for(i in 1:4) {
      x <- d[d$scenario==scenarios[i], ]
      truth <- x[[paste0(metric,"_true")]][1]
      segments(truth,y[i]-.25,truth,y[i]+.25,lty=2,col="#263746",lwd=2)
      xpos <- x[[paste0(metric,"_estimate")]]
      ypos <- y[i]+(x$replicate-5.5)*.035
      keep <- is.finite(xpos)
      points(xpos[keep],ypos[keep],pch=ifelse(x$status[keep]=="accepted",19,4),col=colors[i],cex=.85)
      text(limits[1],y[i]+.32,paste0(if(i<3)"Binary"else"Ordinal", if(i%%2)" balanced"else" rare"),adj=0,cex=.72)
    }
  }
  mtext("Small dense-engine pilot: 40 planned fits, 10 per setting",outer=TRUE,side=3,line=1,cex=1.2,font=2)
  mtext("Probit item-intercept model | Variance truth 0.5 | Recovery summaries condition on acceptance | No interval-coverage claim",
        outer=TRUE,side=1,line=1,cex=.8)
}
png(file.path(out,"pilot.png"),width=1800,height=850,res=150,type=if (capabilities("aqua")) "quartz" else "cairo")
plot_pilot(); dev.off()
pdf(file.path(out,"pilot.pdf"),width=12,height=850/150,useDingbats=FALSE)
plot_pilot(); dev.off()
print(acceptance,row.names=FALSE)
print(recovery,row.names=FALSE)
