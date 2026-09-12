\name{gt_example}
\alias{gt_example}
\title{Load Modeling Tables from Three LLM-Annotated Datasets}
\description{Lists eight documented outcome sets or loads their design columns and modeled outcomes. Installed resources omit raw text and API metadata.}
\usage{
gt_example(name = NULL, coding = c("native", "manuscript"),
  directory = NULL)
}
\arguments{
\item{name}{Outcome-set name, or NULL to list available sets.}
\item{coding}{Use \code{"native"} to preserve response types. Use \code{"manuscript"} for the seven original Gaussian working-score codings.}
\item{directory}{Optional directory containing example RDS resources or source CSV files, supplied explicitly as one nonempty path. A file named \code{<name>.rds} takes precedence over CSV loading. An installed package always loads bundled RDS resources when this argument is omitted, regardless of workspace variables.}
}
\value{A catalog data frame when name is NULL. Otherwise a list with data, outcome names, observation families, object and facet names, example name, coding, source, and interpretation notes. Installed resources also provide portable source-provenance metadata.}
\details{Every set retains 21,600 measurement rows: 100 text objects by 4 evaluators, 3 prompts, 6 temperatures, and 3 seeds. Full tables exceed default dense discrete fitting limits; use a predeclared small panel or a future scalable backend for discrete examples.

Available outcome sets are:
\itemize{
\item \code{hate_speech}: ordinal severity.
\item \code{mental_health_7L}: original Gaussian working score.
\item \code{mental_health_3L}: original Gaussian working score.
\item \code{mental_health_6flag}: six binary flags.
\item \code{mental_health_3group}: three binary flag groups.
\item \code{drug_review}: ordinal holistic sentiment.
\item \code{drug_review_4aspect}: four ordinal aspects.
\item \code{mental_health_nominal}: seven unordered categories.
}
The nominal set has no manuscript-score coding. Detailed variable definitions,
category mappings, preprocessing notes, and the corresponding annotation-paper
and original-corpus references are provided in
the \link[=gtheory_hate_speech]{Hate-Speech},
\link[=gtheory_mental_health]{Mental-Health}, and
\link[=gtheory_drug_review]{Drug-Review} data topics. The
\link[=gtheory_datasets]{dataset overview} documents the shared panel design,
provenance, and installed bibliography.

Standalone functions can use a local \code{.gt_example_data_dir} binding to
configure the CSV directory. This binding must be in the same environment
into which the functions were sourced. The source loader configures the
checkout's public \code{inst/extdata}
directory. Parent environments and callers are not searched. This standalone
convention has no effect on the installed package; use \code{directory} for an
intentional override. An invalid explicit directory produces an error rather
than silently falling back to bundled data.

The mental-health 7L/3L scores are study-defined working scores, not established
clinical severity scales. Labels are model-generated and retain the source
study's preprocessing; no new human adjudication is implied.

The source CSV files are:
\itemize{
\item \file{hate_labeling_final.csv}
\item \file{mh_labeling_final.csv}
\item \file{drug_labeling_final.csv}
}
Bundled data retain design identifiers and modeled outcomes only. Source
checksums, the public OSF deposit link, and extraction details accompany
installed resources. The annotation data retain the CC BY 4.0 license stated
in the public data codebook; see the installed \file{DATA_LICENSE.md}.}
\seealso{\link[=gtheory_datasets]{Dataset overview},
\link[=gtheory_hate_speech]{Hate-Speech data},
\link[=gtheory_mental_health]{Mental-Health data},
\link[=gtheory_drug_review]{Drug-Review data},
\code{\link{gt_family}}, \code{\link{gt_fit}}}
\examples{
gt_example()
x <- gt_example("hate_speech")
nrow(x$data)
is.ordered(x$data$score)
nominal <- gt_example("mental_health_nominal")
levels(nominal$data$label)
}
