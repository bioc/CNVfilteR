#' loadVCFs
#'
#' @description
#' Loads VCFs files
#'
#' @details
#' Loads VCF files and computes alt allele frequency for each variant. It uses
#' \code{\link{loadSNPsFromVCF}} function load the data and identify the
#' correct VCF format for allele frequency computation.
#'
#' If sample.names is not provided, the sample names included in the VCF itself
#' will be used. Both single-sample and multi-sample VCFs are accepted, but when
#' multi-sample VCFs are used, sample.names parameter must be NULL.
#'
#' If vcf is not compressed with bgzip, the function compresses it and generates
#' the .gz file. If .tbi file does not exist for a given VCF file, the function
#' also generates it. All files are generated in a temporary folder.
#'
#' @note Important: Compressed VCF must be compressed with
#' [bgzip ("block gzip") from Samtools htslib](http://www.htslib.org/doc/bgzip.html)
#' and not using the standard Gzip utility.
#'
#' @param vcf.files vector of VCFs paths. Both .vcf and .vcf.gz extensions are allowed.
#' @param sample.names Sample names vector containing sample names for each \code{vcf.files}. If NULL, sample name will be obtained from the VCF sample column.  (Defaults to NULL)
#' @param cnvs.gr \code{GRanges} object containg CNV calls. Call \code{loadCNVcalls} to obtain it. Only those variants in regions affected by CNVs will be loaded to speed up the load.
#' @param min.total.depth Minimum total depth. Variants under this value will be excluded. (Defaults to 10)
#' @param regions.to.exclude A \code{GRanges} object defining the regions for which the variants should be excluded.
#' Useful for defining known difficult regions like pseudogenes where the allele frequency is not trustable. (Defaults to NULL)
#' @param vcf.source VCF source, i.e., the variant caller used to generate the VCF file. If set, the \code{loadSNPsFromVCF} function will not try to recognize the source. (Defaults to NULL)
#' @param ref.support.field Reference allele depth field. (Defaults to NULL)
#' @param alt.support.field Alternative allele depth field. (Defaults to NULL)
#' @param list.support.field Allele support field in a list format: reference allele, alternative allele. (Defaults to NULL)
#' @param homozygous.range Homozygous range. Variants not in the homozygous/heterozygous intervals will be excluded. (Defaults to \code{c(90, 100)})
#' @param heterozygous.range Heterozygous range. Variants not in the homozygous/heterozygous intervals will be excluded. (Defaults to \code{c(28, 72)})
#' @param exclude.indels Whether to exclude indels when loading the variants. TRUE is the recommended value given that indels frequency varies in a different way than SNVs. (Defaults to TRUE)
#' @param genome The name of the genome. (Defaults to "hg19")
#' @param exclude.non.canonical.chrs Whether to exclude non canonical chromosomes (Defaults to TRUE)
#' @param verbose Whether to show information messages. (Defaults to TRUE)
#'
#' @return A list where names are the sample names, and values are the \code{GRanges} objects for each sample.
#'
#' @examples
#' # Load CNVs data (required by loadVCFs to speed up the load process)
#' cnvs.file <- system.file("extdata", "DECoN.CNVcalls.csv", package = "CNVfilteR", mustWork = TRUE)
#' cnvs.gr <- loadCNVcalls(cnvs.file = cnvs.file, chr.column = "Chromosome", start.column = "Start", end.column = "End", cnv.column = "CNV.type", sample.column = "Sample")
#'
#' # Load VCFs data
#' vcf.files <- c(system.file("extdata", "variants.sample1.vcf.gz", package = "CNVfilteR", mustWork = TRUE),
#'                system.file("extdata", "variants.sample2.vcf.gz", package = "CNVfilteR", mustWork = TRUE))
#' vcfs <- loadVCFs(vcf.files, cnvs.gr = cnvs.gr)
#'
#'
#' @import assertthat
#' @importFrom IRanges subsetByOverlaps
#' @importFrom GenomicRanges mcols
#' @importFrom Biostrings width
#' @importFrom methods is
#' @importFrom Rsamtools indexTabix bgzip
#' @export loadVCFs
#'
loadVCFs <- function(vcf.files, sample.names = NULL, cnvs.gr,
                     min.total.depth = 10, regions.to.exclude = NULL, vcf.source = NULL,
                     ref.support.field = NULL, alt.support.field = NULL, list.support.field = NULL,
                     homozygous.range = c(90,100), heterozygous.range = c(28,72), exclude.indels = TRUE,
                     genome = "hg19", exclude.non.canonical.chrs = TRUE, verbose = TRUE) {

  # Check input
  assertthat::assert_that(is.character(vcf.files))
  assertthat::assert_that(is.null(sample.names) || (is.character(sample.names) & length(vcf.files) == length(sample.names)) )
  assertthat::assert_that(methods::is(cnvs.gr, "GRanges"))
  assertthat::assert_that(assertthat::is.number(min.total.depth))
  assertthat::assert_that(methods::is(regions.to.exclude, "GRanges") || is.null(regions.to.exclude))
  assertthat::assert_that(assertthat::is.string(vcf.source) || is.null(vcf.source))
  assertthat::assert_that(assertthat::is.string(ref.support.field) || is.null(ref.support.field))
  assertthat::assert_that(assertthat::is.string(alt.support.field) || is.null(alt.support.field))
  assertthat::assert_that(assertthat::is.string(list.support.field) || is.null(list.support.field))
  assertthat::assert_that(is.numeric(homozygous.range) && length(homozygous.range) == 2)
  assertthat::assert_that(homozygous.range[1] < homozygous.range[2])
  assertthat::assert_that(heterozygous.range[1] < heterozygous.range[2])
  assertthat::assert_that(heterozygous.range[2] < homozygous.range[1])
  assertthat::assert_that(is.numeric(heterozygous.range) && length(heterozygous.range) == 2)
  assertthat::assert_that(is.logical(exclude.indels))
  assertthat::assert_that(assertthat::is.string(genome))
  assertthat::assert_that(is.logical(exclude.non.canonical.chrs))
  assertthat::assert_that(is.logical(verbose))


  # Decide where sample names are obtained from
  sample.names.mode <- NULL
  if(is.null(sample.names)){
    sample.names.mode <-  "readFromVCF"
  } else if (is.vector(sample.names)){
    sample.names.mode <-  "oneSamplePerVCF"
  }

  # Load and filter each VCF
  results <- list()
  for (vcfFile in vcf.files){

    originalVcfFile <- vcfFile
    if (!endsWith(vcfFile, ".gz"))
      vcfFile <- paste0(vcfFile, ".gz")

    # create .gz or .tbi if necessary (in temp dir)
    tbiFile <- paste0(vcfFile, ".tbi")
    if (!file.exists(vcfFile) | !file.exists(tbiFile)) {

      # Copy file to temp
      tempFolder <- tempdir()
      file.copy(originalVcfFile, file.path(tempFolder, basename(originalVcfFile)))
      vcfFile <- file.path(tempFolder, basename(vcfFile))

      # compress
      Rsamtools::bgzip(originalVcfFile, vcfFile, overwrite = TRUE)  # generate .gz in a temp path

      # create tabix file
      tbiFile <- paste0(vcfFile, ".tbi")
      Rsamtools::indexTabix(vcfFile, "vcf")
    }

    # Read data
    variantsList <- loadSNPsFromVCF(vcf.file = vcfFile, verbose = verbose, vcf.source = vcf.source, ref.support.field = ref.support.field,
                                    alt.support.field = alt.support.field, list.support.field = list.support.field, regions.to.filter = cnvs.gr,
                                    genome = genome, exclude.non.canonical.chrs = exclude.non.canonical.chrs)

    # Stop if found > 1 samples in a vcf file and sample.names vector was given
    samplesFoundInVCF <- names(variantsList)
    nSamples <- length(samplesFoundInVCF)
    if (nSamples > 1 & sample.names.mode == "oneSamplePerVCF"){
      stop("More than one sample was found in", vcfFile, "Please, use sample.names parameter only when working with VCF files with one sample column.")
    }

    # process variants depending on mode
    if (sample.names.mode == "readFromVCF"){

      for (sampleName in samplesFoundInVCF){
        vars <-  variantsList[[sampleName]]
        sampleCNVsGR <- cnvs.gr[cnvs.gr$sample == sampleName, ]
        results[[sampleName]] <- auxProcessVariants(vars, sampleCNVsGR, heterozygous.range, homozygous.range, min.total.depth, exclude.indels, regions.to.exclude)
      }

    } else {  # oneSamplePerVCF mode
      vars <- variantsList[[1]]
      sampleName <- sample.names[length(results) + 1]
      sampleCNVsGR <- cnvs.gr[cnvs.gr$sample == sampleName, ]
      results[[sampleName]] <- auxProcessVariants(vars, sampleCNVsGR, heterozygous.range, homozygous.range, min.total.depth, exclude.indels, regions.to.exclude)
    }


  }

  return(results)
}



#' auxProcessVariants
#'
#' @description
#' Auxiliar function called by \code{loadVCFs} to process variants
#'
#' @param vars \code{GRanges} object containing variants for a certain sample.
#' @param cnvGR \code{GRanges} object containg CNV calls for a certain sample.
#' @param heterozygous.range Heterozygous range. Variants not in the homozygous/heterozygous intervals will be excluded.
#' @param homozygous.range Homozygous range. Variants not in the homozygous/heterozygous intervals will be excluded.
#' @param min.total.depth Minimum total depth. Variants under this value will be excluded.
#' @param exclude.indels Whether to exclude indels when loading the variants. TRUE is the recommended value given that indels frequency varies in a different way than SNVs.
#' @param regions.to.exclude A \code{GRanges} object defining the regions for which the variants should be excluded.
#'
#' @return Processed \code{vars}
#'
#' @import assertthat
#' @importFrom IRanges subsetByOverlaps
#' @importFrom GenomicRanges mcols
#'
auxProcessVariants <- function(vars, cnvGR, heterozygous.range, homozygous.range, min.total.depth, exclude.indels, regions.to.exclude){

  # Exclude variants overlaping regions.to.exclude
  if (!is.null(regions.to.exclude)) {
    vars <- IRanges::subsetByOverlaps(vars, regions.to.exclude,  type = "any", invert = TRUE)
  }

  # Subset: only variants on CNV regions
  vars <- IRanges::subsetByOverlaps(vars, cnvGR, type = "any")

  # Process variants
  if (length(vars) > 0){
    mcolumns <- GenomicRanges::mcols(vars)
    mcolumns$indel <- Biostrings::width(mcolumns$ref) > 1 | Biostrings::width(mcolumns$alt) > 1
    mcolumns$type <- ""
    mcolumns <- as.data.frame(mcolumns)  # to speed up
    mcolumns[mcolumns$alt.freq >= heterozygous.range[1] & mcolumns$alt.freq <= heterozygous.range[2], "type"] <- "ht"
    mcolumns[mcolumns$alt.freq >= homozygous.range[1] & mcolumns$alt.freq <= homozygous.range[2], "type"] <- "hm"

    # set meta-columns
    GenomicRanges::mcols(vars) <- as.data.frame(mcolumns)

    # retag as overlap_indel those SNV variants overlapped by an indel. Those variant will no be used in analysis
    snvs <- vars[!vars$indel,]
    indels <- vars[vars$indel,]
    overlapped <- IRanges::subsetByOverlaps(snvs, indels)
    indexes <- which(row.names(GenomicRanges::mcols(vars)) %in% row.names(GenomicRanges::mcols(overlapped)))
    if (length(indexes) > 1){
      GenomicRanges::mcols(vars[indexes,])$type <- "overlap_indel"
    }

    # Filter
    indexes <- which(mcolumns$type %in% c("ht", "hm")
                     & mcolumns$total.depth >= min.total.depth
                     & (!mcolumns$indel | !exclude.indels) )
    vars <- vars[indexes]

  } else {
    GenomicRanges::mcols(vars) <- cbind(GenomicRanges::mcols(vars), data.frame("indel" = logical(), "type" = character()))
  }

  return(vars)
}

