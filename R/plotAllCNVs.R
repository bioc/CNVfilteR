#' plotAllCNVs
#'
#' @description
#' Plots all CNVs on chromosome ideograms
#'
#' @details
#' Plots all CNVs defined at \code{cnvs.gr} on a view of horizontal ideograms representing all chromosomes.
#'
#' @param cnvs.gr \code{GRanges} containing al CNV definitions returned by \code{filterCNVs} or \code{loadCNVcalls} functions.
#' @param genome The name of the genome. (Defaults to "hg19")
#'
#' @return invisibly returns a \code{karyoplot} object
#'
#' @examples
#' cnvs.file <- system.file("extdata", "DECoN.CNVcalls.2.csv", package = "CNVfilteR", mustWork = TRUE)
#' cnvs.gr <- loadCNVcalls(cnvs.file = cnvs.file, chr.column = "Chromosome", start.column = "Start", end.column = "End", cnv.column = "CNV.type", sample.column = "Sample")
#'
#' # Plot all CNVs
#' plotAllCNVs(cnvs.gr)
#'
#'
#' @import assertthat
#' @importFrom CopyNumberPlots plotCopyNumberCalls
#' @importFrom karyoploteR plotKaryotype
#' @importFrom graphics legend
#' @importFrom methods is
#' @export plotAllCNVs
#'
plotAllCNVs <- function(cnvs.gr, genome = "hg19"){

  assertthat::assert_that(methods::is(cnvs.gr, "GRanges"))
  assertthat::assert_that(assertthat::is.string(genome))

  # Add cn column (required by CopyNumberPlots)
  cnvs.gr <- auxAddCNcolumn(cnvs.gr)

  # Plot
  kp <- karyoploteR::plotKaryotype(plot.type=1, genome = genome)
  CopyNumberPlots::plotCopyNumberCalls(kp, cnvs.gr, r1=0.3, cn.colors = CNV_COLORS, label.cex = 0.6, loh.values = FALSE)
  graphics::legend("bottomright", legend=c("Deletion CNV", "Duplication CNV"), fill = c(CNV_COLORS[2], CNV_COLORS[4]), ncol=1, cex = 0.7)

  return(invisible(kp))
}
