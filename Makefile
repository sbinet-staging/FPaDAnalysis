# Require second expansion for tricksy $$() substitutions
.SECONDEXPANSION:

# Define geometry target paths
# FIXME: move GEOM_BASE definition outside of Makefile
GEOM_BASE = sieic5
GEOM_PATH = geom/$(GEOM_BASE)
GEOM_LCDD = $(GEOM_PATH)/$(GEOM_BASE).lcdd
GEOM_HEPREP = $(GEOM_PATH)/$(GEOM_BASE).heprep
GEOM_GDML = $(GEOM_PATH)/$(GEOM_BASE).gdml
GEOM_PANDORA = $(GEOM_PATH)/$(GEOM_BASE).pandora
GEOM_HTML = $(GEOM_PATH)/$(GEOM_BASE).html
LCSIM_CONDITIONS_PREFIX := http%3A%2F%2Fwww.lcsim.org%2Fdetectors%2F
LCSIM_CONDITIONS_PREFIX_ESCAPED := http\%3A\%2F\%2Fwww.lcsim.org\%2Fdetectors\%2F
LCSIM_CONDITIONS := $(PWD)/.lcsim/cache/$(LCSIM_CONDITIONS_PREFIX)$(GEOM_BASE).zip
GEOM_OVERLAP_CHECK = $(GEOM_PATH)/overlapCheck.log
GEOM = $(GEOM_LCDD) $(GEOM_GDML) $(GEOM_HEPREP) $(GEOM_PANDORA) $(GEOM_HTML) $(LCSIM_CONDITIONS) \
	$(GEOM_OVERLAP_CHECK)

# Define tracking strategy list target path
STRATEGIES = $(GEOM_PATH)/config/$(GEOM_BASE)_trackingStrategies.xml

# Grab number of events to simulate
N_EVENTS = $(shell cat nEventsPerRun)

# Create output target file paths for each input file
INPUT_BASE = $(patsubst input/%,%,$(basename $(shell find input -iname "*.promc")))
INPUT_BASE_DIRS = $(sort $(dir $(INPUT_BASE)))
OUTPUT_DIRS = $(sort $(addprefix output/,$(INPUT_BASE_DIRS)) $(sort $(dir $(wildcard output/*/))))

OUTPUT_TRUTH = $(addprefix output/,$(INPUT_BASE:=_truth.slcio))
OUTPUT_SIM = $(addprefix output/,$(INPUT_BASE:=-$(GEOM_BASE).slcio))
OUTPUT_TRACKING = $(addprefix output/,$(INPUT_BASE:=-$(GEOM_BASE)_tracking.slcio))
OUTPUT_PANDORA = $(addprefix output/,$(INPUT_BASE:=-$(GEOM_BASE)_pandora.slcio))
OUTPUT_HEPSIM = $(addprefix output/,$(INPUT_BASE:=-$(GEOM_BASE)_hepsim.slcio))

OUTPUT_TRACKEFF = $(OUTPUT_DIRS:=trackEff-$(GEOM_BASE).pdf)
OUTPUT_TRACKEFF_NORM = $(OUTPUT_DIRS:=trackEff-norm-$(GEOM_BASE).pdf)
OUTPUT_TRACKEFF_DEVANG = $(OUTPUT_DIRS:=trackEff-devAng-$(GEOM_BASE).pdf)
OUTPUT_CLUSTERDIST = $(OUTPUT_DIRS:=clusterDist-$(GEOM_BASE).pdf)
OUTPUT_CLUSTERDIST_EWEIGHT = $(OUTPUT_DIRS:=clusterDist-energyWeighted-$(GEOM_BASE).pdf)
OUTPUT_PFODIST = $(OUTPUT_DIRS:=pfoDist-$(GEOM_BASE).pdf)
OUTPUT_DIAG = $(OUTPUT_TRACKEFF_DEVANG) $(OUTPUT_TRACKEFF) $(OUTPUT_TRACKEFF_NORM) \
			  $(OUTPUT_CLUSTERDIST) $(OUTPUT_CLUSTERDIST_EWEIGHT) \
			  $(OUTPUT_PFODIST)

# Set what output files to build by default
OUTPUT = $(OUTPUT_TRUTH) $(OUTPUT_SIM) $(OUTPUT_TRACKING) $(OUTPUT_PANDORA) $(OUTPUT_HEPSIM) \
	    $(OUTPUT_DIAG)
ifeq ($(MAKECMDGOALS),osg)
.INTERMEDIATE: $(OUTPUT_TRUTH) $(OUTPUT_SIM) $(OUTPUT_TRACKING) $(OUTPUT_PANDORA)
endif

.PHONY: all geom osg clean allclean

all: $(OUTPUT) $(GEOM)

geom: $(GEOM)

osg: $(OUTPUT_HEPSIM)

clean:
	rm -rf output/*

allclean:
	rm -rf output/* $(GEOM) $(dir $(LCSIM_CONDITIONS))

JAVA_OPTS = -Xms1024m -Xmx1024m
CONDITIONS_OPTS=-Dorg.lcsim.cacheDir=$(PWD) -Duser.home=$(PWD)

##### Define geometry targets

$(GEOM_PATH)/compact.xml: $(GEOM_PATH)/compact_dd4hep.xml
	cat $< | sed 's/<includes>.*<\/includes>//;s/type="solenoid"/type="Solenoid"/;s/\<T\>/1/g' > $@

$(GEOM_LCDD): $(GEOM_PATH)/compact.xml
	java $(JAVA_OPTS) $(CONDITIONS_OPTS) -jar $(GCONVERTER) -o lcdd $< $@

$(GEOM_GDML): $(GEOM_LCDD)
	slic -g $< -G $@ > $@.log

$(GEOM_HEPREP): $(GEOM_PATH)/compact.xml
	java $(JAVA_OPTS) $(CONDITIONS_OPTS) -jar $(GCONVERTER) -o heprep $< $@

$(GEOM_PANDORA): $(GEOM_PATH)/compact.xml $$(LCSIM_CONDITIONS)
	java $(JAVA_OPTS) $(CONDITIONS_OPTS) -jar $(GCONVERTER) -o pandora $< $@

%.html: $(GEOM_PATH)/compact.xml $$(LCSIM_CONDITIONS)
	java $(JAVA_OPTS) $(CONDITIONS_OPTS) -jar $(GCONVERTER) -o html $< $@

$(PWD)/.lcsim/cache/$(LCSIM_CONDITIONS_PREFIX_ESCAPED)%.zip: $(GEOM_HEPREP)
	mkdir -p $(@D)
	cd geom/$* && zip -r $@ * &> $@.log

$(GEOM_OVERLAP_CHECK): $(GEOM_GDML) macros/overlapCheck.cpp
	root -b -q -l "macros/overlapCheck.cpp(\"$<\");" | tee $@

##### Define tracking strategy list target

$(STRATEGIES): $(GEOM_PATH)/compact.xml $(GEOM_PATH)/config/prototypeStrategy.xml \
			$(GEOM_PATH)/config/layerWeights.xml $$(LCSIM_CONDITIONS)
	if [ -f $(GEOM_PATH)/config/trainingSample.slcio ]; \
		then java $(JAVA_OPTS) $(CONDITIONS_OPTS) \
			-jar $(CLICSOFT)/distribution/target/lcsim-distribution-*-bin.jar \
			-DprototypeStrategyFile=$(GEOM_PATH)/config/prototypeStrategy.xml \
			-DlayerWeightsFile=$(GEOM_PATH)/config/layerWeights.xml \
			-DtrainingSampleFile=$(GEOM_PATH)/config/trainingSample.slcio \
			-DoutputStrategyFile=$@ \
			$(GEOM_PATH)/config/strategyBuilder.xml \
			&> $@.log; \
	else \
		touch $@; \
	fi

##### Define output targets

# Conversion of promc truth file to slcio
output/%_truth.slcio: input/%.promc
	mkdir -p $(@D)
	java $(JAVA_OPTS) promc2lcio $(abspath $<) $(abspath $@) \
		&> $@.log

# SLIC simulation of truth events
output/%-$(GEOM_BASE).slcio: output/%_truth.slcio $(GEOM_LCDD) $(GEOM_PATH)/config/defaultILCCrossingAngle.mac \
				nEventsPerRun
	time bash -c "time slic -x -i $< \
	    -g $(GEOM_LCDD) \
	    -m $(GEOM_PATH)/config/defaultILCCrossingAngle.mac \
	    -o $@ \
	    -r $(N_EVENTS)" \
	    &> $@.log

# Digitization AND tracking with LCSim
output/%-$(GEOM_BASE)_tracking.slcio: output/%-$(GEOM_BASE).slcio $(STRATEGIES) \
				$(GEOM_PATH)/config/sid_dbd_prePandora_noOverlay.xml \
				$$(LCSIM_CONDITIONS)
	time bash -c "time java $(JAVA_OPTS) $(CONDITIONS_OPTS) \
		-jar $(CLICSOFT)/distribution/target/lcsim-distribution-*-bin.jar \
		-DinputFile=$< \
		-DtrackingStrategies=$(STRATEGIES) \
		-DoutputFile=$@ \
		$(GEOM_PATH)/config/sid_dbd_prePandora_noOverlay.xml" \
		&> $@.log

# Pandora PFA with slicPandora
output/%-$(GEOM_BASE)_pandora.slcio: output/%-$(GEOM_BASE)_tracking.slcio $(GEOM_PANDORA) $(GEOM_PATH)/config/PandoraSettings_$(GEOM_BASE).xml
	$(slicPandora_DIR)/bin/PandoraFrontend \
		-g $(GEOM_PANDORA) \
		-i $< \
		-c $(GEOM_PATH)/config/PandoraSettings_$(GEOM_BASE).xml \
		-o $@ \
		&> $@.log

# Trimming of slicPandora output
output/%-$(GEOM_BASE)_hepsim.slcio: output/%-$(GEOM_BASE)_pandora.slcio output/%_truth.slcio
	rm -f $@
	$(FPADSIM)/lcio2hepsim/lcio2hepsim $^ $@ \
		&> $@.log

##### Analysis target definitions

output/%/trackEff-$(GEOM_BASE).pdf: tools/trackEff.go $(OUTPUT_TRACKING)
	go run tools/trackEff.go -t 40 -o $@ $(shell find $(@D) -name "*_tracking.slcio")

output/%/trackEff-norm-$(GEOM_BASE).pdf: tools/trackEff.go $(OUTPUT_TRACKING)
	go run tools/trackEff.go -t 40 -n -o $@ $(shell find $(@D) -name "*_tracking.slcio")

output/%/trackEff-devAng-$(GEOM_BASE).pdf: tools/trackEff.go $(OUTPUT_TRACKING)
	go run tools/trackEff.go -t 40 -a -o $@ $(shell find $(@D) -name "*_tracking.slcio")

output/%/clusterDist-$(GEOM_BASE).pdf: tools/clusterDist.go $(OUTPUT_PANDORA)
	go run tools/clusterDist.go -t 40 -o $@ $(shell find $(@D) -name "*_pandora.slcio")

output/%/clusterDist-energyWeighted-$(GEOM_BASE).pdf: tools/clusterDist.go $(OUTPUT_PANDORA)
	go run tools/clusterDist.go -t 40 -e -o $@ $(shell find $(@D) -name "*_pandora.slcio")

output/%/pfoDist-$(GEOM_BASE).pdf: tools/PFODist.go $(OUTPUT_PANDORA)
	go run tools/PFODist.go -t 40 -o $@ $(shell find $(@D) -name "*_pandora.slcio")

