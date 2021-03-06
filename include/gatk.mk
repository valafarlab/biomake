outdir ?= .

#
# GATK makefile rules
# 

# http://blog.jgc.org/2007/01/what-makefile-am-i-in.html
MAKEDIR = $(dir $(lastword $(MAKEFILE_LIST)))
ifeq ($(findstring ngsvars.mk,$(MAKEFILE_LIST)),)
include $(MAKEDIR)ngsvars.mk
endif

# GATK_HOME variable
ifndef GATK_HOME
GATK_HOME=.
endif
ifndef GATK_JAVA_MEM
GATK_JAVA_MEM=$(JAVA_MEM)
endif
ifndef GATK_JAR
GATK_JAR=$(GATK_HOME)/GenomeAnalysisTK.jar
endif
ifndef GATK_JAVA_TMPDIR
GATK_JAVA_TMPDIR=$(JAVA_TMPDIR)
endif
ifndef GATK_COMMAND
GATK_COMMAND=java -Xmx$(GATK_JAVA_MEM) -Djava.io.tmpdir=$(GATK_JAVA_TMPDIR) -jar $(GATK_JAR)
endif
ifndef GATK_DBSNP
GATK_DBSNP=$(DBSNP)
endif
ifndef GATK_TARGET_REGIONS
GATK_TARGET_REGIONS=$(TARGET_REGIONS)
endif
ifndef GATK_KNOWN_SITES
GATK_KNOWN_SITES=$(GATK_DBSNP)
endif


# Generic program options

ifndef GATK_UNIFIEDGENOTYPER_OPTIONS
GATK_UNIFIEDGENOTYPER_OPTIONS=-stand_call_conf 30.0 -stand_emit_conf 10.0  --downsample_to_coverage 30 --output_mode EMIT_VARIANTS_ONLY -glm BOTH -nt $(NPROC) -R $(REFERENCE)
ifneq ($(GATK_DBSNP),)
GATK_UNIFIEDGENOTYPER_OPTIONS+=--dbsnp $(GATK_DBSNP)
endif
ifneq ($(GATK_TARGET_REGIONS),)
GATK_UNIFIEDGENOTYPER_OPTIONS+=-L $(GATK_TARGET_REGIONS)
endif
endif
##############################
# Generic genotyping, unifiedgenotyper
##############################
$(outdir)/%.vcf: %.bam
	$(GATK_COMMAND) -T UnifiedGenotyper $(GATK_UNIFIEDGENOTYPER_OPTIONS) -I $< -o $@.tmp && mv $@.tmp $@  && mv $@.tmp.idx $@.idx

##############################
# Realign target creation 
##############################
ifndef GATK_REALIGN_TARGET_CREATOR_OPTIONS
GATK_REALIGN_TARGET_CREATOR_OPTIONS=-R $(REFERENCE)
endif
ifneq ($(GATK_TARGET_REGIONS),)
GATK_REALIGN_TARGET_CREATOR_OPTIONS+=-L $(GATK_TARGET_REGIONS)
endif

$(outdir)/%.intervals: %.bam
	$(GATK_COMMAND) -T RealignerTargetCreator $(GATK_REALIGN_TARGET_CREATOR_OPTIONS) -I $< -o $@.tmp && mv $@.tmp $@

##############################
# Indel realignment
##############################
ifndef GATK_INDELREALIGNER_OPTIONS
GATK_INDELREALIGNER_OPTIONS=-R $(REFERENCE)
endif

$(outdir)/%.realign.bam: %.bam %.intervals
	$(GATK_COMMAND) -T IndelRealigner $(GATK_INDELREALIGNER_OPTIONS) -o $@.tmp --targetIntervals $(word 2, $^) && mv $@.tmp $@  && mv $@.tmp.bai $@.bai

##############################
# Base recalibration
##############################
ifndef GATK_BASERECALIBRATOR_OPTIONS
GATK_BASERECALIBRATOR_OPTIONS=-R $(REFERENCE)
endif
ifneq ($(GATK_TARGET_REGIONS),)
GATK_BASERECALIBRATOR_OPTIONS+=-L $(GATK_TARGET_REGIONS)
endif
$(outdir)/%.recal_data.grp: %.bam %.bai
	$(eval KNOWN_SITES=$(addprefix -knownSites ,$(GATK_KNOWN_SITES)))
	$(GATK_COMMAND) -T BaseRecalibrator $(GATK_BASERECALIBRATOR_OPTIONS) $(KNOWN_SITES) -I $< -o $@.tmp && mv $@.tmp $@

ifndef GATK_PRINTREADS_OPTIONS
GATK_PRINTREADS_OPTIONS=-R $(REFERENCE)
endif
$(outdir)/%.recal.bam: %.bam %.recal_data.grp
	$(GATK_COMMAND) -T PrintReads $(GATK_PRINTREADS_OPTIONS) -I $< -BQSR $(lastword $^) -o $@.tmp && mv $@.tmp $@ && mv $@.tmp.bai $@.bai

##############################
# Clipreads
##############################
ifndef GATK_CLIPREADS_OPTIONS
GATK_CLIPREADS_OPTIONS=
endif
$(outdir)/%.clip.bam: %.bam %.bai
	$(GATK_COMMAND) -T ClipReads $(GATK_CLIPREADS_OPTIONS) -I $< -o $@.tmp && mv $@.tmp $@ && mv $@.tmp.bai $@.bai

##############################
# Variant filtration
##############################
ifndef GATK_VARIANTFILTRATION_OPTIONS
GATK_VARIANTFILTRATION_OPTIONS=
endif
$(outdir)/%.filtered.vcf: %.vcf
	$(GATK_COMMAND) -T VariantFiltration $(GATK_VARIANTFILTRATION_OPTIONS) -R $(REFERENCE) --variant $< --out $@.tmp && mv $@.tmp $@ && mv $@.tmp.idx $@.idx

##############################
# Variant evaluation
##############################
ifndef GATK_VARIANT_EVAL_OPTIONS
GATK_VARIANT_EVAL_OPTIONS=-ST Filter --doNotUseAllStandardModules --evalModule CompOverlap --evalModule CountVariants --evalModule GenotypeConcordance --evalModule TiTvVariantEvaluator --evalModule ValidationReport --stratificationModule Filter
endif
ifneq ($(GATK_DBSNP),)
GATK_VARIANT_EVAL_OPTIONS+=--dbsnp $(GATK_DBSNP)
endif
ifneq ($(GATK_TARGET_REGIONS),)
GATK_VARIANT_EVAL_OPTIONS+=-L $(GATK_TARGET_REGIONS)
endif
$(outdir)/%.eval_metrics: %.vcf
	$(GATK_COMMAND) -T VariantEval $(GATK_VARIANT_EVAL_OPTIONS) -R $(REFERENCE) --eval $< -o $@.tmp && mv $@.tmp $@


##############################
# Read Backed Phasing
##############################
ifndef GATK_READBACKEDPHASING_OPTIONS
GATK_READBACKEDPHASING_OPTIONS=
endif
ifndef GATK_VCFSUFFIX
GATK_VCFSUFFIX=.vcf
endif
$(outdir)/%.phased.vcf: %.bam %.bai
	$(GATK_COMMAND) -T ReadBackedPhasing $(GATK_READBACKEDPHASING_OPTIONS) -I $< --variant $*$(GATK_VCFSUFFIX) -R $(REFERENCE) > $@.tmp && mv $@.tmp $@

##############################
# Select snp variants
##############################
ifndef GATK_SELECTSNPVARIANTS_OPTIONS
GATK_SELECTSNPVARIANTS_OPTIONS=--selectTypeToInclude SNP
endif
$(outdir)/%.snp.vcf: %.vcf
	$(GATK_COMMAND) -T SelectVariants $(GATK_SELECTSNPVARIANTS_OPTIONS) --variant $< --out $@.tmp -R $(REFERENCE) && mv $@.tmp $@

##############################
# Multi-sample variant calling
# 
# Requires a variable GATK_BAM_LIST that contains the bam file
# requirements
# FIXME: these names are poorly chosen
##############################
ifndef GATK_BAM_LIST
GATK_BAM_LIST:=
endif

$(outdir)/all.vcf: $(GATK_BAM_LIST) $(subst .bam,.bai,$(GATK_BAM_LIST))
	$(GATK_COMMAND) -T UnifiedGenotyper $(GATK_UNIFIEDGENOTYPER_OPTIONS) $(addprefix -I , $(GATK_BAM_LIST)) -o $@.tmp && mv $@.tmp $@

$(outdir)/all.phased.vcf: all.vcf $(GATK_BAM_LIST) $(subst .bam,.bai,$(GATK_BAM_LIST))
	$(GATK_COMMAND) -T ReadBackedPhasing $(GATK_READBACKEDPHASING_OPTIONS) $(addprefix -I , $(GATK_BAM_LIST)) --variant $< -R $(REFERENCE) -o $@.tmp && mv $@.tmp $@

##############################
# settings
##############################
.PHONY: gatk-settings gatk-header

print-%:
	@echo '$*=$($*)'

gatk-header:
	@echo -e "\ngatk.mk options"
	@echo "====================="

gatk-settings: gatk-header print-GATK_HOME print-GATK_JAVA_MEM print-GATK_JAR print-GATK_JAVA_TMPDIR print-GATK_COMMAND print-REFERENCE print-GATK_DBSNP print-GATK_TARGET_REGIONS print-GATK_KNOWN_SITES print-NPROC print-GATK_UNIFIEDGENOTYPER_OPTIONS print-GATK_READBACKEDPHASING_OPTIONS print-GATK_VCFSUFFIX print-GATK_SELECTSNPVARIANTS_OPTIONS print-GATK_BAM_LIST print-GATK_REALIGN_TARGET_CREATOR_OPTIONS print-GATK_INDELREALIGNER_OPTIONS print-GATK_BASERECALIBRATOR_OPTIONS print-GATK_PRINTREADS_OPTIONS print-GATK_CLIPREADS_OPTIONS print-GATK_VARIANTFILTRATION_OPTIONS print-GATK_VARIANT_EVAL_OPTIONS
