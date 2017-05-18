.SECONDEXPANSION:

GEOM_BASE = sieic5
GEOM_PATH = geom/$(GEOM_BASE)
GEOM_LCDD = $(GEOM_PATH)/$(GEOM_BASE).lcdd
GEOM_HEPREP = $(GEOM_PATH)/$(GEOM_BASE).heprep
GEOM_GDML = $(GEOM_PATH)/$(GEOM_BASE).gdml
GEOM_PANDORA = $(GEOM_PATH)/$(GEOM_BASE).pandora
GEOM_HTML = $(GEOM_PATH)/$(GEOM_BASE).html
LCSIM_CONDITIONS_PREFIX := http%3A%2F%2Fwww.lcsim.org%2Fdetectors%2F
LCSIM_CONDITIONS_PREFIX_ESCAPED := http\%3A\%2F\%2Fwww.lcsim.org\%2Fdetectors\%2F
LCSIM_CONDITIONS := $(HOME)/.lcsim/cache/$(LCSIM_CONDITIONS_PREFIX)$(GEOM_BASE).zip
GEOM_OVERLAP_CHECK = $(GEOM_PATH)/overlapCheck.log
GEOM = $(GEOM_LCDD) $(GEOM_GDML) $(GEOM_HEPREP) $(GEOM_PANDORA) $(GEOM_HTML) $(LCSIM_CONDITIONS) \
	$(GEOM_OVERLAP_CHECK)

N_EVENTS = 2

INPUT_BASE = $(basename $(notdir $(wildcard input/*.promc)))
OUTPUT_TRUTH = $(addprefix output/,$(INPUT_BASE:=_truth.slcio))
OUTPUT_SIM = $(addprefix output/,$(INPUT_BASE:=-$(GEOM_BASE).slcio))
OUTPUT_TRACKING = $(addprefix output/,$(INPUT_BASE:=-$(GEOM_BASE)_tracking.slcio))
OUTPUT_PANDORA = $(addprefix output/,$(INPUT_BASE:=-$(GEOM_BASE)_pandora.slcio))
OUTPUT_HEPSIM = $(addprefix output/,$(INPUT_BASE:=-$(GEOM_BASE)_hepsim.slcio))

HEPSIM_BASE = $(patsubst %_hepsim.slcio,%,$(notdir $(wildcard input/*_hepsim.slcio)))
OUTPUT_ETA_HISTO = $(addprefix output/,$(HEPSIM_BASE:=-eta_histo.root))

OUTPUT = $(OUTPUT_TRUTH) $(OUTPUT_SIM) $(OUTPUT_TRACKING) $(OUTPUT_PANDORA) $(OUTPUT_HEPSIM) \
	    $(OUTPUT_ETA_HISTO)

.PHONY: all geom clean

all: $(OUTPUT) $(GEOM)

geom: $(GEOM)

clean:
	rm -rf output/*

JAVA_OPTS = -Xms2048m -Xmx2048m

$(GEOM_LCDD): $(GEOM_PATH)/compact.xml
	java $(JAVA_OPTS) -jar $(GCONVERTER) -o lcdd $< $@

$(GEOM_GDML): $(GEOM_LCDD)
	slic -g $< -G $@ > $@.log

$(GEOM_HEPREP): $(GEOM_PATH)/compact.xml
	java $(JAVA_OPTS) -jar $(GCONVERTER) -o heprep $< $@

$(GEOM_PANDORA): $(GEOM_PATH)/compact.xml $(LCSIM_CONDITIONS)
	java $(JAVA_OPTS) -jar $(GCONVERTER) -o pandora $< $@

%.html: $(GEOM_PATH)/compact.xml $$(LCSIM_CONDITIONS)
	java $(JAVA_OPTS) -jar $(GCONVERTER) -o html $< $@

$(HOME)/.lcsim/cache/$(LCSIM_CONDITIONS_PREFIX_ESCAPED)%.zip: $(GEOM_HEPREP)
	mkdir -p $(@D)
	cd geom/$* && zip -r $@ * &> $@.log

$(GEOM_OVERLAP_CHECK): $(GEOM_GDML) macros/overlapCheck.cpp
	root -b -q -l "macros/overlapCheck.cpp(\"$<\");" | tee $@

#####

JAVA_OPTS = -Xms2048m -Xmx2048m
PROMC2LCIO_PATH = /usr/local/promc/examples/promc2lcio

output/%_truth.slcio: input/%.promc
	java $(JAVA_OPTS) promc2lcio $(abspath $<) $(abspath $@) \
		&> $@.log

output/%-$(GEOM_BASE).slcio: output/%_truth.slcio $(GEOM_LCDD) $(GEOM_PATH)/config/defaultILCCrossingAngle.mac
	time bash -c "time slic -x -i $< \
	    -g $(GEOM_LCDD) \
	    -m $(GEOM_PATH)/config/defaultILCCrossingAngle.mac \
	    -o $@ \
	    -r $(N_EVENTS)" \
	    &> $@.log

JENV=-Dorg.lcsim.cacheDir=$(HOME) -Duser.home=$(HOME)

output/%-$(GEOM_BASE)_tracking.slcio: output/%-$(GEOM_BASE).slcio $(GEOM_PATH)/config/$(GEOM_BASE)_trackingStrategies.xml \
				$(GEOM_PATH)/config/sid_dbd_prePandora_noOverlay.xml \
				$$(LCSIM_CONDITIONS)
	time bash -c "time java $(JAVA_OPTS) $(JENV) \
		-jar $(CLICSOFT)/distribution/target/lcsim-distribution-*-bin.jar \
		-DinputFile=$< \
		-DtrackingStrategies=$(GEOM_PATH)/config/$(GEOM_BASE)_trackingStrategies.xml \
		-DoutputFile=$@ \
		$(GEOM_PATH)/config/sid_dbd_prePandora_noOverlay.xml" \
		&> $@.log

output/%-$(GEOM_BASE)_pandora.slcio: output/%-$(GEOM_BASE)_tracking.slcio $(GEOM_PANDORA) $(GEOM_PATH)/config/PandoraSettings_$(GEOM_BASE).xml
	$(slicPandora_DIR)/bin/PandoraFrontend \
		-g $(GEOM_PANDORA) \
		-i $< \
		-c $(GEOM_PATH)/config/PandoraSettings_$(GEOM_BASE).xml \
		-o $@ \
		&> $@.log

output/%-$(GEOM_BASE)_hepsim.slcio: output/%-$(GEOM_BASE)_pandora.slcio output/%_truth.slcio
	rm -f $@
	$(FPADSIM)/lcio2hepsim/lcio2hepsim $^ $@ \
		&> $@.log

#####

output/%-eta_histo.root: input/%_hepsim.slcio macros/etaHistos.cpp
	root -b -q -l "macros/etaHistos.cpp(\"$<\",\"$@\")"

