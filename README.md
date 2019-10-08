# CNVfilteR
R package to remove false positives of CNV calling tools by using SNV calls


## Introduction

Many tools for copy number variant (CNV) detection from NGS data have been 
developed. Usually, these tools were designed for different input data like WGS, WES or
panel data, and their performance may depend on the CNV size. Available
benchmarks show that all these tools obtain false positives, sometimes 
reaching a very high number of them.

With the aim of reducing the number of false positives,
`r BiocStyle::Biocpkg("CNVfilteR")` identifies those CNVs that can be discarded.
This task is performed by using the single nucleotide variant (SNV) calls that are usually 
obtained in common NGS pipelines. As VCF field interpretation is key when working
with these files, `r BiocStyle::Biocpkg("CNVfilteR")` specifically supports 
VCFs produced by VarScan2, Strelka/Strelka2, freeBayes, HaplotypeCaller, and
UnifiedGenotyper. Additionally, results can be plotted using the functions
provided by the R/Bioconductor packages
[karyoploteR](http://bioconductor.org/packages/karyoploteR/) and 
[CopyNumberPlots](http://bioconductor.org/packages/CopyNumberPlots/).



## Installation

`r BiocStyle::Biocpkg("CNVfilteR")` is a 
[Bioconductor](http://bioconductor.org) package and to install it we have
to use `r BiocStyle::Biocpkg("BiocManager")`.

```{r getPackage, eval=FALSE}
  if (!requireNamespace("BiocManager", quietly = TRUE))
      install.packages("BiocManager")
  BiocManager::install("CNVfilteR")
```
