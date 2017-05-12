GEOM_BASE = sieic4
GEOM_PATH = $(addprefix geom/,$(GEOM_BASE))
GEOM_LCDD = $(GEOM_PATH:=/geom.lcdd)
GEOM_GDML = $(GEOM_PATH:=/geom.gdml)
GEOM_HEPREP = $(GEOM_PATH:=/geom.heprep)
GEOM_PANDORA = $(GEOM_PATH:=/geom.pandora)
GEOM_HTML = $(GEOM_PATH:=/geom.html)
GEOM = $(GEOM_LCDD) $(GEOM_GDML) $(GEOM_HEPREP) $(GEOM_PANDORA) $(GEOM_HTML)

N_EVENTS = 3

INPUT_BASE = $(basename $(notdir $(wildcard input/*.promc)))
OUTPUT_TRUTH = $(addprefix output/,$(INPUT_BASE:=_truth.slcio))
OUTPUT_SIM = $(addprefix output/,$(INPUT_BASE:=.slcio))
OUTPUT_TRACKING = $(addprefix output/,$(INPUT_BASE:=_tracking.slcio))
OUTPUT_PANDORA = $(addprefix output/,$(INPUT_BASE:=_pandora.slcio))
OUTPUT_HEPSIM = $(addprefix output/,$(INPUT_BASE:=_hepsim.slcio))
OUTPUT = $(OUTPUT_TRUTH) $(OUTPUT_SIM) $(OUTPUT_TRACKING) $(OUTPUT_PANDORA) $(OUTPUT_HEPSIM)

.PHONY: output geom clean

output: $(OUTPUT)

geom: $(GEOM)

clean:
	rm -rf $(GEOM) $(OUTPUT)

JAVA_OPTS = -Xms2048m -Xmx2048m

geom/%/geom.lcdd: geom/%/compact.xml
	java $(JAVA_OPTS) -jar $(GCONVERTER) -o lcdd $< $@

geom/%/geom.gdml: geom/%/geom.lcdd
	slic -g $< -G $@ > $(@D)/lcdd_gdml_conversion.log

geom/%/geom.heprep: geom/%/compact.xml
	java $(JAVA_OPTS) -jar $(GCONVERTER) -o heprep $< $@

geom/%/geom.pandora: geom/%/compact.xml
	java $(JAVA_OPTS) -jar $(GCONVERTER) -o pandora $< $@

geom/%/geom.html: geom/%/compact.xml
	java $(JAVA_OPTS) -jar $(GCONVERTER) -o html $< $@

#####

JAVA_OPTS = -Xms2048m -Xmx2048m
PROMC2LCIO_PATH = /usr/local/promc/examples/promc2lcio

output/%_truth.slcio: input/%.promc
	java $(JAVA_OPTS) promc2lcio $(abspath $<) $(abspath $@) \
		&> $(@D)/$(basename $(@F)).log

output/%.slcio: output/%_truth.slcio $(GEOM_LCDD) $(GEOM_PATH)/config/defaultILCCrossingAngle.mac
	
	time bash -c "time slic -x -i $< \
	    -g $(GEOM_LCDD) \
	    -m $(GEOM_PATH)/config/defaultILCCrossingAngle.mac \
	    -o $@ \
	    -r $(N_EVENTS)" \
	    &> $(@D)/$(basename $(@F)).log

JENV=-Dorg.lcsim.cacheDir=$(HOME) -Duser.home=$(HOME)

output/%_tracking.slcio: output/%.slcio $(GEOM_PATH)/config/$(GEOM_BASE)_trackingStrategies.xml \
				$(GEOM_PATH)/config/sid_dbd_prePandora_noOverlay.xml
	time bash -c "time java $(JAVA_OPTS) $(JENV) \
		-jar $(CLICSOFT)/distribution/target/lcsim-distribution-*-bin.jar \
		-DinputFile=$< \
		-DtrackingStrategies=$(GEOM_PATH)/config/$(GEOM_BASE)_trackingStrategies.xml \
		-DoutputFile=$@ \
		$(GEOM_PATH)/config/sid_dbd_prePandora_noOverlay.xml" \
		&> $(@D)/$(basename $(@F)).log

output/%_pandora.slcio: output/%_tracking.slcio $(GEOM_PANDORA) $(GEOM_PATH)/config/PandoraSettings_$(GEOM_BASE).xml
	$(slicPandora_DIR)/bin/PandoraFrontend \
		-g $(GEOM_PANDORA) \
		-i $< \
		-c $(GEOM_PATH)/config/PandoraSettings_$(GEOM_BASE).xml \
		-o $@ \
		&> $(@D)/$(basename $(@F)).log

output/%_hepsim.slcio: output/%_pandora.slcio output/%_truth.slcio
	rm -f $@
	$(FPADSIM)/lcio2hepsim/lcio2hepsim $^ $@ \
		&> $(@D)/$(basename $(@F)).log

